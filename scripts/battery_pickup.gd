extends Node3D
## Батарейка для фонарика.

var collected := false
var _t := 0.0
var _base_y := 0.0
var _player: Node3D


func _ready() -> void:
	add_to_group("battery")
	_t = randf() * TAU
	_base_y = position.y


func _process(delta: float) -> void:
	if collected:
		return
	_t += delta
	rotation.y += delta * 0.9
	position.y = _base_y + sin(_t * 1.7) * 0.08

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		return
	if _player.get("active") != true:
		return
	if global_position.distance_to(_player.global_position + Vector3.UP) < 1.6:
		_collect()


func _collect() -> void:
	if collected:
		return
	collected = true
	if _player != null and _player.has_method("add_battery"):
		_player.call("add_battery", 35.0)
	AudioBank.play_3d("battery", get_parent(), global_position, -4.0, 1.0, 26.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3(2.2, 2.2, 2.2), 0.15)
	tween.tween_property(self, "position:y", _base_y + 0.5, 0.25)
	tween.set_parallel(false)
	tween.tween_property(self, "scale", Vector3.ZERO, 0.15)
	tween.tween_callback(queue_free)
