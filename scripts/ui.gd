extends CanvasLayer
## Весь интерфейс: HUD, компас, экраны, настройки и пост-эффекты.
## Строится кодом, чтобы не зависеть от .tscn-файлов.

const POST_SHADER := preload("res://shaders/post_fx.gdshader")

const COL_PARCHMENT := Color(0.93, 0.87, 0.60)
const COL_DIM := Color(0.72, 0.68, 0.50, 0.85)
const COL_GOLD := Color(1.0, 0.80, 0.28)
const COL_RED := Color(1.0, 0.24, 0.18)

var main: Node

var post_rect: ColorRect
var post_mat: ShaderMaterial

var hud_root: Control
var coin_label: Label
var objective_label: Label
var time_label: Label
var notes_label: Label
var battery_bar: ProgressBar
var stamina_bar: ProgressBar
var prompt_label: Label
var toast_label: Label
var compass: Control

var title_root: Control
var title_label: Label
var difficulty_button: Button
var pause_root: Control
var settings_root: Control
var death_root: Control
var death_subtitle: Label
var death_stats: Label
var win_root: Control
var win_stats: Label
var note_panel: PanelContainer
var note_label: Label
var intro_root: Control
var fade_rect: ColorRect

var player: Node3D
var maze: Node3D
var exit_door: Node3D

var _fear := 0.0
var _static := 0.0
var _hurt := 0.0
var _note_timer := 0.0
var _toast_timer := 0.0
var _intro_timer := 0.0
var _title_t := 0.0
var _settings_return := "title"
var _last_coins := -1
var _last_seconds := -1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_build_post()
	_build_hud()
	_build_title()
	_build_pause()
	_build_settings()
	_build_death()
	_build_win()
	_build_note()
	_build_intro()
	_build_fade()

	Game.toast_requested.connect(toast)
	Game.note_requested.connect(show_note)
	Game.all_coins_collected.connect(_on_all_coins)
	show_title()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if settings_root.visible:
		hide_settings()
		get_viewport().set_input_as_handled()
	elif get_tree().paused:
		_call_main("resume")
		get_viewport().set_input_as_handled()
	elif hud_root.visible:
		_call_main("pause")
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	post_mat.set_shader_parameter("fear", clampf(Game.fear, 0.0, 1.0))
	post_mat.set_shader_parameter("static_amount", _static)
	post_mat.set_shader_parameter("hurt", _hurt)

	if hud_root.visible:
		_update_hud()
	compass.queue_redraw()
	_update_title(delta)
	_update_toast(delta)
	_update_note(delta)
	_update_intro(delta)


## --------------------------------------------------------------- пост-эффект

func _build_post() -> void:
	post_mat = ShaderMaterial.new()
	post_mat.shader = POST_SHADER
	post_rect = ColorRect.new()
	post_rect.color = Color.WHITE
	post_rect.material = post_mat
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(post_rect)
	post_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## ------------------------------------------------------------------- HUD

func _build_hud() -> void:
	hud_root = Control.new()
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_root)
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# левый верх: манеты и задача
	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_theme_constant_override("separation", 2)
	left.anchor_left = 0.0
	left.anchor_top = 0.0
	left.offset_left = 34.0
	left.offset_top = 26.0
	left.offset_right = 520.0
	left.offset_bottom = 200.0
	hud_root.add_child(left)

	left.add_child(_label("МАНЕТЫ", 13, COL_DIM, 3))
	coin_label = _label("0 / 8", 42, COL_GOLD, 8)
	left.add_child(coin_label)
	objective_label = _label("НАЙДИ МАНЕТЫ В ЖЁЛТЫХ КОМНАТАХ", 13, COL_DIM, 4)
	left.add_child(objective_label)

	# правый верх: запись и таймер
	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -340.0
	right.offset_right = -34.0
	right.offset_top = 26.0
	right.offset_bottom = 200.0
	right.alignment = BoxContainer.ALIGNMENT_BEGIN
	hud_root.add_child(right)

	var rec := _label("● REC", 14, COL_RED, 4)
	rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(rec)
	time_label = _label("00:00", 30, COL_PARCHMENT, 6)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(time_label)
	notes_label = _label("ЗАПИСИ 0 / 4", 13, COL_DIM, 4)
	notes_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(notes_label)

	# левый низ: фонарь и выносливость
	var bars := VBoxContainer.new()
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.anchor_top = 1.0
	bars.anchor_bottom = 1.0
	bars.offset_left = 34.0
	bars.offset_right = 354.0
	bars.offset_top = -132.0
	bars.offset_bottom = -28.0
	bars.alignment = BoxContainer.ALIGNMENT_END
	bars.add_theme_constant_override("separation", 5)
	hud_root.add_child(bars)
	battery_bar = _add_bar(bars, "ФОНАРЬ", Color(0.95, 0.85, 0.42))
	stamina_bar = _add_bar(bars, "ВЫНОСЛИВОСТЬ", Color(0.55, 0.75, 0.65))

	# низ по центру: подсказка и уведомления
	toast_label = _label("", 16, COL_GOLD, 6)
	toast_label.anchor_left = 0.0
	toast_label.anchor_right = 1.0
	toast_label.anchor_top = 1.0
	toast_label.anchor_bottom = 1.0
	toast_label.offset_top = -178.0
	toast_label.offset_bottom = -146.0
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.modulate.a = 0.0
	hud_root.add_child(toast_label)

	prompt_label = _label("", 18, COL_PARCHMENT, 8)
	prompt_label.anchor_left = 0.0
	prompt_label.anchor_right = 1.0
	prompt_label.anchor_top = 1.0
	prompt_label.anchor_bottom = 1.0
	prompt_label.offset_top = -118.0
	prompt_label.offset_bottom = -82.0
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_root.add_child(prompt_label)

	# прицел
	var dot := ColorRect.new()
	dot.color = Color(0.95, 0.9, 0.7, 0.35)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.anchor_left = 0.5
	dot.anchor_right = 0.5
	dot.anchor_top = 0.5
	dot.anchor_bottom = 0.5
	dot.offset_left = -2.0
	dot.offset_right = 2.0
	dot.offset_top = -2.0
	dot.offset_bottom = 2.0
	hud_root.add_child(dot)

	# компас на выход
	compass = Control.new()
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass.anchor_left = 0.5
	compass.anchor_right = 0.5
	compass.offset_left = -80.0
	compass.offset_right = 80.0
	compass.offset_top = 18.0
	compass.offset_bottom = 178.0
	hud_root.add_child(compass)
	compass.draw.connect(_draw_compass)
	compass.visible = false

	hud_root.visible = false


func _add_bar(parent: Control, text: String, color: Color) -> ProgressBar:
	var label := _label(text, 11, Color(0.85, 0.80, 0.60, 0.8), 3)
	parent.add_child(label)

	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(250.0, 10.0)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	background.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)

	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar


func _update_hud() -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return

	if _last_coins != Game.coins_collected:
		_last_coins = Game.coins_collected
		coin_label.text = "%d / %d" % [Game.coins_collected, Game.coins_goal]
		if Game.exit_unlocked:
			objective_label.text = "ВСЕ МАНЕТЫ СОБРАНЫ — НАЙДИ ВЫХОД"
			objective_label.add_theme_color_override("font_color", COL_GOLD)
		else:
			objective_label.text = "НАЙДИ МАНЕТЫ В ЖЁЛТЫХ КОМНАТАХ"
			objective_label.add_theme_color_override("font_color", COL_DIM)

	battery_bar.value = float(player.get("battery"))
	stamina_bar.value = float(player.get("stamina"))

	var seconds := int(Game.run_time)
	if seconds != _last_seconds:
		_last_seconds = seconds
		time_label.text = Game.format_time(Game.run_time)
	notes_label.text = "ЗАПИСИ %d / 4" % Game.notes_found

	var prompt := ""
	if player.has_method("get_prompt"):
		prompt = str(player.call("get_prompt"))
	prompt_label.text = ("[E] " + prompt) if prompt != "" else ""
	compass.visible = Game.exit_unlocked and exit_door != null and is_instance_valid(exit_door)


func _draw_compass() -> void:
	if not compass.visible or player == null or exit_door == null:
		return
	if not is_instance_valid(player) or not is_instance_valid(exit_door):
		return
	var center := compass.size * 0.5
	compass.draw_circle(center, 30.0, Color(0.02, 0.02, 0.01, 0.5))
	compass.draw_arc(center, 30.0, 0.0, TAU, 48, Color(0.9, 0.8, 0.4, 0.35), 1.5, true)

	var to := exit_door.global_position - player.global_position
	var local := player.global_transform.basis.inverse() * to
	var dir := Vector2(local.x, local.z)
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var tip := center + dir * 20.0
	var left := center + dir.rotated(2.55) * 11.0
	var right := center + dir.rotated(-2.55) * 11.0
	compass.draw_colored_polygon(PackedVector2Array([tip, left, right]),
			Color(1.0, 0.84, 0.32, 0.95))
	compass.draw_circle(center, 3.0, Color(1.0, 0.9, 0.5, 0.9))


## --------------------------------------------------------------- экраны

func _build_title() -> void:
	title_root = Control.new()
	title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_root)
	title_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.015, 0.015, 0.008, 0.80)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_root.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	title_label = _label("БЕКРУМС", 104, COL_PARCHMENT, 14)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)

	var subtitle := _label("У Р О В Е Н Ь   0", 26, Color(0.85, 0.78, 0.45, 0.9), 5)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	var tagline := _label("жёлтые комнаты · мокрый ковролин · гудение ламп",
			14, Color(0.7, 0.66, 0.5, 0.75), 4)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tagline)

	box.add_child(_spacer(26))

	var play := _make_button("НАЧАТЬ СПУСК", _on_play_pressed)
	box.add_child(play)

	difficulty_button = _make_button("СЛОЖНОСТЬ: НОРМАЛЬНО", _on_difficulty_pressed)
	box.add_child(difficulty_button)

	box.add_child(_make_button("НАСТРОЙКИ", func() -> void: show_settings("title")))
	box.add_child(_make_button("ВЫХОД", func() -> void: _call_main("quit_game")))

	box.add_child(_spacer(18))

	var best := "ЛУЧШЕЕ ВРЕМЯ: —"
	if Game.best_time > 0.0:
		best = "ЛУЧШЕЕ ВРЕМЯ: " + Game.format_time(Game.best_time)
	var best_label := _label(best, 13, COL_DIM, 4)
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(best_label)

	box.add_child(_spacer(10))

	var hint := _label("WASD — идти   SHIFT — бежать   CTRL — присесть\n" +
			"F — фонарик   E — взаимодействие   ESC — пауза",
			13, Color(0.68, 0.64, 0.5, 0.7), 4)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _build_pause() -> void:
	var screen := _make_screen()
	pause_root = screen
	var box := _screen_box(pause_root)
	box.add_child(_center_label("ПАУЗА", 54, COL_PARCHMENT, 8))
	box.add_child(_center_label("уровень ждёт", 14, COL_DIM, 4))
	box.add_child(_spacer(16))
	box.add_child(_make_button("ПРОДОЛЖИТЬ", func() -> void: _call_main("resume")))
	box.add_child(_make_button("ЗАНОВО", func() -> void: _call_main("restart_run")))
	box.add_child(_make_button("НАСТРОЙКИ", func() -> void: show_settings("pause")))
	box.add_child(_make_button("В МЕНЮ", func() -> void: _call_main("go_title")))


func _build_settings() -> void:
	settings_root = _make_screen()
	var box := _screen_box(settings_root)
	box.add_child(_center_label("НАСТРОЙКИ", 44, COL_PARCHMENT, 8))
	box.add_child(_spacer(10))

	var sens_row := HBoxContainer.new()
	sens_row.add_theme_constant_override("separation", 16)
	sens_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var sens_name := _label("ЧУВСТВИТЕЛЬНОСТЬ", 15, COL_DIM, 3)
	sens_name.custom_minimum_size = Vector2(280.0, 0.0)
	sens_row.add_child(sens_name)
	var sens := HSlider.new()
	sens.min_value = 0.3
	sens.max_value = 2.5
	sens.step = 0.05
	sens.value = Game.sensitivity
	sens.custom_minimum_size = Vector2(260.0, 26.0)
	sens_row.add_child(sens)
	var sens_value := _label("%.2f" % Game.sensitivity, 15, COL_PARCHMENT, 3)
	sens_value.custom_minimum_size = Vector2(60.0, 0.0)
	sens_row.add_child(sens_value)
	box.add_child(sens_row)

	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 16)
	vol_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var vol_name := _label("ГРОМКОСТЬ", 15, COL_DIM, 3)
	vol_name.custom_minimum_size = Vector2(280.0, 0.0)
	vol_row.add_child(vol_name)
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.01
	vol.value = Game.master_volume
	vol.custom_minimum_size = Vector2(260.0, 26.0)
	vol_row.add_child(vol)
	var vol_value := _label("%d%%" % int(Game.master_volume * 100.0), 15, COL_PARCHMENT, 3)
	vol_value.custom_minimum_size = Vector2(60.0, 0.0)
	vol_row.add_child(vol_value)
	box.add_child(vol_row)

	sens.value_changed.connect(func(v: float) -> void:
		Game.sensitivity = v
		sens_value.text = "%.2f" % v
		Game.save_settings())
	vol.value_changed.connect(func(v: float) -> void:
		Game.master_volume = v
		vol_value.text = "%d%%" % int(v * 100.0)
		Game.apply_audio_settings()
		Game.save_settings())

	box.add_child(_spacer(14))
	box.add_child(_make_button("КАЧЕСТВО: ВЫСОКОЕ", _on_quality_pressed))
	box.add_child(_make_button("ТРЯСКА КАМЕРЫ: ВКЛ", _on_shake_pressed))
	box.add_child(_spacer(14))
	box.add_child(_make_button("НАЗАД", hide_settings))


func _build_death() -> void:
	death_root = _make_screen()
	var box := _screen_box(death_root)
	box.add_child(_center_label("ТЕБЯ НАШЛИ", 66, COL_RED, 12))
	death_subtitle = _center_label("оно всегда знало, где ты", 17, COL_DIM, 4)
	box.add_child(death_subtitle)
	box.add_child(_spacer(18))
	death_stats = _center_label("", 16, COL_PARCHMENT, 4)
	box.add_child(death_stats)
	box.add_child(_spacer(22))
	box.add_child(_make_button("ПОПРОБОВАТЬ СНОВА", func() -> void: _call_main("restart_run")))
	box.add_child(_make_button("В МЕНЮ", func() -> void: _call_main("go_title")))


func _build_win() -> void:
	win_root = _make_screen()
	var box := _screen_box(win_root)
	box.add_child(_center_label("ТЫ ВЫБРАЛСЯ", 64, COL_GOLD, 12))
	box.add_child(_center_label("…или тебе только кажется", 17, COL_DIM, 4))
	box.add_child(_spacer(18))
	win_stats = _center_label("", 17, COL_PARCHMENT, 4)
	box.add_child(win_stats)
	box.add_child(_spacer(22))
	box.add_child(_make_button("ЕЩЁ ОДИН СПУСК", func() -> void: _call_main("restart_run")))
	box.add_child(_make_button("В МЕНЮ", func() -> void: _call_main("go_title")))


func _build_note() -> void:
	note_panel = PanelContainer.new()
	note_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.045, 0.03, 0.92)
	style.border_color = Color(0.75, 0.68, 0.4, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	note_panel.add_theme_stylebox_override("panel", style)
	note_panel.anchor_left = 0.5
	note_panel.anchor_right = 0.5
	note_panel.anchor_top = 1.0
	note_panel.anchor_bottom = 1.0
	note_panel.offset_left = -330.0
	note_panel.offset_right = 330.0
	note_panel.offset_top = -330.0
	note_panel.offset_bottom = -160.0
	note_panel.visible = false
	add_child(note_panel)

	note_label = _label("", 16, Color(0.88, 0.83, 0.65), 3)
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	note_panel.add_child(note_label)


func _build_intro() -> void:
	intro_root = Control.new()
	intro_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(intro_root)
	intro_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.anchor_top = 0.28
	box.anchor_bottom = 0.28
	box.offset_top = -60.0
	box.offset_bottom = 120.0
	box.add_theme_constant_override("separation", 6)
	intro_root.add_child(box)

	var l1 := _label("УРОВЕНЬ 0", 52, COL_PARCHMENT, 10)
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l1)
	var l2 := _label("ЖЁЛТЫЕ КОМНАТЫ", 22, COL_DIM, 6)
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l2)
	intro_root.modulate.a = 0.0
	intro_root.visible = false


func _build_fade() -> void:
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade_rect)
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.visible = false


## ------------------------------------------------------------- публичное

func bind(new_player: Node3D, new_maze: Node3D, new_exit: Node3D) -> void:
	player = new_player
	maze = new_maze
	exit_door = new_exit
	Game.notes_found = 0
	_last_coins = -1
	_last_seconds = -1


func show_title() -> void:
	title_root.visible = true
	hud_root.visible = false
	pause_root.visible = false
	settings_root.visible = false
	death_root.visible = false
	win_root.visible = false
	note_panel.visible = false
	intro_root.visible = false
	_set_static(0.0)
	_set_hurt(0.0)
	_refresh_difficulty()
	fade_rect.visible = false
	fade_rect.color.a = 0.0
	_input_mode(false)


func show_game() -> void:
	title_root.visible = false
	pause_root.visible = false
	settings_root.visible = false
	death_root.visible = false
	win_root.visible = false
	note_panel.visible = false
	hud_root.visible = true
	_set_static(0.0)
	_set_hurt(0.0)
	_show_intro()
	_input_mode(true)


func show_pause() -> void:
	pause_root.visible = true
	hud_root.visible = false
	compass.visible = false
	_input_mode(false)


func hide_pause() -> void:
	pause_root.visible = false
	settings_root.visible = false
	hud_root.visible = true
	_input_mode(true)


func show_settings(from: String) -> void:
	_settings_return = from
	title_root.visible = false
	pause_root.visible = false
	death_root.visible = false
	win_root.visible = false
	settings_root.visible = true
	hud_root.visible = false
	_refresh_quality()
	_input_mode(false)


func hide_settings() -> void:
	settings_root.visible = false
	if _settings_return == "pause":
		pause_root.visible = true
	elif _settings_return == "death":
		death_root.visible = true
	elif _settings_return == "win":
		win_root.visible = true
	else:
		title_root.visible = true
		hud_root.visible = false
	_input_mode(false)


func show_death() -> void:
	death_root.visible = true
	hud_root.visible = false
	note_panel.visible = false
	intro_root.visible = false
	death_subtitle.text = _random_death_line()
	death_stats.text = "МАНЕТЫ: %d / %d     ЗАПИСИ: %d\nВРЕМЯ В УРОВНЕ: %s" % [
		Game.coins_collected, Game.coins_goal, Game.notes_found, Game.format_time(Game.run_time)
	]
	_input_mode(false)


func show_win() -> void:
	win_root.visible = true
	hud_root.visible = false
	note_panel.visible = false
	intro_root.visible = false
	var best := ""
	if Game.best_time > 0.0:
		best = "\nЛУЧШЕЕ ВРЕМЯ: " + Game.format_time(Game.best_time)
	win_stats.text = "ВРЕМЯ: %s     МАНЕТЫ: %d / %d     ЗАПИСИ: %d%s" % [
		Game.format_time(Game.run_time), Game.coins_collected, Game.coins_goal,
		Game.notes_found, best
	]
	_input_mode(false)


func toast(text: String) -> void:
	toast_label.text = text
	toast_label.modulate.a = 1.0
	_toast_timer = 2.8


func show_note(text: String) -> void:
	note_label.text = text
	note_panel.visible = true
	_toast_timer = 0.0
	_note_timer = 9.5


func flash_static(value: float, duration: float) -> void:
	_set_static(value)
	var tween := create_tween()
	tween.tween_method(_set_static, value, 0.0, duration)


func set_hurt(value: float) -> void:
	_hurt = clampf(value, 0.0, 1.0)


## --------------------------------------------------------------- помощники

func _call_main(method: String) -> void:
	if main != null and main.has_method(method):
		main.call(method)


func _on_play_pressed() -> void:
	_call_main("start_run")


func _on_difficulty_pressed() -> void:
	Game.difficulty = (Game.difficulty + 1) % 3
	Game.coins_goal = Game.coin_goal()
	Game.save_settings()
	_refresh_difficulty()


func _on_quality_pressed() -> void:
	Game.quality = 1 - Game.quality
	Game.save_settings()
	_refresh_quality()


func _on_shake_pressed() -> void:
	Game.screen_shake = not Game.screen_shake
	Game.save_settings()
	_refresh_quality()


func _refresh_difficulty() -> void:
	if difficulty_button != null:
		difficulty_button.text = "СЛОЖНОСТЬ: " + Game.difficulty_name()


func _refresh_quality() -> void:
	for child in settings_root.find_children("*", "Button", true, false):
		var button := child as Button
		if button == null:
			continue
		if button.text.begins_with("КАЧЕСТВО"):
			button.text = "КАЧЕСТВО: " + ("ВЫСОКОЕ" if Game.quality >= 1 else "НИЗКОЕ")
		elif button.text.begins_with("ТРЯСКА"):
			button.text = "ТРЯСКА КАМЕРЫ: " + ("ВКЛ" if Game.screen_shake else "ВЫКЛ")


func _update_title(delta: float) -> void:
	if not title_root.visible:
		return
	_title_t += delta
	var target_alpha := 1.0
	if _rng.randf() < delta * 0.7:
		target_alpha = _rng.randf_range(0.35, 0.85)
	title_label.modulate.a = lerpf(title_label.modulate.a, target_alpha, clampf(delta * 9.0, 0.0, 1.0))
	title_label.modulate.g = 0.92 + sin(_title_t * 9.0) * 0.03
	title_label.modulate.b = 0.55 + sin(_title_t * 9.0) * 0.05


func _update_toast(delta: float) -> void:
	if _toast_timer <= 0.0:
		if toast_label.modulate.a > 0.0:
			toast_label.modulate.a = maxf(0.0, toast_label.modulate.a - delta * 1.6)
		return
	_toast_timer -= delta
	if _toast_timer < 0.7:
		toast_label.modulate.a = clampf(_toast_timer / 0.7, 0.0, 1.0)


func _update_note(delta: float) -> void:
	if _note_timer <= 0.0:
		return
	_note_timer -= delta
	if _note_timer < 0.8:
		note_panel.modulate.a = clampf(_note_timer / 0.8, 0.0, 1.0)
	if _note_timer <= 0.0:
		note_panel.visible = false
		note_panel.modulate.a = 1.0


func _update_intro(delta: float) -> void:
	if not intro_root.visible:
		return
	_intro_timer -= delta
	var t := _intro_timer
	var alpha := 0.0
	if t > 4.6:
		alpha = clampf((5.6 - t) / 1.0, 0.0, 1.0)
	elif t > 1.4:
		alpha = 1.0
	else:
		alpha = clampf(t / 1.4, 0.0, 1.0)
	intro_root.modulate.a = alpha
	if t <= 0.0:
		intro_root.visible = false


func _show_intro() -> void:
	intro_root.visible = true
	intro_root.modulate.a = 0.0
	_intro_timer = 5.6


func _random_death_line() -> String:
	var lines := [
		"оно всегда знало, где ты",
		"жёлтые обои не любят гостей",
		"ты слышал шаги. это были его шаги",
		"уровень 0 забрал ещё одного",
		"гудение ламп стало тише. навсегда",
	]
	return lines[_rng.randi_range(0, lines.size() - 1)]


func _on_all_coins() -> void:
	toast("ВСЕ МАНЕТЫ СОБРАНЫ. ВЫХОД АКТИВИРОВАН")
	AudioBank.play("chime", -8.0)


func _input_mode(gameplay: bool) -> void:
	if gameplay:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _make_screen() -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.01, 0.01, 0.008, 0.80)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	root.visible = false
	return root


func _screen_box(screen: Control) -> VBoxContainer:
	for child in screen.get_children():
		if child is CenterContainer and child.get_child_count() > 0:
			return child.get_child(0) as VBoxContainer
	return VBoxContainer.new()


func _make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(380.0, 54.0)
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_color_override("font_color", Color(0.88, 0.84, 0.66))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.80))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.86, 0.40))
	button.add_theme_color_override("font_focus_color", Color(1.0, 0.96, 0.80))
	button.add_theme_stylebox_override("normal", _box(Color(0.05, 0.05, 0.03, 0.85),
			Color(0.42, 0.37, 0.19, 0.65)))
	button.add_theme_stylebox_override("hover", _box(Color(0.16, 0.14, 0.05, 0.95),
			Color(0.95, 0.85, 0.40, 0.9)))
	button.add_theme_stylebox_override("pressed", _box(Color(0.26, 0.21, 0.06, 1.0),
			Color(1.0, 0.90, 0.40, 1.0)))
	button.add_theme_stylebox_override("focus", _box(Color(0.0, 0.0, 0.0, 0.0),
			Color(0.90, 0.80, 0.35, 0.75)))
	button.pressed.connect(callback)
	return button


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _label(text: String, size: int, color: Color, outline: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_constant_override("outline_size", outline)
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _center_label(text: String, size: int, color: Color, outline: int) -> Label:
	var label := _label(text, size, color, outline)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _set_static(value: float) -> void:
	_static = clampf(value, 0.0, 1.0)
