class_name Guardian
extends Node3D
## Guardião de Sal (03_guardiao_de_sal.glb) — GuardAI sem combate letal
## (GDD 07/11): dormente, despertando, patrulha, alerta, perseguição limitada,
## repouso, retornando e pacificado. Variantes por região via `params`.

signal guard_event(type: String)

var SPEC = {
	"body": [Vector3(0, 1.0, 0), "", ""],
	"L1": [Vector3(-0.6, 1.04, 0.49), "body", "^(upper_leg|joint|lower_leg|foot)_00[5-8]$"],
	"L2": [Vector3(-0.6, 1.04, -0.02), "body", "^(upper_leg|joint|lower_leg|foot)_(009|01[0-2])$"],
	"L3": [Vector3(-0.6, 1.04, -0.49), "body", "^(upper_leg|joint|lower_leg|foot)_01[3-6]$"],
	"R1": [Vector3(0.6, 1.04, 0.49), "body", "^(upper_leg|joint|lower_leg|foot)_02[0-3]$"],
	"R2": [Vector3(0.6, 1.04, -0.02), "body", "^(upper_leg|joint|lower_leg|foot)_02[4-7]$"],
	"R3": [Vector3(0.6, 1.04, -0.49), "body", "^(upper_leg|joint|lower_leg|foot)_(02[8-9]|03[0-1])$"],
}
const TRIPOD_A := ["L1", "L3", "R2"]

var P = {}
var params = {"vision_range": 8.5, "vision_angle": deg_to_rad(55), "alert_time": 0.75, "chase_time": 4.0,
	"chase_speed": 4.3, "patrol_speed": 1.9, "hear_radius": 2.0, "scale": 0.8}
var waypoints: Array = []
var perch = Vector3.ZERO
var floor_y = 0.0
var state = "dormant"
var timer = 0.0
var wp = 0
var gait = 0.0
var speed = 0.0
var t = 0.0
var alert_level = 0.0
var yaw = PI
var eye_mat: StandardMaterial3D
var crystal_mat: StandardMaterial3D
var light: OmniLight3D
var cone: MeshInstance3D
var cone_mat: StandardMaterial3D
var player_ref: Node3D

func setup(cfg: Dictionary) -> void:
	waypoints = cfg["waypoints"]
	perch = cfg.get("perch", waypoints[0])
	floor_y = cfg.get("floor_y", waypoints[0].y)
	for k in cfg.get("params", {}):
		params[k] = cfg["params"][k]

func _ready() -> void:
	var model = Props.original("03_guardiao_de_sal.glb")
	var root = Node3D.new()
	root.scale = Vector3.ONE * params["scale"]
	add_child(root)
	IrisRig.build_rig(model, root, SPEC, "body", P)
	model.queue_free()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m = mi as MeshInstance3D
		IrisRig._tune_material(m)
		if m.name.begins_with("eye_003"):
			eye_mat = IrisRig._glow_unique(m)
		elif m.name.begins_with("central_crystal"):
			crystal_mat = IrisRig._glow_unique(m)
	light = OmniLight3D.new()
	light.position = Vector3(0, 1.0, 0.9)
	light.omni_range = 6.0
	add_child(light)
	cone = MeshInstance3D.new()
	cone_mat = StandardMaterial3D.new()
	cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone_mat.albedo_color = Color(Palette.SAL, 0.14)
	cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone_mat.no_depth_test = false
	cone.mesh = _sector_mesh(params["vision_angle"])
	cone.material_override = cone_mat
	cone.top_level = true
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cone)
	global_position = perch

func _sector_mesh(half: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n = 24
	for i in n:
		var a0 = -half + 2.0 * half * i / n
		var a1 = -half + 2.0 * half * (i + 1) / n
		for v in [Vector3.ZERO, Vector3(sin(a1), 0, cos(a1)), Vector3(sin(a0), 0, cos(a0))]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()

func set_assisted(on: bool) -> void:
	if on:
		params["vision_range"] *= 0.78
		params["alert_time"] *= 1.6
		params["chase_time"] *= 0.7
		params["chase_speed"] *= 0.8

func set_state(s: String) -> void:
	if state == s:
		return
	state = s
	timer = 0.0
	guard_event.emit("state:" + s)

func reset(active: bool) -> void:
	timer = 0.0
	if state == "pacified":
		return
	if active:
		global_position = waypoints[0]
		wp = 1 % waypoints.size()
		set_state("patrol")
	else:
		global_position = perch
		set_state("dormant")

func pacify() -> void:
	set_state("pacified")

func can_see(p: Vector3) -> bool:
	var d = Vector2(p.x - global_position.x, p.z - global_position.z)
	var dist = d.length()
	if dist < params["hear_radius"]:
		return true
	if dist > params["vision_range"]:
		return false
	var fwd = Vector2(sin(yaw), cos(yaw))
	if fwd.angle_to(d) > params["vision_angle"] or fwd.angle_to(d) < -params["vision_angle"]:
		return false
	var space = get_world_3d().direct_space_state
	var q = PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), p + Vector3(0, 0.8, 0), 1)
	var hit = space.intersect_ray(q)
	return hit.is_empty()

func _move_toward(goal: Vector3, spd: float, dt: float) -> float:
	var d = Vector2(goal.x - global_position.x, goal.z - global_position.z)
	var dist = d.length()
	if dist < 0.001:
		return 0.0
	var want = atan2(d.x, d.y)
	yaw = lerp_angle(yaw, want, 1.0 - exp(-6 * dt))
	var diff = absf(wrapf(want - yaw, -PI, PI))
	var k = maxf(0.2, 1.0 - diff / 1.5)
	var step = minf(dist, spd * dt) * k
	global_position.x += d.x / dist * step
	global_position.z += d.y / dist * step
	speed = spd * k
	return dist

## ctx: {active: bool, player_pos: Vector3, in_zone: bool, dodging: bool}
func update_guard(dt: float, ctx: Dictionary) -> void:
	t += dt
	timer += dt
	speed = 0.0
	var pp: Vector3 = ctx["player_pos"]
	var in_zone: bool = ctx["in_zone"]
	if state != "pacified":
		if not ctx["active"] and state not in ["dormant", "waking"]:
			set_state("returning")
		if ctx["active"] and state in ["dormant", "returning"]:
			set_state("waking")
	match state:
		"dormant":
			global_position = global_position.lerp(perch, 1.0 - exp(-3 * dt))
		"waking":
			if _move_toward(waypoints[0], params["patrol_speed"], dt) < 0.3:
				wp = 1 % waypoints.size()
				set_state("patrol")
		"returning":
			if _move_toward(perch, params["patrol_speed"] * 1.3, dt) < 0.3:
				set_state("dormant")
		"patrol":
			if _move_toward(waypoints[wp], params["patrol_speed"], dt) < 0.25:
				wp = (wp + 1) % waypoints.size()
			if in_zone and can_see(pp):
				set_state("alert")
				guard_event.emit("alert")
		"alert":
			yaw = lerp_angle(yaw, atan2(pp.x - global_position.x, pp.z - global_position.z), 1.0 - exp(-10 * dt))
			if not in_zone:
				set_state("rest")
			elif timer > params["alert_time"]:
				set_state("chase")
				guard_event.emit("chase")
		"chase":
			_move_toward(pp, params["chase_speed"], dt)
			var dist = Vector2(pp.x - global_position.x, pp.z - global_position.z).length()
			if dist < 1.25 * params["scale"] / 0.8 and not ctx["dodging"] and in_zone:
				guard_event.emit("hit")
				set_state("rest")
			elif not in_zone or timer > params["chase_time"]:
				guard_event.emit("lost")
				set_state("rest")
		"rest":
			if timer > 2.2:
				var best = 0
				var bd = INF
				for i in waypoints.size():
					var dd: float = waypoints[i].distance_to(global_position)
					if dd < bd:
						bd = dd
						best = i
				wp = best
				set_state("patrol")
		"pacified":
			if _move_toward(perch, params["patrol_speed"], dt) < 0.3:
				yaw = lerp_angle(yaw, PI, 1.0 - exp(-2 * dt))
	var on_perch = Vector2(global_position.x - perch.x, global_position.z - perch.z).length() < 1.6
	global_position.y = lerpf(global_position.y, perch.y if on_perch else floor_y, 1.0 - exp(-6 * dt))
	_animate(dt)

func _animate(dt: float) -> void:
	var moving = minf(1.0, speed / 2.0)
	gait += dt * (2.0 + speed * 2.6)
	var resting = state in ["dormant", "rest", "pacified"]
	for leg in ["L1", "L2", "L3", "R1", "R2", "R3"]:
		var ph = gait + (0.0 if leg in TRIPOD_A else PI)
		var s = -1.0 if leg.begins_with("L") else 1.0
		var lift = maxf(0.0, sin(ph)) * 0.35 * moving
		P[leg].rotation.y = cos(ph) * 0.35 * moving * s
		P[leg].rotation.z = s * lift + (s * -0.18 if resting else 0.0)
	P.body.position.y = 1.0 + (-0.22 if resting else 0.0) + absf(sin(gait)) * 0.05 * moving
	P.body.rotation.z = sin(t * 40.0) * 0.03 if state == "alert" else 0.0
	P.body.rotation.x = 0.12 if state == "chase" else 0.0
	rotation.y = yaw
	var hostile = state != "pacified"
	var awake = state not in ["dormant", "pacified"]
	var intensity = (0.8 + 0.4 * sin(t * 2.2) if awake else 0.25) if hostile else 1.4
	if state == "alert":
		intensity = 2.5 + sin(t * 30.0)
	elif state == "chase":
		intensity = 2.0
	alert_level = lerpf(alert_level, 1.0 if state in ["alert", "chase"] else 0.0, 1.0 - exp(-6 * dt))
	var col = Palette.SAL if hostile else Palette.RESSONANCIA
	for m in [eye_mat, crystal_mat]:
		if m:
			m.emission = col
			m.albedo_color = col
			m.emission_energy_multiplier = intensity
	light.light_color = col
	light.light_energy = intensity * 1.5 if (awake or not hostile) else 0.3
	var show = state in ["patrol", "alert", "chase"]
	cone.visible = show
	if show:
		var r: float = params["vision_range"]
		cone.global_position = Vector3(global_position.x, floor_y + 0.04, global_position.z)
		cone.scale = Vector3(r, 1, r)
		cone.rotation = Vector3(0, yaw, 0)
		cone_mat.albedo_color.a = 0.12 + alert_level * 0.18
