extends Node3D
## Манета: парит, вращается, светится и подбирается при подходе.

var collected := false
var _t := 0.0
var _base_y := 0.0
var _player: Node3D
var _light: OmniLight3D


func _ready() -> void:
	add_to_group("coin")
	_t = randf() * TAU
	_base_y = position.y
	_light = get_node_or_null("Glow") as OmniLight3D
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.15, 1.15, 1.15), 0.6)
	tw.tween_property(self, "scale", Vector3.ONE, 0.6)
	tw.set_loops()


func _process(delta: float) -> void:
	if collected:
		return
	_t += delta
	rotation.y += delta * 2.1
	position.y = _base_y + sin(_t * 2.0) * 0.12
	if _light != null:
		_light.light_energy = 0.9 + sin(_t * 4.0) * 0.25

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		return
	if _player.get("active") != true:
		return
	if global_position.distance_to(_player.global_position + Vector3.UP * 1.1) < 1.6:
		_collect()


func _collect() -> void:
	if collected:
		return
	collected = true
	Game.collect_coin()
	AudioBank.play_3d("coin", get_parent(), global_position, -3.0, 1.0, 32.0)
	if _light != null:
		_light.light_energy = 4.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3(3.0, 3.0, 3.0), 0.18)
	tween.tween_property(self, "position:y", _base_y + 0.7, 0.3)
	tween.set_parallel(false)
	tween.tween_property(self, "scale", Vector3.ZERO, 0.2)
	tween.tween_callback(queue_free)
