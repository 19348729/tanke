class_name Sfx
extends Node
## 合成音效：启动时按原网页版 Web Audio 的参数在内存里合成 PCM，不依赖任何音频文件。

const RATE := 22050

var muted := false

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _buf := PackedFloat32Array()  # 合成时的工作缓冲区


func _ready() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

	_streams.select = _render(0.14, func() -> void:
		_tone(660, 0.0, 0.08, "triangle", 0.18, 920))
	_streams.move = _render(0.2, func() -> void:
		_noise(0.0, 0.07, 0.1, 2400)
		_tone(190, 0.02, 0.12, "sine", 0.28, 95))
	_streams.capture = _render(0.6, func() -> void:
		_capture(1))
	_streams.capture_multi = _render(0.7, func() -> void:
		_capture(3))
	_streams.invalid = _render(0.26, func() -> void:
		_tone(150, 0.0, 0.09, "square", 0.1)
		_tone(120, 0.1, 0.11, "square", 0.1))
	_streams.undo = _render(0.22, func() -> void:
		_tone(540, 0.0, 0.16, "sine", 0.18, 260))
	_streams.win = _render(1.25, func() -> void:
		var notes := [523.25, 659.25, 783.99, 1046.5]
		for i in notes.size():
			_tone(notes[i], i * 0.13, 0.34, "triangle", 0.22)
			_tone(notes[i] / 2.0, i * 0.13, 0.34, "sine", 0.12)
		_tone(1046.5, 0.56, 0.6, "triangle", 0.2))


func play(sound: String) -> void:
	if muted or not _streams.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.play()


func play_capture(count: int) -> void:
	play("capture_multi" if count > 1 else "capture")


func _capture(count: int) -> void:
	var boost := mini(count, 3) * 0.12
	_noise(0.0, 0.08, 0.3 + boost, 3200)   # 炸裂
	_noise(0.02, 0.5, 0.35 + boost, 850)   # 轰鸣
	_tone(110, 0.0, 0.45, "sine", 0.42 + boost, 38)  # 低频冲击
	if count > 1:
		_noise(0.12, 0.4, 0.25, 600)  # 连环爆炸余响
		_tone(90, 0.12, 0.4, "sine", 0.3, 32)


func _render(seconds: float, fill: Callable) -> AudioStreamWAV:
	_buf = PackedFloat32Array()
	_buf.resize(int(seconds * RATE))
	_buf.fill(0.0)
	fill.call()
	var buf := _buf
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(tanh(buf[i] * 1.2) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	return s


## 单音：可指数滑音；包络为 12ms 线性起音 + 指数衰减
func _tone(freq: float, delay: float, dur: float, wave: String, vol: float, slide_to := 0.0) -> void:
	var start := int(delay * RATE)
	var n := mini(int(dur * RATE), _buf.size() - start)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := freq * pow(slide_to / freq, t / dur) if slide_to > 0.0 else freq
		phase = fposmod(phase + f / RATE, 1.0)
		var s := 0.0
		match wave:
			"sine":
				s = sin(TAU * phase)
			"triangle":
				s = 1.0 - 4.0 * absf(fposmod(phase + 0.25, 1.0) - 0.5)
			"square":
				s = 1.0 if phase < 0.5 else -1.0
		var env := vol * t / 0.012 if t < 0.012 else vol * pow(0.0001 / vol, (t - 0.012) / (dur - 0.012))
		_buf[start + i] += s * env


## 低通白噪声脉冲，用于爆炸、落子质感
func _noise(delay: float, dur: float, vol: float, cutoff: float) -> void:
	var start := int(delay * RATE)
	var n := mini(int(dur * RATE), _buf.size() - start)
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var y := 0.0
	for i in n:
		var x := randf_range(-1.0, 1.0) * pow(1.0 - float(i) / n, 2.0)
		y += a * (x - y)
		_buf[start + i] += y * vol * 2.0
