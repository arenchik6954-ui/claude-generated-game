extends Node
## Глобальное состояние игры, настройки и прогресс.
## Автозагрузка (Autoload) под именем "Game".

signal coin_collected(collected: int, goal: int)
signal all_coins_collected()
signal player_died()
signal player_won(time: float, notes: int)
signal note_requested(text: String)
signal toast_requested(text: String)

const SETTINGS_PATH := "user://settings.cfg"
const SAVE_PATH := "user://progress.cfg"

const DIFFICULTY_NAMES := ["СПОКОЙНО", "НОРМАЛЬНО", "КОШМАР"]
const COIN_GOALS := [6, 8, 10]
const SPEED_MULTIPLIERS := [0.88, 1.0, 1.14]
const BATTERY_DRAINS := [0.6, 0.85, 1.2]

var coins_goal := 8
var coins_collected := 0
var notes_found := 0
var run_time := 0.0
var playing := false
var fear := 0.0
var exit_unlocked := false

var best_time := -1.0
var runs_escaped := 0
var death_count := 0
var total_coins_ever := 0

var sensitivity := 1.0
var master_volume := 0.85
var quality := 1  # 0 = низкое, 1 = обычное
var difficulty := 1
var screen_shake := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_actions()
	load_settings()
	load_save()
	apply_audio_settings()


func _process(delta: float) -> void:
	if playing and not get_tree().paused:
		run_time += delta


## ---------------------------------------------------------------- сложность

func coin_goal() -> int:
	return COIN_GOALS[clampi(difficulty, 0, COIN_GOALS.size() - 1)]


func entity_speed_mult() -> float:
	return SPEED_MULTIPLIERS[clampi(difficulty, 0, SPEED_MULTIPLIERS.size() - 1)]


func battery_drain() -> float:
	return BATTERY_DRAINS[clampi(difficulty, 0, BATTERY_DRAINS.size() - 1)]


func difficulty_name() -> String:
	return DIFFICULTY_NAMES[clampi(difficulty, 0, DIFFICULTY_NAMES.size() - 1)]


## ---------------------------------------------------------------- состояние

func reset_run() -> void:
	coins_collected = 0
	coins_goal = coin_goal()
	notes_found = 0
	run_time = 0.0
	fear = 0.0
	exit_unlocked = false
	playing = false


func start_run() -> void:
	reset_run()
	playing = true


func collect_coin() -> void:
	coins_collected += 1
	total_coins_ever += 1
	coin_collected.emit(coins_collected, coins_goal)
	if coins_collected >= coins_goal:
		exit_unlocked = true
		all_coins_collected.emit()


func collect_note() -> void:
	notes_found += 1


func kill_player() -> void:
	if not playing:
		return
	playing = false
	death_count += 1
	save_progress()
	player_died.emit()


func escape() -> void:
	if not playing:
		return
	playing = false
	runs_escaped += 1
	if best_time < 0.0 or run_time < best_time:
		best_time = run_time
	save_progress()
	player_won.emit(run_time, notes_found)


## ---------------------------------------------------------------- настройки

func _register_actions() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("sprint", [KEY_SHIFT])
	_bind("crouch", [KEY_CTRL, KEY_C])
	_bind("interact", [KEY_E])
	_bind("flashlight", [KEY_F])
	_bind("pause", [KEY_ESCAPE])
	_bind("restart", [KEY_R])


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)


func apply_audio_settings() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(clampf(master_volume, 0.0, 1.0)))
		AudioServer.set_bus_mute(bus, master_volume <= 0.001)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "sensitivity", sensitivity)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("game", "screen_shake", screen_shake)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	sensitivity = float(cfg.get_value("input", "sensitivity", sensitivity))
	master_volume = float(cfg.get_value("audio", "master_volume", master_volume))
	quality = int(cfg.get_value("video", "quality", quality))
	difficulty = int(cfg.get_value("game", "difficulty", difficulty))
	screen_shake = bool(cfg.get_value("game", "screen_shake", screen_shake))
	sensitivity = clampf(sensitivity, 0.2, 3.0)
	difficulty = clampi(difficulty, 0, 2)


func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "best_time", best_time)
	cfg.set_value("stats", "runs_escaped", runs_escaped)
	cfg.set_value("stats", "death_count", death_count)
	cfg.set_value("stats", "total_coins", total_coins_ever)
	cfg.save(SAVE_PATH)


func load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	best_time = float(cfg.get_value("stats", "best_time", best_time))
	runs_escaped = int(cfg.get_value("stats", "runs_escaped", runs_escaped))
	death_count = int(cfg.get_value("stats", "death_count", death_count))
	total_coins_ever = int(cfg.get_value("stats", "total_coins", total_coins_ever))


func format_time(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	return "%02d:%02d" % [total / 60, total % 60]


func request_note(text: String) -> void:
	note_requested.emit(text)


func toast(text: String) -> void:
	toast_requested.emit(text)
