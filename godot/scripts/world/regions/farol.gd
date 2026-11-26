extends Region
## Farol Nulo — hub e prólogo (Ato I): tutorial de movimento e maré, oficina,
## portais para as três regiões e ecos que pedem retorno.

const H := Vector3(0, 0, -6)  # centro da ilha do Farol
const HR := 16.0

func build() -> void:
	music = "farol"
	env = {"preset": "farol", "center": Vector3(0, 0, 6), "creatures": [["manta", 3.0, 50, 80, -12, 6], ["whale", 10.0, 120, 170, -6, 22], ["manta", 2.4, 40, 70, -16, -4]]}
	add_sector("farol", true)
	var top = mat_top()
	var side = mat_side()
	# ilhota de despertar (sul)
	var start_poly = Builder.octagon(4.5, 0, 34)
	Builder.island(self, start_poly, [start_poly], 0.0, 1.2, 3)
	add_spawn("start", Vector3(0, 0, 35.5), PI)
	# pedras de salto (tutorial)
	Builder.slab(self, Builder.rect(-0.9, 27.6, 0.9, 29.2), 0.5, -1.5, Palette.mat(Palette.ROCHA), Palette.mat(Palette.ROCHA_ESCURA))
	Builder.slab(self, Builder.rect(-0.9, 24.9, 0.9, 26.5), 1.0, -1.5, Palette.mat(Palette.ROCHA), Palette.mat(Palette.ROCHA_ESCURA))
	# ilhota do nó
	var node_poly = Builder.octagon(3.4, 0, 21)
	Builder.island(self, node_poly, [node_poly], 0.6, 1.0, 9)
	var node = add_ix(IX.TideNode.new("no_bacia", ["farol"]), Vector3(1.9, 0.6, 21.2))
	add_ix(IX.Echo.new("farol_ilhota"), Vector3(-2.0, 1.1, 20.4))
	# bacia (canal entre a ilhota e o Farol): alagada na maré alta
	var trough_mat = Palette.mat(Color("#B8A88A"))
	Builder.slab(self, Builder.rect(-2.6, 8.4, 2.6, 18.0), -2.6, -3.4, Palette.mat(Color("#8F7A63")), Palette.mat(Palette.ROCHA_ESCURA))
	for x in [-2.9, 2.9]:
		Builder.slab(self, Builder.rect(x - 0.3, 8.4, x + 0.3, 18.0), -0.2, -3.4, trough_mat, Palette.mat(Palette.ROCHA))
	Builder.stairs(self, Vector3(0, 0.6, 17.9), Vector3(0, -2.6, 14.4), 2.4, 7, Palette.mat(Palette.AREIA_CLARA), Palette.mat(Palette.CERAMICA))
	Builder.stairs(self, Vector3(0, -2.6, 12.2), Vector3(0, 0.0, 8.9), 2.4, 6, Palette.mat(Palette.AREIA_CLARA), Palette.mat(Palette.CERAMICA))
	add_basin("farol", Builder.rect(-2.6, 8.4, 2.6, 18.0), -3.4, -0.35)
	# ilha do Farol
	var hub = Builder.octagon(HR, H.x, H.z)
	Builder.island(self, hub, [hub], 0.0, 1.6, 21, {"root_depth": 18.0})
	# o farol
	_lighthouse(Vector3(-4, 0, -9))
	# mirante para o eco do topo (exige planar)
	Builder.slab(self, Builder.rect(-10.6, -13.6, -9.0, -12.0), 1.0, -0.5, Palette.mat(Palette.ROCHA), Palette.mat(Palette.ROCHA_ESCURA))
	Builder.slab(self, Builder.rect(-12.4, -15.4, -10.8, -13.8), 2.0, -0.5, Palette.mat(Palette.ROCHA), Palette.mat(Palette.ROCHA_ESCURA))
	Builder.slab(self, Builder.rect(-12.2, -18.4, -10.4, -16.6), 3.0, -0.5, Palette.mat(Palette.ROCHA), Palette.mat(Palette.ROCHA_ESCURA))
	var rock = Builder.octagon(2.0, -21.5, -24.0)
	Builder.island(self, rock, [rock], 0.6, 0.8, 41, {"groups": []})
	add_ix(IX.Echo.new("farol_topo"), Vector3(-21.5, 1.2, -24.0))
	# oficina
	Builder.prop(self, "gazebo", Vector3(9.5, 0, -4), {"height": 4.2, "rot": -PI / 2})
	Builder.prop(self, "table_round", Vector3(9.5, 0, -4), {"height": 0.9})
	Builder.prop(self, "bookshelf", Vector3(12.2, 0, -2.2), {"height": 2.0, "rot": -PI / 2})
	Builder.prop(self, "lamp_floor", Vector3(7.4, 0, -1.8), {"height": 1.8})
	Builder.prop(self, "capsule", Vector3(11.5, 0, -6.8), {"height": 1.2})
	add_ix(IX.Workshop.new("oficina"), Vector3(9.5, 0, -4))
	# portais
	var pj = add_ix(IX.Portal.new("portal_jardim", "jardim", "portal", func(): return flag("crossed")), Vector3(-8, 0, -18.5), 0.4)
	add_ix(IX.Portal.new("portal_cidade", "cidade", "portal", func(): return "jardim" in Game.state["memories"]), Vector3(2.5, 0, -19.8), 0.0)
	add_ix(IX.Portal.new("portal_coracao", "coracao", "portal", func(): return "cidade" in Game.state["memories"]), Vector3(11.5, 0, -15.5), -0.5)
	add_spawn("hub", Vector3(0, 0, 6.5), PI)
	add_spawn("portal_jardim", Vector3(-5.5, 0, -12.5), 0.4)
	add_spawn("portal_cidade", Vector3(2.5, 0, -13.3), 0.0)
	add_spawn("portal_coracao", Vector3(8.4, 0, -9.8), -0.5)
	checkpoints.append({"id": "hub", "pos": Vector3(0, 0, 6.5), "radius": 3.0})
	# arquivo (exige relé remoto)
	_archive(Vector3(5.5, 0, 2.0))
	# decoração
	scatter(["crystal1", "crystal2", "crystal3", "crystal5"], H, 6.0, HR - 2.0, 18, 0.0, {"h_min": 0.4, "h_max": 1.1, "avoid": _avoid})
	scatter(["rock1", "rock4", "stone2", "plant3", "plant5", "plant2"], H, 7.0, HR - 1.5, 14, 0.0, {"h_min": 0.5, "h_max": 1.2, "avoid": _avoid})
	Builder.prop(self, "column_broken2", Vector3(3.2, 0, 36.5), {"height": 1.8, "collide": 0.7})
	Builder.prop(self, "rock_cluster1", Vector3(-3.2, 0, 32.2), {"height": 0.9})
	Builder.prop(self, "plant2", Vector3(2.6, 0, 31.6), {"height": 0.9})
	Builder.prop(self, "plant1", Vector3(-2.6, 0, 36.2), {"height": 0.6})
	# epílogo
	if Game.state.get("ending", "") == "keep":
		scatter(["gem_blue", "crystal1", "crystal2"], H, 2.0, HR - 1.0, 30, 0.0, {"h_min": 1.0, "h_max": 3.2})
	elif Game.state.get("ending", "") == "free":
		for i in 8:
			var a = TAU * i / 8.0
			var fall = MeshInstance3D.new()
			var cyl = CylinderMesh.new()
			cyl.top_radius = 1.2
			cyl.bottom_radius = 2.4
			cyl.height = 30.0
			fall.mesh = cyl
			fall.material_override = Builder.water_material({"opacity": 0.55, "energy": 0.4, "flow": Vector2(0, 2.0), "scale": 0.6})
			fall.position = H + Vector3(cos(a) * (HR + 1.0), -16.0, sin(a) * (HR + 1.0))
			add_child(fall)
	# objetivos
	add_objective("farol_wake", func(): return flag("near_node") or flag("crossed"), func(): return Vector3(0, 0.6, 21))
	add_objective("farol_scan", func(): return node.is_scanned() or flag("crossed"), func(): return node.global_position)
	add_objective("farol_tide", func(): return flag("lowered") or flag("crossed"), func(): return node.global_position)
	add_objective("farol_cross", func(): return flag("crossed"), func(): return Vector3(0, 0, 7.5))
	add_objective("farol_portal", func(): return Game.flag("jardim.visited", false), func(): return Vector3(-8, 0, -18.5))
	add_objective("farol_cidade", func(): return not ("jardim" in Game.state["memories"]) or Game.flag("cidade.visited", false), func(): return Vector3(2.5, 0, -19.8))
	add_objective("farol_coracao", func(): return not ("cidade" in Game.state["memories"]) or Game.flag("coracao.visited", false), func(): return Vector3(11.5, 0, -15.5))
	add_objective("farol_end", func(): return false, func(): return Vector3(-4, 0, -9))

func _avoid(x: float, z: float) -> bool:
	var p = Vector2(x, z)
	for c in [Vector2(-4, -9), Vector2(9.5, -4), Vector2(-8, -18.5), Vector2(2.5, -19.8), Vector2(11.5, -15.5), Vector2(5.5, 2.0), Vector2(0, 7), Vector2(-11, -15)]:
		if p.distance_to(c) < 4.0:
			return true
	return absf(x) < 3.0 and z > 4.0

var lantern_mat: StandardMaterial3D
var lantern_light: OmniLight3D

func _lighthouse(at: Vector3) -> void:
	var tiers = [[2.6, 3.0, Palette.CERAMICA], [2.2, 3.0, Palette.PETROLEO], [1.9, 3.0, Palette.CERAMICA], [1.6, 2.4, Palette.PETROLEO]]
	var y = 0.0
	for t in tiers:
		var mi = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = t[0] * 0.92
		cyl.bottom_radius = t[0]
		cyl.height = t[1]
		cyl.radial_segments = 8
		mi.mesh = cyl
		mi.material_override = Palette.mat(t[2])
		mi.position = at + Vector3(0, y + t[1] / 2, 0)
		add_child(mi)
		y += t[1]
	var cage = MeshInstance3D.new()
	var cm = CylinderMesh.new()
	cm.top_radius = 1.2
	cm.bottom_radius = 1.5
	cm.height = 1.6
	cm.radial_segments = 8
	cage.mesh = cm
	cage.material_override = Palette.copper()
	cage.position = at + Vector3(0, y + 0.8, 0)
	add_child(cage)
	var gem = Props.make("gem_blue", {"height": 2.2})
	gem.position = at + Vector3(0, y + 1.6, 0)
	add_child(gem)
	lantern_mat = Interactable.glow_mat(Palette.RESSONANCIA, 0.3)
	for mi in gem.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = lantern_mat
	lantern_light = OmniLight3D.new()
	lantern_light.position = at + Vector3(0, y + 2.6, 0)
	lantern_light.light_color = Palette.RESSONANCIA
	lantern_light.omni_range = 26.0
	lantern_light.light_energy = 0.2
	add_child(lantern_light)
	animated.append(func(dt): gem.rotation.y += dt * 0.4)
	var body = StaticBody3D.new()
	var cs = CollisionShape3D.new()
	var sh = CylinderShape3D.new()
	sh.radius = 2.6
	sh.height = y + 3.0
	cs.shape = sh
	cs.position = at + Vector3(0, (y + 3.0) / 2, 0)
	body.add_child(cs)
	add_child(body)

func _archive(at: Vector3) -> void:
	# casinha de cerâmica com portão a oeste; o eco fica dentro
	var wall = Palette.mat(Palette.CERAMICA)
	var trim = Palette.mat(Palette.PETROLEO)
	Builder.slab(self, Builder.rect(at.x - 3.4, at.z - 2.2, at.x + 2.4, at.z - 1.8), 3.0, 0.0, trim, wall, [])
	Builder.slab(self, Builder.rect(at.x - 3.4, at.z + 1.8, at.x + 2.4, at.z + 2.2), 3.0, 0.0, trim, wall, [])
	Builder.slab(self, Builder.rect(at.x + 2.0, at.z - 2.2, at.x + 2.4, at.z + 2.2), 3.0, 0.0, trim, wall, [])
	Builder.slab(self, Builder.rect(at.x - 3.8, at.z - 2.6, at.x + 2.8, at.z + 2.6), 3.4, 3.0, trim, wall, [])
	add_gate(at + Vector3(-3.6, 0, 0), PI / 2, func(): return flag("archive"), Vector3(3.8, 3.0, 0.4))
	add_ix(IX.Echo.new("farol_arquivo"), at + Vector3(0.3, 0.5, 0))
	Builder.prop(self, "bookshelf", at + Vector3(1.4, 0, -1.2), {"height": 2.2, "rot": PI})
	var rock = Builder.octagon(1.8, 26, 12)
	Builder.island(self, rock, [rock], 2.0, 0.6, 77)
	add_ix(IX.RelayPylon.new("rele_arquivo", func(_p): set_flag("archive")), Vector3(26, 2.0, 12))

func region_tick(_dt: float) -> void:
	var p: Vector3 = main.player.global_position
	if not flag("near_node") and p.z < 24.8 and p.y > 0.2:
		set_flag("near_node")
		main.lume_once("lume.node", 5.0)
	if not flag("lowered") and not high("farol"):
		set_flag("lowered")
		main.lume_once("lume.tide_ok", 5.0)
	if not flag("crossed") and p.z < 8.6 and p.y > -0.3 and Vector2(p.x - H.x, p.z - H.z).length() < HR:
		set_flag("crossed")
		main.lume_once("lume.farol", 5.5)
		Game.save_game()
	if main.mode == "play" and p.z > 26.0 and not flag("near_node"):
		main.lume_once("lume.jump", 5.0)
	var lit = flag("crossed")
	lantern_mat.emission_energy_multiplier = lerpf(lantern_mat.emission_energy_multiplier, 2.4 if lit else 0.3, 0.05)
	lantern_light.light_energy = lerpf(lantern_light.light_energy, 3.0 if lit else 0.2, 0.05)

func on_node_scanned(_n: Interactable) -> void:
	main.lume_once("lume.tide_learn", 6.0)
