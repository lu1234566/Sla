class_name Player
extends CharacterBody3D
## Íris controlável (GDD 03): 4,5 m/s, salto com tolerância de borda
## (coyote + buffer), planar até 3 s segurando o salto, esquiva com
## invulnerabilidade, retorno ao último piso seguro.

signal event(name: String)

const SPEED := 4.5
const ACCEL_GROUND := 32.0
const ACCEL_AIR := 9.0
const GRAVITY := 14.0
const JUMP_VEL := 5.6
const COYOTE := 0.14
const BUFFER := 0.14
const GLIDE_FALL := 1.6
const GLIDE_SPEED := 5.2
const GLIDE_TIME := 3.0
const DODGE_SPEED := 10.0
const DODGE_TIME := 0.24
const DODGE_CD := 0.9

var rig: IrisRig
var cam_yaw = 0.0
var facing = PI
var locked = 0.0
var active = true
var coyote = 0.0
var buffer = 0.0
var glide_left = GLIDE_TIME
var gliding = false
var dodge_t = 0.0
var dodge_cd = 0.0
var dodge_dir = Vector3.FORWARD
var step_dist = 0.0
var turn_rate = 0.0
var speed_h = 0.0
var was_on_floor = true
var safe_points: Array = []
var _safe_timer = 0.0
var glide_fall = GLIDE_FALL
var glide_time = GLIDE_TIME
var anim_flags = {"scanning": false, "interacting": 0.0, "hurt": 0.0}
## entradas de um piloto automático (testes/gravação); null = teclado/controle
var autopilot: Variant = null

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50)
	floor_constant_speed = true
	var shape = CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.35
	var cs = CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.675
	add_child(cs)
	rig = IrisRig.new()
	add_child(rig)

func set_assisted(on: bool) -> void:
	glide_fall = 1.1 if on else GLIDE_FALL
	glide_time = 4.0 if on else GLIDE_TIME

var dodging: bool:
	get: return dodge_t > 0.0

func teleport(pos: Vector3, yaw: float = facing) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	facing = yaw
	gliding = false
	dodge_t = 0.0
	rig.rotation.y = facing

func _input_state() -> Dictionary:
	if autopilot != null:
		return autopilot
	var v = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return {"move": v, "jump_pressed": Input.is_action_just_pressed("jump"), "jump_held": Input.is_action_pressed("jump"),
		"dodge_pressed": Input.is_action_just_pressed("dodge")}

func _physics_process(dt: float) -> void:
	if not active:
		return
	var inp = _input_state() if locked <= 0.0 else {"move": Vector2.ZERO, "jump_pressed": false, "jump_held": false, "dodge_pressed": false}
	if locked > 0.0:
		locked -= dt
	var mv: Vector2 = inp["move"]
	# direção relativa à câmera (yaw 0 = câmera ao sul olhando para o norte)
	var fwd = Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var right = Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
	var dir = right * mv.x + fwd * (-mv.y)
	var mag = minf(1.0, dir.length())
	if mag > 0.001:
		dir = dir.normalized()
	var on_floor = is_on_floor()
	if inp["jump_pressed"]:
		buffer = BUFFER
	else:
		buffer = maxf(0.0, buffer - dt)
	coyote = COYOTE if on_floor else maxf(0.0, coyote - dt)
	# esquiva
	dodge_cd = maxf(0.0, dodge_cd - dt)
	if inp["dodge_pressed"] and dodge_cd <= 0.0:
		dodge_dir = dir if mag > 0.1 else Vector3(sin(facing), 0, cos(facing))
		dodge_t = DODGE_TIME
		dodge_cd = DODGE_CD
		event.emit("dodge")
	var target = dir * SPEED * mag
	if dodge_t > 0.0:
		dodge_t -= dt
		target = dodge_dir * DODGE_SPEED
	elif gliding:
		var g = dir if mag > 0.1 else Vector3(sin(facing), 0, cos(facing))
		target = g * GLIDE_SPEED
	var accel = 80.0 if dodge_t > 0.0 else (ACCEL_GROUND if on_floor else (6.0 if gliding else ACCEL_AIR))
	var k = 1.0 - exp(-accel * dt / SPEED)
	velocity.x += (target.x - velocity.x) * k
	velocity.z += (target.z - velocity.z) * k
	# gravidade, salto, planar
	velocity.y -= GRAVITY * dt
	if buffer > 0.0 and coyote > 0.0:
		velocity.y = JUMP_VEL
		buffer = 0.0
		coyote = 0.0
		event.emit("jump")
	if not inp["jump_held"] and velocity.y > 2.2 and not on_floor:
		velocity.y = 2.2
	var can_glide = Game.has_ability("glide")
	var want_glide = can_glide and inp["jump_held"] and not on_floor and velocity.y < 0.5 and glide_left > 0.0 and dodge_t <= 0.0
	if want_glide and not gliding:
		event.emit("glide")
	gliding = want_glide
	if gliding:
		glide_left -= dt
		velocity.y = maxf(velocity.y, -glide_fall)
	move_and_slide()
	var now_floor = is_on_floor()
	if now_floor and not was_on_floor:
		event.emit("land")
	if now_floor:
		glide_left = glide_time
	was_on_floor = now_floor
	# orientação
	var hv = Vector2(velocity.x, velocity.z).length()
	var prev = facing
	if hv > 0.4 and (mag > 0.1 or dodge_t > 0.0 or gliding):
		facing = lerp_angle(facing, atan2(velocity.x, velocity.z), 1.0 - exp(-14 * dt))
	turn_rate = wrapf(facing - prev, -PI, PI) / maxf(dt, 0.0001)
	rig.rotation.y = facing
	speed_h = hv if now_floor else 0.0
	if now_floor and hv > 0.5:
		step_dist += hv * dt
		if step_dist > 0.62:
			step_dist = 0.0
			event.emit("step")
	_track_safe(dt)

func _process(dt: float) -> void:
	anim_flags["interacting"] = maxf(0.0, anim_flags["interacting"] - dt)
	anim_flags["hurt"] = maxf(0.0, anim_flags["hurt"] - dt)
	rig.animate(dt, {"speed": speed_h, "grounded": is_on_floor(), "vy": velocity.y, "gliding": gliding,
		"scanning": anim_flags["scanning"], "interacting": anim_flags["interacting"] > 0.0, "dodging": dodging,
		"hurt": anim_flags["hurt"] > 0.0, "integrity": Game.state.get("integrity", 3), "turn": turn_rate})

# --- pontos seguros ---------------------------------------------------------------

func floor_body() -> Object:
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		if c.get_normal().y > 0.7:
			return c.get_collider()
	return null

func _supported() -> bool:
	var space = get_world_3d().direct_space_state
	for off in [Vector3(0.5, 0, 0), Vector3(-0.5, 0, 0), Vector3(0, 0, 0.5), Vector3(0, 0, -0.5)]:
		var q = PhysicsRayQueryParameters3D.create(global_position + off + Vector3(0, 0.3, 0), global_position + off + Vector3(0, -0.6, 0), 1)
		if space.intersect_ray(q).is_empty():
			return false
	return true

func _track_safe(dt: float) -> void:
	_safe_timer -= dt
	if _safe_timer > 0.0 or not is_on_floor():
		return
	var body = floor_body()
	if body == null or not (body is Node) or not (body as Node).is_in_group("safe"):
		return
	if not _supported():
		return
	_safe_timer = 0.3
	var p = global_position
	if safe_points.size() > 0:
		var last: Vector3 = safe_points[-1]["pos"]
		if last.distance_to(p) < 0.6:
			return
	safe_points.append({"pos": p, "body": body})
	if safe_points.size() > 20:
		safe_points.pop_front()
