extends CharacterBody3D
## Игрок от первого лица: ходьба, бег, присед, фонарик,
## дыхание, шаги, взаимодействие и страх.

signal noise_made(position: Vector3, radius: float)

const WALK_SPEED := 3.0
const SPRINT_SPEED := 5.3
const CROUCH_SPEED := 1.5
const ACCEL := 14.0
const GRAVITY := 24.0
const EYE_STAND := 1.62
const EYE_CROUCH := 1.12

var active := false
var stamina := 100.0
var battery := 100.0
var flashlight_on := true
var is_sprinting := false
var is_crouching := false
var fear := 0.0

var _pitch := 0.0
var _bob_t := 0.0
var _step_dist := 0.0
var _stamina_delay := 0.0
var _shake := 0.0
var _flicker_t := 0.0
var _base_fov := 78.0
var _rng := RandomNumberGenerator.new()
var _entity: Node3D = null
var _entity_timer := 0.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRay


func _ready() -> void:
	add_to_group("player")
	_rng.randomize()
	_base_fov = camera.fov
	head.position.y = EYE_STAND


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var sens := 0.0022 * Game.sensitivity
		rotate_y(-motion.relative.x * sens)
		_pitch = clampf(_pitch - motion.relative.y * sens, -1.45, 1.45)
		head.rotation.x = _pitch
	elif event.is_action_pressed("flashlight"):
		set_flashlight(not flashlight_on)
	elif event.is_action_pressed("interact"):
		interact()


func _physics_process(delta: float) -> void:
	if not active:
		velocity = Vector3.ZERO
		return

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y))
	direction.y = 0.0
	direction = direction.normalized()

	is_crouching = Input.is_action_pressed("crouch")
	var wants_sprint := Input.is_action_pressed("sprint") and not is_crouching \
			and input.length() > 0.15 and direction.length() > 0.1
	is_sprinting = wants_sprint and stamina > 1.0

	if is_sprinting:
		stamina = maxf(0.0, stamina - 19.0 * delta)
		_stamina_delay = 0.9
	else:
		_stamina_delay = maxf(0.0, _stamina_delay - delta)
		if _stamina_delay <= 0.0:
			stamina = minf(100.0, stamina + 12.0 * delta)

	var speed := WALK_SPEED
	if is_crouching:
		speed = CROUCH_SPEED
	elif is_sprinting:
		speed = SPRINT_SPEED

	var target := direction * speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.lerp(target, clampf(ACCEL * delta, 0.0, 1.0))
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -1.0
	move_and_slide()

	_update_bob(delta, horizontal.length())
	_update_flashlight(delta)
	_update_fear(delta)
	_update_camera(delta)


func _update_bob(delta: float, planar_speed: float) -> void:
	if planar_speed > 0.4:
		var rate := 5.4 + planar_speed * 1.5
		if is_sprinting:
			rate += 2.0
		_bob_t += delta * rate
		_step_dist += planar_speed * delta
		var stride := 2.4 if is_sprinting else 1.85
		if is_crouching:
			stride = 1.4
		if _step_dist >= stride:
			_step_dist = 0.0
			_footstep()
	else:
		_bob_t = lerpf(_bob_t, 0.0, clampf(delta * 4.0, 0.0, 1.0))

	var amplitude := 0.055 if is_sprinting else 0.035
	if is_crouching:
		amplitude = 0.018
	var target_eye := EYE_CROUCH if is_crouching else EYE_STAND
	head.position.y = lerpf(head.position.y, target_eye + sin(_bob_t) * amplitude,
			clampf(delta * 9.0, 0.0, 1.0))
	head.position.x = sin(_bob_t * 0.5) * amplitude * 0.55


func _footstep() -> void:
	var volume := -7.0
	var radius := 9.0
	if is_crouching:
		volume = -24.0
		radius = 3.5
	elif is_sprinting:
		volume = -2.0
		radius = 18.0
	AudioBank.play_3d("step", get_parent(), global_position, volume,
			_rng.randf_range(0.82, 1.18), 28.0, 6.0)
	noise_made.emit(global_position, radius)


func _update_flashlight(delta: float) -> void:
	if flashlight_on and battery > 0.0:
		battery = maxf(0.0, battery - Game.battery_drain() * delta)
		if battery <= 0.0:
			set_flashlight(false)
			Game.toast("ФОНАРИК СЕЛ. НУЖНЫ БАТАРЕЙКИ")
	var lit := flashlight_on and battery > 0.0
	flashlight.visible = lit
	if not lit:
		return

	_flicker_t += delta
	var energy := 3.6
	var reach := 22.0
	if battery < 25.0:
		var luck := _rng.randf()
		if luck < 0.035 or (battery < 10.0 and luck < 0.12):
			energy = 0.35
		energy *= 0.85 + 0.25 * sin(_flicker_t * 23.0)
		reach = 13.0 + battery * 0.2
	flashlight.light_energy = energy
	flashlight.spot_range = reach


func _update_fear(delta: float) -> void:
	_entity_timer -= delta
	if _entity_timer <= 0.0 or (_entity != null and not is_instance_valid(_entity)):
		_entity_timer = 0.5
		_entity = get_tree().get_first_node_in_group("entity") as Node3D

	var target := 0.1
	if _entity != null and is_instance_valid(_entity):
		var d := global_position.distance_to(_entity.global_position)
		if d < 32.0:
			target = maxf(target, (1.0 - d / 32.0) * 0.95)
		if d < 9.0:
			target = 1.0
		if _entity.has_method("is_hunting") and bool(_entity.call("is_hunting")):
			target = maxf(target, 0.72)
	if not flashlight_on or battery <= 0.0:
		target = maxf(target, 0.3)
	if Game.coins_collected > 0:
		target = maxf(target, 0.22)
	fear = lerpf(fear, target, clampf(delta * (1.5 if target > fear else 0.3), 0.0, 1.0))
	Game.fear = fear


func _update_camera(delta: float) -> void:
	var target_fov := _base_fov + (4.5 if is_sprinting else 0.0) + fear * 3.0
	camera.fov = lerpf(camera.fov, target_fov, clampf(delta * 5.0, 0.0, 1.0))

	var shake_amount := fear * 0.011 + _shake
	if not Game.screen_shake:
		shake_amount = 0.0
	camera.h_offset = _rng.randf_range(-1.0, 1.0) * shake_amount
	camera.v_offset = _rng.randf_range(-1.0, 1.0) * shake_amount
	camera.rotation.z = lerpf(camera.rotation.z, sin(_bob_t * 0.5) * 0.007,
			clampf(delta * 6.0, 0.0, 1.0))
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.5)


## ------------------------------------------------------------- действие

func interact() -> void:
	var target := ray_target()
	if target != null and target.has_method("interact"):
		target.call("interact", self)


func ray_target() -> Node:
	if not interact_ray.is_colliding():
		return null
	var collider := interact_ray.get_collider()
	if collider is Node:
		var node := collider as Node
		if node.has_method("interact"):
			return node
	return null


func get_prompt() -> String:
	var target := ray_target()
	if target == null:
		return ""
	if target.has_method("get_prompt"):
		return str(target.call("get_prompt"))
	return "ИСПОЛЬЗОВАТЬ"


func set_flashlight(on: bool) -> void:
	flashlight_on = on
	AudioBank.play("click", -9.0, _rng.randf_range(0.9, 1.1))


func add_battery(amount: float) -> void:
	battery = minf(100.0, battery + amount)
	Game.toast("+%d%% ЗАРЯДА" % int(amount))


func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func look_at_point(point: Vector3) -> void:
	var flat := point - global_position
	rotation.y = atan2(-flat.x, -flat.z)
	var head_pos := global_position + Vector3.UP * head.position.y
	var dir := (point - head_pos).normalized()
	_pitch = clampf(asin(clampf(dir.y, -1.0, 1.0)), -1.4, 1.4)
	head.rotation.x = _pitch


func place_at(position: Vector3, facing: float) -> void:
	global_position = position
	rotation.y = facing
	_pitch = 0.0
	head.rotation.x = 0.0
	velocity = Vector3.ZERO


func deactivate() -> void:
	active = false
	velocity = Vector3.ZERO
	flashlight.visible = false
	is_sprinting = false
