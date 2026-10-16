class_name Explosion
extends Node2D
## 吃子爆炸：闪光 + 冲击波（自绘）+ 火花与烟雾（粒子），播完自动销毁。

const LIFE := 1.3

static var _dot: Texture2D

var _t := 0.0


func _ready() -> void:
	z_index = 10
	if _dot == null:
		_dot = _make_dot()

	var smoke := _burst(10, 1.1, 20.0, 60.0, Vector2(0, -50), 0.9, 1.8)
	smoke.color_ramp = _gradient([Color(0.47, 0.44, 0.42, 0.55), Color(0.35, 0.33, 0.31, 0.0)])
	smoke.scale_amount_curve = _curve(0.6, 1.6)
	add_child(smoke)

	var sparks := _burst(26, 0.7, 120.0, 260.0, Vector2(0, 120), 0.25, 0.55)
	sparks.color_ramp = _gradient([Color("#fde68a"), Color("#fbbf24"), Color("#f97316"), Color(0.94, 0.27, 0.27, 0.0)])
	sparks.scale_amount_curve = _curve(1.0, 0.2)
	add_child(sparks)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t > LIFE:
		queue_free()


func _draw() -> void:
	var k := _t / 0.22
	if k < 1.0:
		draw_circle(Vector2.ZERO, 12 + 30 * k, Color(1, 0.96, 0.75, 1.0 - k), true, -1.0, true)
	var r := _t / 0.5
	if r < 1.0:
		draw_arc(Vector2.ZERO, 12 + 48 * r, 0, TAU, 48, Color(1, 0.6, 0.12, 1.0 - r), 1.0 + 4.0 * (1.0 - r), true)


func _burst(amount: int, life: float, vmin: float, vmax: float, gravity: Vector2, smin: float, smax: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.texture = _dot
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.damping_min = 60.0
	p.damping_max = 120.0
	p.gravity = gravity
	p.scale_amount_min = smin
	p.scale_amount_max = smax
	p.emitting = true
	return p


static func _gradient(colors: Array) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / (colors.size() - 1))
		cols.append(colors[i])
	g.offsets = offsets
	g.colors = cols
	return g


static func _curve(from: float, to: float) -> Curve:
	var c := Curve.new()
	c.max_value = maxf(from, to)
	c.add_point(Vector2(0, from))
	c.add_point(Vector2(1, to))
	return c


static func _make_dot() -> Texture2D:
	var t := GradientTexture2D.new()
	t.width = 32
	t.height = 32
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.gradient = _gradient([Color.WHITE, Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	return t
