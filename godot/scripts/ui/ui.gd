class_name UI
extends CanvasLayer
## HUD mínima (GDD 10) e menus. Construída em código; navegável por teclado,
## mouse e controle (sistema de foco do Godot).

const FONT_R := preload("res://assets/fonts/Lato-Regular.ttf")
const FONT_B := preload("res://assets/fonts/Lato-Bold.ttf")
const FONT_K := preload("res://assets/fonts/Lato-Black.ttf")
const FONT_I := preload("res://assets/fonts/Lato-Italic.ttf")

var root: Control
var hud: Control
var menu_layer: Control
var theme_obj: Theme
var integrity_box: HBoxContainer
var tide_box: VBoxContainer
var echo_label: Label
var obj_panel: PanelContainer
var obj_label: Label
var obj_region: Label
var prompt_panel: PanelContainer
var prompt_key: Label
var prompt_text: Label
var prompt_bar: ProgressBar
var subtitle: PanelContainer
var subtitle_text: Label
var toast: PanelContainer
var toast_title: Label
var toast_text: Label
var labels_layer: Control
var fade: ColorRect
var title_card: VBoxContainer
var popup: PanelContainer
var subtitle_t = 0.0
var toast_t = 0.0
var title_t = 0.0
var menu_open = false
var subtitles_on = true

func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	build_theme(1.0, false)
	_build_hud()
	menu_layer = Control.new()
	menu_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(menu_layer)
	fade = ColorRect.new()
	fade.color = Color(Palette.ABISMO, 0.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)

# --- tema ---------------------------------------------------------------------------

func _box(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, radius: int = 8, pad: int = 14) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s

func build_theme(scale: float, contrast: bool) -> void:
	theme_obj = Theme.new()
	theme_obj.default_font = FONT_R
	theme_obj.default_font_size = int(19 * scale)
	var panel_bg = Color("#050d12") if contrast else Color(0.05, 0.12, 0.16, 0.82)
	var border = Palette.CERAMICA if contrast else Color(0, 0, 0, 0)
	theme_obj.set_stylebox("panel", "PanelContainer", _box(panel_bg, border, 2 if contrast else 0))
	theme_obj.set_color("font_color", "Label", Palette.CERAMICA)
	theme_obj.set_font("font", "Button", FONT_B)
	theme_obj.set_font_size("font_size", "Button", int(20 * scale))
	theme_obj.set_stylebox("normal", "Button", _box(Color(0.16, 0.49, 0.51, 0.22), Color(0.91, 0.85, 0.67, 0.18), 1, 8, 18))
	theme_obj.set_stylebox("hover", "Button", _box(Color(0.49, 0.96, 0.86, 0.18), Palette.RESSONANCIA, 2, 8, 18))
	theme_obj.set_stylebox("focus", "Button", _box(Color(0.49, 0.96, 0.86, 0.22), Palette.RESSONANCIA, 3, 8, 18))
	theme_obj.set_stylebox("pressed", "Button", _box(Palette.RESSONANCIA, Palette.RESSONANCIA, 2, 8, 18))
	theme_obj.set_stylebox("disabled", "Button", _box(Color(0.1, 0.16, 0.2, 0.6), Color(0, 0, 0, 0), 0, 8, 18))
	theme_obj.set_color("font_color", "Button", Palette.CERAMICA)
	theme_obj.set_color("font_hover_color", "Button", Color.WHITE)
	theme_obj.set_color("font_focus_color", "Button", Color.WHITE)
	theme_obj.set_color("font_pressed_color", "Button", Palette.ABISMO)
	theme_obj.set_color("font_disabled_color", "Button", Color(0.91, 0.85, 0.67, 0.4))
	theme_obj.set_stylebox("background", "ProgressBar", _box(Color(0.91, 0.85, 0.67, 0.15), Color(0, 0, 0, 0), 0, 3, 0))
	theme_obj.set_stylebox("fill", "ProgressBar", _box(Palette.RESSONANCIA, Color(0, 0, 0, 0), 0, 3, 0))
	theme_obj.set_stylebox("slider", "HSlider", _box(Color(0.91, 0.85, 0.67, 0.2), Color(0, 0, 0, 0), 0, 3, 2))
	theme_obj.set_stylebox("grabber_area", "HSlider", _box(Palette.RESSONANCIA, Color(0, 0, 0, 0), 0, 3, 2))
	theme_obj.set_stylebox("grabber_area_highlight", "HSlider", _box(Palette.RESSONANCIA, Color(0, 0, 0, 0), 0, 3, 2))
	theme_obj.set_font("font", "OptionButton", FONT_B)
	root.theme = theme_obj

func apply_options(o: Dictionary) -> void:
	build_theme(o["text_scale"], o["contrast"])
	subtitles_on = o["subtitles"]

func _label(text: String, size: int = 19, font: Font = null, color: Color = Palette.CERAMICA) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_color_override("font_color", color)
	return l

func _panel() -> PanelContainer:
	var p = PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

# --- HUD --------------------------------------------------------------------------------

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.visible = false
	root.add_child(hud)
	labels_layer = Control.new()
	labels_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	labels_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(labels_layer)
	# integridade
	var ip = _panel()
	ip.position = Vector2(16, 16)
	integrity_box = HBoxContainer.new()
	integrity_box.add_theme_constant_override("separation", 10)
	integrity_box.add_child(_label(I18n.t("hud.iris"), 14, FONT_K, Palette.RESSONANCIA))
	ip.add_child(integrity_box)
	hud.add_child(ip)
	# maré
	var tp = _panel()
	tp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tp.position = Vector2(-16, 16)
	tp.offset_right = -16
	tide_box = VBoxContainer.new()
	tide_box.add_theme_constant_override("separation", 4)
	tp.add_child(tide_box)
	hud.add_child(tp)
	echo_label = _label("", 15, FONT_B, Color(0.91, 0.85, 0.67, 0.7))
	echo_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	echo_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	echo_label.offset_right = -20
	echo_label.offset_top = 120
	echo_label.name = "Echo"
	hud.add_child(echo_label)
	# objetivo
	obj_panel = _panel()
	obj_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	obj_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	obj_panel.offset_left = 16
	obj_panel.offset_bottom = -16
	var ov = VBoxContainer.new()
	ov.add_child(_label(I18n.t("hud.objective"), 13, FONT_K, Palette.COBRE))
	obj_region = _label("", 13, FONT_R, Color(0.91, 0.85, 0.67, 0.6))
	ov.add_child(obj_region)
	obj_label = _label("", 18, FONT_B)
	obj_label.custom_minimum_size.x = 240
	obj_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ov.add_child(obj_label)
	obj_panel.add_child(ov)
	hud.add_child(obj_panel)
	# prompt
	prompt_panel = _panel()
	prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt_panel.offset_bottom = -16
	var pv = VBoxContainer.new()
	var ph = HBoxContainer.new()
	ph.add_theme_constant_override("separation", 12)
	ph.alignment = BoxContainer.ALIGNMENT_CENTER
	var keybox = PanelContainer.new()
	keybox.add_theme_stylebox_override("panel", _box(Palette.CERAMICA, Color(0, 0, 0, 0), 0, 5, 8))
	prompt_key = _label("E", 17, FONT_K, Palette.ABISMO)
	keybox.add_child(prompt_key)
	ph.add_child(keybox)
	prompt_text = _label("", 18, FONT_K)
	prompt_text.uppercase = true
	ph.add_child(prompt_text)
	pv.add_child(ph)
	prompt_bar = ProgressBar.new()
	prompt_bar.show_percentage = false
	prompt_bar.custom_minimum_size = Vector2(220, 5)
	pv.add_child(prompt_bar)
	prompt_panel.add_child(pv)
	prompt_panel.visible = false
	hud.add_child(prompt_panel)
	# legenda
	subtitle = _panel()
	subtitle.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	subtitle.grow_horizontal = Control.GROW_DIRECTION_BOTH
	subtitle.grow_vertical = Control.GROW_DIRECTION_BEGIN
	subtitle.offset_bottom = -88
	var sh = HBoxContainer.new()
	sh.add_child(_label("Lume", 18, FONT_K, Palette.RESSONANCIA))
	subtitle_text = _label("", 18)
	subtitle_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_text.custom_minimum_size.x = 520
	sh.add_child(subtitle_text)
	subtitle.add_child(sh)
	subtitle.visible = false
	hud.add_child(subtitle)
	# toast (eco, memória)
	toast = _panel()
	toast.add_theme_stylebox_override("panel", _box(Color(0.075, 0.17, 0.23, 0.95), Palette.RESSONANCIA, 2, 10, 22))
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.offset_top = 110
	var tv = VBoxContainer.new()
	toast_title = _label("", 17, FONT_K, Palette.RESSONANCIA)
	toast_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(toast_title)
	toast_text = _label("", 18, FONT_I)
	toast_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_text.custom_minimum_size.x = 560
	toast_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(toast_text)
	toast.add_child(tv)
	toast.visible = false
	hud.add_child(toast)
	# título de região
	title_card = VBoxContainer.new()
	title_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title_card.offset_top = 90
	var t1 = _label("", 64, FONT_K)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t2 = _label("", 22, FONT_I, Palette.COBRE)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_card.add_child(t1)
	title_card.add_child(t2)
	title_card.visible = false
	root.add_child(title_card)

func show_hud(on: bool) -> void:
	hud.visible = on

func set_integrity(n: int, maxn: int) -> void:
	while integrity_box.get_child_count() - 1 < maxn:
		var dot = Panel.new()
		dot.custom_minimum_size = Vector2(20, 20)
		integrity_box.add_child(dot)
	while integrity_box.get_child_count() - 1 > maxn:
		integrity_box.get_child(integrity_box.get_child_count() - 1).free()
	for i in maxn:
		var dot = integrity_box.get_child(i + 1) as Panel
		var on = i < n
		var st = _box(Palette.RESSONANCIA if on else Color(0, 0, 0, 0), Palette.SAL if not on else Palette.RESSONANCIA, 0 if on else 2, 10, 0)
		dot.add_theme_stylebox_override("panel", st)

## sectors: [{name, high, moving, progress, cooldown}]
func set_tides(sectors: Array) -> void:
	while tide_box.get_child_count() < sectors.size():
		var row = VBoxContainer.new()
		var h = HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var icon = _label("", 22, FONT_K)
		icon.name = "Icon"
		var name = _label("", 15, FONT_K)
		name.name = "Name"
		var state = _label("", 15, FONT_K)
		state.name = "State"
		h.add_child(icon)
		h.add_child(name)
		h.add_child(state)
		var bar = ProgressBar.new()
		bar.name = "Bar"
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(180, 4)
		row.add_child(h)
		row.add_child(bar)
		tide_box.add_child(row)
	while tide_box.get_child_count() > sectors.size():
		tide_box.get_child(tide_box.get_child_count() - 1).free()
	for i in sectors.size():
		var s: Dictionary = sectors[i]
		var row = tide_box.get_child(i)
		var col = Palette.RESSONANCIA if s["high"] else Palette.COBRE
		var icon = row.find_child("Icon", true, false) as Label
		icon.text = "≋▲" if s["high"] else "≋▼"
		icon.add_theme_color_override("font_color", col)
		var nm = row.find_child("Name", true, false) as Label
		nm.text = "%s %s" % [I18n.t("hud.tide"), I18n.t("sector." + s["name"])] if sectors.size() > 1 else I18n.t("hud.tide")
		nm.add_theme_color_override("font_color", col)
		var st = row.find_child("State", true, false) as Label
		st.text = I18n.t(("hud.rising" if s["high"] else "hud.falling") if s["moving"] else ("hud.high" if s["high"] else "hud.low"))
		st.add_theme_color_override("font_color", col)
		var bar = row.find_child("Bar", true, false) as ProgressBar
		bar.visible = s["moving"] or s["cooldown"] > 0.0
		bar.value = (s["progress"] if s["moving"] else 1.0 - s["cooldown"]) * 100.0

func set_echoes(n: int, total: int) -> void:
	echo_label.text = I18n.t("hud.echoes", {"n": n, "total": total})
	echo_label.offset_top = 24 + tide_box.get_child_count() * 34 + 12

func set_objective(region_name: String, text: String) -> void:
	obj_region.text = region_name
	if obj_label.text != text:
		obj_label.text = text
		obj_panel.modulate.a = 0.0
		create_tween().tween_property(obj_panel, "modulate:a", 1.0, 0.6)

func set_prompt(p: Dictionary) -> void:
	if p.is_empty():
		prompt_panel.visible = false
		return
	prompt_panel.visible = true
	prompt_key.text = I18n.key_name(p.get("action", "interact")) if p.get("action", "interact") != "touch" else "·"
	prompt_text.text = p["text"]
	var dis: bool = p.get("disabled", false)
	prompt_text.add_theme_color_override("font_color", Color(0.91, 0.85, 0.67, 0.55) if dis else Palette.CERAMICA)
	prompt_bar.visible = p.has("hold") and p["hold"] > 0.0
	prompt_bar.value = p.get("hold", 0.0) * 100.0

func say(text: String, seconds: float = 4.5, force: bool = false) -> void:
	if not subtitles_on and not force:
		return
	subtitle_text.text = text
	subtitle.visible = true
	subtitle_t = seconds

func show_toast(title: String, text: String, seconds: float = 8.0) -> void:
	toast_title.text = title
	toast_text.text = text
	toast.visible = true
	toast_t = seconds

func show_title(t1: String, t2: String, seconds: float = 4.0) -> void:
	(title_card.get_child(0) as Label).text = t1
	(title_card.get_child(1) as Label).text = t2
	title_card.visible = true
	title_card.modulate.a = 0.0
	create_tween().tween_property(title_card, "modulate:a", 1.0, 0.8)
	title_t = seconds

## labels: [{pos: Vector2, text, kind}]
func set_labels(labels: Array) -> void:
	while labels_layer.get_child_count() < labels.size():
		var p = PanelContainer.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l = _label("", 15, FONT_B)
		p.add_child(l)
		labels_layer.add_child(p)
	for i in labels_layer.get_child_count():
		var p = labels_layer.get_child(i) as PanelContainer
		if i >= labels.size():
			p.visible = false
			continue
		var d: Dictionary = labels[i]
		p.visible = true
		var col: Color = {"energy": Palette.RESSONANCIA, "interact": Palette.COBRE, "threat": Palette.SAL, "muted": Color(0.91, 0.85, 0.67, 0.5)}.get(d["kind"], Palette.RESSONANCIA)
		p.add_theme_stylebox_override("panel", _box(Color(0.04, 0.09, 0.13, 0.88), col, 2, 14, 10))
		(p.get_child(0) as Label).text = d["text"]
		p.reset_size()
		p.position = d["pos"] - Vector2(p.size.x / 2, p.size.y)
		p.modulate.a = d.get("alpha", 1.0)

func update_ui(dt: float) -> void:
	if subtitle_t > 0.0:
		subtitle_t -= dt
		if subtitle_t <= 0.0:
			subtitle.visible = false
	if toast_t > 0.0:
		toast_t -= dt
		if toast_t <= 0.0:
			toast.visible = false
	if title_t > 0.0:
		title_t -= dt
		if title_t <= 0.0:
			create_tween().tween_property(title_card, "modulate:a", 0.0, 0.8)

func fade_to(alpha: float, seconds: float = 0.4) -> void:
	var tw = create_tween()
	tw.tween_property(fade, "color:a", alpha, seconds)
	await tw.finished

# --- menus -------------------------------------------------------------------------------

func close_menu() -> void:
	for c in menu_layer.get_children():
		c.queue_free()
	menu_open = false

## Abre um painel de menu. items: [[texto, callable, opções?]]
func open_menu(title: String, items: Array, opts: Dictionary = {}) -> VBoxContainer:
	close_menu()
	menu_open = true
	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.09, 0.13, opts.get("bg_alpha", 0.72))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(bg)
	var wrap = MarginContainer.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m: int = opts.get("margin", 0)
	wrap.add_theme_constant_override("margin_left", m)
	menu_layer.add_child(wrap)
	var center = CenterContainer.new() if not opts.get("left", false) else VBoxContainer.new()
	if opts.get("left", false):
		(center as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(center)
	var panel = PanelContainer.new()
	if not opts.get("bare", false):
		panel.add_theme_stylebox_override("panel", _box(Color(0.075, 0.17, 0.23, 0.97), Palette.RESSONANCIA, 0, 12, 30))
	else:
		panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.custom_minimum_size.x = opts.get("width", 560)
	if opts.get("left", false):
		panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	center.add_child(panel)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = mini(opts.get("height", 0), 620) if opts.get("height", 0) > 0 else 0
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if opts.get("height", 0) > 0:
		scroll.add_child(v)
		panel.add_child(scroll)
	else:
		panel.add_child(v)
	if opts.has("eyebrow"):
		v.add_child(_label(opts["eyebrow"], 14, FONT_K, Palette.RESSONANCIA))
	if title != "":
		v.add_child(_label(title, opts.get("title_size", 34), FONT_K))
	if opts.has("subtitle"):
		var st = _label(opts["subtitle"], 18, FONT_I, Palette.COBRE)
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(st)
	if opts.has("body"):
		var b = _label(opts["body"], 18)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(b)
	var first: Button = null
	for it in items:
		if it is Control:
			v.add_child(it)
			continue
		var btn = Button.new()
		btn.text = it[0]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_ALL
		if it.size() > 2 and it[2].get("disabled", false):
			btn.disabled = true
		var cb: Callable = it[1]
		btn.pressed.connect(func(): Sfx.play("ui"); cb.call())
		btn.focus_entered.connect(func(): Sfx.play("ui_select", -8.0))
		v.add_child(btn)
		if first == null and not btn.disabled:
			first = btn
	if first:
		first.call_deferred("grab_focus")
	return v

func row(label_text: String, control: Control, help: String = "") -> Control:
	var v = VBoxContainer.new()
	var h = HBoxContainer.new()
	var l = _label(label_text, 18)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 180)
	h.add_child(control)
	v.add_child(h)
	if help != "":
		var hl = _label(help, 14, FONT_R, Color(0.91, 0.85, 0.67, 0.6))
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(hl)
	return v
