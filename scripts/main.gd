extends Node3D
## Главный узел: собирает уровень, игрока, манеты, тварь, выход и UI,
## управляет состояниями игры и атмосферными событиями.

const MAZE_SCRIPT := preload("res://scripts/maze.gd")
const UI_SCRIPT := preload("res://scripts/ui.gd")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const COIN_SCENE := preload("res://scenes/coin.tscn")
const BATTERY_SCENE := preload("res://scenes/battery.tscn")
const NOTE_SCENE := preload("res://scenes/note.tscn")
const EXIT_SCENE := preload("res://scenes/exit_door.tscn")
const ENTITY_SCENE := preload("res://scenes/entity.tscn")

const NOTE_TEXTS := [
	"Если ты это читаешь — ты уже не первый.\n\nЯ считал шаги: 1284 в одну сторону. " +
	"Дальше коридор опять начался с той же лампы. Не беги. Оно слышит бег.",
	"Вода в ковролине — не вода. Не пей из луж.\n\nМои руки чешутся уже три дня, " +
	"а на фотографиях я улыбаюсь. Я не улыбался.",
	"Манеты появились, когда я начал считать двери. Теперь их надо собрать все.\n\n" +
	"Я собрал семь и услышал за спиной: «ещё одну». Не оборачивайся на голос.",
	"Выход есть. Я видел красную табличку там, где стены перестают сходиться.\n\n" +
	"Нужны все монеты. И не смотри на него дольше двух секунд.",
]

var world: Node3D
var ui
var player
var maze
var entity
var exit_door

var _environment: Environment
var _gameplay := false
var _world_id := 0
var _seed := 0
var _ambient_timer := 10.0
var _room_tone: AudioStreamPlayer
var _buzz: AudioStreamPlayer
var _heartbeat: AudioStreamPlayer
var _whisper: AudioStreamPlayer
var _fx_tween: Tween
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_setup_environment()
	_setup_audio()

	ui = UI_SCRIPT.new()
	ui.main = self
	add_child(ui)

	Game.all_coins_collected.connect(_on_all_coins)
	Game.coin_collected.connect(_on_coin_collected)
	_build_world()
	ui.show_title()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if not _gameplay:
		return
	if get_tree().paused:
		return
	_apply_quality()
	_update_audio()
	_ambient_events(delta)


## ------------------------------------------------------------- состояния

func start_run() -> void:
	_build_world()
	Game.start_run()
	_gameplay = true
	player.active = true
	ui.show_game()
	_schedule_entity_activation(24.0)
	get_tree().paused = false


func restart_run() -> void:
	Game.playing = false
	get_tree().paused = false
	if _fx_tween != null and _fx_tween.is_valid():
		_fx_tween.kill()
	_build_world()
	Game.start_run()
	_gameplay = true
	player.active = true
	ui.show_game()
	_schedule_entity_activation(20.0)


func pause() -> void:
	if not _gameplay:
		return
	get_tree().paused = true
	ui.show_pause()


func resume() -> void:
	get_tree().paused = false
	ui.hide_pause()
	if _gameplay and player != null:
		player.active = true


func go_title() -> void:
	Game.playing = false
	get_tree().paused = false
	_gameplay = false
	_build_world()
	ui.show_title()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func quit_game() -> void:
	Game.save_settings()
	get_tree().quit()


func _schedule_entity_activation(delay: float) -> void:
	var world_id := _world_id
	await get_tree().create_timer(delay).timeout
	if world_id != _world_id:
		return
	if not _gameplay or entity == null or not is_instance_valid(entity):
		return
	if entity.active:
		return
	entity.activate()
	AudioBank.play("stinger", -8.0, 0.8)
	ui.flash_static(0.45, 1.4)
	ui.toast("ЧТО-ТО ПРОСНУЛОСЬ В КОРИДОРАХ")


## ------------------------------------------------------------- уровень

func _build_world() -> void:
	_world_id += 1
	Game.fear = 0.0
	if world != null and is_instance_valid(world):
		world.free()
	world = Node3D.new()
	world.name = "World"
	add_child(world)

	maze = MAZE_SCRIPT.new()
	maze.name = "Maze"
	world.add_child(maze)
	_seed = _rng.randi()
	maze.generate(_seed)

	player = PLAYER_SCENE.instantiate()
	world.add_child(player)
	player.place_at(maze.spawn_position(), maze.spawn_facing())
	maze.set_player(player)
	player.noise_made.connect(_on_noise)

	Game.reset_run()
	Game.coins_goal = Game.coin_goal()

	_spawn_coins()
	_spawn_batteries()
	_spawn_notes()
	_spawn_exit()
	_spawn_entity()

	ui.bind(player, maze, exit_door)
	get_tree().paused = false


func _spawn_coins() -> void:
	var cells = _pick_guaranteed(Game.coins_goal, 4, 3)
	for cell in cells:
		var coin = COIN_SCENE.instantiate()
		coin.position = maze.cell_to_world(cell) + Vector3(0.0, 1.05, 0.0)
		world.add_child(coin)


func _spawn_batteries() -> void:
	var cells = _pick_guaranteed(6, 3, 2)
	for cell in cells:
		var battery = BATTERY_SCENE.instantiate()
		battery.position = maze.cell_to_world(cell) + Vector3(0.0, 0.55, 0.0)
		world.add_child(battery)


func _spawn_notes() -> void:
	var cells = _pick_guaranteed(4, 4, 2)
	for i in cells.size():
		var cell: Vector2i = cells[i]
		var side := Vector2i.ZERO
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			if not maze.is_open(cell + d):
				side = d
				break
		var note = NOTE_SCENE.instantiate()
		world.add_child(note)
		note.text = NOTE_TEXTS[i % NOTE_TEXTS.size()]
		var center: Vector3 = maze.cell_to_world(cell)
		if side == Vector2i.ZERO:
			note.global_position = center + Vector3(0.0, 1.35, 0.0)
			note.rotation.y = _rng.randf() * TAU
		else:
			var offset := Vector3(float(side.x), 0.0, float(side.y)) * (2.15)
			note.global_position = center + offset + Vector3(0.0, 1.42, 0.0)
			note.rotation.y = atan2(-float(side.x), -float(side.y))


func _spawn_exit() -> void:
	exit_door = EXIT_SCENE.instantiate()
	world.add_child(exit_door)
	var cell: Vector2i = maze.exit_cell
	var center: Vector3 = maze.cell_to_world(cell)
	var wall_dir := Vector2i.ZERO
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if not maze.is_open(cell + d):
			wall_dir = d
			break
	if wall_dir != Vector2i.ZERO:
		exit_door.global_position = center + Vector3(float(wall_dir.x), 0.0,
				float(wall_dir.y)) * 1.95
		exit_door.rotation.y = atan2(-float(wall_dir.x), -float(wall_dir.y))
	else:
		exit_door.global_position = center
		exit_door.rotation.y = 0.0
	exit_door.set_unlocked(false)
	exit_door.used.connect(_on_exit_used)


func _spawn_entity() -> void:
	entity = ENTITY_SCENE.instantiate()
	world.add_child(entity)
	var cell: Vector2i = maze.random_cell_far_from(maze.spawn_position(), 34.0)
	entity.global_position = maze.cell_to_world(cell) + Vector3(0.0, 0.02, 0.0)
	entity.maze = maze
	entity.player = player
	entity.caught_player.connect(_on_caught)
	entity.visible = false


func _on_noise(position: Vector3, radius: float) -> void:
	if entity == null or not is_instance_valid(entity) or not entity.active:
		return
	if entity.global_position.distance_to(position) < radius:
		AudioBank.play_3d("thump", world, entity.global_position + Vector3.UP, -18.0, 1.2, 26.0)


func _on_coin_collected(_collected: int, _goal: int) -> void:
	if not _gameplay:
		return
	ui.flash_static(0.32, 0.55)
	if entity != null and is_instance_valid(entity) and entity.active:
		if entity.global_position.distance_to(player.global_position) < 34.0:
			entity.distract(player.global_position)
	var near: Vector3 = _random_position_around(player.global_position, 6.0, 13.0)
	AudioBank.play_3d("whisper", world, near, -15.0, _rng.randf_range(0.9, 1.1), 20.0)


func _on_all_coins() -> void:
	if exit_door != null and is_instance_valid(exit_door):
		exit_door.set_unlocked(true)
	AudioBank.play("stinger", -6.0, 0.7)
	if player != null and is_instance_valid(player):
		player.add_shake(0.02)


## ------------------------------------------------------------- смерть

func _on_caught() -> void:
	if not _gameplay:
		return
	_gameplay = false
	player.deactivate()
	Game.fear = 1.0
	var world_id := _world_id

	if entity != null and is_instance_valid(entity):
		player.look_at_point(entity.global_position + Vector3.UP * 2.2)
		player.add_shake(0.12)
		var forward: Vector3 = -player.global_transform.basis.z
		var target: Vector3 = player.global_position + forward * 0.85
		target.y = player.global_position.y
		_fx_tween = create_tween()
		_fx_tween.tween_property(entity, "global_position", target, 0.35) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	AudioBank.play("scream", -2.0)
	AudioBank.play("glitch", -5.0)
	ui.flash_static(1.0, 1.7)
	ui.set_hurt(0.75)

	await get_tree().create_timer(1.6).timeout
	if world_id != _world_id:
		return
	Game.kill_player()
	ui.show_death()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_exit_used() -> void:
	if not _gameplay:
		return
	_gameplay = false
	player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var world_id := _world_id
	await _fade(1.0, 1.1)
	if world_id != _world_id:
		return
	Game.escape()
	ui.show_win()
	await get_tree().create_timer(0.5).timeout
	if world_id != _world_id:
		return
	await _fade(0.0, 1.6)


func _fade(alpha: float, duration: float) -> void:
	ui.fade_rect.visible = true
	var tween := create_tween()
	tween.tween_property(ui.fade_rect, "color:a", alpha, duration)
	await tween.finished
	if alpha <= 0.0:
		ui.fade_rect.visible = false


## ------------------------------------------------------------- окружение

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.011, 0.008)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.40, 0.22)
	env.ambient_light_energy = 0.18
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.34, 0.30, 0.16)
	env.fog_light_energy = 0.9
	env.fog_density = 0.030
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.016
	env.volumetric_fog_albedo = Color(0.78, 0.71, 0.38)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 55.0
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.95
	env.ssao_enabled = true
	env.ssao_radius = 1.3
	env.ssao_intensity = 1.5
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.14
	env.adjustment_saturation = 0.9
	_environment = env

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _setup_audio() -> void:
	_room_tone = AudioBank.play_loop("room_tone", -17.0)
	_buzz = AudioBank.play_loop("buzz", -25.0)
	_heartbeat = AudioBank.play_loop("heartbeat", -42.0)
	_whisper = AudioBank.play_loop("whisper_loop", -55.0)


func _apply_quality() -> void:
	if _environment == null:
		return
	var high := Game.quality >= 1
	if _environment.volumetric_fog_enabled != high:
		_environment.volumetric_fog_enabled = high
		_environment.ssao_enabled = high


func _update_audio() -> void:
	var fear := clampf(Game.fear, 0.0, 1.0)
	if _heartbeat != null:
		_heartbeat.volume_db = lerpf(-40.0, -13.0, fear)
	if _whisper != null:
		_whisper.volume_db = lerpf(-58.0, -26.0, clampf((fear - 0.45) * 1.8, 0.0, 1.0))
	if _buzz != null:
		_buzz.volume_db = -25.0 - float(Game.coins_collected) * 0.5


func _ambient_events(delta: float) -> void:
	_ambient_timer -= delta
	if _ambient_timer > 0.0:
		return
	_ambient_timer = _rng.randf_range(8.0, 20.0)
	if player == null or not is_instance_valid(player):
		return

	match _rng.randi_range(0, 4):
		0:
			var far := _random_position_around(player.global_position, 18.0, 34.0)
			AudioBank.play_3d("thump", world, far, -9.0, _rng.randf_range(0.65, 0.95), 60.0, 13.0)
		1:
			var near := _random_position_around(player.global_position, 4.0, 9.0)
			AudioBank.play_3d("whisper", world, near, -17.0, _rng.randf_range(0.9, 1.1), 18.0)
		2:
			var lum := _random_position_around(player.global_position, 5.0, 14.0)
			AudioBank.play_3d("click", world, lum, -11.0, _rng.randf_range(0.8, 1.2), 22.0)
		3:
			var behind: Vector3 = player.global_position + player.global_transform.basis.z * 7.0
			AudioBank.play_3d("step", world, behind, -12.0, _rng.randf_range(0.6, 0.75), 26.0)
		_:
			ui.flash_static(0.28, 0.35)


func _random_position_around(origin: Vector3, min_d: float, max_d: float) -> Vector3:
	var angle := _rng.randf() * TAU
	var distance := _rng.randf_range(min_d, max_d)
	return origin + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)


func _pick_guaranteed(count: int, separation: int, min_dist: int) -> Array:
	var cells: Array = maze.pick_cells(count, separation, min_dist)
	var sep := separation
	while cells.size() < count and sep > 0:
		sep -= 1
		cells = maze.pick_cells(count, sep, min_dist)
	var guard := 0
	while cells.size() < count and guard < count * 12:
		guard += 1
		var cell: Vector2i = maze.random_open_cell()
		if not cells.has(cell):
			cells.append(cell)
	return cells


func _exit_tree() -> void:
	if get_tree().paused:
		get_tree().paused = false
