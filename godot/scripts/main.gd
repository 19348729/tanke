extends Control
## 主界面：搭建棋盘、侧栏和胜负浮层，驱动对局流程（双人 / 人机）。

enum Mode { VS_AI_RED, VS_AI_BLACK, PVP }

const NONE := Vector2i(-1, -1)
const MIN_AI_THINK_MS := 450  ## 电脑至少"想"这么久再落子，节奏更自然
const CUSTOM_ITEM_ID := 99  ## 下拉框里"自定义"的 id（OptionButton 的 id 不能是 -1）

const STONE_800 := Color("#292524")
const STONE_700 := Color("#44403c")
const STONE_500 := Color("#78716c")
const STONE_400 := Color("#a8a29e")
const STONE_200 := Color("#e7e5e4")
const STONE_100 := Color("#f5f5f4")
const STONE_50 := Color("#fafaf9")
const RED_600 := Color("#dc2626")
const AMBER_100 := Color("#fef3c7")
const AMBER_700 := Color("#b45309")
const ORANGE_600 := Color("#ea580c")

const RULES_TEXT := """[b]走子[/b]：沿棋盘线滑行，横竖只能走主网格线，斜线任意点都能走；路径不能有阻挡，落点必须为空。
[b]夹击吃子[/b]：走子后，己方两子在同一直线上紧紧夹住对方一枚或多枚棋子（红-黑-红、红-黑黑-红），被夹的全部消灭；一步可多方向同时吃。只有主动走子才吃子，走进对方两子之间不会被吃。
[b]胜负[/b]：对方存活少于 2 枚，或轮到对方时无子可走，即获胜；连续 %d 步无吃子判和。
[b]快捷键[/b]：Ctrl/⌘+Z 悔棋 · N 新游戏 · H 提示 · Esc 取消选择""" % Rules.NO_CAPTURE_DRAW

# 对局状态
var board := PackedInt32Array()
var turn := Rules.RED
var last_move: Array[Vector2i] = []
var quiet_plies := 0
var outcome := 0
var move_log: Array[String] = []
var history: Array[Dictionary] = []
var selected := NONE

var mode := Mode.VS_AI_RED
var ai_preset := AIConfig.DEFAULT_PRESET  ## AIConfig.PRESETS 下标，CUSTOM 为自定义
var custom_cfg := AIConfig.preset(AIConfig.DEFAULT_PRESET)
var busy := false  ## 动画或电脑思考中，暂不接受走子

# 电脑搜索（工作线程）
var _ai := TankAI.new()
var _ai_thread: Thread
var _ai_token := 0
var _ai_purpose := ""
var _thinking := false

# 界面
var _board_view: BoardView
var _sfx: Sfx
var _badges := {}
var _score_cards := {}
var _status: Label
var _log: RichTextLabel
var _rules: RichTextLabel
var _undo_btn: Button
var _hint_btn: Button
var _sound_btn: Button
var _ai_opt: OptionButton
var _ai_tune_btn: Button
var _ai_desc: Label
var _ai_info: Label
var _settings_panel: AISettingsPanel
var _overlay: Control
var _overlay_panel: PanelContainer
var _overlay_icon: Label
var _overlay_title: Label
var _overlay_score: Label
var _confetti: CPUParticles2D
var _serif: SystemFont


func _ready() -> void:
	var saved := AIConfig.load_settings()
	ai_preset = saved.preset
	custom_cfg = saved.custom
	mode = clampi(saved.mode, 0, Mode.size() - 1) as Mode
	_sfx = Sfx.new()
	add_child(_sfx)
	_build_ui()
	_new_game()


func _exit_tree() -> void:
	_cancel_ai()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var k := event as InputEventKey
	if k.keycode == KEY_Z and (k.ctrl_pressed or k.meta_pressed):
		_undo()
	elif k.keycode == KEY_N:
		_new_game()
	elif k.keycode == KEY_H:
		_hint()
	elif k.keycode == KEY_ESCAPE and selected != NONE:
		selected = NONE
		_refresh()


# ---------------------------------------------------------------- 对局流程

func _new_game() -> void:
	_cancel_ai()
	board = Rules.initial_board()
	turn = Rules.RED
	last_move = []
	quiet_plies = 0
	outcome = 0
	move_log = ["对局开始，红方先行。"]
	_ai_info.text = ""
	history.clear()
	selected = NONE
	busy = false
	_board_view.hint_move = []
	_board_view.board = board
	_board_view.sync_pieces()
	_overlay.visible = false
	_refresh()
	_maybe_ai_turn()


func _human_side() -> int:
	return Rules.BLACK if mode == Mode.VS_AI_BLACK else Rules.RED


func _is_human_turn() -> bool:
	return mode == Mode.PVP or turn == _human_side()


func _on_cell_clicked(cell: Vector2i) -> void:
	if busy or outcome != 0 or not _is_human_turn():
		return
	var v := board[Rules.idx(cell)]
	if v == turn:
		selected = NONE if cell == selected else cell
		_sfx.play("select")
		_refresh()
	elif selected != NONE and Rules.is_valid_move(board, selected, cell):
		_play_move(selected, cell)
	elif selected != NONE or v != Rules.EMPTY:
		_invalid()


func _invalid() -> void:
	_sfx.play("invalid")
	_board_view.shake(4.0)


func _play_move(from: Vector2i, to: Vector2i) -> void:
	var token := _ai_token
	history.append(_snapshot())
	var res := Rules.apply_move(board, from, to)
	var caps: PackedInt32Array = res.captured
	var mover := turn
	selected = NONE
	busy = true
	_board_view.hint_move = []
	_refresh()
	_sfx.play("move")
	await _board_view.animate_move(from, to, caps)
	if token != _ai_token:
		return  # 动画期间开了新局 / 悔棋
	if not caps.is_empty():
		_sfx.play_capture(caps.size())

	board = res.board
	quiet_plies = 0 if not caps.is_empty() else quiet_plies + 1
	last_move = [from, to]
	turn = Rules.opponent(mover)
	var line := "%s %s → %s" % [Rules.side_name(mover), Rules.notation(from), Rules.notation(to)]
	if not caps.is_empty():
		line += "  吃 %d 子" % caps.size()
	move_log.append(line)
	outcome = Rules.outcome(board, turn, quiet_plies)
	busy = false
	if outcome != 0:
		move_log.append(_outcome_text())
		_refresh()
		_show_outcome()
	else:
		_refresh()
		_maybe_ai_turn()


func _undo() -> void:
	if (busy and not _thinking) or not _can_undo():
		return
	_cancel_ai()
	var snap: Dictionary = history.pop_back()
	if mode != Mode.PVP:
		# 人机模式一次退回到玩家上一次走棋前
		while snap.turn != _human_side() and not history.is_empty():
			snap = history.pop_back()
	board = snap.board
	turn = snap.turn
	last_move = snap.last_move
	quiet_plies = snap.quiet
	move_log = snap.log
	outcome = 0
	selected = NONE
	busy = false
	_board_view.hint_move = []
	_board_view.board = board
	_board_view.sync_pieces()
	_overlay.visible = false
	_sfx.play("undo")
	_refresh()
	_maybe_ai_turn()


func _can_undo() -> bool:
	if mode == Mode.PVP:
		return not history.is_empty()
	for snap in history:
		if snap.turn == _human_side():
			return true
	return false


func _snapshot() -> Dictionary:
	return {
		"board": board.duplicate(), "turn": turn, "last_move": last_move.duplicate(),
		"quiet": quiet_plies, "log": move_log.duplicate(),
	}


# ---------------------------------------------------------------- 电脑

func _maybe_ai_turn() -> void:
	if outcome == 0 and not _is_human_turn():
		_start_search("play", ai_config())


func _hint() -> void:
	if busy or outcome != 0 or not _is_human_turn():
		return
	var cfg := AIConfig.preset(AIConfig.DEFAULT_PRESET)
	cfg.noise = 0
	_start_search("hint", cfg)


func _start_search(purpose: String, cfg: Dictionary) -> void:
	_cancel_ai()
	_ai_purpose = purpose
	_thinking = true
	busy = true
	_ai.abort = false
	_refresh()
	_ai_thread = Thread.new()
	_ai_thread.start(_search_worker.bind(board.duplicate(), turn, cfg.duplicate(), _ai_token))


func _search_worker(b: PackedInt32Array, side: int, cfg: Dictionary, token: int) -> void:
	var t0 := Time.get_ticks_msec()
	var mv := _ai.choose_move(b, side, cfg)
	var stats := {"depth": _ai.reached_depth, "nodes": _ai.nodes, "ms": Time.get_ticks_msec() - t0}
	_on_search_done.call_deferred(mv, token, stats)


func _on_search_done(mv: Vector2i, token: int, stats: Dictionary) -> void:
	if token != _ai_token:
		return  # 已被取消，线程已在 _cancel_ai 中回收
	_ai_thread.wait_to_finish()
	_ai_thread = null
	if _ai_purpose == "hint":
		_thinking = false
		busy = false
		if mv.x >= 0:
			selected = Rules.cell(mv.x)
			_board_view.hint_move = [Rules.cell(mv.x), Rules.cell(mv.y)]
			_sfx.play("select")
		_refresh()
		return
	_ai_info.text = _stats_text(stats)
	var elapsed: int = stats.ms
	if elapsed < MIN_AI_THINK_MS:
		await get_tree().create_timer((MIN_AI_THINK_MS - elapsed) / 1000.0).timeout
		if token != _ai_token:
			return
	_thinking = false
	_play_move(Rules.cell(mv.x), Rules.cell(mv.y))


## 当前生效的电脑配置
func ai_config() -> Dictionary:
	return custom_cfg.duplicate() if ai_preset == AIConfig.CUSTOM else AIConfig.preset(ai_preset)


func _stats_text(stats: Dictionary) -> String:
	if stats.depth == 0:
		return "电脑上一步：随手一步"
	var nodes: int = stats.nodes
	var n := "%.1f 万" % (nodes / 10000.0) if nodes >= 10000 else str(nodes)
	return "电脑上一步：算到 %d 步 · %s 个局面 · %.1f 秒" % [stats.depth, n, stats.ms / 1000.0]


func _select_ai(id: int) -> void:
	if id == CUSTOM_ITEM_ID:
		_settings_panel.open(custom_cfg)
		return
	ai_preset = id
	_save_settings()
	_refresh()


func _on_ai_applied(cfg: Dictionary) -> void:
	custom_cfg = cfg
	ai_preset = AIConfig.CUSTOM
	_save_settings()
	_refresh()


func _save_settings() -> void:
	AIConfig.save_settings(ai_preset, custom_cfg, mode)


func _cancel_ai() -> void:
	_ai_token += 1
	if _ai_thread != null:
		_ai.abort = true
		_ai_thread.wait_to_finish()
		_ai_thread = null
	_thinking = false


# ---------------------------------------------------------------- 界面刷新

func _refresh() -> void:
	var human := _is_human_turn() and not busy and outcome == 0
	_board_view.board = board
	_board_view.selected = selected
	_board_view.targets = Rules.moves_from(board, selected) if selected != NONE else ([] as Array[Vector2i])
	_board_view.last_move = last_move
	_board_view.active_side = turn if human else 0
	_board_view.refresh()

	for side: int in [Rules.RED, Rules.BLACK]:
		var alive := Rules.count(board, side)
		var active := turn == side and outcome == 0
		var badge: Dictionary = _badges[side]
		var color := RED_600 if side == Rules.RED else STONE_800
		badge.panel.add_theme_stylebox_override("panel", _sb(color if active else Color(1, 1, 1, 0.7), 18))
		badge.name.add_theme_color_override("font_color", Color.WHITE if active else STONE_400)
		badge.count.text = "×%d" % alive
		badge.count.add_theme_color_override("font_color", Color(1, 1, 1, 0.8) if active else STONE_400)
		badge.dot.add_theme_color_override("font_color", Color.WHITE if active else color.lerp(Color.WHITE, 0.5))
		var card: Dictionary = _score_cards[side]
		card.body.text = "存活 %d · 阵亡 %d" % [alive, 9 - alive]
		var tint := Color("#fef2f2") if side == Rules.RED else STONE_100
		var edge := Color("#fca5a5") if side == Rules.RED else STONE_400
		card.panel.add_theme_stylebox_override("panel",
			_sb(tint, 12, edge, 1) if active else _sb(STONE_50, 12, STONE_100, 1))

	if outcome != 0:
		_status.text = _outcome_text()
	elif _thinking:
		_status.text = "正在计算提示…" if _ai_purpose == "hint" else "电脑思考中…"
	elif mode == Mode.PVP:
		_status.text = "轮到%s走棋" % Rules.side_name(turn)
	else:
		_status.text = "轮到你走棋（%s）" % Rules.side_name(turn)

	_undo_btn.disabled = not _can_undo() or (busy and not _thinking)
	_hint_btn.disabled = busy or outcome != 0 or not _is_human_turn()
	var vs_ai := mode != Mode.PVP
	_ai_opt.disabled = not vs_ai
	_ai_tune_btn.disabled = not vs_ai
	_ai_opt.select(_ai_opt.get_item_index(CUSTOM_ITEM_ID if ai_preset == AIConfig.CUSTOM else ai_preset))
	if not vs_ai:
		_ai_desc.text = "双人对战，不使用电脑。"
	elif ai_preset == AIConfig.CUSTOM:
		var c := custom_cfg
		_ai_desc.text = "自定义：深度 %d · %s · 攻 %d / 守 %d" % [c.depth, AIConfig.format_value("time_ms", c.time_ms), c.attack, c.defense]
	else:
		_ai_desc.text = AIConfig.PRESETS[ai_preset].desc
	_ai_info.visible = vs_ai and _ai_info.text != ""

	var lines := PackedStringArray()
	for i in range(move_log.size() - 1, -1, -1):
		var text := move_log[i]
		if text.contains("吃"):
			text = "[color=#%s]%s[/color]" % [ORANGE_600.to_html(false), text]
		if i == move_log.size() - 1:
			text = "[b]%s[/b]" % text
		lines.append(text)
	_log.text = "\n".join(lines)


func _outcome_text() -> String:
	if outcome == Rules.DRAW:
		return "连续 %d 步无吃子，和棋。" % Rules.NO_CAPTURE_DRAW
	var who := Rules.side_name(outcome)
	if Rules.count(board, Rules.opponent(outcome)) >= Rules.MIN_PIECES:
		return "%s无子可走，%s胜！" % [Rules.side_name(Rules.opponent(outcome)), who]
	return "%s胜！" % who


func _show_outcome() -> void:
	var red_alive := Rules.count(board, Rules.RED)
	var black_alive := Rules.count(board, Rules.BLACK)
	if outcome == Rules.DRAW:
		_overlay_icon.text = "＝"
		_overlay_title.text = "和 棋"
		_overlay_icon.add_theme_color_override("font_color", STONE_500)
		_overlay_title.add_theme_color_override("font_color", STONE_700)
	else:
		var color := RED_600 if outcome == Rules.RED else STONE_800
		var title := "%s 胜利!" % Rules.side_name(outcome)
		if mode != Mode.PVP:
			title = "你赢了!" if outcome == _human_side() else "电脑获胜"
		_overlay_icon.text = "★"
		_overlay_title.text = title
		_overlay_icon.add_theme_color_override("font_color", color)
		_overlay_title.add_theme_color_override("font_color", color)
	_overlay_score.text = "红 %d : %d 黑" % [red_alive, black_alive]
	_overlay.visible = true
	_confetti.emitting = outcome != Rules.DRAW
	_confetti.restart()
	if outcome != Rules.DRAW:
		_sfx.play("win")
	_overlay_panel.scale = Vector2.ONE * 0.6
	_overlay_panel.modulate.a = 0.0
	await get_tree().process_frame
	_overlay_panel.pivot_offset = _overlay_panel.size / 2.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_overlay_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_overlay_panel, "modulate:a", 1.0, 0.2)


# ---------------------------------------------------------------- 界面搭建

func _build_ui() -> void:
	theme = _build_theme()

	var bg := TextureRect.new()
	var grad := GradientTexture2D.new()
	grad.gradient = Explosion._gradient([STONE_200, Color("#fffbeb"), Color("#d6d3d1")])
	grad.fill_from = Vector2.ZERO
	grad.fill_to = Vector2.ONE
	bg.texture = grad
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	center.add_child(row)

	# 左：回合徽章 + 棋盘
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 16)
	row.add_child(left)
	var badges := HBoxContainer.new()
	left.add_child(badges)
	badges.add_child(_make_badge(Rules.BLACK))
	var gap := Control.new()
	gap.size_flags_horizontal = SIZE_EXPAND_FILL
	badges.add_child(gap)
	badges.add_child(_make_badge(Rules.RED))

	_board_view = BoardView.new()
	_board_view.cell_clicked.connect(_on_cell_clicked)
	left.add_child(_board_view)
	_build_overlay()

	# 右：侧栏
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(330, 0)
	var panel_sb := _sb(Color(1, 1, 1, 0.92), 18, STONE_200, 1)
	panel_sb.shadow_color = Color(0, 0, 0, 0.12)
	panel_sb.shadow_size = 18
	panel_sb.shadow_offset = Vector2(0, 8)
	panel_sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", panel_sb)
	row.add_child(panel)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 14)
	panel.add_child(side)

	var title := _label("坦克大战", 32, STONE_800)
	title.add_theme_font_override("font", _serif)
	side.add_child(title)
	side.add_child(_label("传统民间策略棋 · 夹击吃子", 12, STONE_500))

	# 对局设置
	var settings := GridContainer.new()
	settings.columns = 2
	settings.add_theme_constant_override("h_separation", 10)
	settings.add_theme_constant_override("v_separation", 8)
	side.add_child(settings)
	settings.add_child(_label("模式", 13, STONE_500))
	var mode_opt := OptionButton.new()
	for text in ["人机对战 · 我执红（先手）", "人机对战 · 我执黑（后手）", "双人对战"]:
		mode_opt.add_item(text)
	mode_opt.selected = mode
	mode_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	mode_opt.item_selected.connect(func(i: int) -> void:
		mode = i as Mode
		_save_settings()
		_new_game())
	settings.add_child(mode_opt)
	settings.add_child(_label("电脑", 13, STONE_500))
	var ai_row := HBoxContainer.new()
	ai_row.add_theme_constant_override("separation", 6)
	ai_row.size_flags_horizontal = SIZE_EXPAND_FILL
	settings.add_child(ai_row)
	_ai_opt = OptionButton.new()
	for i in AIConfig.PRESETS.size():
		if i == 3:
			_ai_opt.add_separator("性格")
		_ai_opt.add_item(AIConfig.PRESETS[i].name, i)
	_ai_opt.add_separator()
	_ai_opt.add_item("自定义…", CUSTOM_ITEM_ID)
	_ai_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	_ai_opt.item_selected.connect(func(index: int) -> void: _select_ai(_ai_opt.get_item_id(index)))
	ai_row.add_child(_ai_opt)
	_ai_tune_btn = Button.new()
	_ai_tune_btn.text = "调整"
	_ai_tune_btn.tooltip_text = "以当前电脑为起点，自定义各项参数"
	_ai_tune_btn.pressed.connect(func() -> void: _settings_panel.open(ai_config()))
	ai_row.add_child(_ai_tune_btn)
	settings.add_child(Control.new())
	_ai_desc = _label("", 12, STONE_500)
	_ai_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ai_desc.size_flags_horizontal = SIZE_EXPAND_FILL
	settings.add_child(_ai_desc)

	# 战况
	var scores := HBoxContainer.new()
	scores.add_theme_constant_override("separation", 8)
	side.add_child(scores)
	for s: int in [Rules.RED, Rules.BLACK]:
		scores.add_child(_make_score_card(s))

	_status = _label("", 15, STONE_800)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(_status)
	_ai_info = _label("", 11, STONE_400)
	_ai_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(_ai_info)

	# 按钮
	var buttons := GridContainer.new()
	buttons.columns = 2
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 8)
	side.add_child(buttons)
	var new_btn := _button("新游戏", _new_game)
	new_btn.add_theme_stylebox_override("normal", _sb(STONE_800, 8))
	new_btn.add_theme_stylebox_override("hover", _sb(STONE_700, 8))
	new_btn.add_theme_stylebox_override("pressed", _sb(STONE_700, 8))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		new_btn.add_theme_color_override(state, STONE_100)
	buttons.add_child(new_btn)
	_undo_btn = _button("悔棋", _undo)
	buttons.add_child(_undo_btn)
	_hint_btn = _button("提示", _hint)
	buttons.add_child(_hint_btn)
	buttons.add_child(_button("规则", func() -> void: _rules.visible = not _rules.visible))
	_sound_btn = _button("音效：开", _toggle_sound)
	buttons.add_child(_sound_btn)
	buttons.add_child(_button("全屏", _toggle_fullscreen))

	_rules = RichTextLabel.new()
	_rules.bbcode_enabled = true
	_rules.fit_content = true
	_rules.text = RULES_TEXT
	_rules.add_theme_font_size_override("normal_font_size", 13)
	_rules.add_theme_font_size_override("bold_font_size", 13)
	_rules.add_theme_color_override("default_color", STONE_700)
	_rules.visible = false
	var rules_box := PanelContainer.new()
	var rules_sb := _sb(Color("#fffbeb"), 10, Color("#fde68a"), 1)
	rules_sb.set_content_margin_all(12)
	rules_box.add_theme_stylebox_override("panel", rules_sb)
	rules_box.add_child(_rules)
	_rules.visibility_changed.connect(func() -> void: rules_box.visible = _rules.visible)
	rules_box.visible = false
	side.add_child(rules_box)

	# 对战记录
	var log_box := PanelContainer.new()
	log_box.size_flags_vertical = SIZE_EXPAND_FILL
	log_box.custom_minimum_size = Vector2(0, 180)
	var log_sb := _sb(STONE_50, 10, STONE_100, 1)
	log_sb.set_content_margin_all(14)
	log_box.add_theme_stylebox_override("panel", log_sb)
	side.add_child(log_box)
	var log_col := VBoxContainer.new()
	log_box.add_child(log_col)
	log_col.add_child(_label("对战记录", 12, STONE_400))
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.size_flags_vertical = SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 13)
	_log.add_theme_font_size_override("bold_font_size", 13)
	_log.add_theme_color_override("default_color", STONE_700)
	_log.add_theme_constant_override("line_separation", 5)
	log_col.add_child(_log)

	_settings_panel = AISettingsPanel.new(_sb)
	_settings_panel.applied.connect(_on_ai_applied)
	# 取消时把下拉框恢复成实际生效的选项
	_settings_panel.visibility_changed.connect(func() -> void:
		if not _settings_panel.visible:
			_refresh())
	add_child(_settings_panel)


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(PRESET_FULL_RECT)
	_overlay.mouse_filter = MOUSE_FILTER_STOP
	_overlay.z_index = 50  # 盖过坦克与爆炸层
	_overlay.visible = false
	_board_view.add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.3)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.add_child(dim)

	_confetti = CPUParticles2D.new()
	var bar := Image.create(10, 5, false, Image.FORMAT_RGBA8)
	bar.fill(Color.WHITE)
	_confetti.texture = ImageTexture.create_from_image(bar)
	_confetti.position = Vector2(310, -10)
	_confetti.amount = 70
	_confetti.lifetime = 3.2
	_confetti.one_shot = true
	_confetti.explosiveness = 0.15
	_confetti.emitting = false
	_confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_confetti.emission_rect_extents = Vector2(300, 4)
	_confetti.direction = Vector2.DOWN
	_confetti.spread = 25.0
	_confetti.initial_velocity_min = 60.0
	_confetti.initial_velocity_max = 160.0
	_confetti.gravity = Vector2(0, 140)
	_confetti.angular_velocity_min = -400.0
	_confetti.angular_velocity_max = 400.0
	_confetti.scale_amount_min = 0.8
	_confetti.scale_amount_max = 1.4
	var palette := Explosion._gradient([Color("#ef4444"), Color("#f97316"), Color("#fbbf24"), Color("#22c55e"), Color("#3b82f6"), Color("#a855f7"), Color("#ec4899")])
	palette.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	_confetti.color_initial_ramp = palette
	_overlay.add_child(_confetti)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.add_child(center)
	_overlay_panel = PanelContainer.new()
	var sb := _sb(Color(1, 1, 1, 0.96), 20)
	sb.set_content_margin_all(32)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 24
	_overlay_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_overlay_panel)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	_overlay_panel.add_child(col)
	_overlay_icon = _label("★", 56, RED_600)
	_overlay_title = _label("", 32, STONE_800)
	_overlay_title.add_theme_font_override("font", _serif)
	_overlay_score = _label("", 14, STONE_400)
	for l in [_overlay_icon, _overlay_title, _overlay_score]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
	var again := _button("再来一局", _new_game)
	again.custom_minimum_size = Vector2(160, 44)
	again.add_theme_stylebox_override("normal", _sb(STONE_800, 22))
	again.add_theme_stylebox_override("hover", _sb(STONE_700, 22))
	again.add_theme_stylebox_override("pressed", _sb(STONE_700, 22))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		again.add_theme_color_override(state, Color.WHITE)
	col.add_child(again)
	var review := _button("查看棋盘", func() -> void: _overlay.visible = false)
	review.flat = true
	col.add_child(review)


func _make_badge(side: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var dot := _label("●", 12, Color.WHITE)
	var side_lbl := _label(Rules.side_name(side), 16, Color.WHITE)
	side_lbl.add_theme_font_override("font", _serif)
	var count := _label("", 13, Color.WHITE)
	for l in [dot, side_lbl, count]:
		row.add_child(l)
	_badges[side] = {"panel": panel, "dot": dot, "name": side_lbl, "count": count}
	return panel


func _make_score_card(side: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	panel.add_child(col)
	var head := _label("● " + Rules.side_name(side), 14, RED_600 if side == Rules.RED else STONE_800)
	var body := _label("", 12, STONE_500)
	col.add_child(head)
	col.add_child(body)
	_score_cards[side] = {"panel": panel, "body": body}
	return panel


func _toggle_sound() -> void:
	_sfx.muted = not _sfx.muted
	_sound_btn.text = "音效：关" if _sfx.muted else "音效：开"
	_sfx.play("select")


func _toggle_fullscreen() -> void:
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _build_theme() -> Theme:
	var th := Theme.new()
	var sans := SystemFont.new()
	# 注意："PingFang SC" 在 Godot 里会解析到 PingFang HK 字面，缺"稳"等简体字，所以冬青黑体 GB 放最前
	sans.font_names = PackedStringArray(["Hiragino Sans GB", "PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", "Source Han Sans SC", "sans-serif"])
	th.default_font = sans
	th.default_font_size = 15
	_serif = SystemFont.new()
	_serif.font_names = PackedStringArray(["Songti SC", "STSong", "SimSun", "Noto Serif CJK SC", "Source Han Serif SC", "serif"])
	_serif.font_weight = 700

	for t in ["Button", "OptionButton"]:
		th.set_stylebox("normal", t, _sb(STONE_100, 8))
		th.set_stylebox("hover", t, _sb(STONE_200, 8))
		th.set_stylebox("pressed", t, _sb(Color("#d6d3d1"), 8))
		th.set_stylebox("focus", t, StyleBoxEmpty.new())
		th.set_stylebox("disabled", t, _sb(Color(STONE_100, 0.6), 8))
		th.set_color("font_color", t, STONE_700)
		th.set_color("font_hover_color", t, STONE_800)
		th.set_color("font_pressed_color", t, STONE_800)
		th.set_color("font_focus_color", t, STONE_700)
		th.set_color("font_disabled_color", t, Color("#d6d3d1"))
	th.set_stylebox("panel", "PopupMenu", _sb(Color.WHITE, 8, STONE_200, 1))
	th.set_color("font_color", "PopupMenu", STONE_700)
	th.set_color("font_hover_color", "PopupMenu", STONE_800)
	th.set_stylebox("hover", "PopupMenu", _sb(AMBER_100, 6))
	th.set_color("font_color", "Label", STONE_800)
	return th


func _sb(bg: Color, radius := 8, border := Color.TRANSPARENT, width := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.anti_aliasing = true
	return sb


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.pressed.connect(on_press)
	return b
