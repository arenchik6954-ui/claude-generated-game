extends Node
## Процедурный звук. Все эффекты синтезируются в рантайме —
## в проекте нет ни одного внешнего аудиофайла.
## Автозагрузка под именем "AudioBank".

const RATE := 22050.0
const AMBIENT_RATE := 11025.0
const FADE := 500

var _streams: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _world_bus := "Master"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 90210
	_setup_bus()
	_build_library()


func _setup_bus() -> void:
	var idx := AudioServer.get_bus_index("Maze")
	if idx < 0:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "Maze")
		AudioServer.set_bus_send(idx, "Master")
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.78
		reverb.damping = 0.5
		reverb.spread = 0.85
		reverb.wet = 0.32
		reverb.dry = 0.95
		reverb.predelay_msec = 32.0
		AudioServer.add_bus_effect(idx, reverb)
	_world_bus = "Maze"


## ------------------------------------------------------------- генераторы

func _build_library() -> void:
	_streams["buzz"] = _to_wav(_gen_buzz(), true, int(AMBIENT_RATE))
	_streams["room_tone"] = _to_wav(_gen_room_tone(), true, int(AMBIENT_RATE))
	_streams["heartbeat"] = _to_wav(_gen_heartbeat(), true, int(AMBIENT_RATE))
	_streams["growl"] = _to_wav(_gen_growl(), true, int(AMBIENT_RATE))
	_streams["whisper"] = _to_wav(_gen_whisper(), false, int(AMBIENT_RATE))
	_streams["whisper_loop"] = _to_wav(_gen_whisper(), true, int(AMBIENT_RATE))
	_streams["static"] = _to_wav(_gen_static(), false, int(RATE))
	_streams["step"] = _to_wav(_gen_step(), false, int(RATE))
	_streams["coin"] = _to_wav(_gen_coin(), false, int(RATE))
	_streams["battery"] = _to_wav(_gen_battery(), false, int(RATE))
	_streams["note"] = _to_wav(_gen_note(), false, int(RATE))
	_streams["scream"] = _to_wav(_gen_scream(), false, int(RATE))
	_streams["stinger"] = _to_wav(_gen_stinger(), false, int(RATE))
	_streams["door"] = _to_wav(_gen_door(), false, int(RATE))
	_streams["chime"] = _to_wav(_gen_chime(), false, int(RATE))
	_streams["click"] = _to_wav(_gen_click(), false, int(AMBIENT_RATE))
	_streams["thump"] = _to_wav(_gen_thump(), false, int(RATE))
	_streams["glitch"] = _to_wav(_gen_glitch(), false, int(RATE))


func _gen_buzz() -> PackedFloat32Array:
	var rate := int(AMBIENT_RATE)
	var n := rate
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var s := sin(TAU * 120.0 * t) * 0.40
		s += sin(TAU * 240.0 * t) * 0.20
		s += sin(TAU * 360.0 * t) * 0.10
		s += sin(TAU * 600.0 * t) * 0.04
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.35
		s += lp * 0.11
		s *= 0.8 + 0.2 * sin(TAU * 6.0 * t)
		out[i] = s * 0.30
	return _loopify(out, 400)


func _gen_room_tone() -> PackedFloat32Array:
	var rate := int(AMBIENT_RATE)
	var n := rate * 8
	var out := PackedFloat32Array()
	out.resize(n)
	var brown := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		brown = clampf(brown + _rng.randf_range(-1.0, 1.0) * 0.03, -1.0, 1.0) * 0.998
		lp += (brown - lp) * 0.06
		var s := lp * 1.5
		s += sin(TAU * 43.0 * t) * 0.10
		s += sin(TAU * 86.0 * t) * 0.04
		s *= 0.72 + 0.28 * sin(TAU * 0.125 * t)
		out[i] = s * 0.5
	return _loopify(out, 2200)


func _gen_heartbeat() -> PackedFloat32Array:
	var rate := int(AMBIENT_RATE)
	var n := int(rate * 1.1)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(rate)
		var s := _thump_sample(t, 0.02, 56.0)
		s += _thump_sample(t, 0.30, 47.0) * 0.7
		s += _thump_sample(t, 0.02, 120.0) * 0.18
		out[i] = clampf(s, -1.0, 1.0) * 0.8
	return _loopify(out, 200)


func _thump_sample(t: float, start: float, freq: float) -> float:
	if t < start:
		return 0.0
	var dt := t - start
	if dt > 0.28:
		return 0.0
	var env := exp(-dt * 24.0)
	return sin(TAU * (freq - 18.0 * dt) * dt) * env


func _gen_growl() -> PackedFloat32Array:
	var rate := int(AMBIENT_RATE)
	var n := int(rate * 2.6)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var f := 61.0 + sin(TAU * 0.7 * t) * 10.0 + sin(TAU * 5.3 * t) * 3.0
		var s := sin(TAU * f * t) * 0.5 + sin(TAU * f * 2.02 * t) * 0.22
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.09
		s += lp * 0.65
		s *= 0.55 + 0.45 * sin(TAU * 1.6 * t)
		out[i] = tanh(s * 1.9) * 0.42
	return _loopify(out, 900)


func _gen_whisper() -> PackedFloat32Array:
	var rate := int(AMBIENT_RATE)
	var n := rate * 4
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.42
		var syl := pow(maxf(sin(TAU * 5.5 * t + 1.0), 0.0), 6.0)
		var swell := pow(maxf(sin(TAU * 1.25 * t), 0.0), 2.0)
		out[i] = lp * (0.12 + syl * 0.8) * swell * 0.22
	return _loopify(out, 1200)


func _gen_static() -> PackedFloat32Array:
	var rate := int(RATE)
	var n := rate
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = _rng.randf_range(-1.0, 1.0) * 0.42
	return _loopify(out, 600)


func _gen_menu_drone() -> PackedFloat32Array:
	var rate := int(AMBIENT_RATE)
	var n := rate * 8
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var s := sin(TAU * 38.0 * t) * 0.35
		s += sin(TAU * 38.6 * t) * 0.30
		s += sin(TAU * 57.0 * t) * 0.12
		s += sin(TAU * 114.3 * t) * 0.05
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.03
		s += lp * 0.9
		s *= 0.6 + 0.4 * sin(TAU * 0.09 * t)
		out[i] = s * 0.42
	return _loopify(out, 1800)


func _gen_step() -> PackedFloat32Array:
	var rate := int(RATE)
	var n := int(rate * 0.25)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var env := exp(-t * 26.0)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.16
		var thump := sin(TAU * (74.0 - 30.0 * t) * t) * exp(-t * 16.0)
		out[i] = clampf(lp * 1.7 + thump * 0.9, -1.0, 1.0) * env * 0.55
	return out


func _gen_coin() -> PackedFloat32Array:
	var rate := int(RATE)
	var n := int(rate * 0.9)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(rate)
		var env := exp(-t * 5.0)
		var s := sin(TAU * 1046.5 * t) * 0.42
		s += sin(TAU * 1568.0 * t) * 0.28
		s += sin(TAU * 2093.0 * t) * 0.14
		s += sin(TAU * 3136.0 * t) * 0.08 * exp(-t * 14.0)
		s *= 0.88 + 0.12 * sin(TAU * 21.0 * t)
		out[i] = s * env * 0.5
	return out


func _gen_battery() -> PackedFloat32Array:
	var rate := int(RATE)
	var n := int(rate * 0.5)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(rate)
		var env := exp(-t * 6.0)
		var f := 420.0 + 900.0 * clampf(t / 0.35, 0.0, 1.0)
		var s := sin(TAU * f * t) * 0.4
		s += sin(TAU * f * 2.0 * t) * 0.12
		s += _rng.randf_range(-1.0, 1.0) * 0.15 * exp(-t * 60.0)
		out[i] = s * env * 0.5
	return out


func _gen_note() -> PackedFloat32Array:
	var rate := int(RATE)
	var n := int(rate * 0.6)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.34
		var env := exp(-t * 7.0) * (0.6 + 0.4 * sin(TAU * 14.0 * t))
		out[i] = lp * env * 0.35
	return out


func _gen_scream() -> PackedFloat32Array:
	var rate := int(RATE)
	var n := int(rate * 1.8)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(rate)
		var f := lerpf(980.0, 150.0, clampf(t / 1.0, 0.0, 1.0))
		f *= 1.0 + 0.06 * sin(TAU * 31.0 * t)
		var s := sin(TAU * f * t)
		s += sin(TAU * f * 1.51 * t) * 0.45
		s = tanh(s * 2.6) * 0.75
		s += _rng.randf_range(-1.0, 1.0) * 0.45 * exp(-t * 3.0)
		s += _thump_sample(t, 0.0, 60.0) * 0.8
		var env := minf(t * 30.0, 1.0) * exp(-maxf(t - 0.9, 0.0) * 2.2)
		out[i] = clampf(s, -1.0, 1.0) * env * 0.7
	return out


func _gen_stinger() -> PackedFloat32Array:
	var rate := int(RATE)
	var n := int(rate * 1.6)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.06
		var swell := pow(clampf(t / 0.75, 0.0, 1.0), 2.5)
		var s := lp * swell * 0.8
		s += sin(TAU * lerpf(90.0, 38.0, clampf(t / 1.2, 0.0, 1.0)) * t) * 0.4 * swell
		s += _thump_sample(t, 0.72, 55.0) * 0.9
		out[i] = clampf(s, -1.0, 1.0) * 0.8
	return out


func _gen_door() -> PackedFloat32Array:
	var rate := int(RATE)
	var n := int(rate * 1.2)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(rate)
		var s := sin(TAU * (220.0 - 60.0 * t) * t) * exp(-t * 7.0) * 0.4
		s += sin(TAU * 517.0 * t) * exp(-t * 11.0) * 0.18
		s += sin(TAU * 941.0 * t) * exp(-t * 16.0) * 0.1
		s += _rng.randf_range(-1.0, 1.0) * exp(-t * 30.0) * 0.4
		out[i] = clampf(s, -1.0, 1.0) * 0.6
	return out


func _gen_chime() -> PackedFloat32Array:
	var rate := int(RATE)
	var n := int(rate * 2.0)
	var out := PackedFloat32Array()
	out.resize(n)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for i in n:
		var t := float(i) / float(rate)
		var s := 0.0
		for k in notes.size():
			var start := 0.12 * float(k)
			if t >= start:
				var dt := t - start
				s += sin(TAU * float(notes[k]) * dt) * exp(-dt * 2.4) * 0.16
		out[i] = clampf(s, -1.0, 1.0)
	return out


func _gen_click() -> PackedFloat32Array:
	var rate := int(AMBIENT_RATE)
	var n := int(rate * 0.12)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(rate)
		out[i] = _rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.5
	return out


func _gen_thump() -> PackedFloat32Array:
	var rate := int(RATE)
	var n := int(rate * 1.4)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.03
		var s := sin(TAU * (52.0 - 10.0 * t) * t) * exp(-t * 3.2) * 0.8
		s += lp * exp(-t * 2.0) * 1.4
		out[i] = clampf(s, -1.0, 1.0) * 0.7
	return out


func _gen_glitch() -> PackedFloat32Array:
	var rate := int(RATE)
	var n := int(rate * 0.45)
	var out := PackedFloat32Array()
	out.resize(n)
	var hold := 0.0
	for i in n:
		var t := float(i) / float(rate)
		if i % 90 == 0:
			hold = _rng.randf_range(-1.0, 1.0)
		var s := signf(hold) * 0.35 + sin(TAU * 1800.0 * t) * 0.2
		out[i] = s * exp(-t * 6.0) * 0.5
	return out


## ------------------------------------------------------------- конвертация

func _to_wav(samples: PackedFloat32Array, looped: bool, rate: int) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


func _loopify(samples: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	var n := samples.size()
	if fade <= 0 or fade * 2 >= n:
		return samples
	var out := PackedFloat32Array()
	out.resize(n - fade)
	for i in out.size():
		out[i] = samples[i]
	for i in fade:
		var w := float(i) / float(fade)
		out[i] = lerpf(samples[n - fade + i], samples[i], w)
	return out


## ------------------------------------------------------------- воспроизведение

func stream_for(name: String) -> AudioStream:
	return _streams.get(name, null) as AudioStream


func play(name: String, volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	var stream := stream_for(name)
	if stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.bus = "Master"
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
	return player


func play_loop(name: String, volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	var stream := stream_for(name)
	if stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.bus = _world_bus
	add_child(player)
	player.play()
	return player


func play_3d(name: String, parent: Node, position: Vector3, volume_db := 0.0,
		pitch := 1.0, max_distance := 34.0, unit_size := 8.0) -> AudioStreamPlayer3D:
	var stream := stream_for(name)
	if stream == null or parent == null:
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = max_distance
	player.unit_size = unit_size
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.bus = _world_bus
	parent.add_child(player)
	player.global_position = position
	player.play()
	player.finished.connect(player.queue_free)
	return player


func make_3d_loop(name: String, parent: Node, volume_db := 0.0, max_distance := 40.0,
		unit_size := 9.0) -> AudioStreamPlayer3D:
	var stream := stream_for(name)
	if stream == null or parent == null:
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.max_distance = max_distance
	player.unit_size = unit_size
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.bus = _world_bus
	parent.add_child(player)
	player.play()
	return player
