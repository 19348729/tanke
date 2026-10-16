extends SceneTree
## 规则与 AI 的无界面自测：godot --headless --path godot --script res://tests/test_rules.gd

var _failed := 0


func _init() -> void:
	_test_initial()
	_test_moves()
	_test_captures()
	_test_outcome()
	_test_config()
	_test_ai()
	_test_personality()
	_test_self_play()
	print("\n%s" % ("ALL TESTS PASSED" if _failed == 0 else "%d TEST(S) FAILED" % _failed))
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failed += 1


func _empty() -> PackedInt32Array:
	var b := PackedInt32Array()
	b.resize(Rules.SIZE * Rules.SIZE)
	b.fill(Rules.EMPTY)
	return b


func _put(b: PackedInt32Array, side: int, cells: Array) -> PackedInt32Array:
	for c: Vector2i in cells:
		b[Rules.idx(c)] = side
	return b


func _test_initial() -> void:
	print("initial board")
	var b := Rules.initial_board()
	_check(Rules.count(b, Rules.RED) == 9 and Rules.count(b, Rules.BLACK) == 9, "9 vs 9")
	_check(Rules.outcome(b, Rules.RED, 0) == 0, "game in progress")


func _test_moves() -> void:
	print("moves")
	var b := Rules.initial_board()
	var m := Rules.moves_from(b, Vector2i(0, 8))
	_check(m.size() == 3 and Vector2i(0, 2) in m and not Vector2i(0, 0) in m, "corner slides up until blocked: %s" % [m])
	var c := _put(_empty(), Rules.RED, [Vector2i(3, 3)])
	m = Rules.moves_from(c, Vector2i(3, 3))
	var ortho := m.filter(func(p: Vector2i) -> bool: return p.x == 3 or p.y == 3)
	_check(ortho.is_empty() and m.size() == 14, "center point moves only diagonally (%d)" % m.size())
	var e := _put(_empty(), Rules.RED, [Vector2i(4, 4)])
	_check(Rules.moves_from(e, Vector2i(4, 4)).size() == 24, "main point on empty board: 8 lines, 24 targets")
	_check(not Rules.is_valid_move(Rules.initial_board(), Vector2i(1, 7), Vector2i(1, 5)), "no orthogonal from center")


func _test_captures() -> void:
	print("captures")
	var b := _put(_empty(), Rules.RED, [Vector2i(0, 4), Vector2i(4, 6)])
	_put(b, Rules.BLACK, [Vector2i(2, 4)])
	var r := Rules.apply_move(b, Vector2i(4, 6), Vector2i(4, 4))
	_check(r.captured.size() == 1 and r.board[Rules.idx(Vector2i(2, 4))] == Rules.EMPTY, "single pinch")

	b = _put(_empty(), Rules.RED, [Vector2i(0, 4), Vector2i(6, 6)])
	_put(b, Rules.BLACK, [Vector2i(2, 4), Vector2i(4, 4)])
	r = Rules.apply_move(b, Vector2i(6, 6), Vector2i(6, 4))
	_check(r.captured.size() == 2, "pinch two in a row")

	b = _put(_empty(), Rules.RED, [Vector2i(0, 4), Vector2i(4, 4)])
	_put(b, Rules.BLACK, [Vector2i(2, 6)])
	r = Rules.apply_move(b, Vector2i(2, 6), Vector2i(2, 4))
	_check(r.captured.is_empty() and Rules.count(r.board, Rules.BLACK) == 1, "walking into a pinch is safe")

	b = _put(_empty(), Rules.RED, [Vector2i(1, 1), Vector2i(4, 2)])
	_put(b, Rules.BLACK, [Vector2i(2, 2)])
	r = Rules.apply_move(b, Vector2i(4, 2), Vector2i(3, 3))
	_check(r.captured.size() == 1, "diagonal pinch through a center point")

	b = _put(_empty(), Rules.RED, [Vector2i(3, 1), Vector2i(8, 8)])
	_put(b, Rules.BLACK, [Vector2i(3, 3)])
	r = Rules.apply_move(b, Vector2i(8, 8), Vector2i(3, 5))
	_check(r.captured.is_empty(), "no vertical pinch along a center column")

	b = _put(_empty(), Rules.RED, [Vector2i(0, 4), Vector2i(4, 0), Vector2i(4, 6)])
	_put(b, Rules.BLACK, [Vector2i(2, 4), Vector2i(4, 2)])
	r = Rules.apply_move(b, Vector2i(4, 6), Vector2i(4, 4))
	_check(r.captured.size() == 2, "one move pinches in two directions")


func _test_outcome() -> void:
	print("outcome")
	var b := _put(_empty(), Rules.RED, [Vector2i(0, 0), Vector2i(2, 2)])
	_put(b, Rules.BLACK, [Vector2i(8, 8)])
	_check(Rules.outcome(b, Rules.BLACK, 0) == Rules.RED, "fewer than 2 pieces loses")
	b = _put(_empty(), Rules.BLACK, [Vector2i(0, 0), Vector2i(8, 8)])
	_put(b, Rules.RED, [Vector2i(1, 1), Vector2i(2, 0), Vector2i(0, 2), Vector2i(7, 7), Vector2i(8, 6), Vector2i(6, 8)])
	_check(Rules.outcome(b, Rules.BLACK, 0) == Rules.RED, "no legal move loses")
	_check(Rules.outcome(Rules.initial_board(), Rules.RED, Rules.NO_CAPTURE_DRAW) == Rules.DRAW, "quiet-move draw")


func _test_config() -> void:
	print("ai config")
	var c := AIConfig.sanitize({"depth": 99, "time_ms": -5, "noise": "abc", "attack": 120.4})
	_check(c.depth == 8 and c.time_ms == 200 and c.noise == AIConfig.preset(1).noise and c.attack == 120, "sanitize clamps, rounds, defaults: %s" % [c])
	_check(c.size() == AIConfig.FIELDS.size(), "sanitize fills every field")
	for i in AIConfig.PRESETS.size():
		var p := AIConfig.preset(i)
		_check(AIConfig.sanitize(p) == p, "preset %s within ranges" % AIConfig.PRESETS[i].name)
	_check(AIConfig.warnings(AIConfig.preset(1)) == "", "normal preset has no warnings")
	_check(AIConfig.warnings({"depth": 8, "time_ms": 500, "quiesce": 4, "noise": 0, "blunder": 0, "attack": 100, "defense": 100, "position": 4, "mobility": 1}) != "", "warns when depth exceeds time budget")


func _test_ai() -> void:
	print("ai")
	var ai := TankAI.new()
	var b := _put(_empty(), Rules.RED, [Vector2i(0, 4), Vector2i(4, 6), Vector2i(8, 8)])
	_put(b, Rules.BLACK, [Vector2i(2, 4), Vector2i(0, 0), Vector2i(8, 0)])
	for i in AIConfig.PRESETS.size():
		var cfg := AIConfig.preset(i)
		var t0 := Time.get_ticks_msec()
		var mv := ai.choose_move(b, Rules.RED, cfg)
		var dt := Time.get_ticks_msec() - t0
		var legal := Rules.is_valid_move(b, Rules.cell(mv.x), Rules.cell(mv.y))
		_check(legal and dt < int(cfg.time_ms) + 500, "%s: legal move in %d ms (depth %d, %d nodes)" % [AIConfig.PRESETS[i].name, dt, ai.reached_depth, ai.nodes])
	var strong := AIConfig.preset(1)
	strong.noise = 0
	var mv := ai.choose_move(b, Rules.RED, strong)
	var caps: PackedInt32Array = Rules.apply_move(b, Rules.cell(mv.x), Rules.cell(mv.y)).captured
	_check(caps.size() >= 1, "normal takes the free capture")
	var t1 := Time.get_ticks_msec()
	var opening := ai.choose_move(Rules.initial_board(), Rules.RED, AIConfig.preset(2))
	_check(opening.x >= 0 and Time.get_ticks_msec() - t1 < 3500, "hard opening within time (%d ms, depth %d)" % [Time.get_ticks_msec() - t1, ai.reached_depth])


## 一子换一子的局面：激进型（进攻 > 防守）应该吃，稳健型（防守 > 进攻）应该放弃
func _test_personality() -> void:
	print("personality")
	# 红方唯一的吃子是 e3→e5 吃 c5，随后黑方 g1→e3 夹回 e5
	var b := _put(_empty(), Rules.RED, [Vector2i(0, 4), Vector2i(4, 6), Vector2i(8, 2)])
	_put(b, Rules.BLACK, [Vector2i(2, 4), Vector2i(4, 2), Vector2i(6, 8), Vector2i(8, 0)])
	var trade := Vector2i(Rules.idx(Vector2i(4, 6)), Rules.idx(Vector2i(4, 4)))
	var ai := TankAI.new()
	for i in [3, 4]:
		var cfg := AIConfig.preset(i)
		cfg.noise = 0
		cfg.position = 0
		cfg.mobility = 0
		cfg.depth = 2
		var mv := ai.choose_move(b, Rules.RED, cfg)
		var took := mv == trade
		_check(took == (i == 3), "%s %s the 1-for-1 trade" % [AIConfig.PRESETS[i].name, "takes" if took else "declines"])


func _test_self_play() -> void:
	print("self-play (easy vs normal)")
	var ai := TankAI.new()
	var b := Rules.initial_board()
	var side := Rules.RED
	var quiet := 0
	var result := 0
	var plies := 0
	while result == 0 and plies < 300:
		var mv := ai.choose_move(b, side, AIConfig.preset(0 if side == Rules.RED else 1))
		var r: Dictionary = Rules.apply_move(b, Rules.cell(mv.x), Rules.cell(mv.y))
		b = r.board
		quiet = 0 if r.captured.size() > 0 else quiet + 1
		side = Rules.opponent(side)
		result = Rules.outcome(b, side, quiet)
		plies += 1
	_check(result != 0, "game ends after %d plies, result=%d, red %d / black %d" % [plies, result, Rules.count(b, Rules.RED), Rules.count(b, Rules.BLACK)])
