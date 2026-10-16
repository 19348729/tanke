class_name Rules
extends RefCounted
## 坦克棋纯规则层：棋盘是 9x9 的 PackedInt32Array，与渲染、输入完全解耦，界面和 AI 共用。
##
## 坐标 (col, row) 取 0..8：偶数坐标是主网格交叉点，奇数坐标是方格中心，
## 只有 col % 2 == row % 2 的点可以落子（"米"字格拓扑）。

const SIZE := 9
const EMPTY := 0
const RED := 1
const BLACK := 2
const DRAW := 3

const MIN_PIECES := 2        ## 存活少于此数即判负
const NO_CAPTURE_DRAW := 60  ## 连续这么多步（双方合计）无吃子判和，避免无限对局

## 斜线：任意落点都可沿斜线一格一格走
const DIAG_DIRS := [Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]
## 横竖：只存在于主网格线上，一步跨两个坐标单位
const ORTHO_DIRS := [Vector2i(0, 2), Vector2i(0, -2), Vector2i(2, 0), Vector2i(-2, 0)]
const ALL_DIRS := [
	Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1),
	Vector2i(0, 2), Vector2i(0, -2), Vector2i(2, 0), Vector2i(-2, 0),
]


static func opponent(side: int) -> int:
	return BLACK if side == RED else RED


static func side_name(side: int) -> String:
	return "红方" if side == RED else "黑方"


static func idx(c: Vector2i) -> int:
	return c.y * SIZE + c.x


@warning_ignore("integer_division")
static func cell(i: int) -> Vector2i:
	return Vector2i(i % SIZE, i / SIZE)


static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < SIZE and c.y >= 0 and c.y < SIZE


static func is_node(c: Vector2i) -> bool:
	return in_bounds(c) and c.x % 2 == c.y % 2


static func is_main(c: Vector2i) -> bool:
	return c.x % 2 == 0 and c.y % 2 == 0


## 棋谱坐标：列 a–i（左到右），行 1–9（下到上）
static func notation(c: Vector2i) -> String:
	return "%s%d" % [char(97 + c.x), SIZE - c.y]


static func dirs_from(c: Vector2i) -> Array:
	return ALL_DIRS if is_main(c) else DIAG_DIRS


static func initial_board() -> PackedInt32Array:
	var b := PackedInt32Array()
	b.resize(SIZE * SIZE)
	b.fill(EMPTY)
	for c in [0, 2, 4, 6, 8]:
		b[idx(Vector2i(c, 0))] = BLACK
		b[idx(Vector2i(c, 8))] = RED
	for c in [1, 3, 5, 7]:
		b[idx(Vector2i(c, 1))] = BLACK
		b[idx(Vector2i(c, 7))] = RED
	return b


static func count(b: PackedInt32Array, side: int) -> int:
	return b.count(side)


## 从 from 出发的全部合法落点：沿线滑行，遇子或出界即停
static func moves_from(b: PackedInt32Array, from: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in dirs_from(from):
		var p := from + d
		while in_bounds(p) and b[idx(p)] == EMPTY:
			out.append(p)
			p += d
	return out


static func is_valid_move(b: PackedInt32Array, from: Vector2i, to: Vector2i) -> bool:
	return to in moves_from(b, from)


static func has_any_move(b: PackedInt32Array, side: int) -> bool:
	for i in b.size():
		if b[i] != side:
			continue
		var from := cell(i)
		for d: Vector2i in dirs_from(from):
			var p := from + d
			if in_bounds(p) and b[idx(p)] == EMPTY:
				return true
	return false


## 夹击判定（b 中棋子已落到 at）：沿每条线向外，"连续对方棋子 + 己方棋子收尾"即被吃。
## 只有主动走子的一方能吃子；方格中心没有横竖线，只能沿斜线夹击。
static func find_captures(b: PackedInt32Array, at: Vector2i, side: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var foe := opponent(side)
	for d: Vector2i in dirs_from(at):
		var run := PackedInt32Array()
		var p := at + d
		while in_bounds(p):
			var v := b[idx(p)]
			if v == foe:
				run.append(idx(p))
			else:
				if v == side:
					out.append_array(run)
				break
			p += d
	return out


## 执行一步（不校验合法性），返回 {"board": 新棋盘, "captured": 被吃棋子的索引}
static func apply_move(b: PackedInt32Array, from: Vector2i, to: Vector2i) -> Dictionary:
	var nb := b.duplicate()
	var side := nb[idx(from)]
	nb[idx(to)] = side
	nb[idx(from)] = EMPTY
	var caps := find_captures(nb, to, side)
	for c in caps:
		nb[c] = EMPTY
	return {"board": nb, "captured": caps}


## 对局结果：0 进行中；RED / BLACK 获胜；DRAW 和棋。side_to_move 是轮到走棋的一方。
static func outcome(b: PackedInt32Array, side_to_move: int, quiet_plies: int) -> int:
	if count(b, RED) < MIN_PIECES:
		return BLACK
	if count(b, BLACK) < MIN_PIECES:
		return RED
	if not has_any_move(b, side_to_move):
		return opponent(side_to_move)
	if quiet_plies >= NO_CAPTURE_DRAW:
		return DRAW
	return 0
