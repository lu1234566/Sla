extends Region
## Coração Abissal — anel de ilhas em volta de um abismo; no centro, o Coração
## (esfera de vidro com água suspensa). Três setores de maré independentes:
## Oeste, Norte e Leste. Ensina a Ressonância dupla e fecha a campanha.
##
## Fluxo: Ilha Sul (Ressonância dupla; nó duplo Oeste+Norte ergue a ponte em
## dois lances) → Ilha Norte (nó duplo Norte+Leste) → espiral: plataformas
## (Oeste alto), ponte líquida (Norte alto, nó simples no patamar) e trincheira
## (Leste baixo) → Santuário 3 → Anel do Coração (guardião abissal, 3 pilões,
## pilares do padrão Oeste ▲ Norte ▼ Leste ▲) → abrir o Coração → escolha.

const S = Vector3(0, 0, 32)        # Ilha Sul (chegada)
const WP = Vector3(-12.5, 0, 3.0)  # pilar oeste (meio da ponte)
const N = Vector3(0, 0, -32)       # Ilha Norte
const L1 = Vector3(23.4, -4.5, -32)
const L2 = Vector3(23.4, -4.5, -12)
const RING_Y = -10.0
const R_OUT = 15.0
const R_IN = 6.5
const HEART = Vector3(0, -5.0, 0)
const TRENCH_X = 23.4
const SANCT_FRONT = 14.4
const S_SCALE = 2.0
const PYLON_REACH = 16.0
const PATTERN = {"oeste": true, "norte": false, "leste": true}

var pylons: Array = []
var pillars: Array = []
var tubes = {}  # setor -> MeshInstance3D (água no tubo de vidro)
var bottom_nodes = {}
var guard: Guardian
var sanct_center = Vector3.ZERO
var fountain = Vector3.ZERO
var heart_shell: MeshInstance3D
var heart_core: Node3D
var heart_light: OmniLight3D
var beam: MeshInstance3D
var core_mat: StandardMaterial3D
var node_bridge: Interactable
var node_spiral: Interactable
var node_l1: Interactable
var back_portal: Interactable

func build() -> void:
	music = "coracao"
	env = {"preset": "coracao", "center": Vector3(0, -6, 0), "distant": "#14404A",
		"creatures": [["whale", 11.0, 120, 170, -20, 10], ["manta", 3.2, 50, 80, -24, -8], ["anglerfish", 1.6, 30, 45, -22, -12], ["fish2", 1.0, 26, 40, -18, -6]]}
	kill_y = -30.0
	Game.set_flag("coracao.visited")
	add_sector("oeste", false)
	add_sector("norte", false)
	add_sector("leste", true)
	_south()
	_bridges()
	_north()
	_spiral()
	_sanctuary()
	_ring()
	_heart()
	_abyss_decor()
	_objectives()

# --- utilidades ------------------------------------------------------------------

func _top() -> Material:
	return Palette.mat(Color("#5E7E86"))

func _side() -> Material:
	return Palette.mat(Palette.ROCHA_ESCURA)

func _isle(c: Vector3, r: float, seed: int, depth: float = -1.0, safe: bool = true) -> PackedVector2Array:
	var poly = Builder.octagon(r, c.x, c.z)
	var mats = {"top": _top(), "side": _side(), "root": Palette.mat(Palette.NOITE)}
	if depth > 0.0:
		mats["root_depth"] = depth
	if not safe:
		mats["groups"] = []
	Builder.island(self, poly, [poly], c.y, 1.4, seed, mats)
	return poly

func _glow_crystals(center: Vector3, r_min: float, r_max: float, count: int, avoid: Callable = Callable()) -> void:
	for i in count:
		var a = rng.randf() * TAU
		var r = rng.randf_range(r_min, r_max)
		var p = center + Vector3(cos(a) * r, 0, sin(a) * r)
		if avoid.is_valid() and avoid.call(p):
			continue
		var n = ["crystal1", "crystal2", "crystal3", "crystal5", "mushroom1", "mushroom3"][rng.randi() % 6]
		Builder.prop(self, n, p, {"height": rng.randf_range(0.5, 1.4), "rot": rng.randf() * TAU})

# --- Ilha Sul: Câmara da Ressonância ----------------------------------------------

func _south() -> void:
	_isle(S, 9.0, 301, 12.0)
	add_spawn("portal", S + Vector3(0, 0, 3.0), PI)
	add_ix(IX.Portal.new("portal_volta", "farol", "portal_coracao", _always), S + Vector3(5.6, 0, 4.5), -PI / 2)
	# câmara: quatro colunas e teto
	var ch = S + Vector3(-3.6, 0, -2.0)
	for o in [Vector2(-2.2, -2.2), Vector2(2.2, -2.2), Vector2(-2.2, 2.2), Vector2(2.2, 2.2)]:
		Builder.prop(self, "column", ch + Vector3(o.x, 0, o.y), {"height": 3.6, "collide": 0.5})
	Builder.slab(self, Builder.rect(ch.x - 2.8, ch.z - 2.8, ch.x + 2.8, ch.z + 2.8), 4.0, 3.6, Palette.mat(Palette.CERAMICA), Palette.mat(Palette.PETROLEO), [])
	add_ix(IX.Pedestal.new("ressonancia", "dual"), ch)
	add_ix(IX.Echo.new("coracao_camara"), ch + Vector3(-1.4, 0.6, 1.6))
	var halo = MeshInstance3D.new()
	halo.mesh = Interactable.ring_mesh(1.6, 0.06)
	halo.material_override = Palette.glow(1.6, Palette.COBRE)
	halo.position = ch + Vector3(0, 3.3, 0)
	add_child(halo)
	animated.append(func(dt): halo.rotation.y += dt * 0.6)
	# nó duplo Oeste+Norte (ergue a ponte longa)
	node_bridge = add_ix(IX.TideNode.new("no_ponte", ["oeste", "norte"]), S + Vector3(1.2, 0, -6.0))
	# mirante do Coração
	Builder.stairs(self, S + Vector3(4.6, 0, 1.6), S + Vector3(4.6, 2.4, -2.4), 2.0, 7, Palette.mat(Palette.AREIA_CLARA), Palette.mat(Palette.CERAMICA))
	Builder.slab(self, Builder.rect(S.x + 3.2, S.z - 6.0, S.x + 6.0, S.z - 2.4), 2.4, -0.6, Palette.mat(Palette.CERAMICA), Palette.mat(Palette.PETROLEO))
	add_ix(IX.Echo.new("coracao_mirante"), S + Vector3(4.6, 3.0, -5.0))
	Builder.prop(self, "lamp_stand", S + Vector3(3.6, 2.4, -5.6), {"height": 1.6})
	_glow_crystals(S, 3.0, 8.0, 16, _avoid_south)

func _avoid_south(p: Vector3) -> bool:
	var rel = Vector2(p.x - S.x, p.z - S.z)
	if rel.distance_to(Vector2(-3.6, -2.0)) < 3.6 or rel.distance_to(Vector2(1.2, -6.0)) < 2.4:
		return true
	if rel.x > 2.6 and rel.x < 7.0 and rel.y < 2.4:
		return true
	if rel.distance_to(Vector2(5.6, 4.5)) < 2.0 or rel.distance_to(Vector2(0, 3.0)) < 1.6:
		return true
	return absf(rel.x + 2.0) < 2.0 and rel.y < -5.0

func _always() -> bool:
	return true

# --- Ponte longa em dois lances (Oeste e Norte) -------------------------------------

func _bridges() -> void:
	_isle(WP, 2.8, 311, 6.0)
	Builder.prop(self, "lamp_city", WP + Vector3(1.2, 0, 1.0), {"height": 2.6})
	add_bridge(Vector3(-3.4, 0, 25.4), Vector3(-11.4, 0, 5.4), 2.4, _west_up)
	add_bridge(Vector3(-11.4, 0, 0.6), Vector3(-3.4, 0, -24.4), 2.4, _north_up)
	for p in [Vector3(-3.4, 0, 25.4), Vector3(-11.4, 0, 5.4), Vector3(-11.4, 0, 0.6), Vector3(-3.4, 0, -24.4)]:
		var mi = MeshInstance3D.new()
		mi.mesh = Interactable.ring_mesh(1.0, 0.07)
		mi.material_override = Palette.glow(1.0)
		mi.position = p + Vector3(0, 0.05, 0)
		mi.scale = Vector3(1, 0.3, 1)
		add_child(mi)

func _west_up() -> bool:
	return high("oeste") and sector_level("oeste") > 0.6

func _north_up() -> bool:
	return high("norte") and sector_level("norte") > 0.6

# --- Ilha Norte -----------------------------------------------------------------------

func _north() -> void:
	_isle(N, 9.0, 321, 10.0)
	add_spawn("norte", N + Vector3(-2.2, 0, 5.4), -0.3)
	checkpoints.append({"id": "norte", "pos": N + Vector3(-2.2, 0, 5.4), "radius": 2.2})
	node_spiral = add_ix(IX.TideNode.new("no_espiral", ["norte", "leste"]), N + Vector3(3.6, 0, 3.0))
	for c in [Vector3(-4.5, 0, -3.0), Vector3(4.0, 0, -5.0), Vector3(-1.0, 0, -6.4)]:
		Builder.prop(self, "column_broken2", N + c, {"height": 2.2, "collide": 0.6, "rot": c.x})
	Builder.prop(self, "statue", N + Vector3(0, 0, -2.0), {"height": 2.6, "collide": 0.7})
	# agulha alta (opcional): só planando a partir da borda oeste
	_isle(Vector3(-17.6, -2.0, -38.0), 1.3, 331, 9.0, false)
	add_ix(IX.Echo.new("coracao_agulha"), Vector3(-17.6, -1.4, -38.0))
	_glow_crystals(N, 3.0, 8.0, 14, _avoid_north)

func _avoid_north(p: Vector3) -> bool:
	var rel = Vector2(p.x - N.x, p.z - N.z)
	if rel.distance_to(Vector2(3.6, 3.0)) < 2.6 or rel.distance_to(Vector2(-2.2, 5.4)) < 1.8:
		return true
	if rel.x > 6.0 and absf(rel.y) < 2.0:
		return true
	return rel.x < -1.0 and rel.y > 4.5

# --- Espiral: plataformas (Oeste) → ponte (Norte) → trincheira (Leste) -------------

func _spiral() -> void:
	# lance 1: plataformas de flutuação descendo para leste
	var xs = [10.3, 12.9, 15.5, 18.1]
	for i in xs.size():
		add_floater("oeste", Builder.ngon(1.2, 6, xs[i], N.z, PI / 6), -0.9 * (i + 1), -12.0)
	_isle(L1, 2.8, 341, 5.0)
	node_l1 = add_ix(IX.TideNode.new("no_patamar", ["norte"]), L1 + Vector3(0.9, 0, 0.6))
	# lance 2: ponte líquida (Norte alto)
	add_bridge(L1 + Vector3(0, 0, 2.3), L2 + Vector3(0, 0, -2.3), 2.4, _north_up)
	_isle(L2, 2.8, 351, 5.0)
	add_ix(IX.Echo.new("coracao_espiral"), L2 + Vector3(1.4, 0.6, -0.6))
	# lance 3: escada até o leito e trincheira (alaga com Leste alto)
	Builder.stairs(self, L2 + Vector3(0, 0, 2.62), Vector3(TRENCH_X, -12.0, -1.0), 2.4, 12, Palette.mat(Palette.AREIA_CLARA), Palette.mat(Palette.CERAMICA))
	var floor_poly = Builder.rect(TRENCH_X - 2.0, -9.4, TRENCH_X + 2.0, 14.0)
	Builder.slab(self, floor_poly, -12.0, -12.8, Palette.mat(Color("#6C7F7C")), _side())
	for x in [TRENCH_X - 2.8, TRENCH_X + 2.0]:
		Builder.slab(self, Builder.rect(x, -9.4, x + 0.8, 11.0), -8.0, -12.8, _top(), _side())
	add_basin("leste", Builder.rect(TRENCH_X - 2.0, -9.4, TRENCH_X + 2.0, 11.0), -12.6, -8.3)
	add_ix(IX.Echo.new("coracao_leito", _east_dry), Vector3(TRENCH_X + 1.2, -11.4, 6.0))
	for z in [2.0, 5.5, 9.0]:
		Builder.prop(self, ["mushroom2", "mushroom4", "crystal2"][int(z) % 3], Vector3(TRENCH_X - 1.3, -12.0, z), {"height": 0.8})
	Builder.stairs(self, Vector3(TRENCH_X, -12.0, 11.0), Vector3(TRENCH_X, RING_Y, SANCT_FRONT - 0.2), 2.4, 4, Palette.mat(Palette.AREIA_CLARA), Palette.mat(Palette.CERAMICA))

func _east_dry() -> bool:
	return sector_level("leste") < 0.3

# --- Santuário 3 ----------------------------------------------------------------------

func _sanctuary() -> void:
	var model = Props.original("04_santuario_das_mares.glb")
	model.scale = Vector3.ONE * S_SCALE
	model.rotation.y = PI
	model.position = Vector3(TRENCH_X, RING_Y - 0.15 * S_SCALE, SANCT_FRONT + 6.0)
	add_child(model)
	var zf = INF
	for mi in model.find_children("terrace*", "MeshInstance3D", true, false):
		var m = mi as MeshInstance3D
		var arr = m.mesh.surface_get_arrays(0)
		for v in arr[Mesh.ARRAY_VERTEX]:
			var w: Vector3 = m.global_transform * v
			if absf(w.x - TRENCH_X) < 1.0:
				zf = minf(zf, w.z)
	if zf < INF:
		model.position.z += SANCT_FRONT - zf
	sanct_center = model.position + Vector3(0, 0.15 * S_SCALE, 0)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		IrisRig._tune_material(mi)
		if mi.name.begins_with("heart"):
			mi.visible = false
	collide_model(model, ["island_root", "pool_water", "energy_ring", "heart", "portal_inner", "cap_"])
	var s_spawn = sanctuary_spawn(sanct_center, Vector3(0, 0, -1), S_SCALE)
	fountain = sanctuary_fountain(sanct_center, Vector3(0, 0, -1), S_SCALE)
	add_spawn("santuario", s_spawn + Vector3(0, 0.1, 0), PI * 1.25)
	checkpoints.append({"id": "santuario", "pos": s_spawn, "radius": 3.0})
	add_ix(IX.Action.new("fonte", _fountain_prompt, _fountain_act, 2.4, "scan.sanctuary"), fountain)
	back_portal = add_front_portal("portal_santuario", sanct_center, Vector3(0, 0, -1), Vector3(1, 0, 0), S_SCALE, "portal_coracao", _rested)
	# passarela até o anel
	var a = Vector2(sanct_center.x - 3.0, SANCT_FRONT + 0.9)
	var b = Vector2(9.0, 9.0)
	var d = b - a
	Builder.slab(self, Builder.rect_c((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, 2.6, d.length() + 1.2, atan2(-d.x, d.y)), RING_Y, RING_Y - 0.8, Palette.mat(Palette.CERAMICA), Palette.mat(Palette.PETROLEO))

func _rested() -> bool:
	return flag("rested")

func _fountain_prompt(_ctx: Dictionary) -> Dictionary:
	if not flag("rested"):
		return {"text": I18n.t("prompt.rest"), "action": "interact"}
	return {}

func _fountain_act(_ctx: Dictionary) -> void:
	if not flag("rested"):
		set_flag("rested")
		main.rest_at("santuario")

# --- Anel do Coração: guardião abissal, pilões e padrão -----------------------------

func _ring() -> void:
	var outer = Builder.octagon(R_OUT, 0, 0)
	var inner = Builder.octagon(R_IN, 0, 0)
	Builder.island(self, outer, Builder.ring(outer, inner), RING_Y, 2.4, 361, {"top": _top(), "side": _side(), "root_depth": 0.1})
	var rim = MeshInstance3D.new()
	rim.mesh = Interactable.ring_mesh(R_IN * cos(PI / 8) - 0.2, 0.08)
	rim.material_override = Palette.glow(1.4)
	rim.position = Vector3(0, RING_Y + 0.05, 0)
	rim.scale = Vector3(1, 0.3, 1)
	add_child(rim)
	# cobertura: grandes cristais
	for c in [[135, 12.6], [215, 8.2], [235, 12.6], [300, 8.2], [315, 12.6], [30, 12.6], [105, 8.2], [160, 8.0], [20, 8.0], [62, 8.2]]:
		Builder.prop(self, "gem_blue", _polar(c[0], c[1]), {"height": 2.8, "collide": 0.9, "cover": true, "rot": float(c[0])})
	# guardião abissal: maior, mais lento, visão longa
	var wp = []
	for i in 8:
		var a = PI / 2 + i * TAU / 8 + PI / 8
		wp.append(Vector3(cos(a) * 10.2, RING_Y, -sin(a) * 10.2))
	guard = add_guardian({"waypoints": wp, "perch": Vector3(0, RING_Y, -11.0), "floor_y": RING_Y,
		"params": {"scale": 1.15, "patrol_speed": 1.5, "chase_speed": 3.8, "vision_range": 12.0, "vision_angle": deg_to_rad(42), "alert_time": 0.9}},
		outer, RING_Y + 1.4, _guard_active)
	guardians[-1]["exit"] = Vector3(TRENCH_X - 1.0, RING_Y, SANCT_FRONT + 0.6)
	if flag("pylons"):
		guard.pacify()
	# três pilões fora do anel (alcance curto: é preciso entrar no anel)
	for p in [["rele_oeste", Vector3(-17.2, RING_Y + 1.4, 2.0)], ["rele_norte", Vector3(3.0, RING_Y + 1.4, -17.2)], ["rele_leste", Vector3(16.6, RING_Y + 1.4, -4.0)]]:
		var pos: Vector3 = p[1]
		_isle(pos, 1.3, int(pos.x * 7 + pos.z), 4.0, false)
		var py = add_ix(IX.RelayPylon.new(p[0], _on_pylon), pos)
		py.reach = PYLON_REACH
		py.radius = PYLON_REACH
		pylons.append(py)
	# pilares do padrão + nós simples + tubos que mostram o nível de cada setor
	var spots = {"oeste": [190.0, 170.0], "norte": [280.0, 260.0], "leste": [350.0, 10.0]}
	for sid in spots:
		var pil_pos = _polar(spots[sid][0], 12.9)
		var sym = "▲" if PATTERN[sid] else "▼"
		var pil = add_ix(IX.ReadingPillar.new("pilar_" + sid, "scan.pattern", {"pattern": "%s %s" % [I18n.t("sector." + sid), sym]}, _on_pillar), pil_pos)
		pillars.append(pil)
		var lbl = Label3D.new()
		lbl.text = sym
		lbl.font_size = 140
		lbl.pixel_size = 0.008
		lbl.modulate = Palette.RESSONANCIA if PATTERN[sid] else Palette.COBRE
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = pil_pos + Vector3(0, 3.3, 0)
		add_child(lbl)
		bottom_nodes[sid] = add_ix(IX.TideNode.new("no_" + sid + "_anel", [sid]), _polar(spots[sid][1], 12.3))
		_tube(sid, _polar(spots[sid][0] + 6.5, 12.9))
	# píer até o Coração
	Builder.slab(self, Builder.rect(-1.3, 2.6, 1.3, R_IN * cos(PI / 8) + 0.4), RING_Y, RING_Y - 0.6, Palette.mat(Palette.CERAMICA), Palette.mat(Palette.PETROLEO))
	add_ix(IX.Action.new("coracao_no", _heart_prompt, _heart_act, 2.0, "scan.sanctuary"), Vector3(0, RING_Y, 3.4))

## Ponto no anel por ângulo (graus; 0 = leste, 90 = sul) e raio.
func _polar(deg: float, r: float) -> Vector3:
	var a = deg_to_rad(deg)
	return Vector3(cos(a) * r, RING_Y, sin(a) * r)

func _tube(sid: String, pos: Vector3) -> void:
	var glass = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.34
	cyl.bottom_radius = 0.34
	cyl.height = 2.6
	cyl.radial_segments = 10
	glass.mesh = cyl
	glass.material_override = Palette.mat(Color("#BFEFFF"), {"alpha": 0.22, "roughness": 0.1})
	glass.position = pos + Vector3(0, 1.3, 0)
	add_child(glass)
	var water = MeshInstance3D.new()
	var wc = CylinderMesh.new()
	wc.top_radius = 0.28
	wc.bottom_radius = 0.28
	wc.height = 1.0
	wc.radial_segments = 10
	water.mesh = wc
	water.material_override = Palette.glow(1.2)
	water.position = pos
	add_child(water)
	tubes[sid] = water

func _guard_active() -> bool:
	return not flag("pylons")

func _on_pylon(_p: Interactable) -> void:
	var on = 0
	for p in pylons:
		if p.active:
			on += 1
	if on >= pylons.size():
		set_flag("pylons")
		guard.pacify()
		Sfx.play("pacify")
		main.say("lume.pacified", 4.5)

func _on_pillar(_p: Interactable) -> void:
	for p in pillars:
		if not p.read:
			return
	main.say("lume.pattern", 6.0, {"pattern": _pattern_text()})

func _pattern_text() -> String:
	var parts = []
	for sid in ["oeste", "norte", "leste"]:
		parts.append("%s %s" % [I18n.t("sector." + sid), "▲" if PATTERN[sid] else "▼"])
	return " · ".join(parts)

func _pattern_ok() -> bool:
	for sid in PATTERN:
		if high(sid) != PATTERN[sid] or sectors[sid].transitioning:
			return false
	return true

# --- O Coração ----------------------------------------------------------------------

func _heart() -> void:
	heart_shell = MeshInstance3D.new()
	var sm = SphereMesh.new()
	sm.radius = 3.4
	sm.height = 6.8
	sm.radial_segments = 24
	sm.rings = 12
	heart_shell.mesh = sm
	var shell_mat = StandardMaterial3D.new()
	shell_mat.albedo_color = Color(0.75, 0.95, 1.0, 0.22)
	shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell_mat.roughness = 0.05
	shell_mat.metallic = 0.2
	shell_mat.emission_enabled = true
	shell_mat.emission = Palette.RESSONANCIA
	shell_mat.emission_energy_multiplier = 0.15
	shell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	heart_shell.material_override = shell_mat
	heart_shell.position = HEART
	heart_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(heart_shell)
	var water = MeshInstance3D.new()
	var wm = SphereMesh.new()
	wm.radius = 2.6
	wm.height = 3.4
	wm.is_hemisphere = false
	water.mesh = wm
	water.material_override = Builder.water_material({"opacity": 0.85, "energy": 0.5, "scale": 2.0, "wave": 0.0})
	water.position = HEART + Vector3(0, -0.8, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	heart_core = Props.make("crystal3", {"height": 2.4})
	heart_core.position = HEART + Vector3(0, -1.1, 0)
	add_child(heart_core)
	core_mat = Palette.unique(Palette.RESSONANCIA, {"emission": Palette.RESSONANCIA, "energy": 0.8})
	var glow = MeshInstance3D.new()
	var gm = SphereMesh.new()
	gm.radius = 0.6
	gm.height = 1.2
	glow.mesh = gm
	glow.material_override = core_mat
	glow.position = HEART
	add_child(glow)
	heart_light = OmniLight3D.new()
	heart_light.light_color = Palette.RESSONANCIA
	heart_light.omni_range = 22.0
	heart_light.light_energy = 1.2
	heart_light.position = HEART
	add_child(heart_light)
	for i in 3:
		var ring = MeshInstance3D.new()
		ring.mesh = Interactable.ring_mesh(4.2 + i * 0.7, 0.07)
		ring.material_override = Palette.glow(1.0 + i * 0.3, Palette.COBRE if i == 1 else Palette.RESSONANCIA)
		ring.position = HEART
		ring.rotation = Vector3(0.4 * (i + 1), i * 1.1, 0.2 * i)
		add_child(ring)
		var spd = 0.15 + i * 0.1
		animated.append(func(dt): ring.rotate_object_local(Vector3.UP, dt * spd * (2.5 if flag("open") else 1.0)))
	beam = MeshInstance3D.new()
	var bm = CylinderMesh.new()
	bm.top_radius = 0.8
	bm.bottom_radius = 1.4
	bm.height = 60.0
	beam.mesh = bm
	var beam_mat = Palette.unique(Palette.RESSONANCIA, {"emission": Palette.RESSONANCIA, "energy": 2.5, "alpha": 0.35, "unshaded": true})
	beam.material_override = beam_mat
	beam.position = HEART + Vector3(0, 30.0, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	_apply_heart_state(true)
	animated.append(_anim_heart)

func _apply_heart_state(instant: bool) -> void:
	var open = flag("open")
	beam.visible = open
	if instant:
		heart_shell.scale = Vector3.ONE * (1.5 if open else 1.0)
		heart_shell.visible = not open

func _anim_heart(dt: float) -> void:
	heart_core.rotation.y += dt * (1.6 if flag("open") else 0.4)
	var ready = flag("pylons") and _pattern_ok()
	core_mat.emission_energy_multiplier = (3.0 + sin(t * 3.0)) if flag("open") else ((1.6 + 0.6 * sin(t * 5.0)) if ready else 0.8)
	heart_light.light_energy = 2.4 if flag("open") else (1.6 if ready else 1.0)

func _heart_prompt(_ctx: Dictionary) -> Dictionary:
	if Game.state.get("ending", "") != "" and flag("chosen"):
		return {}
	if flag("open"):
		return {"text": I18n.t("prompt.choose", {"choice": I18n.t("final.free") + " / " + I18n.t("final.keep")}), "action": "interact"}
	if not flag("pylons"):
		return {"text": I18n.t("refuse.no_power"), "action": "interact", "disabled": true}
	if not _pattern_ok():
		return {"text": I18n.t("scan.pattern", {"pattern": _pattern_text()}), "action": "interact", "disabled": true}
	return {"text": I18n.t("prompt.heart"), "action": "interact"}

func _heart_act(_ctx: Dictionary) -> void:
	if not flag("open"):
		set_flag("open")
		Sfx.play("unlock")
		beam.visible = true
		var tw = create_tween()
		tw.tween_property(heart_shell, "scale", Vector3.ONE * 1.5, 2.0).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(heart_shell.hide)
		main.on_memory("coracao")
		main.say("lume.heart", 5.0)
		main.cam.look_at_point(HEART, 3.0)
		return
	_open_choice()

func _open_choice() -> void:
	main.narrate("final.question")
	main.mode = "paused"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play("ui_open")
	main.ui.open_menu(I18n.t("region.coracao"), [
		[I18n.t("final.free"), _choose_free],
		[I18n.t("final.keep"), _choose_keep],
		[I18n.t("menu.back"), main.resume],
	], {"body": I18n.t("final.question"), "width": 640})

func _choose_free() -> void:
	_choose("free")

func _choose_keep() -> void:
	_choose("keep")

func _choose(c: String) -> void:
	set_flag("chosen")
	main.ui.close_menu()
	main.mode = "play"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	main.finish(c)

# --- abismo (cenário) -------------------------------------------------------------------

func _abyss_decor() -> void:
	var r2 = RandomNumberGenerator.new()
	r2.seed = 909
	# cristais pendentes sob o anel e brilho no fundo do abismo
	for i in 22:
		var a = r2.randf() * TAU
		var r = r2.randf_range(4.0, 14.0)
		var p = Props.make(["crystal1", "crystal3", "crystal5"][i % 3], {"height": r2.randf_range(1.5, 4.0)})
		p.position = Vector3(cos(a) * r, RING_Y - 2.4 - r2.randf_range(0.0, 1.5), sin(a) * r)
		p.rotation = Vector3(PI, r2.randf() * TAU, 0)
		add_child(p)
	var pit = MeshInstance3D.new()
	var disc = CylinderMesh.new()
	disc.top_radius = 9.0
	disc.bottom_radius = 9.0
	disc.height = 0.1
	disc.radial_segments = 24
	pit.mesh = disc
	pit.material_override = Palette.mat(Color("#0E3E48"), {"emission": Palette.RESSONANCIA, "energy": 0.35, "alpha": 0.6, "unshaded": true})
	pit.position = Vector3(0, -26.0, 0)
	add_child(pit)
	# bolhas de água suspensa subindo do abismo
	for i in 26:
		var b = MeshInstance3D.new()
		var sm = SphereMesh.new()
		var rad = r2.randf_range(0.12, 0.35)
		sm.radius = rad
		sm.height = rad * 2.0
		sm.radial_segments = 8
		sm.rings = 4
		b.mesh = sm
		b.material_override = Palette.glow(1.4)
		var a = r2.randf() * TAU
		var r = r2.randf_range(1.0, 6.0)
		b.position = Vector3(cos(a) * r, r2.randf_range(-26, -6), sin(a) * r)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b)
		var spd = r2.randf_range(0.6, 1.6)
		animated.append(func(dt): b.position.y = -26.0 + fmod(b.position.y + 26.0 + dt * spd, 22.0))

# --- objetivos e lógica ---------------------------------------------------------------

func _objectives() -> void:
	add_objective("k_dual", func(): return Game.has_ability("dual"), func(): return S + Vector3(-3.6, 0, -2.0))
	add_objective("k_bridge", func(): return flag("crossed"), func(): return node_bridge.global_position if not (high("oeste") and high("norte")) else N + Vector3(-3.0, 0, 7.6))
	add_objective("k_spiral", func(): return flag("trench_done"), func(): return _spiral_target())
	add_objective("k_sanct", func(): return flag("rested"), func(): return fountain)
	add_objective("k_guardian", func(): return flag("pylons"), func(): return _next_pylon())
	add_objective("k_pattern", func(): return _pattern_ok() or flag("open"), func(): return _next_pattern_node())
	add_objective("k_heart", func(): return flag("open"), func(): return Vector3(0, RING_Y, 3.4))
	add_objective("k_choose", func(): return flag("chosen"), func(): return Vector3(0, RING_Y, 3.4))
	add_objective("k_done", func(): return false, func(): return back_portal.global_position)

func _spiral_target() -> Vector3:
	var p: Vector3 = main.player.global_position
	if p.y > -2.0 and p.z < -20.0:
		return node_spiral.global_position if high("leste") else Vector3(10.3, -0.9, N.z)
	if not high("norte"):
		return node_l1.global_position
	if high("leste"):
		return node_spiral.global_position
	return Vector3(TRENCH_X, -12.0, 8.0)

func _next_pylon() -> Vector3:
	for p in pylons:
		if not p.active:
			return p.global_position
	return Vector3.ZERO

func _next_pattern_node() -> Vector3:
	for sid in ["oeste", "norte", "leste"]:
		if high(sid) != PATTERN[sid]:
			return bottom_nodes[sid].global_position
	return Vector3(0, RING_Y, 3.4)

func region_tick(_dt: float) -> void:
	var p: Vector3 = main.player.global_position
	for sid in tubes:
		var w: MeshInstance3D = tubes[sid]
		var lv = maxf(0.05, sector_level(sid))
		w.scale = Vector3(1, lv * 2.4, 1)
		w.position.y = RING_Y + lv * 1.2
	if not flag("crossed") and p.z < -22.0 and p.y > -1.0 and absf(p.x) < 10.0:
		set_flag("crossed")
		main.lume_once("lume.dual", 6.0)
	if not flag("trench_done") and p.z > 12.0 and p.y < -9.0 and p.x > TRENCH_X - 4.0:
		set_flag("trench_done")
	if Game.has_ability("dual"):
		main.lume_once("lume.dual", 6.0)
	if main.mode == "play":
		main.lume_once("lume.coracao", 5.0)
