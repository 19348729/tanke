class_name AIConfig
extends RefCounted
## 电脑对手的可调参数与预设。配置统一用 Dictionary 表示，便于存盘、交给搜索线程。
##
## 强度类：depth / time_ms / quiesce —— 看多远、想多久。
## 性格类：noise / blunder / attack / defense / position / mobility —— 怎么权衡、多稳定。

const SAVE_PATH := "user://settings.cfg"
const CUSTOM := -1  ## 预设下标：-1 表示自定义

## 参数表：设置面板据此生成滑块，sanitize 据此补默认值和夹取范围
const FIELDS := [
	{"key": "depth", "label": "搜索深度", "group": "强度", "min": 1, "max": 8, "step": 1,
		"tip": "最多往后算几步（双方各走一次算两步）。思考时间不够时会提前停下。"},
	{"key": "time_ms", "label": "思考时间", "group": "强度", "min": 200, "max": 5000, "step": 100,
		"tip": "每步最多思考多久，到时用已算完的最深一层结果。"},
	{"key": "quiesce", "label": "吃子延伸", "group": "强度", "min": 0, "max": 6, "step": 1,
		"tip": "算到底后继续跟进连续吃子交换的步数，避免只看半步、被反夹。"},
	{"key": "noise", "label": "随机性", "group": "性格", "min": 0, "max": 200, "step": 5,
		"tip": "给每步评分加随机扰动：越大越不按套路走，也越容易走软。"},
	{"key": "blunder", "label": "失误率", "group": "性格", "min": 0, "max": 50, "step": 1,
		"tip": "每步有这个概率直接随手走一步。"},
	{"key": "attack", "label": "进攻欲望", "group": "性格", "min": 50, "max": 200, "step": 5,
		"tip": "吃掉对方一子的价值。高于防守时愿意以子换子、主动找夹击。"},
	{"key": "defense", "label": "防守意识", "group": "性格", "min": 50, "max": 200, "step": 5,
		"tip": "保住己方一子的价值。高于进攻时避免兑子、优先自保。"},
	{"key": "position", "label": "占位意识", "group": "性格", "min": 0, "max": 15, "step": 1,
		"tip": "站在主网格交叉点（横竖斜八向可走）的加分。"},
	{"key": "mobility", "label": "机动意识", "group": "性格", "min": 0, "max": 5, "step": 1,
		"tip": "棋子周围每个空位的加分，越高越爱保持走位空间。"},
]

const PRESETS := [
	{"name": "简单", "desc": "只看一步，偶尔走错，适合熟悉规则。",
		"cfg": {"depth": 1, "time_ms": 300, "quiesce": 2, "noise": 90, "blunder": 10,
			"attack": 100, "defense": 100, "position": 4, "mobility": 1}},
	{"name": "普通", "desc": "会算吃子交换，攻守均衡。",
		"cfg": {"depth": 3, "time_ms": 900, "quiesce": 4, "noise": 8, "blunder": 0,
			"attack": 100, "defense": 100, "position": 4, "mobility": 1}},
	{"name": "困难", "desc": "算得最深，不留情面，每步约 2 秒。",
		"cfg": {"depth": 8, "time_ms": 2200, "quiesce": 4, "noise": 0, "blunder": 0,
			"attack": 100, "defense": 100, "position": 4, "mobility": 1}},
	{"name": "激进型", "desc": "舍得兑子，到处找夹击机会。",
		"cfg": {"depth": 3, "time_ms": 1200, "quiesce": 4, "noise": 12, "blunder": 0,
			"attack": 145, "defense": 80, "position": 2, "mobility": 1}},
	{"name": "稳健型", "desc": "先保自己，占住要点再慢慢磨。",
		"cfg": {"depth": 3, "time_ms": 1200, "quiesce": 5, "noise": 4, "blunder": 0,
			"attack": 90, "defense": 145, "position": 7, "mobility": 2}},
	{"name": "新手型", "desc": "想到哪走到哪，经常送子。",
		"cfg": {"depth": 1, "time_ms": 200, "quiesce": 0, "noise": 160, "blunder": 30,
			"attack": 100, "defense": 100, "position": 0, "mobility": 0}},
]
const DEFAULT_PRESET := 1


static func preset(i: int) -> Dictionary:
	return (PRESETS[clampi(i, 0, PRESETS.size() - 1)].cfg as Dictionary).duplicate()


static func field(key: String) -> Dictionary:
	for f: Dictionary in FIELDS:
		if f.key == key:
			return f
	return {}


## 补齐缺失项、夹到合法范围、取整（用于读档和外部输入）
static func sanitize(cfg: Dictionary) -> Dictionary:
	var base := preset(DEFAULT_PRESET)
	var out := {}
	for f: Dictionary in FIELDS:
		var v: Variant = cfg.get(f.key, base[f.key])
		if not (v is int or v is float):
			v = base[f.key]
		out[f.key] = clampi(int(round(float(v))), f.min, f.max)
	return out


static func format_value(key: String, v: int) -> String:
	match key:
		"time_ms":
			return "%.1f 秒" % (v / 1000.0)
		"blunder":
			return "%d%%" % v
		"depth", "quiesce":
			return "%d 步" % v
	return str(v)


## 粗估这个时间内大约能算到几步（实测约 2.5 万局面/秒），用于提醒"深度设了但算不到"
static func reachable_depth(time_ms: int) -> int:
	if time_ms < 400:
		return 2
	if time_ms < 1500:
		return 3
	if time_ms < 3500:
		return 4
	return 5


## 配置的风险提示，空字符串表示没问题
static func warnings(cfg: Dictionary) -> String:
	var notes := PackedStringArray()
	var reach := reachable_depth(cfg.time_ms)
	if cfg.depth > reach:
		notes.append("思考 %s 大约只能算到 %d 步，深度 %d 多半用不满。" % [format_value("time_ms", cfg.time_ms), reach, cfg.depth])
	if cfg.defense < 70 and cfg.attack > cfg.defense * 1.6:
		notes.append("防守过低，电脑会频繁送子换子。")
	if cfg.position * 4 + cfg.mobility * 8 > mini(cfg.attack, cfg.defense):
		notes.append("占位/机动权重接近一子价值，电脑可能为了站位丢子。")
	return "\n".join(notes)


## 读档：{"preset": 下标或 CUSTOM, "custom": 自定义配置, "mode": 对战模式}
static func load_settings() -> Dictionary:
	var out := {"preset": DEFAULT_PRESET, "custom": preset(DEFAULT_PRESET), "mode": 0}
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK:
		return out
	out.preset = clampi(int(file.get_value("ai", "preset", DEFAULT_PRESET)), CUSTOM, PRESETS.size() - 1)
	var custom: Variant = file.get_value("ai", "custom", {})
	out.custom = sanitize(custom if custom is Dictionary else {})
	out.mode = int(file.get_value("game", "mode", 0))
	return out


static func save_settings(preset_index: int, custom: Dictionary, mode: int) -> void:
	var file := ConfigFile.new()
	file.set_value("ai", "preset", preset_index)
	file.set_value("ai", "custom", custom)
	file.set_value("game", "mode", mode)
	file.save(SAVE_PATH)
