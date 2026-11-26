class_name Decor
## Ambiente e cenário distante: céu, névoa, luz, oceano suspenso, ilhas no
## horizonte, nuvens e criaturas nadando no ar (o oceano que esqueceu de cair).

const SKY_SHADER := preload("res://assets/shaders/sky.gdshader")

const PRESETS := {
	"farol": {"top": "#081620", "mid": "#143645", "horizon": "#1B4250", "fog": "#1B4250", "fog_density": 0.008, "sun": "#FFD6A0", "sun_energy": 1.5, "ambient": "#A8E2E6", "ambient_energy": 0.75, "moon": Vector3(-0.45, 0.32, -0.83)},
	"jardim": {"top": "#081620", "mid": "#143645", "horizon": "#1E4A56", "fog": "#1E4A56", "fog_density": 0.009, "sun": "#FFD6A0", "sun_energy": 1.6, "ambient": "#A8E2E6", "ambient_energy": 0.8, "moon": Vector3(-0.3, 0.35, -0.88)},
	"cidade": {"top": "#110E22", "mid": "#2A2340", "horizon": "#4A3A52", "fog": "#3A3048", "fog_density": 0.010, "sun": "#F3AB63", "sun_energy": 1.4, "ambient": "#C9B8E0", "ambient_energy": 0.7, "moon": Vector3(0.5, 0.25, -0.83)},
	"coracao": {"top": "#02070C", "mid": "#07202A", "horizon": "#0D3440", "fog": "#0B2730", "fog_density": 0.012, "sun": "#9FE8E0", "sun_energy": 1.0, "ambient": "#6FB7C0", "ambient_energy": 0.7, "moon": Vector3(0.1, 0.55, -0.83)},
	"final_free": {"top": "#22406A", "mid": "#6E7FA0", "horizon": "#F0B88A", "fog": "#C9A08A", "fog_density": 0.006, "sun": "#FFE2B0", "sun_energy": 2.0, "ambient": "#FFE6CC", "ambient_energy": 0.9, "moon": Vector3(-0.6, 0.12, -0.78)},
	"final_keep": {"top": "#050C14", "mid": "#173040", "horizon": "#5A8C96", "fog": "#4A7A86", "fog_density": 0.008, "sun": "#BFF4FF", "sun_energy": 1.2, "ambient": "#BFEFFF", "ambient_energy": 0.9, "moon": Vector3(-0.45, 0.45, -0.77)},
}

static func apply_environment(we: WorldEnvironment, sun: DirectionalLight3D, preset: String, glow: bool, quality: String) -> void:
	var p: Dictionary = PRESETS.get(preset, PRESETS["farol"])
	var env = we.environment if we.environment else Environment.new()
	var sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("top_color", Color(p["top"]))
	sky_mat.set_shader_parameter("mid_color", Color(p["mid"]))
	sky_mat.set_shader_parameter("horizon_color", Color(p["horizon"]))
	sky_mat.set_shader_parameter("moon_dir", p["moon"])
	var sky = Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(p["ambient"])
	env.ambient_light_energy = p["ambient_energy"]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(p["fog"])
	env.fog_density = p["fog_density"]
	env.fog_sky_affect = 0.0
	env.glow_enabled = glow and quality == "high"
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	we.environment = env
	sun.light_color = Color(p["sun"])
	sun.light_energy = p["sun_energy"]
	sun.shadow_enabled = quality == "high"
	var md: Vector3 = p["moon"]
	sun.look_at_from_position(Vector3.ZERO, -md.normalized(), Vector3.UP)

## Oceano suspenso bem abaixo do arquipélago.
static func ocean(parent: Node3D, y: float = -34.0, preset: String = "") -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(2400, 2400)
	plane.subdivide_width = 48
	plane.subdivide_depth = 48
	mi.mesh = plane
	var deep = Color("#0B2E39")
	var shallow = Color("#154A55")
	if preset == "cidade":
		deep = Color("#1A1630")
		shallow = Color("#30284A")
	elif preset == "coracao":
		deep = Color("#04141A")
		shallow = Color("#0A2A33")
	elif preset == "final_free":
		deep = Color("#2C5A70")
		shallow = Color("#5A8CA0")
	elif preset == "final_keep":
		deep = Color("#7FB8C2")
		shallow = Color("#BFE8EE")
	mi.material_override = Builder.water_material({"deep": deep, "shallow": shallow, "opacity": 1.0, "streaks": 0.45, "scale": 0.09, "energy": 0.04, "wave": 0.25})
	mi.position.y = y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## Ilhas distantes com pilares (marcos no horizonte).
static func distant_islands(parent: Node3D, seed: int, count: int = 9, tint: Color = Color("#3B6B72")) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	var rng = RandomNumberGenerator.new()
	rng.seed = seed
	var top = Palette.mat(tint)
	var side = Palette.mat(tint.darkened(0.35))
	for i in count:
		var a = TAU * i / count + rng.randf() * 0.4
		var dist = rng.randf_range(110, 210)
		var r = rng.randf_range(12, 24)
		var c = Vector2(cos(a), sin(a)) * dist
		var y = rng.randf_range(-14, 6)
		var n = 6 + rng.randi() % 3
		var poly = PackedVector2Array()
		for k in n:
			var b = TAU * k / n + rng.randf() * 0.3
			poly.append(Vector2(cos(b), sin(b)) * r * rng.randf_range(0.8, 1.1))
		var holder = Node3D.new()
		holder.position = Vector3(c.x, y, c.y)
		root.add_child(holder)
		var mi = MeshInstance3D.new()
		mi.mesh = Builder.prism_mesh(poly, 0.0, -1.5, top, side)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		var rm = MeshInstance3D.new()
		rm.mesh = Builder.root_mesh(r, r * 1.1, n, rng.randi(), side)
		rm.position.y = -1.5
		rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(rm)
		for k in 2 + rng.randi() % 3:
			var h = r * rng.randf_range(0.6, 1.5)
			var pm = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(r * 0.12, h, r * 0.12)
			pm.mesh = box
			pm.material_override = side
			pm.position = Vector3(rng.randf_range(-0.5, 0.5) * r, h / 2, rng.randf_range(-0.4, 0.4) * r)
			pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(pm)
	return root

## Nuvens baixas à deriva.
static func clouds(parent: Node3D, seed: int, count: int = 14, y_range: Vector2 = Vector2(-16, -6)) -> Array:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed
	var out = []
	for i in count:
		var c = Props.make(["cloud1", "cloud2", "cloud3"][i % 3], {"height": rng.randf_range(2.0, 5.0)})
		c.scale *= Vector3(3.5, 1.0, 3.5)
		var a = rng.randf() * TAU
		var d = rng.randf_range(30, 120)
		c.position = Vector3(cos(a) * d, rng.randf_range(y_range.x, y_range.y), sin(a) * d)
		c.set_meta("speed", rng.randf_range(0.3, 0.9))
		parent.add_child(c)
		out.append(c)
	return out

## Criaturas do oceano suspenso: baleias e arraias nadando no céu em órbitas lentas.
static func sky_creatures(parent: Node3D, kinds: Array, seed: int) -> Array:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed
	var out = []
	for k in kinds:
		var c = Props.make(k[0], {"height": k[1], "anim": "Swim"})
		var holder = Node3D.new()
		holder.add_child(c)
		parent.add_child(holder)
		out.append({"node": holder, "r": rng.randf_range(k[2], k[3]), "y": rng.randf_range(k[4], k[5]), "speed": rng.randf_range(0.03, 0.07) * (1 if rng.randf() > 0.5 else -1), "phase": rng.randf() * TAU, "center": Vector2(rng.randf_range(-20, 20), rng.randf_range(-30, 10))})
	return out

static func animate_creatures(list: Array, time: float) -> void:
	for c in list:
		var a: float = c["phase"] + time * c["speed"]
		var r: float = c["r"]
		var ctr: Vector2 = c["center"]
		var n: Node3D = c["node"]
		n.position = Vector3(ctr.x + cos(a) * r, c["y"] + sin(time * 0.3 + c["phase"]) * 2.0, ctr.y + sin(a) * r)
		# tangente da órbita (o modelo nada para +Z)
		var tangent = Vector3(-sin(a), 0, cos(a)) * sign(c["speed"])
		n.rotation.y = atan2(tangent.x, tangent.z)
