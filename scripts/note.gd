extends StaticBody3D
## Записка, приклеенная к стене. Читается через E.

var text := ""
var read := false
var _paper: MeshInstance3D


func _ready() -> void:
	add_to_group("note")
	collision_layer = 2
	collision_mask = 0
	_paper = get_node_or_null("Paper") as MeshInstance3D


func interact(_player: Node) -> void:
	if not read:
		read = true
		Game.collect_note()
		AudioBank.play_3d("note", get_parent(), global_position, -6.0, 1.0, 20.0)
		if _paper != null:
			_paper.rotation.z += 0.03
	else:
		AudioBank.play_3d("note", get_parent(), global_position, -14.0, 1.15, 16.0)
	Game.request_note(text)


func get_prompt() -> String:
	return "ПЕРЕЧИТАТЬ" if read else "ПРОЧИТАТЬ"
