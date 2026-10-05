class_name UiTheme
extends RefCounted
## Тёмная тема редактора и общие цвета. Шрифт — системный (кириллица без искажений).

const BG := Color(0.11, 0.115, 0.13)
const PANEL := Color(0.15, 0.155, 0.175)
const PANEL2 := Color(0.19, 0.195, 0.22)
const TEXT := Color(0.9, 0.91, 0.93)
const DIM := Color(0.62, 0.64, 0.68)
const ACCENT := Color(0.95, 0.76, 0.38)
const ERROR := Color(0.95, 0.4, 0.38)
const WARN := Color(0.98, 0.78, 0.35)
const OK := Color(0.5, 0.85, 0.55)
const SILVER := Color(0.82, 0.88, 1.0)
const HEIGHT_COLORS := {"low": Color(0.35, 0.6, 0.95), "mid": Color(0.95, 0.72, 0.3), "high": Color(0.45, 0.85, 0.45),
	"shop": Color(0.8, 0.55, 0.95), "": Color(0.7, 0.7, 0.7)}

static var _font: Font
static var _bold: Font


static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI", "Arial", "Noto Sans", "DejaVu Sans"])
		_font = f
	return _font


static func bold() -> Font:
	if _bold == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI Semibold", "Segoe UI", "Arial"])
		f.font_weight = 600
		_bold = f
	return _bold


static func make() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 15
	var panel := _box(PANEL, 0)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	for c: String in ["Label", "Button", "CheckBox", "CheckButton", "OptionButton", "MenuButton", "LineEdit", "ItemList", "Tree", "TabBar", "PopupMenu", "TextEdit", "SpinBox"]:
		t.set_color("font_color", c, TEXT)
	t.set_color("font_color", "TabContainer", TEXT)
	var btn := _box(PANEL2, 4)
	btn.content_margin_left = 10
	btn.content_margin_right = 10
	btn.content_margin_top = 5
	btn.content_margin_bottom = 5
	t.set_stylebox("normal", "Button", btn)
	var hov := btn.duplicate()
	hov.bg_color = PANEL2.lightened(0.12)
	t.set_stylebox("hover", "Button", hov)
	var prs := btn.duplicate()
	prs.bg_color = ACCENT.darkened(0.45)
	t.set_stylebox("pressed", "Button", prs)
	t.set_stylebox("hover_pressed", "Button", prs)
	var dis := btn.duplicate()
	dis.bg_color = PANEL.darkened(0.1)
	t.set_stylebox("disabled", "Button", dis)
	t.set_color("font_disabled_color", "Button", DIM.darkened(0.3))
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	var edit := _box(Color(0.09, 0.095, 0.11), 3)
	edit.content_margin_left = 6
	edit.content_margin_right = 6
	edit.content_margin_top = 4
	edit.content_margin_bottom = 4
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("normal", "TextEdit", edit)
	t.set_stylebox("panel", "ItemList", _box(Color(0.09, 0.095, 0.11), 3))
	t.set_stylebox("panel", "Tree", _box(Color(0.09, 0.095, 0.11), 3))
	t.set_stylebox("panel", "TabContainer", _box(PANEL, 0))
	t.set_stylebox("panel", "PopupMenu", _box(PANEL2, 4))
	t.set_color("font_hover_color", "PopupMenu", ACCENT)
	t.set_stylebox("panel", "TooltipPanel", _box(Color(0.06, 0.06, 0.07, 0.96), 4))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 14)
	return t


static func _box(col: Color, r: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.corner_radius_top_left = r
	s.corner_radius_top_right = r
	s.corner_radius_bottom_left = r
	s.corner_radius_bottom_right = r
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


static func label(text: String, size: int = 15, col: Color = TEXT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func header(text: String) -> Label:
	var l := label(text, 16, ACCENT)
	l.add_theme_font_override("font", bold())
	return l


static func button(text: String, tip: String = "", cb: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	if cb.is_valid():
		b.pressed.connect(cb)
	return b
