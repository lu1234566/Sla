class_name IrisRig
extends Node3D
## Íris — rig procedural sobre o GLB original (peças separadas, sem esqueleto).
## Altura-alvo 1,35 m (GDD 06). Animações: idle, caminhada, salto, queda,
## planar, escaneamento, interação, esquiva e dano.

const HEIGHT := 1.35
const MODEL_HEIGHT := 3.23

## pivô -> [posição da junta no modelo, pai, filtro por nome de peça]
var SPEC = {
	"hips": [Vector3(0, 1.5, 0), "", ""],
	"torso": [Vector3(0, 1.62, 0), "hips", "^(torso|chest|core|neck|backpack|battery|shoulder)"],
	"head": [Vector3(0, 2.32, 0), "torso", "^(helmet|visor|eye_strip)"],
	"antenna": [Vector3(0.34, 2.86, -0.06), "head", "^antenna"],
	"armL": [Vector3(-0.6, 2.02, 0.02), "torso", "^arm_0(2[0-4])"],
	"foreL": [Vector3(-0.72, 1.64, 0.04), "armL", "^(elbow|gauntlet|hand)_02[0-4]"],
	"armR": [Vector3(0.6, 2.02, 0.02), "torso", "^arm_02[5-9]"],
	"foreR": [Vector3(0.72, 1.64, 0.04), "armR", "^(elbow|gauntlet|hand)_02[5-9]"],
	"legL": [Vector3(-0.22, 1.5, 0), "hips", "^thigh.*_00[0-6]$"],
	"shinL": [Vector3(-0.25, 1.03, 0), "legL", "^(boot|sole|shin|knee).*_00[0-6]$"],
	"legR": [Vector3(0.22, 1.5, 0), "hips", "^thigh.*_(00[7-9]|01[0-3])$"],
	"shinR": [Vector3(0.25, 1.03, 0), "legR", "^(boot|sole|shin|knee).*_(00[7-9]|01[0-3])$"],
}

var P = {}
var base = {}
var core_mat: StandardMaterial3D
var eye_mat: StandardMaterial3D
var visor_color = Color("#7CF4DC")
var phase = 0.0
var t = 0.0
var w = {"move": 0.0, "air": 0.0, "glide": 0.0, "scan": 0.0, "interact": 0.0, "dodge": 0.0, "hurt": 0.0}
var lean = 0.0

func _ready() -> void:
	var model = Props.original("01_iris_exploradora.glb")
	var root = Node3D.new()
	root.scale = Vector3.ONE * HEIGHT / MODEL_HEIGHT
	add_child(root)
	build_rig(model, root, SPEC, "hips", P)
	model.queue_free()
	for k in P:
		base[k] = P[k].position
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m = mi as MeshInstance3D
		_tune_material(m)
		if m.name.begins_with("core_018"):
			core_mat = _glow_unique(m)
		elif m.name.begins_with("eye_strip"):
			eye_mat = _glow_unique(m)

static func _tune_material(m: MeshInstance3D) -> void:
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for s in m.mesh.get_surface_count():
		var src = m.get_active_material(s) as StandardMaterial3D
		if src and not src.has_meta("tuned"):
			src.roughness = 0.85
			src.metallic = 0.3 if src.resource_name == "gold" else 0.0
			if src.resource_name == "glow":
				src.emission_enabled = true
				src.emission = src.albedo_color
				src.emission_energy_multiplier = 1.6
			src.set_meta("tuned", true)

static func _glow_unique(m: MeshInstance3D) -> StandardMaterial3D:
	var mat = (m.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	m.set_surface_override_material(0, mat)
	return mat

## Cria pivôs nas juntas e re-parenteia as peças (vértices já em espaço do modelo).
static func build_rig(model: Node, root: Node3D, spec: Dictionary, root_pivot: String, out: Dictionary) -> void:
	var world = {}
	for name in spec:
		var def: Array = spec[name]
		var g = Node3D.new()
		g.name = name
		out[name] = g
		world[name] = def[0]
		var parent_world: Vector3 = world[def[1]] if def[1] != "" else Vector3.ZERO
		g.position = def[0] - parent_world
		(out[def[1]] if def[1] != "" else root).add_child(g)
	var regexes = {}
	for name in spec:
		if spec[name][2] != "":
			var re = RegEx.new()
			re.compile(spec[name][2])
			regexes[name] = re
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m = mi as MeshInstance3D
		var owner = root_pivot
		for name in spec:
			if regexes.has(name) and regexes[name].search(m.name):
				owner = name
		m.owner = null
		m.get_parent().remove_child(m)
		m.transform = Transform3D(Basis.IDENTITY, -world[owner])
		out[owner].add_child(m)

func set_visor(c: Color) -> void:
	visor_color = c

## s: speed, grounded, vy, gliding, scanning, interacting, dodging, hurt, integrity, turn
func animate(dt: float, s: Dictionary) -> void:
	t += dt
	var run = minf(1.0, s.speed / 4.5)
	w.move = lerpf(w.move, run if s.grounded else 0.0, 1.0 - exp(-10 * dt))
	w.air = lerpf(w.air, 0.0 if s.grounded else 1.0, 1.0 - exp(-12 * dt))
	w.glide = lerpf(w.glide, 1.0 if s.gliding else 0.0, 1.0 - exp(-8 * dt))
	w.scan = lerpf(w.scan, 1.0 if s.scanning else 0.0, 1.0 - exp(-8 * dt))
	w.interact = lerpf(w.interact, 1.0 if s.interacting else 0.0, 1.0 - exp(-10 * dt))
	w.dodge = lerpf(w.dodge, 1.0 if s.dodging else 0.0, 1.0 - exp(-18 * dt))
	w.hurt = lerpf(w.hurt, 1.0 if s.hurt else 0.0, 1.0 - exp(-10 * dt))
	phase += dt * (s.speed / 1.15) * PI
	var sw = sin(phase)
	var cw = cos(phase)
	var idle = sin(t * 2.1)
	var stride = 0.75 * w.move
	var air = w.air * (1.0 - w.glide)
	# mesma convenção do protótipo web (ambos os motores: mão direita, Y para cima)
	P.legL.rotation.x = -sw * stride - air * 0.55 + w.glide * 0.35 - w.dodge * 0.9
	P.legR.rotation.x = sw * stride + air * 0.25 + w.glide * 0.5 - w.dodge * 0.9
	P.shinL.rotation.x = maxf(0.0, -cw) * w.move + air * 0.9 + w.glide * 0.3 + w.dodge * 1.4
	P.shinR.rotation.x = maxf(0.0, cw) * w.move + air * 0.4 + w.glide * 0.4 + w.dodge * 1.4
	var arm = 0.6 * w.move
	P.armL.rotation.x = sw * arm - air * 0.6 - w.interact * 1.2 - w.dodge * 0.6
	P.armR.rotation.x = -sw * arm - air * 0.6 - w.interact * 1.2 - w.scan * 1.5 - w.dodge * 0.6
	P.armL.rotation.z = -0.08 - w.glide * 1.25 - air * 0.35
	P.armR.rotation.z = 0.08 + w.glide * 1.25 + air * 0.35 - w.scan * 0.2
	P.foreL.rotation.x = -0.25 - 0.3 * w.move - w.interact * 0.3
	P.foreR.rotation.x = -0.25 - 0.3 * w.move - w.interact * 0.3 - w.scan * 0.4
	var bob = absf(sw) * 0.09 * w.move + idle * 0.015 * (1.0 - w.move)
	P.hips.position.y = base.hips.y + bob - w.dodge * 0.35 - w.hurt * 0.1
	P.hips.rotation.x = w.glide * 0.35 + w.dodge * 0.6 + w.move * 0.06 - w.hurt * 0.2
	P.torso.rotation.y = sw * 0.12 * w.move
	lean = lerpf(lean, -s.get("turn", 0.0) * 0.08, 1.0 - exp(-6 * dt))
	P.hips.rotation.z = lean * (w.move + w.glide)
	var look = (1.0 - w.move) * (1.0 - w.air)
	P.head.rotation.y = sin(t * 0.45) * 0.35 * look
	P.head.rotation.x = sin(t * 0.7) * 0.06 * look - w.scan * 0.15 - w.glide * 0.25
	P.head.rotation.z = w.scan * 0.18
	P.antenna.rotation.x = sin(t * 3.1) * 0.12 + w.move * 0.25 * sin(phase * 2.0) - s.vy * 0.03
	P.antenna.rotation.z = sin(t * 2.3) * 0.08
	var integ: int = s.get("integrity", 3)
	var pulse = w.scan * (0.6 + 0.6 * sin(t * 14.0))
	if core_mat:
		core_mat.emission_energy_multiplier = 0.4 + integ * 0.45 + pulse
		var warn = maxf(w.hurt, 0.5 + 0.5 * sin(t * 5.0) if integ <= 1 else 0.0)
		var col = visor_color.lerp(Palette.SAL, warn)
		core_mat.emission = col
		core_mat.albedo_color = col
		if eye_mat:
			eye_mat.emission = col
			eye_mat.albedo_color = col
