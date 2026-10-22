extends Node3D
## «ОНО» — тварь, которая бродит по уровню, слышит бег,
## видит свет фонарика и охотится по сетке лабиринта.

signal caught_player

enum State { IDLE, WANDER, HUNT, SEARCH }

@export var base_speed := 3.25
@export var catch_distance := 1.35

var active := false
var state := State.IDLE
var maze
var player

var _path := PackedVector3Array()
var _path_index := 0
var _repath := 0.0
var _perception := 0.0
var _last_known := Vector3.ZERO
var _lost_timer := 0.0
var _step_timer := 0.0
var _t := 0.0

var _body: Node3D
var _head: Node3D
var _growl: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("entity")
	_rng.randomize()
	_body = get_node_or_null("Body") as Node3D
	_head = get_node_or_null("Head") as Node3D
	_growl = AudioBank.make_3d_loop("growl", self, -60.0, 48.0, 11.0)
	visible = false


func activate() -> void:
	active = true
	visible = true
	state = State.WANDER
	_last_known = global_position
	_pick_wander_target()


func distract(target: Vector3) -> void:
	if not active or state == State.HUNT:
		return
	state = State.SEARCH
	_last_known = target
	_set_path_to(target)


func is_hunting() -> bool:
	return state == State.HUNT


func _physics_process(delta: float) -> void:
	if not active or player == null or not is_instance_valid(player):
		return
	_t += delta

	_perception -= delta
	if _perception <= 0.0:
		_perception = 0.2
		_update_perception()

	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.45 if state == State.HUNT else 1.8
		_update_path()

	_move(delta)
	_update_visual()

	if player.get("active") == true:
		if global_position.distance_to(player.global_position) < catch_distance:
			_catch()


## ------------------------------------------------------- восприятие

func _update_perception() -> void:
	var dist := global_position.distance_to(player.global_position)
	if dist > 55.0:
		return

	var sees := _sees_player()
	var hears := false
	if player.get("is_sprinting") == true and dist < 19.0:
		hears = true
	if player.get("flashlight_on") == true and dist < 30.0 and sees:
		hears = true

	if sees or hears:
		if state != State.HUNT:
			_alert()
		state = State.HUNT
		_last_known = player.global_position
		_lost_timer = 0.0


func _sees_player() -> bool:
	var dist := global_position.distance_to(player.global_position)
	if dist > 30.0:
		return false
	var eye := global_position + Vector3.UP * 2.2
	var target := player.global_position + Vector3.UP * 1.4
	return maze.has_line_of_sight(eye, target)


func _alert() -> void:
	var dist := global_position.distance_to(player.global_position)
	if dist < 24.0:
		AudioBank.play_3d("stinger", get_parent(), global_position, -10.0, 1.0, 40.0)
	if _growl != null:
		_growl.pitch_scale = 1.12


## ------------------------------------------------------- навигация

func _update_path() -> void:
	if maze == null:
		return

	if state == State.HUNT:
		if _sees_player():
			_lost_timer = 0.0
			_last_known = player.global_position
			_set_path_to(_last_known)
		else:
			_lost_timer += 0.45
			if _lost_timer > 4.5 or global_position.distance_to(_last_known) < 2.2:
				state = State.SEARCH
				_pick_wander_target()
			else:
				_set_path_to(_last_known)
	elif state == State.SEARCH:
		if global_position.distance_to(_last_known) < 2.4:
			state = State.WANDER
			_pick_wander_target()
		else:
			_set_path_to(_last_known)
	else:
		if _path.is_empty() or _path_index >= _path.size() - 1:
			_pick_wander_target()


func _set_path_to(target: Vector3) -> void:
	_path = maze.world_path(global_position, target)
	_path_index = 0
	if _path.size() > 1 and global_position.distance_to(_path[0]) < 1.2:
		_path_index = 1


func _pick_wander_target() -> void:
	if maze == null:
		return
	if state != State.SEARCH:
		state = State.WANDER
	var cell: Vector2i = maze.random_cell_far_from(global_position, 7.0)
	_last_known = maze.cell_to_world(cell)
	_set_path_to(_last_known)


func _move(delta: float) -> void:
	global_position.y = 0.02
	if _path.is_empty() or _path_index >= _path.size():
		return
	var target := _path[_path_index]
	var flat := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if flat.length() < 0.5:
		_path_index += 1
		return

	var dir := flat.normalized()
	var speed := _current_speed()

	# вплотную — идёт напрямую на игрока, а не по центрам клеток
	if state == State.HUNT and global_position.distance_to(player.global_position) < 5.5:
		var chase := player.global_position - global_position
		chase.y = 0.0
		if chase.length() > 0.05:
			dir = chase.normalized()
	global_position += dir * speed * delta
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 7.0, 0.0, 1.0))

	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = 0.52 if state == State.HUNT else 0.85
		var volume := -9.0 if state == State.HUNT else -20.0
		AudioBank.play_3d("step", get_parent(), global_position, volume,
				_rng.randf_range(0.62, 0.74), 34.0, 7.0)


func _current_speed() -> float:
	var progress := 0.0
	if Game.coins_goal > 0:
		progress = clampf(float(Game.coins_collected) / float(Game.coins_goal), 0.0, 1.0)
	var speed := base_speed * Game.entity_speed_mult() * (1.0 + progress * 0.24)
	if state != State.HUNT:
		speed *= 0.42
	return speed


## ------------------------------------------------------- внешность

func _update_visual() -> void:
	if _body != null:
		_body.position.y = 1.12 + sin(_t * 4.2) * 0.035
		_body.rotation.z = sin(_t * 2.1) * 0.035
	if _head != null:
		var twitch := 0.25 if state == State.HUNT else 0.07
		_head.rotation.z = sin(_t * 1.9) * twitch
		_head.rotation.x = sin(_t * 2.7) * twitch * 0.6

	if _growl != null and player != null and is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		var closeness := 1.0 - clampf(dist / 26.0, 0.0, 1.0)
		var base := -6.0 if state == State.HUNT else -20.0
		_growl.volume_db = lerpf(-34.0, base, closeness)


func _catch() -> void:
	active = false
	if _growl != null:
		_growl.stop()
	caught_player.emit()
