extends Control

# ─────────────────────────────────────────────
# LAB RESULTS — what the laboratory found, on screen when the plan finishes.
#
# One block per matchup: its name, its setup, and the verdict — who won how
# often, how close it was, how long it took, and how well each side shot. The
# full tables (per chassis, every run) are in lab_report.md; OPEN REPORT goes
# straight to it.
#
# Same frame as the options and tutorials screens, opened into Master's overlay.
# ─────────────────────────────────────────────

signal run_again
signal open_report
signal quit_game

const COL_DIM    := HUDPalette.DIM
const COL_BRIGHT := HUDPalette.BRIGHT
const COL_WARN   := HUDPalette.WARN
const COL_BODY   := Color(0.95, 1.0, 0.97)
const COL_HOVER  := Color(0.86, 1.0, 0.88)
const PANEL_WIDTH := 980.0

## Set before adding: the plan's title and Lab.summary() rows.
var title: String = "Laboratory"
var rows: Array = []
var report_path: String = ""
var hover_sound: AudioStreamPlayer
var confirm_sound: AudioStreamPlayer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_WIDTH * 0.5 - 24.0
	panel.offset_right = PANEL_WIDTH * 0.5 + 24.0
	panel.offset_top = 14.0
	panel.offset_bottom = -12.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.02, 0.03, 0.03, 0.95)
	box.border_color = Color(COL_DIM, 0.3)
	box.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)

	var column := VBoxContainer.new()
	column.anchor_left = 0.5
	column.anchor_right = 0.5
	column.anchor_bottom = 1.0
	column.offset_left = -PANEL_WIDTH * 0.5
	column.offset_right = PANEL_WIDTH * 0.5
	column.offset_top = 24.0
	column.offset_bottom = -20.0
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	column.add_child(_label("LABORATORY — %s" % title.to_upper(), COL_BRIGHT, 34, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_label("WIN RATES ARE THE ALLIES' SIDE.  WINNER HP = HOW MUCH THE WINNING SIDE HAD LEFT.",
		COL_DIM, 15, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_rule())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 2)
	scroll.add_child(page)

	if rows.is_empty():
		page.add_child(_label("NO FIGHTS RAN", COL_DIM, 20, HORIZONTAL_ALIGNMENT_CENTER))
	for i in rows.size():
		var s: Dictionary = rows[i]
		if i > 0:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 10)
			page.add_child(gap)
		page.add_child(_label(str(s["label"]).to_upper(), COL_BRIGHT, 22, HORIZONTAL_ALIGNMENT_LEFT))
		page.add_child(_label(str(s["setup"]).to_upper(), COL_DIM, 15, HORIZONTAL_ALIGNMENT_LEFT))
		var runs: int = int(s["runs"])
		var decided: int = int(s["decided"])
		var verdict := "ALLIES WIN %s   HOSTILES WIN %s   DRAWS %d   OF %d" % [
			_pct(s["ally_wins"], runs), _pct(s["hostile_wins"], runs), int(s["draws"]), runs]
		var detail := "AVG %ds   WINNER KEPT %s OF ITS ROBOTS, %s HP   ACCURACY %s / %s   DAMAGE %d / %d" % [
			int(float(s["time"]) / maxf(1, runs)),
			_pct(s["winner_left"], decided) if decided > 0 else "-",
			_pct(s["winner_hp"], decided) if decided > 0 else "-",
			_pct(s["a_hits"], s["a_shots"]), _pct(s["h_hits"], s["h_shots"]), int(s["a_dmg"]), int(s["h_dmg"])]
		page.add_child(_label(verdict, COL_WARN if int(s["ally_wins"]) * 2 < runs else COL_BODY, 19, HORIZONTAL_ALIGNMENT_LEFT))
		page.add_child(_label(detail, COL_BODY, 16, HORIZONTAL_ALIGNMENT_LEFT))

	column.add_child(_rule())
	if report_path != "":
		var where := _label("FULL TABLES: %s" % report_path, COL_DIM, 13, HORIZONTAL_ALIGNMENT_CENTER)
		where.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		column.add_child(where)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 60)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(footer)
	footer.add_child(_button("RUN AGAIN", run_again))
	footer.add_child(_button("OPEN REPORT", open_report))
	footer.add_child(_button("QUIT", quit_game))


func _button(text: String, sig: Signal) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(200, 0)
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", COL_BRIGHT)
	b.add_theme_color_override("font_hover_color", COL_HOVER)
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	b.add_theme_color_override("font_focus_color", COL_BRIGHT)
	b.mouse_entered.connect(func() -> void:
		if hover_sound != null and hover_sound.is_inside_tree():
			hover_sound.play())
	b.pressed.connect(func() -> void:
		if confirm_sound != null and confirm_sound.is_inside_tree():
			confirm_sound.play()
		sig.emit())
	return b


func _label(text: String, col: Color, size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(COL_DIM, 0.35)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _pct(a: float, b: float) -> String:
	if b <= 0.0:
		return "-"
	return "%d%%" % int(round(100.0 * a / b))
