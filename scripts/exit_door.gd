extends StaticBody3D
## Выход. Открывается только когда собраны все манеты.

signal used

var unlocked := false
var opened := false
var _t := 0.0

@onready var sign_light: OmniLight3D = $Light
@onready var sign_label: Label3D = $Label
@onready var door: MeshInstance3D = $Door


func _ready() -> void:
	add_to_group("exit")
	collision_layer = 3
	collision_mask = 0
	_apply_visual()


func set_unlocked(value: bool) -> void:
	unlocked = value
	_apply_visual()


func _apply_visual() -> void:
	if sign_light == null:
		return
	sign_light.visible = unlocked
	if door != null:
		door.rotation.y = 0.0
	if sign_label != null:
		if unlocked:
			sign_label.modulate = Color(2.4, 0.25, 0.18)
		else:
			sign_label.modulate = Color(0.35, 0.1, 0.08)


func _process(delta: float) -> void:
	if not unlocked or opened:
		return
	_t += delta
	sign_light.light_energy = 1.6 + sin(_t * 2.6) * 0.7
	if sign_label != null:
		var pulse := 2.2 + sin(_t * 2.6) * 0.8
		sign_label.modulate = Color(pulse, 0.25, 0.18)
	door.position.y = 1.12 + sin(_t * 1.2) * 0.006


func interact(player: Node) -> void:
	if not unlocked:
		AudioBank.play_3d("door", get_parent(), global_position, -7.0, 0.75, 26.0)
		Game.toast("ЗАПЕРТО. НУЖНЫ ВСЕ МАНЕТЫ")
		if player != null and player.has_method("add_shake"):
			player.call("add_shake", 0.02)
		return
	opened = true
	AudioBank.play_3d("door", get_parent(), global_position, -2.0, 0.9, 40.0)
	AudioBank.play_3d("chime", get_parent(), global_position, -4.0, 1.0, 40.0)
	if door != null:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(door, "position:y", 2.55, 0.5).set_ease(Tween.EASE_IN)
		tween.tween_property(sign_light, "light_energy", 6.0, 0.4)
	used.emit()


func get_prompt() -> String:
	return "ПРОЙТИ" if unlocked else "ОТКРЫТЬ"
