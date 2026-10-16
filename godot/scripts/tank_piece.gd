class_name TankPiece
extends Node2D
## 单个坦克棋子：程序化绘制（履带、负重轮、车体、炮塔、五角星徽记），
## 行进时车头转向前进方向，到位后再转回本方朝向。

const UNIT := 0.48  ## 设计稿 100 单位 → 48 像素
const OUTLINE := Color("#1c1917")
const STAR := [
	Vector2(50, 38.6), Vector2(51.7, 42.3), Vector2(55.7, 42.7), Vector2(52.7, 45.4), Vector2(53.6, 49.3),
	Vector2(50, 47.2), Vector2(46.4, 49.3), Vector2(47.3, 45.4), Vector2(44.3, 42.7), Vector2(48.3, 42.3),
]

var player := Rules.RED
var home_facing := 0.0  ## 0 = 炮口朝上
var facing := 0.0:
	set(v):
		facing = v
		queue_redraw()
var selected := false:
	set(v):
		selected = v
		_update_scale()
		queue_redraw()
var hovered := false:
	set(v):
		hovered = v
		_update_scale()

var _ring_t := 0.0
var _box := StyleBoxFlat.new()
var _scale_tween: Tween


func setup(side: int) -> void:
	player = side
	home_facing = 0.0 if side == Rules.RED else PI
	facing = home_facing
	_box.anti_aliasing = true
	_box.corner_detail = 6


func _process(delta: float) -> void:
	if selected:
		_ring_t += delta
		queue_redraw()


## 驶向目标点；await 它直到抵达
func drive_to(target: Vector2, duration: float) -> void:
	var want := (target - position).angle() + PI / 2.0
	var tw := create_tween()
	tw.tween_method(_turn.bind(facing, want), 0.0, 1.0, 0.12)
	tw.tween_property(self, "position", target, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	create_tween().tween_method(_turn.bind(want, home_facing), 0.0, 1.0, 0.3) \
		.set_trans(Tween.TRANS_SINE)


## 被吃：闪白、膨胀、淡出
func destroy() -> void:
	selected = false
	z_index = 5
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "modulate", Color(3, 2.4, 1.6, 1), 0.08)
	tw.tween_property(self, "scale", Vector2.ONE * 1.35, 0.18)
	tw.chain().tween_property(self, "modulate:a", 0.0, 0.14)
	tw.chain().tween_callback(queue_free)


func _turn(t: float, from: float, to: float) -> void:
	facing = lerp_angle(from, to, t)


func _update_scale() -> void:
	if not is_inside_tree():
		return
	var target := 1.22 if selected else (1.1 if hovered else 1.0)
	z_index = 2 if selected else 1
	if _scale_tween:
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.tween_property(self, "scale", Vector2.ONE * target, 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var red := player == Rules.RED
	var track := Color("#7f1d1d") if red else Color("#1c1917")
	var body_light := Color("#f87171") if red else Color("#71717a")
	var body_dark := Color("#991b1b") if red else Color("#27272a")
	var turret_light := Color("#ef4444") if red else Color("#52525b")
	var turret_dark := Color("#7f1d1d") if red else Color("#09090b")
	var accent := Color("#fecaca") if red else Color("#d6d3d1")

	# 选中：光晕 + 旋转虚线圈（不随车体转动）
	if selected:
		draw_circle(Vector2.ZERO, 29, Color(0.92, 0.70, 0.03, 0.16), true, -1.0, true)
		var segs := 12
		for i in segs:
			var a0 := _ring_t * 1.4 + i * TAU / segs
			draw_arc(Vector2.ZERO, 29, a0, a0 + TAU / segs * 0.62, 6, Color("#eab308"), 2.2, true)

	# 接地阴影
	draw_set_transform(Vector2(0, 19), 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, 19, Color(0, 0, 0, 0.2), true, -1.0, true)

	# 车体：设计稿坐标 0..100，炮管朝 +y；旋转 PI 后炮口朝上
	draw_set_transform(Vector2.ZERO, facing + PI, Vector2(UNIT, UNIT))
	var o := Vector2(-50, -50)
	_rbox(Rect2(12, 10, 17, 80), 8, track, 2)
	_rbox(Rect2(71, 10, 17, 80), 8, track, 2)
	for cy in [20, 36, 52, 68, 81]:
		draw_circle(Vector2(20.5, cy) + o, 4.5, Color(0.05, 0.04, 0.03, 0.55), true, -1.0, true)
		draw_circle(Vector2(79.5, cy) + o, 4.5, Color(0.05, 0.04, 0.03, 0.55), true, -1.0, true)
	_rbox(Rect2(24, 18, 52, 64), 9, body_dark, 3)
	_rbox(Rect2(26, 20, 48, 40), 8, body_light.lerp(body_dark, 0.35), 0)
	_rbox(Rect2(28, 22, 44, 10), 5, Color(1, 1, 1, 0.18), 0)
	# 炮管 + 炮口制退器
	_rbox(Rect2(45.5, 52, 9, 46), 3, turret_dark, 2)
	_rbox(Rect2(43, 92, 14, 8), 2.5, turret_dark, 2)
	# 炮塔（叠圆模拟径向渐变）
	var tc := Vector2(50, 44) + o
	draw_circle(tc, 19, turret_dark, true, -1.0, true)
	for k in 4:
		var t := float(k + 1) / 4.0
		draw_circle(tc + Vector2(-3, -3) * t, 19 - 5 * t, turret_dark.lerp(turret_light, t), true, -1.0, true)
	draw_arc(tc, 19, 0, TAU, 40, OUTLINE, 2.5, true)
	# 舱盖与徽记
	draw_circle(tc, 9, Color(accent, 0.9), true, -1.0, true)
	draw_arc(tc, 9, 0, TAU, 28, Color(OUTLINE, 0.6), 1.5, true)
	var star := PackedVector2Array()
	for p: Vector2 in STAR:
		star.append(p + o)
	draw_colored_polygon(star, Color("#7f1d1d") if red else Color("#fafaf9", 0.9))
	draw_set_transform(Vector2.ZERO)


func _rbox(r: Rect2, radius: float, fill: Color, border: int) -> void:
	_box.bg_color = fill
	_box.set_corner_radius_all(int(radius))
	_box.set_border_width_all(border)
	_box.border_color = OUTLINE
	draw_style_box(_box, Rect2(r.position + Vector2(-50, -50), r.size))
