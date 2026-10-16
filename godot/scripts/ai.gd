class_name TankAI
extends RefCounted
## 电脑对手：迭代加深 Negamax + Alpha-Beta 剪枝，叶子节点做"只看吃子"的静态搜索，
## 防止在吃子交换的半途停下误判。搜索在内部棋盘上原地走子/还原，避免频繁复制。
## 运行在工作线程中；主线程把 abort 设为 true 即可让搜索尽快结束。
## 所有可调参数见 AIConfig。

const WIN := 100000
const INF := 1000000

var abort := false
var nodes := 0
var reached_depth := 0

var _b := PackedInt32Array()
var _cnt := PackedInt32Array([0, 0, 0])
var _deadline := 0
var _stop := false
var _quiesce_depth := 4
var _attack := 100
var _defense := 100
var _position := 4
var _mobility := 1
var _root := Rules.RED  ## 电脑自己是哪一方：性格权重始终站在它的视角


## 返回 Vector2i(起点索引, 终点索引)；无棋可走时返回 (-1, -1)
func choose_move(board: PackedInt32Array, side: int, cfg: Dictionary) -> Vector2i:
	cfg = AIConfig.sanitize(cfg)
	var noise: int = cfg.noise
	_quiesce_depth = cfg.quiesce
	_attack = cfg.attack
	_defense = cfg.defense
	_position = cfg.position
	_mobility = cfg.mobility
	_root = side
	_b = board.duplicate()
	_cnt = PackedInt32Array([0, Rules.count(_b, Rules.RED), Rules.count(_b, Rules.BLACK)])
	_deadline = Time.get_ticks_msec() + int(cfg.time_ms)
	_stop = false
	nodes = 0
	reached_depth = 0

	var root := _gen(side, false)
	if root.is_empty():
		return Vector2i(-1, -1)
	if randi_range(1, 100) <= int(cfg.blunder):
		var pick: Array = root.pick_random()  # 随手一步
		return Vector2i(pick[0], pick[1])
	var best: Array = root[0]

	for depth in range(1, int(cfg.depth) + 1):
		var alpha := -INF
		var iter_best: Array = []
		var iter_score := -INF
		for mv: Array in root:
			_make(mv, side)
			# 有扰动时用全窗口拿到精确分，扰动才公平
			var hi := INF if noise > 0 else -alpha
			var s := -_negamax(Rules.opponent(side), depth - 1, -INF, hi, 1)
			_unmake(mv, side)
			if _stop:
				break
			if noise > 0:
				s += randi_range(-noise, noise)
			if s > iter_score:
				iter_score = s
				iter_best = mv
			alpha = maxi(alpha, s)
		if _stop:
			# 第一层都没算完时，用已算出的最好着法兜底
			if depth == 1 and not iter_best.is_empty():
				best = iter_best
			break
		best = iter_best
		reached_depth = depth
		# 上一轮最佳着法排到最前，下一轮剪枝更高效
		root.erase(best)
		root.push_front(best)
		if absi(iter_score) >= WIN - 100:
			break  # 已算出必胜或必败，无需更深
	return Vector2i(best[0], best[1])


func _negamax(side: int, depth: int, alpha: int, beta: int, ply: int) -> int:
	nodes += 1
	if (nodes & 255) == 0 and (abort or Time.get_ticks_msec() > _deadline):
		_stop = true
	if _stop:
		return 0
	if _cnt[side] < Rules.MIN_PIECES:
		return -(WIN - ply)
	if depth <= 0:
		return _quiesce(side, alpha, beta, ply, _quiesce_depth)
	var moves := _gen(side, false)
	if moves.is_empty():
		return -(WIN - ply)  # 无子可走判负
	var best := -INF
	for mv: Array in moves:
		_make(mv, side)
		var s := -_negamax(Rules.opponent(side), depth - 1, -beta, -alpha, ply + 1)
		_unmake(mv, side)
		if _stop:
			return 0
		if s > best:
			best = s
		if s > alpha:
			alpha = s
		if alpha >= beta:
			break
	return best


func _quiesce(side: int, alpha: int, beta: int, ply: int, qdepth: int) -> int:
	nodes += 1
	if _cnt[side] < Rules.MIN_PIECES:
		return -(WIN - ply)
	var stand := _evaluate(side)
	if qdepth <= 0 or stand >= beta:
		return stand
	alpha = maxi(alpha, stand)
	for mv: Array in _gen(side, true):
		_make(mv, side)
		var s := -_quiesce(Rules.opponent(side), -beta, -alpha, ply + 1, qdepth - 1)
		_unmake(mv, side)
		if s >= beta:
			return s
		alpha = maxi(alpha, s)
	return alpha


## 局面评估：电脑每子值 defense、玩家每子值 attack，两者不等就形成进攻 / 防守性格；
## 再加主网格占位和周边空位（机动性）。权重不对称，所以先站在电脑视角算，再按 side 取正负。
func _evaluate(side: int) -> int:
	var score := _score_for_root()
	return score if side == _root else -score


func _score_for_root() -> int:
	var foe := Rules.opponent(_root)
	var score := _cnt[_root] * _defense - _cnt[foe] * _attack
	if _position == 0 and _mobility == 0:
		return score
	for i in _b.size():
		var v := _b[i]
		if v == Rules.EMPTY:
			continue
		var c := Rules.cell(i)
		var bonus := 0
		if Rules.is_main(c):
			bonus += _position
		if _mobility > 0:
			for d: Vector2i in Rules.dirs_from(c):
				var p := c + d
				if Rules.in_bounds(p) and _b[Rules.idx(p)] == Rules.EMPTY:
					bonus += _mobility
		score += bonus if v == _root else -bonus
	return score


## 生成着法：[起点, 终点, 被吃索引数组]，吃子多的排前面
func _gen(side: int, captures_only: bool) -> Array:
	var out := []
	for i in _b.size():
		if _b[i] != side:
			continue
		var from := Rules.cell(i)
		var targets := Rules.moves_from(_b, from)
		_b[i] = Rules.EMPTY
		for to in targets:
			var ti := Rules.idx(to)
			_b[ti] = side
			var caps := Rules.find_captures(_b, to, side)
			_b[ti] = Rules.EMPTY
			if captures_only and caps.is_empty():
				continue
			out.append([i, ti, caps])
		_b[i] = side
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[2].size() > b[2].size())
	return out


func _make(mv: Array, side: int) -> void:
	_b[mv[0]] = Rules.EMPTY
	_b[mv[1]] = side
	var caps: PackedInt32Array = mv[2]
	for c in caps:
		_b[c] = Rules.EMPTY
	_cnt[Rules.opponent(side)] -= caps.size()


func _unmake(mv: Array, side: int) -> void:
	var foe := Rules.opponent(side)
	var caps: PackedInt32Array = mv[2]
	for c in caps:
		_b[c] = foe
	_cnt[foe] += caps.size()
	_b[mv[1]] = Rules.EMPTY
	_b[mv[0]] = side
