class_name Region
extends Node3D
## Base das regiões: setores de maré, interativos, bacias de água (perigo),
## guardiões, spawns, checkpoints, objetivos e ambiente.

const IX := preload("res://scripts/world/ix.gd")
const MECH := preload("res://scripts/world/mech.gd")

var main: Node
var sectors = {}  # id -> TideSector
var sector_default = {}  # id -> bool (maré alta inicial)
var interactables: Array = []
var hazards: Array = []  # {poly, sector, lo, hi, mesh}
var guardians: Array = []  # {guard, zone, zone_top, active: Callable}
var spawns = {}  # id -> {pos: Vector3, yaw: float}
var checkpoints: Array = []  # {id, pos, radius}
var objectives: Array = []  # {id, done: Callable, target: Callable}
var unsafe_zones: Array = []  # {sector, poly, top}
var gates: Array = []
var floaters: Array = []
var bridges: Array = []
var movers: Array = []
var animated: Array = []  # Callables (dt) -> void
var kill_y = -30.0
var music = "farol"
var env = {}  # parâmetros de ambiente (céu, névoa, luz)
var rng = RandomNumberGenerator.new()
var t = 0.0

func _init(region_id: String = "") -> void:
	id = region_id
	name = region_id

var id = ""

## Sobrescrever: constrói a geometria e registra tudo.
func build() -> void:
	pass

## Sobrescrever: lógica por quadro específica da região.
func region_tick(_dt: float) -> void:
	pass

## Chamado quando um nó de maré é escaneado pela primeira vez.
func on_node_scanned(_n: Interactable) -> void:
	pass

## Registra um interativo como filho de outro nó (ex.: sobre uma plataforma móvel).
func attach_ix(node: Interactable, parent: Node3D, local_pos: Vector3) -> Interactable:
	node.region = self
	node.position = local_pos
	parent.add_child(node)
	interactables.append(node)
	return node

## Colisões convexas a partir das malhas de um modelo (escala já aplicada).
func collide_model(model: Node3D, skip: Array = [], groups: Array = ["safe"]) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m = mi as MeshInstance3D
		var skip_it = false
		for s in skip:
			if m.name.begins_with(s):
				skip_it = true
		if skip_it:
			continue
		var shape = m.mesh.create_convex_shape(true, true) as ConvexPolygonShape3D
		var xf = global_transform.affine_inverse() * m.global_transform
		var pts = PackedVector3Array()
		for v in shape.points:
			pts.append(xf * v)
		var conv = ConvexPolygonShape3D.new()
		conv.points = pts
		var body = StaticBody3D.new()
		for g in groups:
			body.add_to_group(g)
		var cs = CollisionShape3D.new()
		cs.shape = conv
		body.add_child(cs)
		add_child(body)

# --- setores -----------------------------------------------------------------------

func add_sector(sid: String, start_high: bool) -> TideSector:
	var s = TideSector.new(sid, Game.sector_high(id, sid, start_high))
	sector_default[sid] = start_high
	s.started.connect(func(h): _on_tide_started(sid, h))
	s.finished.connect(func(h): _on_tide_finished(sid, h))
	sectors[sid] = s
	return s

func high(sid: String) -> bool:
	return sectors[sid].high

func sector_level(sid: String) -> float:
	return sectors[sid].level

func sectors_moving(list: Array) -> bool:
	for s in list:
		if sectors[s].transitioning:
			return true
	return false

func tide_refusal(list: Array) -> String:
	for s in list:
		var r: String = sectors[s].refusal(player_unsafe(s))
		if r != "":
			return r
	return ""

func toggle_sectors(list: Array) -> void:
	if tide_refusal(list) != "":
		Sfx.play("fail")
		return
	for s in list:
		sectors[s].force_toggle()
	Game.stat("tides")

func _on_tide_started(sid: String, to_high: bool) -> void:
	Game.set_sector(id, sid, to_high)
	Sfx.play("tide_up" if to_high else "tide_down")
	if main:
		main.on_tide_started(sid, to_high)

func _on_tide_finished(sid: String, is_high: bool) -> void:
	if main:
		main.on_tide_finished(sid, is_high)

## Íris está num volume que a maré alta deste setor inundaria?
func player_unsafe(sid: String) -> bool:
	if main == null:
		return false
	var p: Vector3 = main.player.global_position
	for z in unsafe_zones:
		if z["sector"] == sid and Builder.inside(z["poly"], Vector2(p.x, p.z)) and p.y < z["top"]:
			return true
	return false

# --- água e perigo ------------------------------------------------------------------

## Bacia: água do setor entre lo (maré baixa) e hi (maré alta) sobre o polígono.
func add_basin(sid: String, poly: PackedVector2Array, lo: float, hi: float, params: Dictionary = {}) -> Dictionary:
	var p = {"opacity": 0.82, "energy": 0.25, "scale": 1.3}
	p.merge(params, true)
	var mesh = Builder.water(self, poly, hi, p)
	var h = {"poly": poly, "sector": sid, "lo": lo, "hi": hi, "mesh": mesh}
	hazards.append(h)
	unsafe_zones.append({"sector": sid, "poly": poly, "top": hi - 0.3})
	return h

func water_level_at(p: Vector3) -> float:
	for h in hazards:
		if Builder.inside(h["poly"], Vector2(p.x, p.z)):
			return lerpf(h["lo"], h["hi"], sector_level(h["sector"]))
	return -INF

# --- interativos -------------------------------------------------------------------

func add_ix(node: Interactable, pos: Vector3, rot_y: float = 0.0) -> Interactable:
	node.region = self
	node.position = pos
	node.rotation.y = rot_y
	add_child(node)
	interactables.append(node)
	return node

func add_guardian(cfg: Dictionary, zone: PackedVector2Array, zone_top: float, active: Callable) -> Guardian:
	var g = Guardian.new()
	g.setup(cfg)
	add_child(g)
	guardians.append({"guard": g, "zone": zone, "zone_top": zone_top, "active": active})
	return g

func add_floater(sid: String, poly: PackedVector2Array, y_hi: float, y_lo: float, inverted: bool = false) -> Node3D:
	var f = MECH.Floater.new(self, sid, poly, y_hi, y_lo, inverted)
	add_child(f)
	floaters.append(f)
	return f

func add_gate(pos: Vector3, rot_y: float, cond: Callable, size: Vector3 = Vector3(3.0, 3.6, 0.45)) -> Node3D:
	var g = MECH.Gate.new(cond, size)
	g.position = pos
	g.rotation.y = rot_y
	add_child(g)
	gates.append(g)
	return g

func add_bridge(a: Vector3, b: Vector3, width: float, cond: Callable) -> Node3D:
	var br = MECH.LiquidBridge.new(a, b, width, cond)
	add_child(br)
	bridges.append(br)
	return br

func add_mover(points: Array, size: Vector3, powered: Callable, speed: float = 2.0) -> Node3D:
	var m = MECH.Mover.new(points, size, powered, speed)
	add_child(m)
	movers.append(m)
	return m

## Santuário (04_santuario_das_mares, escala s, centro do terraço em `top`,
## entrada voltada para `front`): ponto de chegada na faixa da frente, fonte
## na borda da piscina e portal de volta numa plataforma lateral à escada.
func sanctuary_spawn(top: Vector3, front: Vector3, s: float) -> Vector3:
	return top + front * (2.4 * s)

func sanctuary_fountain(top: Vector3, front: Vector3, s: float) -> Vector3:
	return top + front * (1.5 * s)

func add_front_portal(pid: String, top: Vector3, front: Vector3, side: Vector3, s: float, dest_spawn: String, cond: Callable) -> Interactable:
	var edge = 2.65 * s
	var f0 = 1.6 * s + 0.2
	var f1 = edge + 3.4
	var poly = PackedVector2Array()
	for k in [[-1, f0], [1, f0], [1, f1], [-1, f1]]:
		var p = top + side * (1.7 * s + k[0] * 0.8 * s) + front * k[1]
		poly.append(Vector2(p.x, p.z))
	var cw = (poly[1] - poly[0]).cross(poly[2] - poly[1]) > 0.0
	if not cw:
		poly.reverse()
	Builder.slab(self, poly, top.y, top.y - 0.8, Palette.mat(Palette.CERAMICA), Palette.mat(Palette.PETROLEO))
	var at = top + front * (edge + 1.7) + side * (1.7 * s)
	return add_ix(IX.Portal.new(pid, "farol", dest_spawn, cond), at, atan2(side.x, side.z))

func add_spawn(sid: String, pos: Vector3, yaw: float = PI) -> void:
	spawns[sid] = {"pos": pos, "yaw": yaw}

func add_objective(oid: String, done: Callable, target: Callable) -> void:
	objectives.append({"id": oid, "done": done, "target": target})

func current_objective() -> Dictionary:
	for o in objectives:
		if not o["done"].call():
			return o
	return {}

## Chave de flag com prefixo da região.
func f(key: String) -> String:
	return id + "." + key

func flag(key: String) -> bool:
	return Game.flag(f(key), false)

func set_flag(key: String, v: Variant = true) -> void:
	Game.set_flag(f(key), v)

# --- atualização --------------------------------------------------------------------

func tick(dt: float) -> void:
	t += dt
	for s in sectors.values():
		s.update(dt)
	for h in hazards:
		var mi: MeshInstance3D = h["mesh"]
		mi.position.y = lerpf(h["lo"], h["hi"], sector_level(h["sector"]))
	for fl in floaters:
		fl.update(dt)
	for g in gates:
		g.update(dt)
	for b in bridges:
		b.update(dt)
	for m in movers:
		m.update(dt)
	for a in animated:
		a.call(dt)
	region_tick(dt)

## Ajusta mecanismos instantaneamente (ao carregar).
func settle() -> void:
	for g in gates:
		g.update(0.0, true)
	for b in bridges:
		b.update(0.0, true)
	for fl in floaters:
		fl.update(0.0)
	for h in hazards:
		(h["mesh"] as MeshInstance3D).position.y = lerpf(h["lo"], h["hi"], sector_level(h["sector"]))

# --- utilidades de construção -----------------------------------------------------

func mat_top() -> Material:
	return Palette.mat(Palette.AREIA)

func mat_side() -> Material:
	return Palette.mat(Palette.ROCHA)

func scatter(names: Array, center: Vector3, r_min: float, r_max: float, count: int, y: float, opts: Dictionary = {}) -> void:
	var avoid: Callable = opts.get("avoid", Callable())
	for i in count:
		var a = rng.randf() * TAU
		var r = r_min + rng.randf() * (r_max - r_min)
		var x = center.x + cos(a) * r
		var z = center.z + sin(a) * r
		if avoid.is_valid() and avoid.call(x, z):
			continue
		var n: String = names[rng.randi() % names.size()]
		var h: float = opts.get("h_min", 0.5) + rng.randf() * (opts.get("h_max", 1.2) - opts.get("h_min", 0.5))
		Builder.prop(self, n, Vector3(x, y, z), {"height": h, "tone": opts.get("tone", "rocha"), "variant": rng.randi() % 3, "rot": rng.randf() * TAU})
