extends OmniLight3D
## Мерцающая/умирающая лампа под потолком.

enum Mode { STEADY, FLICKER, DYING }

var mode: int = Mode.STEADY
var base_energy := 1.5
var panel: MeshInstance3D
var panel_mat: StandardMaterial3D

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _state := 1.0


func setup(new_mode: int, new_panel: MeshInstance3D, new_mat: StandardMaterial3D) -> void:
	mode = new_mode
	panel = new_panel
	panel_mat = new_mat
	base_energy = light_energy
	_rng.randomize()
	_t = _rng.randf() * 12.0
	_apply(1.0)


func _process(delta: float) -> void:
	if mode == Mode.STEADY:
		return
	_t += delta
	if mode == Mode.FLICKER:
		if _rng.randf() < delta * 2.6:
			if _rng.randf() < 0.4:
				_state = _rng.randf_range(0.05, 0.45)
			else:
				_state = 1.0
		_apply(_state)
	else:
		var slow := 0.55 + 0.45 * sin(_t * 2.3)
		if fmod(_t, 7.0) > 6.3:
			slow = 0.04
		elif _rng.randf() < delta * 0.6:
			slow *= 0.2
		_apply(slow)


func _apply(value: float) -> void:
	light_energy = base_energy * value
	if panel_mat != null:
		panel_mat.emission_energy_multiplier = 2.0 * value
	if panel != null:
		panel.visible = value > 0.06
