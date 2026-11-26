extends RefCounted
## Mecanismos do mundo controlados por condição/maré.
## Uso: const MECH := preload("res://scripts/world/mech.gd")


## Portão/porta que desce quando a condição é verdadeira.
class Gate extends Node3D:
	var cond: Callable
	var door: AnimatableBody3D
	var open_t = 0.0
	var height = 3.6
	var glyph_mat: StandardMaterial3D

	func _init(condition: Callable, size: Vector3 = Vector3(3.0, 3.6, 0.45), mat: Material = null) -> void:
		cond = condition
		height = size.y
		door = AnimatableBody3D.new()
		door.sync_to_physics = false
		var mi = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = size
		mi.mesh = box
		mi.material_override = mat if mat else Palette.mat(Palette.CERAMICA)
		mi.position.y = size.y / 2
		door.add_child(mi)
		var glyph = MeshInstance3D.new()
		var tm = Interactable.ring_mesh(0.5, 0.08)
		glyph.mesh = tm
		glyph_mat = Interactable.glow_mat(Palette.SAL, 0.6)
		glyph.material_override = glyph_mat
		glyph.rotation.x = PI / 2
		glyph.position = Vector3(0, size.y * 0.55, size.z / 2 + 0.02)
		door.add_child(glyph)
		var cs = CollisionShape3D.new()
		var sh = BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position.y = size.y / 2
		door.add_child(cs)
		add_child(door)

	var is_open: bool:
		get: return cond.call()

	func update(dt: float, instant: bool = false) -> void:
		var target = 1.0 if cond.call() else 0.0
		var was = open_t
		open_t = target if instant else move_toward(open_t, target, dt / 1.6)
		if was < 0.01 and open_t >= 0.01:
			Sfx.play("door")
		door.position.y = -open_t * (height + 0.2)
		glyph_mat.emission = Palette.RESSONANCIA if target > 0.5 else Palette.SAL
		glyph_mat.albedo_color = glyph_mat.emission
		door.get_child(2).disabled = open_t > 0.6


## Plataforma de flutuação: sobe com a maré do setor (ou desce, se invertida).
class Floater extends AnimatableBody3D:
	var sector: String
	var hi = 0.0
	var lo = -7.0
	var inverted = false
	var phase = 0.0
	var region: Node
	## opcional: enquanto falso, a plataforma fica presa no fundo
	var gate: Callable

	func _init(r: Node, sector_id: String, poly: PackedVector2Array, y_hi: float, y_lo: float, inv: bool = false) -> void:
		region = r
		sector = sector_id
		hi = y_hi
		lo = y_lo
		inverted = inv
		sync_to_physics = true
		phase = randf() * TAU
		var c = Builder.centroid(poly)
		var local = PackedVector2Array()
		for p in poly:
			local.append(p - c)
		position = Vector3(c.x, y_hi, c.y)
		var mi = MeshInstance3D.new()
		mi.mesh = Builder.prism_mesh(local, 0.0, -0.5, Palette.mat(Palette.AREIA_CLARA), Palette.mat(Palette.ROCHA))
		add_child(mi)
		var root = MeshInstance3D.new()
		var rr = 0.0
		for p in local:
			rr = maxf(rr, p.length())
		root.mesh = Builder.root_mesh(rr * 0.9, 1.4, 6, int(c.x * 13 + c.y * 7), Palette.mat(Palette.ROCHA_ESCURA))
		root.position.y = -0.5
		add_child(root)
		var glow = MeshInstance3D.new()
		var disc = CylinderMesh.new()
		disc.top_radius = rr * 0.6
		disc.bottom_radius = rr * 0.6
		disc.height = 0.02
		glow.mesh = disc
		glow.material_override = Palette.glow(1.2)
		glow.position.y = -1.95
		add_child(glow)
		var shape = ConvexPolygonShape3D.new()
		var pts = PackedVector3Array()
		for p in local:
			pts.append(Vector3(p.x, 0.0, p.y))
			pts.append(Vector3(p.x, -0.5, p.y))
		shape.points = pts
		var cs = CollisionShape3D.new()
		cs.shape = shape
		add_child(cs)

	func update(_dt: float) -> void:
		var lv: float = region.sector_level(sector)
		if inverted:
			lv = 1.0 - lv
		if gate.is_valid() and not gate.call():
			lv = 0.0
		var y = lerpf(lo, hi, pow(lv, 1.4)) + sin(Time.get_ticks_msec() * 0.0009 + phase) * 0.05 * lv
		position.y = y


## Ponte líquida: atravessável quando a condição (maré + energia) vale.
class LiquidBridge extends StaticBody3D:
	var cond: Callable
	var level = 0.0
	var water: MeshInstance3D
	var cs: CollisionShape3D

	func _init(a: Vector3, b: Vector3, width: float, condition: Callable) -> void:
		cond = condition
		var d = b - a
		var length = Vector2(d.x, d.z).length()
		position = (a + b) / 2
		rotation.y = atan2(d.x, d.z)
		var box = BoxMesh.new()
		box.size = Vector3(width, 0.8, length)
		water = MeshInstance3D.new()
		water.mesh = box
		water.material_override = Builder.water_material({"opacity": 0.9, "energy": 0.6, "scale": 1.2, "flow": Vector2(0, -0.8), "deep": Color("#1C7F86"), "shallow": Color("#3DB8B0"), "wave": 0.0})
		water.position.y = -0.42
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(water)
		cs = CollisionShape3D.new()
		var sh = BoxShape3D.new()
		sh.size = Vector3(width, 0.8, length)
		cs.shape = sh
		cs.position.y = -0.42
		add_child(cs)

	func update(dt: float, instant: bool = false) -> void:
		var target = 1.0 if cond.call() else 0.0
		level = target if instant else lerpf(level, target, 1.0 - exp(-3 * dt))
		water.visible = level > 0.02
		water.scale = Vector3(minf(1.0, level * 1.4), maxf(0.02, level), 1.0)
		water.position.y = -0.42 - (1.0 - level) * 0.6
		cs.disabled = level < 0.75


## Plataforma que viaja entre pontos quando energizada (elevador, bonde).
class Mover extends AnimatableBody3D:
	var points: Array = []
	var powered: Callable
	var speed = 2.0
	var wait = 3.0
	var _i = 0
	var _dir = 1
	var _wait = 0.0

	func _init(pts: Array, size: Vector3, power: Callable, spd: float = 2.0, mat: Material = null) -> void:
		points = pts
		powered = power
		speed = spd
		sync_to_physics = true
		position = pts[0]
		var mi = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = size
		mi.mesh = box
		mi.material_override = mat if mat else Palette.mat(Palette.CERAMICA)
		mi.position.y = -size.y / 2
		add_child(mi)
		var edge = MeshInstance3D.new()
		var em = BoxMesh.new()
		em.size = Vector3(size.x + 0.06, 0.06, size.z + 0.06)
		edge.mesh = em
		edge.material_override = Palette.copper()
		edge.position.y = -0.03
		add_child(edge)
		var cs = CollisionShape3D.new()
		var sh = BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position.y = -size.y / 2
		add_child(cs)
		add_to_group("mover")

	func update(dt: float) -> void:
		if not powered.call() or points.size() < 2:
			return
		if _wait > 0.0:
			_wait -= dt
			return
		var nxt = _i + _dir
		var goal: Vector3 = points[nxt]
		var to = goal - position
		var step = speed * dt
		if to.length() <= step:
			position = goal
			_i = nxt
			if _i == points.size() - 1 or _i == 0:
				_dir = -_dir
			_wait = wait
		else:
			position += to.normalized() * step
