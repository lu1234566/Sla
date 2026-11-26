class_name CameraRig
extends Node3D
## Câmera em terceira pessoa (GDD 03): órbita com distância ajustável,
## colisão por raio, suavização, modo de movimento reduzido e trajetos
## cinematográficos.

var camera: Camera3D
var yaw = 0.0
var pitch = 0.32
var dist = 6.0
var target_dist = 6.0
var actual_dist = 6.0
var focus = Vector3.ZERO
var reduce_motion = false
var shake = 0.0
var exclude: Array[RID] = []
var _cine: Dictionary = {}
var override_look: Variant = null  # {target: Vector3, until: float, pitch, dist}
var _clock = 0.0

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 62
	camera.near = 0.08
	camera.far = 1600
	add_child(camera)
	camera.current = true

func snap_behind(facing: float, at: Vector3) -> void:
	yaw = facing + PI
	focus = at + Vector3(0, 1.25, 0)
	actual_dist = dist

var in_cinematic: bool:
	get: return not _cine.is_empty()

## points: [{pos, look}], duração em s.
func play(points: Array, duration: float, on_done: Callable = Callable()) -> void:
	_cine = {"points": points, "t": 0.0, "duration": duration, "done": on_done}

func skip() -> void:
	if _cine.is_empty():
		return
	var cb: Callable = _cine["done"]
	_cine = {}
	if cb.is_valid():
		cb.call()

static func _catmull(points: Array, key: String, t: float) -> Vector3:
	var n = points.size()
	var f = clampf(t, 0.0, 1.0) * (n - 1)
	var i = mini(int(f), n - 2)
	var u = f - i
	var p0: Vector3 = points[maxi(i - 1, 0)][key]
	var p1: Vector3 = points[i][key]
	var p2: Vector3 = points[i + 1][key]
	var p3: Vector3 = points[mini(i + 2, n - 1)][key]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u)

func look_at_point(target: Vector3, seconds: float, p: float = 0.45, d: float = 7.0) -> void:
	override_look = {"target": target, "until": _clock + seconds, "pitch": p, "dist": d}

func update_camera(dt: float, look: Vector2, wheel: float, target: Vector3, facing: float) -> void:
	_clock += dt
	if not _cine.is_empty():
		_cine["t"] += dt / _cine["duration"]
		var e = 0.5 - 0.5 * cos(PI * minf(1.0, _cine["t"]))
		camera.global_position = _catmull(_cine["points"], "pos", e)
		camera.look_at(_catmull(_cine["points"], "look", e), Vector3.UP)
		if _cine["t"] >= 1.0:
			skip()
		return
	yaw -= look.x
	pitch = clampf(pitch + look.y, -0.35, 1.2)
	if wheel != 0.0:
		target_dist = clampf(target_dist + wheel * 0.6, 2.5, 11.0)
	var want_dist = target_dist
	if override_look != null:
		if _clock < override_look["until"]:
			var tg: Vector3 = override_look["target"]
			yaw = lerp_angle(yaw, atan2(target.x - tg.x, target.z - tg.z), 1.0 - exp(-2.4 * dt))
			pitch = lerpf(pitch, override_look["pitch"], 1.0 - exp(-2.0 * dt))
			want_dist = override_look["dist"]
		else:
			override_look = null
	dist = lerpf(dist, want_dist, 1.0 - exp(-10 * dt))
	var want = target + Vector3(0, 1.25, 0)
	var lag = 30.0 if reduce_motion else 12.0
	focus.x = lerpf(focus.x, want.x, 1.0 - exp(-lag * dt))
	focus.z = lerpf(focus.z, want.z, 1.0 - exp(-lag * dt))
	focus.y = lerpf(focus.y, want.y, 1.0 - exp(-(30.0 if reduce_motion else 7.0) * dt))
	var dir = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var d = dist
	var space = get_world_3d().direct_space_state
	var q = PhysicsRayQueryParameters3D.create(focus, focus + dir * (dist + 0.4), 1, exclude)
	var hit = space.intersect_ray(q)
	if not hit.is_empty():
		d = maxf(0.9, minf(d, focus.distance_to(hit["position"]) - 0.35))
	actual_dist = lerpf(actual_dist, d, 1.0 - exp(-(25.0 if d < actual_dist else 4.0) * dt))
	var pos = focus + dir * actual_dist
	if shake > 0.0 and not reduce_motion:
		pos += Vector3(randf() - 0.5, randf() - 0.5, 0) * shake
		shake = maxf(0.0, shake - dt * 1.5)
	camera.global_position = pos
	camera.look_at(focus, Vector3.UP)
