extends Region
## Jardim Mineral — ensina maré e planar (GDD 06/12). Porta da fatia vertical
## do protótipo web, expandida com a Asa de Vidro, a comporta e o anel do
## santuário com dois condutos.

const A := Vector3(0, 0, 36)
const B := Vector3(0, 0, 14)
const C := Vector3(0, 0, -16)
const D_Z := -40.5
const D_TOP := 3.3
const S_SCALE := 2.4
const PLAZA_R := 8.5
const ORDER := ["●", "▲", "■"]

var node_b: Interactable
var conductor: Interactable
var steps_vis: Array = []
var steps_ramp: StaticBody3D
var circuit_mat: StandardMaterial3D
var plates: Array = []
var plate_idx = 0
var guardian: Guardian
var pillar: Interactable
var conduit_a: Interactable
var conduit_b: Interactable
var fountain = Vector3.ZERO
var heart: Node3D
var ring_mesh: MeshInstance3D
var z_south = 0.0
var back_portal: Interactable
var node_c: Interactable

func build() -> void:
	music = "jardim"
	env = {"preset": "jardim", "center": Vector3(0, 0, 0), "distant": "#3B6B72"}
	Game.set_flag("jardim.visited")
	add_sector("jardim", true)
	_arrival()
	_cistern()
	_bridge_and_floaters()
	_garden()
	_sanctuary()
	_objectives()

# --- A: chegada -------------------------------------------------------------------

func _arrival() -> void:
	var a = Builder.octagon(7.5, A.x, A.z)
	Builder.island(self, a, [a], 0.0, 1.4, 11)
	add_spawn("portal", Vector3(0, 0, 39.5), PI)
	add_ix(IX.Portal.new("portal_volta", "farol", "portal_jardim", func(): return true), Vector3(-4.4, 0, 39.6), PI / 2)
	Builder.slab(self, Builder.rect(-1.4, 23.0, 1.4, 29.4), 0.0, -0.8, Palette.mat(Palette.AREIA_CLARA), Palette.mat(Palette.CERAMICA))
	# mirante e rocha do eco (opcional: exige planar)
	Builder.slab(self, Builder.rect(-5.8, 33.0, -3.4, 36.0), 0.9, -0.6, Palette.mat(Palette.ROCHA), Palette.mat(Palette.ROCHA_ESCURA))
	var rock = Builder.octagon(1.6, -14.2, 34.5)
	Builder.island(self, rock, [rock], -0.4, 0.6, 51, {"groups": []})
	add_ix(IX.Echo.new("jardim_mirante"), Vector3(-14.2, 0.2, 34.5))
	Builder.prop(self, "column_broken2", Vector3(4.8, 0, 38.8), {"height": 2.0, "collide": 0.75})
	Builder.prop(self, "column_broken", Vector3(3.6, 0, 33.0), {"height": 0.9, "rot": 1.2})
	Builder.prop(self, "rock3", Vector3(5.2, 0, 34.0), {"height": 1.1, "collide": 0.55})
	Builder.prop(self, "crystal2", Vector3(-1.8, 0, 31.2), {"height": 0.9})
	Builder.prop(self, "plant3", Vector3(2.5, 0, 42.0), {"height": 0.9})
	Builder.prop(self, "plant5", Vector3(-2.2, 0, 42.4), {"height": 0.9})

# --- B: cisterna -------------------------------------------------------------------

func _cistern() -> void:
	var outline = Builder.octagon(10.0, B.x, B.z)
	Builder.island(self, outline, Builder.minus_rect(outline, -3, 11, 3, 17), 0.0, 4.4, 23, {"root_depth": 9.0})
	Builder.slab(self, Builder.rect(-3, 11, 3, 17), -3.5, -4.4, Palette.mat(Color("#8F7A63")), Palette.mat(Palette.ROCHA_ESCURA))
	add_basin("jardim", Builder.rect(-3, 11, 3, 17), -4.1, -0.45)
	# escada de cristal (visual) + rampa (colisão) ativas na maré baixa
	for i in range(1, 9):
		var top = -3.5 + i * 0.4375
		var zc = 11.3 + (8 - i) * 0.6
		var mi = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(1.25, 0.32, 0.6)
		mi.mesh = box
		mi.material_override = Palette.mat(Color("#58D6C4"), {"emission": Palette.RESSONANCIA, "energy": 0.45, "roughness": 0.3})
		mi.position = Vector3(-2.38, top - 0.16, zc)
		add_child(mi)
		steps_vis.append(mi)
	steps_ramp = Builder.ramp(self, Vector3(-2.38, -3.5, 15.85), Vector3(-2.38, 0.0, 11.0), 1.2, [])
	# condutor
	conductor = add_ix(IX.Conductor.new("condutor", 1, func(): return not high("jardim") and sector_level("jardim") < 0.3), Vector3(0, -3.5, 14))
	conductor.on_change = _on_conductor
	# trilha de circuito: fundo -> parede -> topo -> emissor
	circuit_mat = Palette.unique(Color("#8A5A35"), {"emission": Palette.COBRE, "energy": 0.15})
	for s in [[Vector3(0.22, 0.04, 2.3), Vector3(0, -3.48, 12.15)], [Vector3(0.22, 3.5, 0.04), Vector3(0, -1.75, 11.03)], [Vector3(0.22, 0.04, 5.4), Vector3(0, 0.02, 8.25)]]:
		var mi = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = s[0]
		mi.mesh = box
		mi.material_override = circuit_mat
		mi.position = s[1]
		add_child(mi)
	node_b = add_ix(IX.TideNode.new("no_cisterna", ["jardim"]), Vector3(6.0, 0, 17.5))
	add_ix(IX.Echo.new("jardim_cisterna", func(): return sector_level("jardim") < 0.3), Vector3(2.2, -3.1, 16.3))
	for e in [Vector3(0, 0, 5.6), Vector3(0, 0, -3.9)]:
		for sx in [-1.55, 1.55]:
			Builder.prop(self, "column_broken2", e + Vector3(sx, 0, 0), {"height": 1.3, "collide": 0.45})
			var cap = MeshInstance3D.new()
			var oct = SphereMesh.new()
			oct.radius = 0.22
			oct.height = 0.44
			oct.radial_segments = 4
			oct.rings = 2
			cap.mesh = oct
			cap.material_override = Interactable.glow_mat(Palette.RESSONANCIA, 0.3)
			cap.position = e + Vector3(sx, 1.55, 0)
			add_child(cap)
			animated.append(func(_dt): (cap.material_override as StandardMaterial3D).emission_energy_multiplier = 1.8 if conductor.aligned else 0.3)
	Builder.prop(self, "column_broken", Vector3(-7.2, 0, 18.2), {"height": 1.4, "rot": 0.4})
	Builder.prop(self, "column", Vector3(7.4, 0, 9.0), {"height": 3.6, "collide": 0.6})
	Builder.prop(self, "rock5", Vector3(4.6, 0, 21.0), {"height": 0.9, "collide": 0.45})
	Builder.prop(self, "rock6", Vector3(-4.8, 0, 21.4), {"height": 1.0, "collide": 0.5})
	Builder.prop(self, "crystal1", Vector3(7.4, 0, 19.0), {"height": 0.9})
	Builder.prop(self, "crystal2b", Vector3(7.9, 0, 18.4), {"height": 0.7})
	Builder.prop(self, "plant3", Vector3(-8.0, 0, 13.6), {"height": 0.9})
	Builder.prop(self, "plant2", Vector3(-3.2, 0, 7.4), {"height": 1.1})
	Builder.prop(self, "pipe_straight", Vector3(2.4, -3.5, 12.0), {"height": 0.5})

func _on_conductor(c: Interactable) -> void:
	if c.aligned:
		main.say("lume.conductor", 4.5)
		Sfx.play("activate")

func _bridge_and_floaters() -> void:
	add_bridge(Vector3(0, 0, 5.7), Vector3(0, 0, -3.4), 2.6, func(): return high("jardim") and sector_level("jardim") > 0.6 and conductor.aligned)
	for f in [[11.9, 13.0, 0.35], [14.6, 11.0, 1.1], [17.0, 8.6, 1.85]]:
		add_floater("jardim", Builder.ngon(1.15, 6, f[0], f[1], PI / 6), f[2], -7.0 - f[0] * 0.1)
	var perch = Builder.octagon(1.6, 19.0, 5.6)
	Builder.island(self, perch, [perch], 2.55, 3.6, 77)
	add_ix(IX.Echo.new("jardim_flutuante"), Vector3(19.0, 3.05, 5.6))

# --- C: Jardim e praça do guardião -------------------------------------------------

func _garden() -> void:
	var outer = Builder.octagon(14.0, C.x, C.z)
	var inner = Builder.octagon(PLAZA_R, C.x, C.z)
	Builder.island(self, outer, Builder.ring(outer, inner), 0.0, 3.0, 31, {"root_depth": 13.0})
	Builder.slab(self, inner, -2.2, -3.0, Palette.mat(Color("#A88566")), Palette.mat(Palette.ROCHA_ESCURA))
	add_basin("jardim", inner, -2.75, -0.4)
	var ap = PLAZA_R * cos(PI / 8)
	Builder.stairs(self, Vector3(0, 0, C.z + ap + 0.05), Vector3(0, -2.2, C.z + ap - 2.5), 2.4, 5, Palette.mat(Palette.AREIA_CLARA), Palette.mat(Palette.CERAMICA))
	Builder.stairs(self, Vector3(C.x + ap + 0.05, 0, C.z), Vector3(C.x + ap - 2.5, -2.2, C.z), 2.4, 5, Palette.mat(Palette.AREIA_CLARA), Palette.mat(Palette.CERAMICA))
	# comportas nas duas entradas da praça (abrem pela alavanca da ilhota)
	add_gate(Vector3(0, 0, C.z + ap + 0.35), 0.0, func(): return flag("sluice"), Vector3(2.8, 2.6, 0.35))
	add_gate(Vector3(C.x + ap + 0.35, 0, C.z), PI / 2, func(): return flag("sluice"), Vector3(2.8, 2.6, 0.35))
	# poleiro do guardião
	Builder.slab(self, Builder.ngon(1.3, 6, C.x, C.z), -0.15, -3.0, Palette.mat(Palette.AREIA_CLARA), Palette.mat(Palette.ROCHA), [])
	for r in [[1.25, 0.4, "rock4", 1.3], [-1.1, 0.9, "rock6", 1.1], [0.3, -1.35, "rock7", 1.5]]:
		Builder.prop(self, r[2], Vector3(C.x + r[0], -2.2, C.z + r[1]), {"height": r[3]})
	# cristais de cobertura (bloqueiam a visão do guardião)
	for cv in [[-6.0, 4.0, 2.6], [-6.3, -2.8, 3.0], [0.9, -7.0, 2.8], [6.2, -4.0, 2.5], [4.4, 5.5, 2.3]]:
		Builder.prop(self, "gem_blue", Vector3(C.x + cv[0], -2.2, C.z + cv[1]), {"height": cv[2], "collide": 0.8, "cover": true, "rot": cv[0]})
	# placas e pilar de leitura
	var defs = [["▲", 1.2, -5.9], ["●", -6.2, 0.8], ["■", 5.6, 4.3]]
	for d in defs:
		var pl = add_ix(IX.Plate.new("placa_" + d[0], d[0], func(): return not high("jardim") and sector_level("jardim") < 0.3, _on_plate), Vector3(C.x + d[1], -2.2, C.z + d[2]))
		plates.append(pl)
	pillar = add_ix(IX.ReadingPillar.new("pilar", "scan.pillar", {"order": " ".join(ORDER)}, func(_p): main.say("lume.pillar", 5.0, {"order": " ".join(ORDER)})), Vector3(3.2, 0, C.z + ap + 1.8))
	add_ix(IX.Echo.new("jardim_praca", func(): return sector_level("jardim") < 0.3), Vector3(C.x - 5.4, -1.8, C.z - 5.0))
	# guardião
	var wp = []
	for w in [[-4.2, 1.8], [-4.2, -2.6], [-1.2, -4.6], [2.8, -3.8], [4.3, 0.2], [2.0, 3.9], [-1.4, 4.2]]:
		wp.append(Vector3(C.x + w[0], -2.2, C.z + w[1]))
	guardian = add_guardian({"waypoints": wp, "perch": Vector3(C.x, -0.15, C.z), "floor_y": -2.2}, inner, -1.0, func(): return not high("jardim") and not flag("plates"))
	guardians[-1]["exit"] = Vector3(0, 0, C.z + ap + 2.2)
	if flag("plates"):
		guardian.pacify()
	# nó da praça: baixar a maré sem voltar à cisterna (a ponte cairia)
	node_c = add_ix(IX.TideNode.new("no_praca", ["jardim"]), Vector3(-4.2, 0, -6.6))
	# Asa de Vidro no desembarque da ponte
	add_ix(IX.Pedestal.new("asa", "glide"), Vector3(3.0, 0, -5.6))
	add_spawn("jardim_cp", Vector3(0, 0, C.z + 14 * cos(PI / 8) - 1.6), PI)
	checkpoints.append({"id": "jardim_cp", "pos": Vector3(0, 0, C.z + 14 * cos(PI / 8) - 1.6), "radius": 2.6})
	# torre de pedra (a primeira pedra só flutua na maré alta) e ilhota da comporta
	add_floater("jardim", Builder.rect(-10.55, -22.75, -9.05, -21.25), 0.8, -6.0)
	Builder.slab(self, Builder.rect(-11.7, -21.9, -10.3, -20.5), 1.5, -0.5, Palette.mat(Palette.ROCHA), Palette.mat(Palette.ROCHA_ESCURA))
	Builder.slab(self, Builder.rect(-11.9, -19.9, -10.1, -18.1), 2.2, -0.5, Palette.mat(Palette.ROCHA), Palette.mat(Palette.ROCHA_ESCURA))
	var islet = Builder.octagon(2.4, -20.5, -19.0)
	Builder.island(self, islet, [islet], 1.0, 0.8, 91)
	add_ix(IX.Lever.new("comporta", func(_l): set_flag("sluice"); main.say("lume.sluice_open", 4.5)), Vector3(-20.0, 1.0, -20.2), PI / 2)
	add_ix(IX.Echo.new("jardim_ilhota"), Vector3(-21.3, 1.8, -18.2))
	Builder.prop(self, "plant2", Vector3(-21.5, 1.0, -18.2), {"height": 0.9})
	# portão norte (abre com o circuito das placas)
	add_gate(Vector3(0, 0, C.z - 14 * cos(PI / 8) + 0.35), 0.0, func(): return flag("plates"))
	for sx in [-1.95, 1.95]:
		Builder.prop(self, "column", Vector3(sx, 0, C.z - 14 * cos(PI / 8) + 0.35), {"height": 4.2, "collide": 0.72})
	var avoid = _avoid_garden
	scatter(["crystal1", "crystal2", "crystal3", "crystal5", "crystal1b", "crystal2b"], C, PLAZA_R + 1.2, 12.5, 30, 0.0, {"avoid": avoid, "h_min": 0.4, "h_max": 1.3})
	scatter(["plant2", "plant3", "plant5", "plant1"], C, PLAZA_R + 1.2, 12.6, 12, 0.0, {"avoid": avoid, "h_min": 0.5, "h_max": 1.1})
	Builder.prop(self, "column_broken2", Vector3(C.x + 9.5, 0, C.z - 4.5), {"height": 2.6, "collide": 0.75})
	Builder.prop(self, "column", Vector3(C.x + 6.8, 0, C.z - 9.4), {"height": 4.0, "collide": 0.65})

func _avoid_garden(x: float, z: float) -> bool:
	if Vector2(x - C.x, z - C.z).length() < PLAZA_R + 0.8:
		return true
	if absf(x) < 2.4 and z > C.z + 9:
		return true
	if absf(x) < 3.0 and z < C.z - 9:
		return true
	if x < C.x - 8.5 and z > C.z - 8 and z < C.z - 1:
		return true
	if Vector2(x - 3.2, z - (C.z + 9.6)).length() < 2.0 or Vector2(x - 3.0, z + 5.6).length() < 2.0:
		return true
	return false

func _on_plate(pl: Interactable) -> void:
	if flag("plates"):
		return
	if pl.glyph == ORDER[plate_idx]:
		pl.set_lit(true)
		plate_idx += 1
		Sfx.play("plate")
		if plate_idx >= ORDER.size():
			set_flag("plates")
			guardian.pacify()
			Sfx.play("pacify")
			main.say("lume.pacified", 4.5)
	else:
		plate_idx = 0
		for p in plates:
			p.set_lit(false)
		Sfx.play("plate_wrong")
		main.say("lume.plates_wrong", 3.0)

# --- D: santuário -------------------------------------------------------------------

func _sanctuary() -> void:
	var model = Props.original("04_santuario_das_mares.glb")
	model.scale = Vector3.ONE * S_SCALE
	model.position = Vector3(0, D_TOP - 0.15 * S_SCALE, D_Z)
	add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		IrisRig._tune_material(mi)
	collide_model(model, ["island_root", "pool_water", "energy_ring", "heart", "portal_inner", "cap_"])
	# borda sul do terraço em x = 0
	z_south = -INF
	for mi in model.find_children("terrace*", "MeshInstance3D", true, false):
		var m = mi as MeshInstance3D
		var arr = m.mesh.surface_get_arrays(0)
		for v in arr[Mesh.ARRAY_VERTEX]:
			var w: Vector3 = m.global_transform * v
			if absf(w.x) < 1.0:
				z_south = maxf(z_south, w.z)
	var z_north = C.z - 14 * cos(PI / 8)
	Builder.stairs(self, Vector3(0, 0, z_north + 0.1), Vector3(0, D_TOP, z_south + 0.02), 2.6, 9, Palette.mat(Palette.AREIA_CLARA), Palette.mat(Palette.CERAMICA))
	# coração (memória) e anel
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if mi.name.begins_with("heart"):
			heart = _repivot(mi)
		elif mi.name.begins_with("energy_ring"):
			ring_mesh = mi
	var s_top = Vector3(0, D_TOP, D_Z)
	var s_spawn = sanctuary_spawn(s_top, Vector3(0, 0, 1), S_SCALE)
	fountain = sanctuary_fountain(s_top, Vector3(0, 0, 1), S_SCALE)
	add_spawn("santuario", s_spawn + Vector3(0, 0.1, 0), PI)
	checkpoints.append({"id": "santuario", "pos": s_spawn, "radius": 3.0})
	add_ix(IX.TideNode.new("no_santuario", ["jardim"]), Vector3(-4.6, D_TOP, D_Z + 2.4))
	# conduto A: parapeito baixo ao lado da escadaria (só seco na maré baixa)
	var zl = (z_north + z_south) * 0.5
	Builder.slab(self, Builder.rect(-4.6, zl - 1.4, -1.3, zl + 1.4), 1.2, 0.4, Palette.mat(Palette.AREIA_CLARA), Palette.mat(Palette.CERAMICA))
	Builder.slab(self, Builder.rect(-4.9, zl - 1.7, -4.6, zl + 1.7), 2.3, 0.4, Palette.mat(Palette.CERAMICA), Palette.mat(Palette.CERAMICA), [])
	Builder.slab(self, Builder.rect(-4.9, zl - 1.7, -1.3, zl - 1.4), 2.3, 0.4, Palette.mat(Palette.CERAMICA), Palette.mat(Palette.CERAMICA), [])
	Builder.slab(self, Builder.rect(-4.9, zl + 1.4, -1.3, zl + 1.7), 2.3, 0.4, Palette.mat(Palette.CERAMICA), Palette.mat(Palette.CERAMICA), [])
	add_basin("jardim", Builder.rect(-4.6, zl - 1.4, -1.3, zl + 1.4), 0.6, 2.1)
	conduit_a = add_ix(IX.Conduit.new("conduto_a", func(): return sector_level("jardim") < 0.3, _conduit_lit), Vector3(-3.4, 1.2, zl))
	# conduto B: plataforma de flutuação a leste (sobe na maré alta)
	var fl = add_floater("jardim", Builder.rect_c(8.6, D_Z + 1.0, 3.2, 3.2), D_TOP, -4.0)
	conduit_b = attach_ix(IX.Conduit.new("conduto_b", func(): return sector_level("jardim") > 0.9, _conduit_lit), fl, Vector3(0.4, 0, 0))
	# fonte: despertar o anel, memória e descanso
	add_ix(IX.Action.new("fonte", _fountain_prompt, _fountain_act, 2.6, "scan.sanctuary"), fountain)
	back_portal = add_front_portal("portal_santuario", Vector3(0, D_TOP, D_Z), Vector3(0, 0, 1), Vector3(1, 0, 0), S_SCALE, "portal_jardim", func(): return flag("rested"))
	animated.append(_anim_sanctuary)

func _anim_sanctuary(dt: float) -> void:
	if heart and heart.visible:
		heart.rotation.y += dt * 0.8
	if ring_mesh:
		ring_mesh.rotation.z += dt * (0.4 if flag("ring") else 0.05)
		var m = ring_mesh.get_active_material(0) as StandardMaterial3D
		if m:
			m.emission_energy_multiplier = 2.2 if flag("ring") else 0.3

func _repivot(mi: MeshInstance3D) -> Node3D:
	var center = mi.get_aabb().get_center()
	var pivot = Node3D.new()
	mi.get_parent().add_child(pivot)
	pivot.position = mi.position + center
	mi.get_parent().remove_child(mi)
	pivot.add_child(mi)
	mi.position = -center
	return pivot

func _conduit_lit(_c: Interactable) -> void:
	if conduit_a.lit and conduit_b.lit:
		Sfx.play("unlock")
		main.say("lume.ring", 4.5)
	else:
		main.say("lume.conduit", 3.0)

func _fountain_prompt(_ctx: Dictionary) -> Dictionary:
	if not (conduit_a.lit and conduit_b.lit):
		return {}
	if not flag("ring"):
		return {"text": I18n.t("prompt.ring"), "action": "interact"}
	if not flag("rested"):
		return {"text": I18n.t("prompt.rest"), "action": "interact"}
	return {}

func _fountain_act(_ctx: Dictionary) -> void:
	if not flag("ring"):
		set_flag("ring")
		if heart:
			var tw = create_tween()
			tw.tween_property(heart, "scale", Vector3.ONE * 0.01, 1.4)
			tw.tween_callback(func(): heart.visible = false)
		main.on_memory("jardim")
		main.say("lume.portal_new", 5.0)
	elif not flag("rested"):
		set_flag("rested")
		main.rest_at("santuario")

func _objectives() -> void:
	var p = func(): return main.player.global_position
	add_objective("j_reach", func(): return flag("reached_b") or flag("reached_c"), func(): return B)
	add_objective("j_scan", func(): return node_b.is_scanned() or flag("reached_c"), func(): return node_b.global_position)
	add_objective("j_lower", func(): return conductor.aligned or not high("jardim") or flag("reached_c"), func(): return node_b.global_position)
	add_objective("j_conductor", func(): return conductor.aligned or flag("reached_c"), func(): return Vector3(0, -3.5, 14))
	add_objective("j_climb", func(): return high("jardim") or p.call().y > -0.6 or flag("reached_c"), func(): return Vector3(-2.4, 0, 11.4))
	add_objective("j_raise", func(): return (high("jardim") and conductor.aligned) or flag("reached_c"), func(): return node_b.global_position)
	add_objective("j_cross", func(): return flag("reached_c"), func(): return Vector3(0, 0, 1))
	add_objective("j_wing", func(): return Game.has_ability("glide"), func(): return Vector3(3.0, 0, -5.6))
	add_objective("j_sluice", func(): return flag("sluice"), func(): return Vector3(-20.0, 1.0, -20.2))
	add_objective("j_plates_tide", func(): return not high("jardim") or flag("plates"), func(): return node_c.global_position)
	add_objective("j_pillar", func(): return pillar.read or flag("plates"), func(): return pillar.global_position)
	add_objective("j_plates", func(): return flag("plates"), func(): return plates[1].global_position)
	add_objective("j_sanct", func(): return flag("reached_d"), func(): return Vector3(0, 0, C.z - 13.5))
	add_objective("j_conduits", func(): return conduit_a.lit and conduit_b.lit, func(): return conduit_a.global_position if not conduit_a.lit else conduit_b.global_position)
	add_objective("j_ring", func(): return flag("ring"), func(): return fountain)
	add_objective("j_rest", func(): return flag("rested"), func(): return fountain)
	add_objective("j_done", func(): return false, func(): return back_portal.global_position)

func region_tick(_dt: float) -> void:
	var p: Vector3 = main.player.global_position
	var dry = sector_level("jardim") < 0.3
	for i in steps_vis.size():
		var mi: MeshInstance3D = steps_vis[i]
		mi.position.x = lerpf(mi.position.x, -2.38 if dry else -3.6, 1.0 - exp(-(4.0 + i * 0.3) * _dt))
		mi.visible = mi.position.x > -3.55
	steps_ramp.collision_layer = 1 if dry else 0
	circuit_mat.emission = Palette.RESSONANCIA if conductor.aligned else Palette.COBRE
	circuit_mat.emission_energy_multiplier = (0.9 + 0.5 * sin(t * 4.0)) if conductor.aligned else 0.15
	if not flag("reached_b") and p.z < 23.5 and p.z > 4.5 and p.y > -1.0:
		set_flag("reached_b")
		main.lume_once("lume.jardim", 5.0)
	if not flag("reached_c") and p.z < -4.0 and p.y > -1.0:
		set_flag("reached_c")
		main.lume_once("lume.bridge", 4.0)
	if Game.has_ability("glide") and not flag("sluice") and flag("reached_c"):
		if main.obj_t > 3.0:
			main.lume_once("lume.sluice", 5.0)
	if not flag("reached_d") and p.z < C.z - 15.0 and p.y > 2.5:
		set_flag("reached_d")
