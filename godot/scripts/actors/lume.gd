class_name Lume
extends Node3D
## Lume — drone companheiro (02_lume_drone.glb): segue Íris sem colisão,
## escaneia, marca pontos e leva o sinal a relés distantes (GDD 07).

const SCALE := 0.24
var SPEC = {
	"body": [Vector3.ZERO, "", ""],
	"wingL": [Vector3(-0.4, 0.12, 0), "body", "^wing.*_00[5-7]$"],
	"wingR": [Vector3(0.4, 0.12, 0), "body", "^wing.*_(00[8-9]|010)$"],
	"lens": [Vector3(0, 0.02, 0.52), "body", "^lens"],
	"antenna": [Vector3(0.03, 0.34, 0), "body", "^antenna"],
}
var P = {}
var vel = Vector3.ZERO
var mode = "follow"
var target = Vector3.ZERO
var on_arrive: Callable
var pulse = 0.0
var t = 0.0
var light: OmniLight3D
var lens_mat: StandardMaterial3D
var pulse_mesh: MeshInstance3D
var _pulse_t = 1.0

func _ready() -> void:
	var model = Props.original("02_lume_drone.glb")
	var root = Node3D.new()
	root.scale = Vector3.ONE * SCALE
	add_child(root)
	IrisRig.build_rig(model, root, SPEC, "body", P)
	model.queue_free()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		IrisRig._tune_material(mi)
		if (mi as MeshInstance3D).name.begins_with("lens_003"):
			lens_mat = IrisRig._glow_unique(mi)
	light = OmniLight3D.new()
	light.light_color = Palette.RESSONANCIA
	light.omni_range = 5.0
	light.light_energy = 1.2
	add_child(light)
	pulse_mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radial_segments = 24
	sphere.rings = 12
	pulse_mesh.mesh = sphere
	var pm = StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.cull_mode = BaseMaterial3D.CULL_FRONT
	pm.albedo_color = Color(Palette.RESSONANCIA, 0.0)
	pulse_mesh.material_override = pm
	pulse_mesh.visible = false
	pulse_mesh.top_level = true
	add_child(pulse_mesh)

func place(p: Vector3) -> void:
	global_position = p
	vel = Vector3.ZERO

func fly_to(p: Vector3, cb: Callable = Callable()) -> void:
	mode = "travel"
	target = p
	on_arrive = cb

func follow() -> void:
	mode = "follow"
	on_arrive = Callable()

func scan_pulse(radius: float = 18.0) -> void:
	pulse = 1.0
	_pulse_t = 0.0
	pulse_mesh.visible = true
	pulse_mesh.set_meta("radius", radius)

func update_lume(dt: float, iris_pos: Vector3, iris_yaw: float, cam_pos: Vector3) -> void:
	t += dt
	var goal: Vector3
	if mode == "follow":
		var side = Vector3(0.75, 1.85 + sin(t * 1.7) * 0.08, -0.35).rotated(Vector3.UP, iris_yaw)
		goal = iris_pos + side
	else:
		goal = target + Vector3(0, sin(t * 2.0) * 0.1, 0)
	var k = 18.0 if mode == "follow" else 10.0
	var to_goal = goal - global_position
	vel += to_goal * k * dt
	vel *= exp(-(7.0 if mode == "follow" else 4.5) * dt)
	var max_v = 9.0 if mode == "travel" else 14.0
	if vel.length() > max_v:
		vel = vel.normalized() * max_v
	global_position += vel * dt
	if mode == "travel" and to_goal.length() < 0.4:
		mode = "hover"
		var cb = on_arrive
		on_arrive = Callable()
		if cb.is_valid():
			cb.call()
	var flat = Vector2(vel.x, vel.z)
	var want_yaw = rotation.y
	if flat.length() > 0.6:
		want_yaw = atan2(vel.x, vel.z)
	else:
		want_yaw = atan2(cam_pos.x - global_position.x, cam_pos.z - global_position.z)
	rotation.y = lerp_angle(rotation.y, want_yaw, 1.0 - exp(-5 * dt))
	rotation.x = clampf(flat.length() * 0.05, -0.4, 0.4)
	var flap = sin(t * 18.0) * 0.12
	P.wingL.rotation.z = -0.1 + flap
	P.wingR.rotation.z = 0.1 - flap
	P.lens.rotation.z += dt * (1.5 + pulse * 12.0)
	P.antenna.rotation.x = sin(t * 3.0) * 0.15
	pulse = lerpf(pulse, 0.0, 1.0 - exp(-2.5 * dt))
	if lens_mat:
		lens_mat.emission_energy_multiplier = 1.4 + pulse * 3.0
	light.light_energy = 1.2 + pulse * 5.0
	if _pulse_t < 1.0:
		_pulse_t = minf(1.0, _pulse_t + dt / 1.1)
		pulse_mesh.global_position = global_position
		var r: float = pulse_mesh.get_meta("radius", 18.0)
		pulse_mesh.scale = Vector3.ONE * (0.3 + _pulse_t * r)
		(pulse_mesh.material_override as StandardMaterial3D).albedo_color.a = (1.0 - _pulse_t) * 0.22
		pulse_mesh.visible = _pulse_t < 1.0
