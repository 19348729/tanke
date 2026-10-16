class_name BoardView
extends Control
## 棋盘：木纹底、米字格、坐标、落点提示、上一步/提示标记，以及坦克与爆炸特效层。
## 只负责显示和把点击翻译成格子坐标，规则判断交给 main.gd。

signal cell_clicked(cell: Vector2i)

const STEP := 60.0
const PAD := 60.0
const FRAME := 10.0
const HIT_RADIUS := 27.0
const NONE := Vector2i(-1, -1)

const WOOD_EDGE := Color("#8a5f33")
const DIAG_LINE := Color("#bb9866")
const MAIN_LINE := Color("#6b4f2a")
const BORDER := Color("#5b4226")
const MOVE_GREEN := Color("#16a34a")
const LAST_AMBER := Color("#d97706")
const HINT_BLUE := Color("#2563eb")

var board := PackedInt32Array()
var selected := NONE
var targets: Array[Vector2i] = []
var last_move: Array[Vector2i] = []
var hint_move: Array[Vector2i] = []
var active_side := 0  ## 当前可由鼠标操作的一方（0 = 不可操作）

var _hover := NONE
var _pieces := {}  # 棋盘索引 -> TankPiece
var _layer: Node2D
var _wood: Texture2D
var _frame_box: StyleBoxFlat
var _time := 0.0
var _shake := Vector2.ZERO


func _ready() -> void:
	var side := FRAME * 2 + PAD * 2 + STEP * (Rules.SIZE - 1)
	custom_minimum_size = Vector2(side, side)
	mouse_filter = MOUSE_FILTER_STOP
	_wood = _make_wood_texture()
	_frame_box = StyleBoxFlat.new()
	_frame_box.bg_color = WOOD_EDGE
	_frame_box.set_corner_radius_all(12)
	_frame_box.shadow_color = Color(0.26, 0.16, 0.05, 0.45)
	_frame_box.shadow_size = 22
	_frame_box.shadow_offset = Vector2(0, 12)
	_layer = Node2D.new()
	add_child(_layer)


func _process(delta: float) -> void:
	_time += delta
	if not targets.is_empty() or not hint_move.is_empty():
		queue_redraw()


func to_px(c: Vector2i) -> Vector2:
	return Vector2(FRAME + PAD + c.x * STEP, FRAME + PAD + c.y * STEP)


func cell_at(pos: Vector2) -> Vector2i:
	var g := (pos - Vector2(FRAME + PAD, FRAME + PAD)) / STEP
	var best := NONE
	var best_d := HIT_RADIUS
	for cx in [floori(g.x), ceili(g.x)]:
		for cy in [floori(g.y), ceili(g.y)]:
			var c := Vector2i(cx, cy)
			if not Rules.is_node(c):
				continue
			var d := to_px(c).distance_to(pos)
			if d < best_d:
				best_d = d
				best = c
	return best


## 按棋盘重建全部坦克（新局、悔棋时用，无动画）
func sync_pieces() -> void:
	for p in _pieces.values():
		p.queue_free()
	_pieces.clear()
	for i in board.size():
		if board[i] == Rules.EMPTY:
			continue
		var t := TankPiece.new()
		t.setup(board[i])
		t.position = to_px(Rules.cell(i))
		_layer.add_child(t)
		_pieces[i] = t
	_hover = NONE
	refresh()


## 刷新选中/悬停等显示状态
func refresh() -> void:
	for i: int in _pieces:
		_pieces[i].selected = Rules.cell(i) == selected
	_apply_hover()
	queue_redraw()


## 播放走子动画；await 它直到坦克到位、爆炸开始
func animate_move(from: Vector2i, to: Vector2i, captures: PackedInt32Array) -> void:
	var piece: TankPiece = _pieces.get(Rules.idx(from))
	_pieces.erase(Rules.idx(from))
	_pieces[Rules.idx(to)] = piece
	piece.selected = false
	var dist := to_px(from).distance_to(to_px(to))
	await piece.drive_to(to_px(to), clampf(0.16 + dist / 900.0, 0.22, 0.6))
	for ci in captures:
		var victim: TankPiece = _pieces.get(ci)
		_pieces.erase(ci)
		if victim:
			victim.destroy()
		var fx := Explosion.new()
		fx.position = to_px(Rules.cell(ci))
		_layer.add_child(fx)
	if not captures.is_empty():
		shake(5.0 + 2.0 * captures.size())


func shake(strength := 6.0) -> void:
	var wobble := func(t: float) -> void:
		_shake = Vector2(sin(t * 60.0), cos(t * 47.0)) * (1.0 - t) * strength
		_layer.position = _shake
		queue_redraw()
	var tw := create_tween()
	tw.tween_method(wobble, 0.0, 1.0, 0.32)
	tw.tween_callback(wobble.bind(1.0))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var c := cell_at(event.position)
		if c != _hover:
			_hover = c
			_apply_hover()
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c := cell_at(event.position)
		if c != NONE:
			cell_clicked.emit(c)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != NONE:
		_hover = NONE
		_apply_hover()
		queue_redraw()


func _apply_hover() -> void:
	var clickable := false
	for i: int in _pieces:
		var own := active_side != 0 and board[i] == active_side
		var h := own and Rules.cell(i) == _hover
		_pieces[i].hovered = h
		clickable = clickable or h
	clickable = clickable or (_hover in targets)
	mouse_default_cursor_shape = CURSOR_POINTING_HAND if clickable else CURSOR_ARROW


func _draw() -> void:
	draw_set_transform(_shake)
	var side := size.x
	draw_style_box(_frame_box, Rect2(Vector2.ZERO, Vector2(side, side)))
	draw_texture_rect(_wood, Rect2(FRAME, FRAME, side - FRAME * 2, side - FRAME * 2), false)

	var o := Vector2(FRAME + PAD, FRAME + PAD)
	var span := STEP * (Rules.SIZE - 1)
	# 斜线
	for r in range(0, Rules.SIZE - 1, 2):
		for c in range(0, Rules.SIZE - 1, 2):
			var a := o + Vector2(c, r) * STEP
			draw_line(a, a + Vector2(2, 2) * STEP, DIAG_LINE, 1.5, true)
			draw_line(a + Vector2(2, 0) * STEP, a + Vector2(0, 2) * STEP, DIAG_LINE, 1.5, true)
	# 主网格
	for i in range(0, Rules.SIZE, 2):
		var p := i * STEP
		draw_line(o + Vector2(0, p), o + Vector2(span, p), MAIN_LINE, 2.5, true)
		draw_line(o + Vector2(p, 0), o + Vector2(p, span), MAIN_LINE, 2.5, true)
	# 双线外框
	draw_rect(Rect2(o, Vector2(span, span)), BORDER, false, 4.0)
	draw_rect(Rect2(o - Vector2(8, 8), Vector2(span + 16, span + 16)), Color(BORDER, 0.55), false, 1.5)

	# 坐标（与对战记录的 a1 记谱一致）
	var font := get_theme_default_font()
	for i in Rules.SIZE:
		var col_label := char(97 + i)
		var row_label := str(Rules.SIZE - i)
		var x := o.x + i * STEP
		draw_string(font, Vector2(x - 10, o.y + span + 40), col_label, HORIZONTAL_ALIGNMENT_CENTER, 20, 13, Color(BORDER, 0.6))
		draw_string(font, Vector2(o.x - 48, o.y + i * STEP + 5), row_label, HORIZONTAL_ALIGNMENT_CENTER, 20, 13, Color(BORDER, 0.6))

	# 上一步：起点小圈 + 虚线 + 终点光环
	if last_move.size() == 2:
		var f := to_px(last_move[0])
		var t := to_px(last_move[1])
		draw_arc(f, 8, 0, TAU, 24, Color(LAST_AMBER, 0.7), 2.5, true)
		draw_dashed_line(f, t, Color(LAST_AMBER, 0.4), 2.0, 6.0, true, true)
		draw_circle(t, 28, Color(LAST_AMBER, 0.12), true, -1.0, true)
		draw_arc(t, 28, 0, TAU, 40, Color(LAST_AMBER, 0.8), 2.0, true)

	# 提示着法：蓝色箭头路径
	if hint_move.size() == 2:
		var hp := 0.6 + 0.4 * sin(_time * 4.0)
		var hf := to_px(hint_move[0])
		var ht := to_px(hint_move[1])
		draw_line(hf, ht, Color(HINT_BLUE, 0.5 * hp), 5.0, true)
		draw_circle(ht, 20, Color(HINT_BLUE, 0.18 * hp), true, -1.0, true)
		draw_arc(ht, 20, 0, TAU, 36, Color(HINT_BLUE, 0.9 * hp), 2.5, true)

	# 交叉点与可落点
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	for r in Rules.SIZE:
		for c in Rules.SIZE:
			var cell := Vector2i(c, r)
			if not Rules.is_node(cell):
				continue
			var p := to_px(cell)
			if cell in targets:
				draw_circle(p, 9.0 + 3.0 * pulse, Color(0.13, 0.77, 0.37, 0.28), true, -1.0, true)
				draw_circle(p, 5.5, MOVE_GREEN, true, -1.0, true)
				if cell == _hover:
					draw_arc(p, 17, 0, TAU, 36, MOVE_GREEN, 2.5, true)
			elif board.is_empty() or board[Rules.idx(cell)] == Rules.EMPTY:
				var main := Rules.is_main(cell)
				draw_circle(p, 4.0 if main else 3.0, Color("#8a6a3f") if main else Color("#c4a878"), true, -1.0, true)
	draw_set_transform(Vector2.ZERO)


## 木纹：线性渐变底色 + 横向拉长的噪声年轮，低分辨率生成后放大
func _make_wood_texture() -> Texture2D:
	var n := 200
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 7
	noise.frequency = 1.0
	noise.fractal_octaves = 3
	var c0 := Color("#f3dcae")
	var c1 := Color("#ecca90")
	var c2 := Color("#dfb273")
	for y in n:
		for x in n:
			var g := float(x + y) / (2.0 * (n - 1))
			var base := c0.lerp(c1, g / 0.45) if g < 0.45 else c1.lerp(c2, (g - 0.45) / 0.55)
			var grain := noise.get_noise_2d(x * 0.03, y * 0.5)
			var ring := 0.5 + 0.5 * sin(grain * 14.0 + y * 0.08)
			img.set_pixel(x, y, base.darkened(0.05 * ring + 0.03 * grain))
	return ImageTexture.create_from_image(img)
