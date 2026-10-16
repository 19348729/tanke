class_name AISettingsPanel
extends Control
## "自定义电脑"弹层：可从任一预设载入，再用滑块微调；应用后通过 applied 信号交回 main.gd。
## 滑块由 AIConfig.FIELDS 自动生成，新增参数只需改参数表。

signal applied(cfg: Dictionary)

var _cfg := {}
var _sliders := {}
var _values := {}
var _warning: Label
var _panel: PanelContainer
var _style: Callable  ## main.gd 的 _sb，用来保持同一套视觉


func _init(style_box: Callable) -> void:
	_style = style_box


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	z_index = 100
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.08, 0.06, 0.45)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(560, 0)
	var sb: StyleBoxFlat = _style.call(Color.WHITE, 18)
	sb.set_content_margin_all(26)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 28
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)
	col.add_child(_text("自定义电脑", 22, Color("#292524")))
	col.add_child(_text("从预设载入后再微调，下一步棋起生效，设置会自动保存。", 12, Color("#78716c")))

	var presets := HFlowContainer.new()
	presets.add_theme_constant_override("h_separation", 6)
	presets.add_theme_constant_override("v_separation", 6)
	col.add_child(presets)
	for i in AIConfig.PRESETS.size():
		var p: Dictionary = AIConfig.PRESETS[i]
		var b := Button.new()
		b.text = p.name
		b.tooltip_text = p.desc
		b.custom_minimum_size = Vector2(76, 32)
		b.pressed.connect(func() -> void: _load(AIConfig.preset(i)))
		presets.add_child(b)

	var group := ""
	var grid: GridContainer
	for f: Dictionary in AIConfig.FIELDS:
		if f.group != group:
			group = f.group
			var head := _text(group, 13, Color("#b45309"))
			col.add_child(head)
			grid = GridContainer.new()
			grid.columns = 3
			grid.add_theme_constant_override("h_separation", 14)
			grid.add_theme_constant_override("v_separation", 10)
			col.add_child(grid)
		var name_lbl := _text(f.label, 14, Color("#44403c"))
		name_lbl.custom_minimum_size = Vector2(72, 0)
		name_lbl.tooltip_text = f.tip
		name_lbl.mouse_filter = MOUSE_FILTER_PASS
		var slider := HSlider.new()
		slider.min_value = f.min
		slider.max_value = f.max
		slider.step = f.step
		slider.tooltip_text = f.tip
		slider.size_flags_horizontal = SIZE_EXPAND_FILL
		slider.size_flags_vertical = SIZE_SHRINK_CENTER
		slider.value_changed.connect(_on_slider.bind(f.key))
		var value_lbl := _text("", 14, Color("#292524"))
		value_lbl.custom_minimum_size = Vector2(64, 0)
		value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(name_lbl)
		grid.add_child(slider)
		grid.add_child(value_lbl)
		_sliders[f.key] = slider
		_values[f.key] = value_lbl

	_warning = _text("", 12, Color("#c2410c"))
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.custom_minimum_size = Vector2(0, 34)
	col.add_child(_warning)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	col.add_child(buttons)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(96, 38)
	cancel.pressed.connect(close)
	buttons.add_child(cancel)
	var ok := Button.new()
	ok.text = "应用"
	ok.custom_minimum_size = Vector2(96, 38)
	ok.add_theme_stylebox_override("normal", _style.call(Color("#292524"), 8))
	ok.add_theme_stylebox_override("hover", _style.call(Color("#44403c"), 8))
	ok.add_theme_stylebox_override("pressed", _style.call(Color("#44403c"), 8))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		ok.add_theme_color_override(state, Color.WHITE)
	ok.pressed.connect(func() -> void:
		applied.emit(_cfg.duplicate())
		close())
	buttons.add_child(ok)


func open(cfg: Dictionary) -> void:
	_load(cfg)
	visible = true
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.15)


func close() -> void:
	visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _load(cfg: Dictionary) -> void:
	_cfg = AIConfig.sanitize(cfg)
	for key: String in _sliders:
		_sliders[key].set_value_no_signal(_cfg[key])
		_values[key].text = AIConfig.format_value(key, _cfg[key])
	_warning.text = AIConfig.warnings(_cfg)


func _on_slider(v: float, key: String) -> void:
	_cfg[key] = int(v)
	_values[key].text = AIConfig.format_value(key, int(v))
	_warning.text = AIConfig.warnings(_cfg)


func _text(s: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
