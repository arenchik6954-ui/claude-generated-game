extends Node3D
## Процедурный Уровень 0: генерация комнат, геометрии, света,
## коллизий и навигационной сетки для твари.

const CELL := 4.4
const WALL_H := 3.0
const COLS := 27
const ROWS := 27

const FLUORESCENT := preload("res://scripts/fluorescent.gd")

var cols := COLS
var rows := ROWS
var solid: Array = []
var cells_open: Array[Vector2i] = []
var spawn_cell := Vector2i(1, 1)
var exit_cell := Vector2i(1, 1)
var astar := AStar2D.new()
var rng := RandomNumberGenerator.new()

var _distances: Dictionary = {}
var _lights: Array[OmniLight3D] = []
var _player: Node3D
var _light_timer := 0.0
var _rng_seed := 0


func generate(seed_value: int) -> void:
	_rng_seed = seed_value
	rng.seed = seed_value
	_clear()
	_generate_grid()
	_collect_open_cells()
	_find_spawn()
	_compute_distances()
	_find_exit()
	_build_astar()
	_build_mesh()
	_build_collision()
	_spawn_lights()
	_spawn_props()


func set_player(node: Node3D) -> void:
	_player = node


func _clear() -> void:
	for child in get_children():
		child.queue_free()
	_lights.clear()
	cells_open.clear()
	_distances.clear()
	astar = AStar2D.new()


## ---------------------------------------------------------- сетка лабиринта

func _generate_grid() -> void:
	solid.clear()
	for y in rows:
		var row := PackedByteArray()
		row.resize(cols)
		row.fill(1)
		solid.append(row)

	var start := Vector2i(1, 1)
	_carve(start)
	var stack: Array[Vector2i] = [start]
	var dirs := [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]

	while not stack.is_empty():
		var cur: Vector2i = stack[stack.size() - 1]
		_shuffle(dirs)
		var moved := false
		for d in dirs:
			var nxt: Vector2i = cur + d
			if nxt.x < 1 or nxt.y < 1 or nxt.x > cols - 2 or nxt.y > rows - 2:
				continue
			if solid[nxt.y][nxt.x] == 0:
				continue
			_carve(nxt)
			_carve(cur + Vector2i(d.x / 2, d.y / 2))
			stack.append(nxt)
			moved = true
			break
		if not moved:
			stack.pop_back()

	# Петли и открытые «залы» — бекрумс не должен быть идеальным лабиринтом.
	for y in range(1, rows - 1):
		for x in range(1, cols - 1):
			if solid[y][x] == 1 and rng.randf() < 0.17:
				solid[y][x] = 0

	# Несколько просторных комнат.
	for i in 10:
		var w := rng.randi_range(2, 4)
		var h := rng.randi_range(2, 4)
		var x0 := rng.randi_range(1, maxi(1, cols - w - 2))
		var y0 := rng.randi_range(1, maxi(1, rows - h - 2))
		for y in range(y0, y0 + h):
			for x in range(x0, x0 + w):
				if x > 0 and y > 0 and x < cols - 1 and y < rows - 1:
					solid[y][x] = 0


func _carve(cell: Vector2i) -> void:
	if cell.x >= 0 and cell.y >= 0 and cell.x < cols and cell.y < rows:
		solid[cell.y][cell.x] = 0


func _collect_open_cells() -> void:
	cells_open.clear()
	var reachable := {}
	var start := Vector2i(1, 1)
	var queue: Array[Vector2i] = [start]
	reachable[start] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in _four_dirs():
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows:
				continue
			if solid[n.y][n.x] == 0 and not reachable.has(n):
				reachable[n] = true
				queue.append(n)

	for y in rows:
		for x in cols:
			if solid[y][x] == 0:
				if reachable.has(Vector2i(x, y)):
					cells_open.append(Vector2i(x, y))
				else:
					solid[y][x] = 1


func _find_spawn() -> void:
	var candidates: Array[Vector2i] = []
	for c in cells_open:
		var open_neighbors := 0
		for d in _four_dirs():
			if is_open(c + d):
				open_neighbors += 1
		if open_neighbors >= 2:
			candidates.append(c)
	if candidates.is_empty():
		spawn_cell = cells_open[0] if not cells_open.is_empty() else Vector2i(1, 1)
	else:
		spawn_cell = candidates[rng.randi_range(0, candidates.size() - 1)]


func _compute_distances() -> void:
	_distances.clear()
	_distances[spawn_cell] = 0
	var queue: Array[Vector2i] = [spawn_cell]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var d0: int = _distances[c]
		for d in _four_dirs():
			var n: Vector2i = c + d
			if is_open(n) and not _distances.has(n):
				_distances[n] = d0 + 1
				queue.append(n)


func _find_exit() -> void:
	var best := -1
	exit_cell = spawn_cell
	for c in cells_open:
		var d := distance(c)
		if d > best:
			best = d
			exit_cell = c


## ------------------------------------------------------------- геометрия

func _build_mesh() -> void:
	var floor_st := SurfaceTool.new()
	floor_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall_st := SurfaceTool.new()
	wall_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ceil_st := SurfaceTool.new()
	ceil_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for y in rows:
		for x in cols:
			if solid[y][x] == 1:
				continue
			var p := Vector3(x * CELL, 0.0, y * CELL)
			_quad(floor_st, p, p + Vector3(CELL, 0, 0),
					p + Vector3(CELL, 0, CELL), p + Vector3(0, 0, CELL), Vector3.UP)
			var cp := p + Vector3(0, WALL_H, 0)
			_quad(ceil_st, cp, cp + Vector3(CELL, 0, 0),
					cp + Vector3(CELL, 0, CELL), cp + Vector3(0, 0, CELL), Vector3.DOWN)

			if not is_open(Vector2i(x, y - 1)):
				_quad(wall_st, p, p + Vector3(CELL, 0, 0),
						p + Vector3(CELL, WALL_H, 0), p + Vector3(0, WALL_H, 0), Vector3(0, 0, 1))
			if not is_open(Vector2i(x, y + 1)):
				var pz := p + Vector3(0, 0, CELL)
				_quad(wall_st, pz, pz + Vector3(CELL, 0, 0),
						pz + Vector3(CELL, WALL_H, 0), pz + Vector3(0, WALL_H, 0), Vector3(0, 0, -1))
			if not is_open(Vector2i(x - 1, y)):
				_quad(wall_st, p, p + Vector3(0, 0, CELL),
						p + Vector3(0, WALL_H, CELL), p + Vector3(0, WALL_H, 0), Vector3(1, 0, 0))
			if not is_open(Vector2i(x + 1, y)):
				var px := p + Vector3(CELL, 0, 0)
				_quad(wall_st, px, px + Vector3(0, 0, CELL),
						px + Vector3(0, WALL_H, CELL), px + Vector3(0, WALL_H, 0), Vector3(-1, 0, 0))

	var mesh := ArrayMesh.new()
	floor_st.commit(mesh)
	wall_st.commit(mesh)
	ceil_st.commit(mesh)
	mesh.surface_set_material(0, _make_shader("res://shaders/carpet.gdshader"))
	mesh.surface_set_material(1, _make_shader("res://shaders/wallpaper.gdshader"))
	mesh.surface_set_material(2, _make_shader("res://shaders/ceiling.gdshader"))

	var instance := MeshInstance3D.new()
	instance.name = "LevelMesh"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(instance)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		normal: Vector3) -> void:
	var points := [a, b, c, a, c, d]
	var uvs: Array[Vector2] = []
	for point in points:
		uvs.append(_uv_for(point, normal))
	for i in points.size():
		st.set_normal(normal)
		st.set_uv(uvs[i])
		st.add_vertex(points[i])


func _uv_for(p: Vector3, n: Vector3) -> Vector2:
	if absf(n.y) > 0.5:
		return Vector2(p.x, p.z)
	var tangent := Vector3(-n.z, 0.0, n.x).normalized()
	if tangent.length() < 0.01:
		tangent = Vector3.RIGHT
	return Vector2(p.dot(tangent), p.y)


func _make_shader(path: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	return mat


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var y := 0
	while y < rows:
		var x := 0
		while x < cols:
			if solid[y][x] == 1:
				var start_x := x
				while x < cols and solid[y][x] == 1:
					x += 1
				var width := x - start_x
				_add_box(body, Vector3(start_x * CELL, 0.0, y * CELL),
						Vector3(width * CELL, WALL_H, CELL))
			else:
				x += 1
		y += 1

	_add_box(body, Vector3(0.0, -1.0, 0.0), Vector3(cols * CELL, 1.0, rows * CELL))
	_add_box(body, Vector3(0.0, WALL_H, 0.0), Vector3(cols * CELL, 1.0, rows * CELL))


func _add_box(body: Node3D, origin: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = origin + size * 0.5
	body.add_child(collision)


## ------------------------------------------------------------------- свет

func _spawn_lights() -> void:
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(1.5, 0.09, 0.72)
	var used: Array[Vector2i] = []

	for y in range(0, rows):
		for x in range(0, cols):
			var cell := Vector2i(x, y)
			if x % 3 != 1 or y % 3 != 1:
				continue
			if not is_open(cell):
				continue
			var too_close := false
			for other in used:
				if absi(other.x - x) + absi(other.y - y) < 2:
					too_close = true
					break
			if too_close:
				continue
			used.append(cell)

			var panel_mat := StandardMaterial3D.new()
			panel_mat.albedo_color = Color(0.92, 0.93, 0.82)
			panel_mat.roughness = 0.6
			var panel := MeshInstance3D.new()
			panel.mesh = panel_mesh
			panel.material_override = panel_mat
			panel.position = cell_to_world(cell) + Vector3(0.0, WALL_H - 0.07, 0.0)
			add_child(panel)

			var roll := rng.randf()
			if roll < 0.12:
				# перегоревшая лампа
				panel_mat.albedo_color = Color(0.20, 0.20, 0.18)
				panel_mat.emission_enabled = false
				continue

			panel_mat.emission_enabled = true
			panel_mat.emission = Color(1.0, 0.96, 0.78)
			panel_mat.emission_energy_multiplier = 2.0

			var light = OmniLight3D.new()
			light.position = cell_to_world(cell) + Vector3(0.0, WALL_H - 0.45, 0.0)
			light.light_color = Color(1.0, 0.96, 0.80)
			light.light_energy = 1.9
			light.omni_range = 7.2
			light.omni_attenuation = 1.3
			light.shadow_enabled = true
			light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
			light.shadow_bias = 0.05
			light.light_specular = 0.35
			light.light_volumetric_fog_energy = 1.4
			light.visible = false
			light.set_script(FLUORESCENT)
			add_child(light)
			var mode := 0
			if roll > 0.94:
				mode = 2
			elif roll > 0.74:
				mode = 1
			light.call("setup", mode, panel, panel_mat)
			_lights.append(light)


func _process(delta: float) -> void:
	if _lights.is_empty():
		return
	_light_timer -= delta
	if _light_timer > 0.0:
		return
	_light_timer = 0.35

	var origin := Vector3.ZERO
	if _player != null and is_instance_valid(_player):
		origin = _player.global_position
	else:
		return

	var limit := 10 if Game.quality >= 1 else 7
	var indexed: Array = []
	for i in _lights.size():
		var light := _lights[i]
		var d := light.global_position.distance_squared_to(origin)
		indexed.append({"i": i, "d": d})
	indexed.sort_custom(func(a, b): return a["d"] < b["d"])
	for i in _lights.size():
		_lights[i].visible = false
	for i in mini(limit, indexed.size()):
		_lights[int(indexed[i]["i"])].visible = true


## ------------------------------------------------------------------ пропсы

func _spawn_props() -> void:
	var crate_mat := StandardMaterial3D.new()
	crate_mat.albedo_color = Color(0.26, 0.18, 0.10)
	crate_mat.roughness = 0.92
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3.ONE

	var body := StaticBody3D.new()
	body.name = "Props"
	body.collision_layer = 1
	add_child(body)

	for cell in pick_cells(38, 1, 2):
		if is_open(cell + Vector2i(0, 1)) == false and is_open(cell + Vector2i(0, -1)) == false:
			continue
		var size := Vector3(rng.randf_range(0.45, 0.95), rng.randf_range(0.35, 0.85),
				rng.randf_range(0.45, 0.95))
		var side: Vector2i = _four_dirs()[rng.randi_range(0, 3)]
		var center := cell_to_world(cell) + Vector3(side.x, 0.0, side.y) * (CELL * 0.5 - 0.8)
		center += Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))

		var instance := MeshInstance3D.new()
		instance.mesh = box_mesh
		instance.material_override = crate_mat
		instance.scale = size
		instance.position = center + Vector3(0.0, size.y * 0.5, 0.0)
		instance.rotation.y = rng.randf_range(-0.5, 0.5)
		add_child(instance)

		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = instance.position
		collision.rotation = instance.rotation
		body.add_child(collision)


## --------------------------------------------------------------- запросы

func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL, 0.0, (cell.y + 0.5) * CELL)


func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / CELL)), int(floor(pos.z / CELL)))


func is_open(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= cols or cell.y >= rows:
		return false
	return solid[cell.y][cell.x] == 0


func distance(cell: Vector2i) -> int:
	return int(_distances.get(cell, 9999))


func distance_between(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func spawn_position() -> Vector3:
	return cell_to_world(spawn_cell) + Vector3(0.0, 0.15, 0.0)


func spawn_facing() -> float:
	for d in _four_dirs():
		if is_open(spawn_cell + d):
			return atan2(-float(d.x), -float(d.y))
	return 0.0


func exit_position() -> Vector3:
	return cell_to_world(exit_cell)


func random_open_cell() -> Vector2i:
	return cells_open[rng.randi_range(0, cells_open.size() - 1)]


func random_cell_far_from(pos: Vector3, min_distance: float) -> Vector2i:
	var cell := world_to_cell(pos)
	var candidates: Array[Vector2i] = []
	for c in cells_open:
		if distance_between(c, cell) >= int(min_distance / CELL) and distance(c) > 3:
			candidates.append(c)
	if candidates.is_empty():
		return cells_open[rng.randi_range(0, cells_open.size() - 1)]
	return candidates[rng.randi_range(0, candidates.size() - 1)]


func pick_cells(count: int, min_sep: int, min_dist_from_spawn: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var pool: Array[Vector2i] = []
	for c in cells_open:
		if c == spawn_cell or c == exit_cell:
			continue
		if distance(c) < min_dist_from_spawn:
			continue
		pool.append(c)
	_shuffle(pool)
	for c in pool:
		if result.size() >= count:
			break
		var ok := true
		for other in result:
			if distance_between(other, c) < min_sep:
				ok = false
				break
		if ok:
			result.append(c)
	return result


func world_path(from_pos: Vector3, to_pos: Vector3) -> PackedVector3Array:
	var from_cell := world_to_cell(from_pos)
	var to_cell := world_to_cell(to_pos)
	var points := PackedVector3Array()
	if not is_open(from_cell) or not is_open(to_cell):
		return points
	if not astar.has_point(_id(from_cell)) or not astar.has_point(_id(to_cell)):
		return points
	var ids := astar.get_id_path(_id(from_cell), _id(to_cell))
	for id in ids:
		var c := Vector2i(id % cols, int(floor(float(id) / float(cols))))
		points.append(cell_to_world(c))
	return points


func has_line_of_sight(a: Vector3, b: Vector3) -> bool:
	var dist := a.distance_to(b)
	if dist < 0.01:
		return true
	var steps := int(ceil(dist / 0.35))
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / float(steps))
		if not is_open(world_to_cell(p)):
			return false
	return true


func _build_astar() -> void:
	astar = AStar2D.new()
	for c in cells_open:
		astar.add_point(_id(c), Vector2(c))
	for c in cells_open:
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var n: Vector2i = c + d
			if is_open(n) and astar.has_point(_id(n)):
				astar.connect_points(_id(c), _id(n), true)


func _id(cell: Vector2i) -> int:
	return cell.y * cols + cell.x


func _four_dirs() -> Array[Vector2i]:
	return [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
