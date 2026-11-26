extends Region
## Cidade Invertida — bairros pendurados de cabeça para baixo sob placas
## flutuantes. Ensina o Relé remoto e combina maré + energia + furtividade.
##
## Fluxo: Praça do Relógio (Terminal → relé do elevador) → Mercado Caído (rede
## de condutores até a porta) → Praça Alagada (maré baixa: comporta; maré alta:
## plataformas até a varanda; da varanda, relé do portão) → Rua dos Guardiões
## (maré baixa, dois guardiões, dois pilões de curto alcance) → Santuário 2.
## Opcionais: bonde (relé) e torre pendurada (descer e voltar de elevador).

const P0 = Vector3(0, 0, 30)       # Praça do Relógio (chegada)
const P1 = Vector3(0, -8, 7.6)     # Mercado Caído
const P2 = Vector3(0, -8, -24)     # Praça Alagada
const P3 = Vector3(-30, -8, -24)   # Rua dos Guardiões
const SANCT_Y = -4.0
const SANCT_SOUTH = -44.4          # borda sul do terraço do santuário
const S_SCALE = 2.0
const TWIN_REACH = 6.5

var conductors: Array = []
var strips: Array = []
var pylons_street: Array = []
var guards: Array = []
var fountain = Vector3.ZERO
var sanct_center = Vector3.ZERO
var heart: Node3D
var ring_mesh: MeshInstance3D
var back_portal: Interactable

func build() -> void:
	music = "cidade"
	env = {"preset": "cidade", "center": Vector3(-8, -6, 2), "distant": "#4A3E5C",
		"creatures": [["whale", 9.0, 110, 160, -2, 26], ["manta", 3.0, 50, 80, -20, -6], ["dolphin", 2.2, 40, 60, -16, -4]]}
	kill_y = -32.0
	Game.set_flag("cidade.visited")
	add_sector("cidade", true)
	_plaza_clock()
	_market()
	_flooded_plaza()
	_street()
	_sanctuary()
	_hanging_city()
	_objectives()

# --- utilidades ------------------------------------------------------------------

func _stone_top() -> Material:
	return Palette.mat(Color("#CDB48E"))

func _stone_side() -> Material:
	return Palette.mat(Color("#8C7A66"))

## Placa da cidade (calçada com meio-fio de cerâmica).
func _plate(center: Vector3, r: float, seed: int) -> PackedVector2Array:
	var outline = Builder.octagon(r, center.x, center.z)
	Builder.island(self, outline, [outline], center.y, 1.2, seed, {"top": _stone_top(), "side": _stone_side(), "root_depth": 0.1, "root": _stone_side()})
	_curb(outline, center.y)
	return outline

func _curb(outline: PackedVector2Array, y: float) -> void:
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		var mid = (a + b) * 0.5
		var dir = b - a
		var mi = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(dir.length(), 0.16, 0.28)
		mi.mesh = box
		mi.material_override = Palette.mat(Palette.CERAMICA)
		mi.position = Vector3(mid.x, y + 0.08, mid.y)
		mi.rotation.y = -atan2(dir.y, dir.x)
		add_child(mi)

## Prédio de cabeça para baixo (pende a partir de `at`).
func _hang(model: String, at: Vector3, height: float, rot: float = 0.0) -> Node3D:
	var p = Props.make(model, {"height": height})
	p.position = at
	p.rotation = Vector3(PI, rot, 0)
	add_child(p)
	return p

func _walk(poly: PackedVector2Array, y: float) -> void:
	Builder.slab(self, poly, y, y - 0.8, Palette.mat(Palette.CERAMICA), Palette.mat(Palette.PETROLEO))

func _rock(pos: Vector3, r: float, seed: int) -> void:
	var poly = Builder.octagon(r, pos.x, pos.z)
	Builder.island(self, poly, [poly], pos.y, 0.8, seed, {"top": _stone_top(), "side": _stone_side()})

# --- P0: Praça do Relógio ----------------------------------------------------------

func _plaza_clock() -> void:
	_plate(P0, 10.0, 101)
	add_spawn("portal", P0 + Vector3(0, 0, 4.5), PI)
	add_ix(IX.Portal.new("portal_volta", "farol", "portal_cidade", _always), P0 + Vector3(-5.2, 0, 5.6), PI / 2)
	add_ix(IX.Pedestal.new("terminal", "relay", true), P0 + Vector3(5.0, 0, 1.0))
	Builder.prop(self, "bell_tower", P0 + Vector3(-6.0, 0, 2.5), {"height": 7.5, "collide": 1.5, "rot": 0.3})
	Builder.prop(self, "streetlight2", P0 + Vector3(4.0, 0, 6.0), {"height": 3.2})
	Builder.prop(self, "streetlight", P0 + Vector3(-3.5, 0, -6.0), {"height": 3.0})
	Builder.prop(self, "streetlight", P0 + Vector3(3.5, 0, -6.0), {"height": 3.0})
	Builder.prop(self, "bench", P0 + Vector3(2.6, 0, 7.6), {"height": 0.7, "rot": PI})
	Builder.prop(self, "well", P0 + Vector3(1.5, 0, -1.5), {"height": 1.8, "collide": 0.9})
	# elevador até o Mercado Caído: relé na rocha a oeste (ou alavanca lá embaixo)
	add_mover([Vector3(0, 0, 19.3), Vector3(0, -8, 19.3)], Vector3(3.0, 0.4, 3.0), _lift_powered, 2.0)
	_rock(Vector3(-15, 3.0, 22), 2.0, 131)
	add_ix(IX.RelayPylon.new("rele_elevador", _on_lift_relay), Vector3(-15, 3.0, 22))
	for sx in [-1.9, 1.9]:
		Builder.prop(self, "support", Vector3(sx, 0, 20.9), {"height": 3.4, "collide": 0.25})
	# bonde (opcional): relé na borda leste liga a gôndola até a placa do eco
	add_ix(IX.RelayPylon.new("rele_bonde", _on_tram_relay), P0 + Vector3(8.0, 0, -3.4))
	add_mover([P0 + Vector3(10.6, 0, 3.0), Vector3(32, 0, 34)], Vector3(2.6, 0.35, 2.6), _tram_powered, 2.6)
	_plate(Vector3(37, 0, 36), 4.0, 141)
	add_ix(IX.Echo.new("cidade_bonde"), Vector3(37, 0.6, 36.5))
	Builder.prop(self, "streetlight", Vector3(38.6, 0, 34.2), {"height": 3.0})
	Builder.prop(self, "bench", Vector3(35.6, 0, 38.8), {"height": 0.7, "rot": 0.4})
	# o bairro pendurado sob a praça
	_hang("bld_4story", P0 + Vector3(-5.0, -1.2, -1.0), 10.0, 0.2)
	_hang("bld_3story_slim", P0 + Vector3(0.5, -1.2, 2.0), 8.0, 1.7)
	_hang("bld_balcony", P0 + Vector3(5.5, -1.2, 0.0), 9.0, -0.4)

func _always() -> bool:
	return true

func _lift_powered() -> bool:
	return flag("elevator") or flag("lift_call")

func _tram_powered() -> bool:
	return flag("tram")

func _on_lift_relay(_p: Interactable) -> void:
	set_flag("elevator")
	Sfx.play("door_tech")

func _on_tram_relay(_p: Interactable) -> void:
	set_flag("tram")

func _on_lift_lever(_l: Interactable) -> void:
	set_flag("lift_call")

# --- P1: Mercado Caído (rede de condutores) ---------------------------------------

func _market() -> void:
	_plate(P1, 11.0, 151)
	add_spawn("mercado", P1 + Vector3(0, 0, 8.4), PI)
	checkpoints.append({"id": "mercado", "pos": P1 + Vector3(0, 0, 8.4), "radius": 2.4})
	add_ix(IX.Lever.new("chamar_elevador", _on_lift_lever), P1 + Vector3(2.6, 0, 9.4), PI)
	for m in [["market1", Vector3(-7.0, 0, 4.0), 0.4, 2.2], ["market2", Vector3(7.5, 0, 5.0), -0.5, 2.2], ["cart", Vector3(-7.6, 0, -1.6), 1.2, 1.3],
			["crate", Vector3(6.4, 0, -6.4), 0.2, 0.9], ["barrel", Vector3(7.4, 0, -5.4), 0.0, 1.0], ["barrel", Vector3(-3.0, 0, 7.2), 0.0, 1.0]]:
		Builder.prop(self, m[0], P1 + m[1], {"height": m[3], "rot": m[2], "collide": true})
	add_ix(IX.Echo.new("cidade_mercado"), P1 + Vector3(-5.0, 0.6, 7.6))
	# fonte de energia → C1 → C2 → C3 → porta sul
	var src = Props.make("vessel_tall", {"height": 2.6})
	src.position = P1 + Vector3(-8.6, 0, -4.4)
	add_child(src)
	var orb = MeshInstance3D.new()
	var sm = SphereMesh.new()
	sm.radius = 0.4
	sm.height = 0.8
	orb.mesh = sm
	orb.material_override = Palette.glow(2.2)
	orb.position = src.position + Vector3(0, 3.0, 0)
	add_child(orb)
	var nodes = [src.position, P1 + Vector3(-4.6, 0, -2.0), P1 + Vector3(0, 0, -5.4), P1 + Vector3(4.6, 0, -2.0), P1 + Vector3(0, 0, -9.9)]
	for i in nodes.size() - 1:
		var a: Vector3 = nodes[i]
		var b: Vector3 = nodes[i + 1]
		var mi = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.24, 0.05, Vector2(b.x - a.x, b.z - a.z).length())
		mi.mesh = box
		var m = Palette.unique(Color("#6A4A2E"), {"emission": Palette.COBRE, "energy": 0.15})
		mi.material_override = m
		mi.position = (a + b) * 0.5 + Vector3(0, 0.03, 0)
		mi.rotation.y = atan2(b.x - a.x, b.z - a.z)
		add_child(mi)
		strips.append(m)
	for i in 3:
		var c = add_ix(IX.Conductor.new("juncao_%d" % i, i + 1, Callable(), "90" if i == 1 else "t"), nodes[i + 1])
		c.on_change = _on_network
		conductors.append(c)
	# porta sul e ponte para a Praça Alagada
	var door_z = P1.z - 11.0 * cos(PI / 8)
	add_gate(Vector3(0, P1.y, door_z - 0.3), 0.0, _network_ok)
	for sx in [-2.05, 2.05]:
		Builder.prop(self, "tech_column", Vector3(sx, P1.y, door_z - 0.3), {"height": 4.0, "collide": 0.55})
	_walk(Builder.rect(-1.5, P2.z + 12.0 * cos(PI / 8) - 0.6, 1.5, door_z + 0.2), P1.y)
	_hang("bld_columns", P1 + Vector3(-4.0, -1.2, 0.0), 9.0, 0.5)
	_hang("bld_round", P1 + Vector3(4.0, -1.2, 3.0), 8.0, 2.0)
	# torre pendurada (opcional): descer até a base e voltar de elevador
	var east = P1.x + 11.0 * cos(PI / 8)
	_walk(Builder.rect(east - 0.3, 8.6, 14.1, 11.4), P1.y)
	_plate(Vector3(18, -14, 10), 3.0, 161)
	add_ix(IX.Echo.new("cidade_torre"), Vector3(18.6, -13.4, 11.0))
	_hang("bld_6story", Vector3(18, -15.2, 10), 14.0, 0.4)
	add_ix(IX.RelayPylon.new("rele_torre", _on_tower_relay), Vector3(19.6, -14, 8.2))
	add_mover([Vector3(15.0, -14, 10), Vector3(15.0, -8, 10)], Vector3(2.2, 0.35, 2.2), _tower_powered, 2.0)

func _on_tower_relay(_p: Interactable) -> void:
	set_flag("tower_lift")

func _tower_powered() -> bool:
	return flag("tower_lift")

func _aligned_upto(n: int) -> bool:
	for i in n:
		if not conductors[i].aligned:
			return false
	return true

func _network_ok() -> bool:
	return conductors.size() == 3 and _aligned_upto(3)

func _on_network(_c: Interactable) -> void:
	if _network_ok():
		Sfx.play("unlock")
		main.say("lume.network_ok", 4.0)

# --- P2: Praça Alagada --------------------------------------------------------------

func _flooded_plaza() -> void:
	var outer = Builder.octagon(12.0, P2.x, P2.z)
	var inner = Builder.octagon(7.0, P2.x, P2.z)
	Builder.island(self, outer, Builder.ring(outer, inner), P2.y, 3.0, 171, {"top": _stone_top(), "side": _stone_side(), "root_depth": 0.1})
	_curb(outer, P2.y)
	Builder.slab(self, inner, P2.y - 2.5, P2.y - 3.0, Palette.mat(Color("#9C8A70")), Palette.mat(Palette.ROCHA_ESCURA))
	add_basin("cidade", inner, P2.y - 3.2, P2.y - 0.3)
	var ap = 7.0 * cos(PI / 8)
	Builder.stairs(self, Vector3(P2.x, P2.y, P2.z + ap + 0.05), Vector3(P2.x, P2.y - 2.5, P2.z + ap - 2.8), 2.2, 6, Palette.mat(Palette.AREIA_CLARA), Palette.mat(Palette.CERAMICA))
	add_ix(IX.TideNode.new("no_praca", ["cidade"]), P2 + Vector3(-4.0, 0, 9.6))
	add_ix(IX.Lever.new("comporta", _on_dock), P2 + Vector3(-2.4, -2.5, -3.4), PI)
	add_ix(IX.Echo.new("cidade_praca", _plaza_dry), P2 + Vector3(2.8, -2.1, 3.4))
	for d in [[-4.0, -2.0, 1.1], [1.0, -5.0, 0.9]]:
		Builder.prop(self, "barrel", P2 + Vector3(d[0], -2.5, d[1]), {"height": d[2], "collide": true})
	# plataformas presas no fundo até a comporta abrir; sobem com a maré alta
	var steps = [[4.4, 3.0, 0.8], [4.4, 0.4, 1.6], [4.4, -2.2, 2.4]]
	for s in steps:
		var fl = add_floater("cidade", Builder.ngon(1.1, 6, P2.x + s[0], P2.z + s[1], PI / 6), P2.y + s[2], P2.y - 2.4)
		fl.gate = _dock_open
	# varanda sobre o anel leste (alcançável só pelas plataformas)
	var balcony = Builder.rect(P2.x + 6.0, P2.z - 6.0, P2.x + 10.6, P2.z - 2.6)
	Builder.slab(self, balcony, P2.y + 3.2, P2.y + 2.7, Palette.mat(Palette.CERAMICA), Palette.mat(Palette.PETROLEO))
	for c in [Vector2(10.3, -5.7), Vector2(10.3, -2.9)]:
		Builder.prop(self, "support_long", Vector3(P2.x + c.x, P2.y, P2.z + c.y), {"height": 2.7, "collide": 0.2})
	Builder.slab(self, Builder.rect(P2.x + 10.4, P2.z - 6.0, P2.x + 10.6, P2.z - 2.6), P2.y + 4.0, P2.y + 3.2, Palette.mat(Palette.CERAMICA), Palette.mat(Palette.CERAMICA))
	add_ix(IX.Echo.new("cidade_varanda"), Vector3(P2.x + 9.6, P2.y + 3.8, P2.z - 5.2))
	Builder.prop(self, "lamp_city", Vector3(P2.x + 6.4, P2.y + 3.2, P2.z - 5.6), {"height": 2.4})
	# fachada com janela: o pilão do portão só é visto da altura da varanda
	var wx = P2.x + 13.4
	var wall_top = Palette.mat(Palette.CERAMICA)
	var wall_side = Palette.mat(Color("#A89070"))
	Builder.slab(self, Builder.rect(wx, P2.z - 16.0, wx + 0.5, P2.z + 6.0), P2.y + 3.4, P2.y - 4.0, wall_top, wall_side)
	Builder.slab(self, Builder.rect(wx, P2.z - 16.0, wx + 0.5, P2.z - 7.0), P2.y + 8.0, P2.y + 3.4, wall_top, wall_side)
	Builder.slab(self, Builder.rect(wx, P2.z - 2.0, wx + 0.5, P2.z + 6.0), P2.y + 8.0, P2.y + 3.4, wall_top, wall_side)
	Builder.slab(self, Builder.rect(wx, P2.z - 7.0, wx + 0.5, P2.z - 2.0), P2.y + 8.0, P2.y + 5.4, wall_top, wall_side)
	_hang("bld_4story_center", Vector3(wx + 3.0, P2.y + 20.0, P2.z - 5.0), 12.0, PI / 2)
	_rock(Vector3(P2.x + 17.0, P2.y + 1.8, P2.z - 4.5), 1.6, 181)
	add_ix(IX.RelayPylon.new("rele_portao", _on_gate_relay), Vector3(P2.x + 17.0, P2.y + 1.8, P2.z - 4.5))
	# portão oeste para a Rua dos Guardiões
	var west = P2.x - 12.0 * cos(PI / 8)
	add_gate(Vector3(west + 0.3, P2.y, P2.z), PI / 2, _gate_open)
	for sz in [-2.05, 2.05]:
		Builder.prop(self, "tech_column", Vector3(west + 0.3, P2.y, P2.z + sz), {"height": 4.0, "collide": 0.55})
	_walk(Builder.rect(P3.x + 8.3, P2.z - 1.5, west + 0.6, P2.z + 1.5), P2.y)
	_hang("bld_gable", P2 + Vector3(-3.0, -3.2, 2.0), 9.0, 0.7)
	_hang("bld_2story_wide", P2 + Vector3(3.0, -3.2, -2.0), 8.0, 2.4)

func _plaza_dry() -> bool:
	return sector_level("cidade") < 0.3

func _dock_open() -> bool:
	return flag("dock")

func _gate_open() -> bool:
	return flag("gate")

func _on_dock(_l: Interactable) -> void:
	set_flag("dock")
	main.say("lume.sluice_open", 4.0)

func _on_gate_relay(_p: Interactable) -> void:
	set_flag("gate")
	Sfx.play("door_tech")

# --- P3: Rua dos Guardiões (guardiões gêmeos) ---------------------------------------

func _street() -> void:
	var x0 = P3.x - 6.0
	var x1 = P3.x + 6.0
	var z0 = P3.z - 12.0
	var z1 = P3.z + 12.0
	var street = Builder.rect(x0, z0, x1, z1)
	var facade_top = Palette.mat(Palette.CERAMICA)
	var facade_side = Palette.mat(Color("#A89070"))
	# calçada leste (entrada) e sul (saída); fachadas a oeste e ao norte
	Builder.slab(self, Builder.rect(x1, z0 - 2.5, x1 + 2.5, z1 + 2.5), P3.y, P3.y - 3.0, _stone_top(), _stone_side())
	Builder.slab(self, Builder.rect(x0 - 2.5, z0 - 2.5, x1, z0), P3.y, P3.y - 3.0, _stone_top(), _stone_side())
	Builder.slab(self, Builder.rect(x0 - 0.6, z0, x0, z1 + 0.6), P3.y + 6.0, P3.y - 3.0, facade_top, facade_side)
	Builder.slab(self, Builder.rect(x0, z1, x1, z1 + 0.6), P3.y + 6.0, P3.y - 3.0, facade_top, facade_side)
	Builder.slab(self, street, P3.y - 2.0, P3.y - 3.0, Palette.mat(Color("#9C8A70")), Palette.mat(Palette.ROCHA_ESCURA))
	add_basin("cidade", street, P3.y - 2.7, P3.y - 0.4)
	var facades = ["bld_3story", "bld_2story", "bld_4story", "bld_gable"]
	for i in 4:
		_hang(facades[i], Vector3(x0 - 3.0, P3.y + 15.0, z0 + 3.0 + i * 6.0), 9.0, PI / 2)
	Builder.stairs(self, Vector3(x1 + 0.02, P3.y, P3.z + 4.0), Vector3(x1 - 2.8, P3.y - 2.0, P3.z + 4.0), 2.2, 5, Palette.mat(Palette.AREIA_CLARA), Palette.mat(Palette.CERAMICA))
	Builder.stairs(self, Vector3(P3.x, P3.y - 2.0, z0 + 3.0), Vector3(P3.x, P3.y, z0 + 0.02), 2.2, 5, Palette.mat(Palette.AREIA_CLARA), Palette.mat(Palette.CERAMICA))
	var entry = Vector3(x1 + 1.4, P3.y, P3.z + 1.2)
	add_spawn("rua", entry, -PI / 2)
	checkpoints.append({"id": "rua", "pos": entry, "radius": 1.8})
	# bancas: cobertura que bloqueia a visão
	for c in [[-2.4, 7.0, "market1"], [2.8, 8.6, "market2"], [-2.8, -1.6, "market2"], [2.2, -6.4, "market1"], [-1.0, 10.4, "cart"]]:
		Builder.prop(self, c[2], Vector3(P3.x + c[0], P3.y - 2.0, P3.z + c[1]), {"height": 2.3 if c[2] != "cart" else 1.4, "collide": 1.2, "cover": true, "rot": c[1] * 0.3})
	# dois guardiões, patrulhas cruzadas e mais rápidas
	var paths = [[[-3.5, 10.0], [3.5, 10.0], [3.5, 1.0], [-3.5, 1.0]], [[3.5, -10.0], [-3.5, -10.0], [-3.5, -1.0], [3.5, -1.0]]]
	var perches = [Vector3(x1 + 1.4, P3.y, P3.z + 9.0), Vector3(x1 + 1.4, P3.y, P3.z - 9.0)]
	for i in 2:
		var wp = []
		for w in paths[i]:
			wp.append(Vector3(P3.x + w[0], P3.y - 2.0, P3.z + w[1]))
		var g = add_guardian({"waypoints": wp, "perch": perches[i], "floor_y": P3.y - 2.0,
			"params": {"patrol_speed": 2.4, "chase_speed": 4.4, "vision_range": 7.5}}, street, P3.y - 0.8, _twins_active)
		guardians[-1]["exit"] = entry
		guards.append(g)
		if flag("twins"):
			g.pacify()
	# pilões de curto alcance contra a fachada oeste
	for i in 2:
		var pos = Vector3(x0 + 1.4, P3.y - 2.0, P3.z + (8.5 if i == 0 else -5.0))
		var py = add_ix(IX.RelayPylon.new("rele_rua_%d" % i, _on_twin_pylon), pos)
		py.reach = TWIN_REACH
		py.radius = TWIN_REACH
		pylons_street.append(py)
	add_gate(Vector3(P3.x, P3.y, z0 - 2.2), 0.0, _twins_done)
	for sx in [-2.05, 2.05]:
		Builder.prop(self, "tech_column", Vector3(P3.x + sx, P3.y, z0 - 2.2), {"height": 4.0, "collide": 0.55})

func _twins_active() -> bool:
	return not high("cidade") and not flag("twins")

func _twins_done() -> bool:
	return flag("twins")

func _on_twin_pylon(_p: Interactable) -> void:
	var on = 0
	for p in pylons_street:
		if p.active:
			on += 1
	if on >= 2:
		set_flag("twins")
		for g in guards:
			g.pacify()
		Sfx.play("pacify")
		main.say("lume.pacified", 4.5)
	else:
		main.say("lume.twins", 3.5)

# --- Santuário 2 --------------------------------------------------------------------

func _sanctuary() -> void:
	var model = Props.original("04_santuario_das_mares.glb")
	model.scale = Vector3.ONE * S_SCALE
	model.position = Vector3(P3.x, SANCT_Y - 0.15 * S_SCALE, SANCT_SOUTH - 6.0)
	add_child(model)
	# alinha a borda sul do terraço com SANCT_SOUTH
	var zs = -INF
	for mi in model.find_children("terrace*", "MeshInstance3D", true, false):
		var m = mi as MeshInstance3D
		var arr = m.mesh.surface_get_arrays(0)
		for v in arr[Mesh.ARRAY_VERTEX]:
			var w: Vector3 = m.global_transform * v
			if absf(w.x - P3.x) < 1.0:
				zs = maxf(zs, w.z)
	if zs > -INF:
		model.position.z += SANCT_SOUTH - zs
	sanct_center = model.position + Vector3(0, 0.15 * S_SCALE, 0)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		IrisRig._tune_material(mi)
		if mi.name.begins_with("heart"):
			heart = mi
		elif mi.name.begins_with("energy_ring"):
			ring_mesh = mi
	collide_model(model, ["island_root", "pool_water", "energy_ring", "heart", "portal_inner", "cap_"])
	var z0 = P3.z - 12.0
	Builder.stairs(self, Vector3(P3.x, P3.y, z0 - 2.6), Vector3(P3.x, SANCT_Y, SANCT_SOUTH + 0.02), 2.4, 8, Palette.mat(Palette.AREIA_CLARA), Palette.mat(Palette.CERAMICA))
	var s_spawn = sanctuary_spawn(sanct_center, Vector3(0, 0, 1), S_SCALE)
	fountain = sanctuary_fountain(sanct_center, Vector3(0, 0, 1), S_SCALE)
	add_spawn("santuario", s_spawn + Vector3(0, 0.1, 0), PI)
	checkpoints.append({"id": "santuario", "pos": s_spawn, "radius": 3.0})
	add_ix(IX.Action.new("fonte", _fountain_prompt, _fountain_act, 2.4, "scan.sanctuary"), fountain)
	back_portal = add_front_portal("portal_santuario", sanct_center, Vector3(0, 0, 1), Vector3(-1, 0, 0), S_SCALE, "portal_cidade", _rested)
	animated.append(_anim_sanctuary)

func _rested() -> bool:
	return flag("rested")

func _anim_sanctuary(dt: float) -> void:
	var woke = "cidade" in Game.state["memories"]
	if heart:
		heart.visible = not woke
	if ring_mesh:
		ring_mesh.rotation.z += dt * (0.4 if woke else 0.05)
		var m = ring_mesh.get_active_material(0) as StandardMaterial3D
		if m:
			m.emission_energy_multiplier = 2.2 if woke else 0.3

func _fountain_prompt(_ctx: Dictionary) -> Dictionary:
	if not flag("twins"):
		return {}
	if not ("cidade" in Game.state["memories"]):
		return {"text": I18n.t("prompt.ring"), "action": "interact"}
	if not flag("rested"):
		return {"text": I18n.t("prompt.rest"), "action": "interact"}
	return {}

func _fountain_act(_ctx: Dictionary) -> void:
	if not ("cidade" in Game.state["memories"]):
		main.on_memory("cidade")
		main.say("lume.portal_new", 5.0)
	elif not flag("rested"):
		set_flag("rested")
		main.rest_at("santuario")

# --- cidade pendurada (cenário) -----------------------------------------------------

func _hanging_city() -> void:
	var models = ["bld_2story", "bld_2story_wide", "bld_3story", "bld_4story", "bld_round", "bld_columns", "bld_gable", "bld_6story", "bld_1story"]
	var r2 = RandomNumberGenerator.new()
	r2.seed = 404
	# torres sob a cidade, longe das áreas jogáveis
	var placed = 0
	var tries = 0
	while placed < 26 and tries < 200:
		tries += 1
		var a = r2.randf() * TAU
		var r = r2.randf_range(24, 70)
		var at = Vector3(cos(a) * r - 8, r2.randf_range(-26, -16), sin(a) * r)
		if _near_play(at, 6.0):
			continue
		_hang(models[r2.randi() % models.size()], at, r2.randf_range(8, 16), r2.randf() * TAU)
		placed += 1
	# tetos: placas invertidas acima, com prédios pendendo em direção a Íris
	for c in [Vector3(-14, 22, 12), Vector3(16, 26, -10), Vector3(-36, 24, -30), Vector3(10, 30, 40), Vector3(-30, 28, 30)]:
		var ceil_poly = Builder.octagon(9.0, c.x, c.z)
		var mi = MeshInstance3D.new()
		mi.mesh = Builder.prism_mesh(ceil_poly, c.y + 1.2, c.y, _stone_side(), Palette.mat(Color("#6E5E50")), true)
		add_child(mi)
		for k in 4:
			var off = Vector3(r2.randf_range(-5, 5), 0, r2.randf_range(-5, 5))
			_hang(models[r2.randi() % models.size()], c + off, r2.randf_range(6, 11), r2.randf() * TAU)
	# lanternas flutuantes (luz quente da cidade)
	for i in 16:
		var at = Vector3(r2.randf_range(-44, 40), r2.randf_range(-4, 10), r2.randf_range(-56, 44))
		if _near_play(at, 3.0):
			continue
		var lamp = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = 0.35
		sm.height = 0.7
		sm.radial_segments = 6
		sm.rings = 3
		lamp.mesh = sm
		lamp.material_override = Palette.glow(2.0, Palette.COBRE)
		lamp.position = at
		add_child(lamp)

## Ponto perto (no plano) de uma área jogável.
func _near_play(p: Vector3, margin: float) -> bool:
	var areas = [[P0, 10.0], [P1, 11.0], [P2, 14.0], [Vector3(P3.x, 0, P3.z - 8), 18.0], [Vector3(18, 0, 10), 4.0], [Vector3(37, 0, 36), 4.0], [Vector3(22, 0, 33), 12.0], [Vector3(-15, 0, 22), 3.0]]
	for c in areas:
		var ctr: Vector3 = c[0]
		if Vector2(p.x - ctr.x, p.z - ctr.z).length() < float(c[1]) + margin:
			return true
	return false

# --- objetivos e lógica ---------------------------------------------------------------

func _objectives() -> void:
	add_objective("c_terminal", func(): return Game.has_ability("relay"), func(): return P0 + Vector3(5.0, 0, 1.0))
	add_objective("c_elevator", func(): return _lift_powered() or flag("market"), func(): return Vector3(-15, 3, 22))
	add_objective("c_ride", func(): return flag("market"), func(): return Vector3(0, -8, 19.3))
	add_objective("c_network", func(): return _network_ok(), func(): return _next_conductor())
	add_objective("c_plaza_low", func(): return flag("dock"), func(): return P2 + Vector3(-2.4, -2.5, -3.4))
	add_objective("c_plaza_high", func(): return flag("balcony") or flag("gate"), func(): return Vector3(P2.x + 8.0, P2.y + 3.2, P2.z - 4.3))
	add_objective("c_gate_relay", func(): return flag("gate"), func(): return Vector3(P2.x + 17.0, P2.y + 1.8, P2.z - 4.5))
	add_objective("c_twins", func(): return flag("twins"), func(): return _next_twin())
	add_objective("c_sanct", func(): return "cidade" in Game.state["memories"], func(): return fountain)
	add_objective("c_rest", func(): return flag("rested"), func(): return fountain)
	add_objective("c_done", func(): return false, func(): return back_portal.global_position)

func _next_conductor() -> Vector3:
	for c in conductors:
		if not c.aligned:
			return c.global_position
	return P1 + Vector3(0, 0, -9.9)

func _next_twin() -> Vector3:
	for p in pylons_street:
		if not p.active:
			return p.global_position
	return P3

func region_tick(_dt: float) -> void:
	var p: Vector3 = main.player.global_position
	# trilhos de energia acendem até a primeira junção desalinhada
	for i in strips.size():
		var on = _aligned_upto(i)
		var m: StandardMaterial3D = strips[i]
		m.emission = Palette.RESSONANCIA if on else Palette.COBRE
		m.emission_energy_multiplier = (1.0 + 0.4 * sin(t * 4.0 - i)) if on else 0.15
	if not flag("market") and p.y < -6.0 and p.y > -9.5 and p.z < 18.0 and p.z > -3.0 and absf(p.x) < 11.0:
		set_flag("market")
		main.lume_once("lume.network", 5.0)
	if not flag("balcony") and p.y > P2.y + 2.8 and p.y < P2.y + 4.5 and Builder.inside(Builder.rect(P2.x + 6.0, P2.z - 6.0, P2.x + 10.6, P2.z - 2.6), Vector2(p.x, p.z)):
		set_flag("balcony")
	if Game.has_ability("relay"):
		main.lume_once("lume.relay_get", 6.0)
	if main.mode == "play":
		main.lume_once("lume.cidade", 5.0)
