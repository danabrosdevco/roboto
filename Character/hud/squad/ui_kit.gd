extends RefCounted

# ─────────────────────────────────────────────
# UI KIT — how the squad manager looks, in one place: what each colour means,
# the fonts, and the few pieces every page is built from.
#
# EACH COLOUR HAS ONE JOB.
#   BRIGHT green  what you can act on, what is selected, what is ready
#   DIM green     labels, secondary facts, anything empty
#   MONEY amber   resources and prices — and nothing else
#   COMPUTE blue  compute, the other currency
#   PROBLEM red   something is wrong: no weapon, destroyed, can't afford
# The old screen used amber for money, warnings and buttons at once, so
# nothing on it said "do this next".
#
# TYPE. DS-Digital throughout, the game's font: bold for names and headings,
# upright regular for everything else (the italic cut the HUD uses is harder
# to read in a block).
# ─────────────────────────────────────────────

const BRIGHT := HUDPalette.BRIGHT
const DIM := HUDPalette.DIM
const MONEY := HUDPalette.WARN
const COMPUTE := HUDPalette.SIGNAL
const PROBLEM := HUDPalette.CRIT
## Card and panel fill, border at rest, and the border of an empty slot.
const PANEL := Color(0.055, 0.085, 0.075, 0.96)
const LINE := Color(0.20, 0.33, 0.25)
const FAINT := Color(0.16, 0.25, 0.19)

const FONT_BOLD := preload("res://2d_assets/fonts/DS-Digital/DS-DIGIB.TTF")
const FONT_BODY := preload("res://2d_assets/fonts/DS-Digital/DS-DIGI.TTF")

const HEADING := 16
const BODY := 15
const SMALL := 13


static func label(text: String, color: Color = DIM, size: int = BODY, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT_BOLD if bold else FONT_BODY)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Centred in a row, so a big word and a small one beside it (HANGAR, then
	# 4 SEATS) share a middle instead of a top edge.
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## A paragraph: wraps to its container instead of widening it.
static func text_block(text: String, color: Color = DIM, size: int = BODY) -> Label:
	var l := label(text, color, size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Section heading: "DEPLOYING", "IN STORES · WEAPON".
static func heading(text: String) -> Label:
	var l := label(text, DIM, HEADING, true)
	return l


static func box(border: Color = LINE, fill: Color = PANEL, width: int = 1, pad: float = 8.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(pad)
	return sb


## A clickable block. Children should ignore the mouse so the card gets it;
## `on_click` runs on a left click, and hover lights the border.
static func card(border: Color, on_click: Callable, hover: Callable, pad: float = 8.0) -> PanelContainer:
	var c := PanelContainer.new()
	var rest := box(border, PANEL, 2 if border == BRIGHT else 1, pad)
	var lit := box(BRIGHT if border != PROBLEM else PROBLEM, PANEL, 2 if border == BRIGHT else 1, pad)
	c.add_theme_stylebox_override("panel", rest)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	c.mouse_entered.connect(func():
		c.add_theme_stylebox_override("panel", lit)
		hover.call())
	c.mouse_exited.connect(func(): c.add_theme_stylebox_override("panel", rest))
	c.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			c.accept_event()
			on_click.call())
	return c


## A baked icon at its own size, tinted. Null textures give an empty box of
## the same size, so a layout never jumps when an icon is missing.
static func icon(tex: Texture2D, tint: Color, size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = size
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.modulate = tint
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## A flat text button. The text carries the colour; hover brightens it.
static func button(text: String, color: Color = BRIGHT, size: int = BODY, bold: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", FONT_BOLD if bold else FONT_BODY)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", color.lightened(0.35))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", color)
	b.add_theme_color_override("font_disabled_color", Color(color, 0.45))
	b.add_theme_stylebox_override("normal", box(Color(color, 0.55), Color(0, 0, 0, 0), 1, 6.0))
	b.add_theme_stylebox_override("hover", box(color, Color(color, 0.08), 1, 6.0))
	b.add_theme_stylebox_override("pressed", box(color, Color(color, 0.16), 1, 6.0))
	b.add_theme_stylebox_override("disabled", box(Color(color, 0.25), Color(0, 0, 0, 0), 1, 6.0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


## Seats: one square per point of supply, filled while taken.
static func seats(used: int, cap: int) -> Control:
	var c := Control.new()
	var n := maxi(cap, used)
	c.custom_minimum_size = Vector2(n * 14, 14)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var top := (c.size.y - 10.0) * 0.5
		for i in n:
			var r := Rect2(i * 14 + 1, top, 10, 10)
			if i < used:
				c.draw_rect(r, PROBLEM if i >= cap else BRIGHT)
			else:
				c.draw_rect(r.grow(-0.5), DIM, false, 1.0))
	return c


## Rank as chevrons: none for a new robot, one per rank after that. A word
## here ("RECRUIT") read as the button for buying robots.
static func chevrons(rank: int) -> Control:
	var c := Control.new()
	var n := clampi(rank, 0, 5)
	c.custom_minimum_size = Vector2(n * 9 + 2, 14)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		for i in n:
			var x := i * 9.0 + 1.0
			c.draw_polyline(PackedVector2Array([Vector2(x, 11), Vector2(x + 3.5, 5), Vector2(x + 7, 11)]),
				BRIGHT, 1.5, true))
	return c


static func spacer(width: float = 0.0, height: float = 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Pushes whatever follows it in a row to the far end.
static func fill() -> Control:
	var c := spacer()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func hbox(separation: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


static func vbox(separation: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


# remove_child BEFORE queue_free: a second rebuild in the same frame would
# otherwise find the old rows still parented and add a fresh set beside them.
static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## The frame's first word, upper case: "SOLDIER", "CHASER".
static func frame_word(frame: ChassisDefinition) -> String:
	if frame == null or frame.display_name == "":
		return "ROBOT"
	return frame.display_name.split(" ", false)[0].to_upper()


## What an item does, for the UI. Gear's use count is said in words ("2 PER
## MISSION"): effect_summary's bare "x2" sat beside the stores count "X2" and
## read as the same number.
static func effect_text(item: ItemDefinition) -> String:
	var s := item.effect_summary()
	if item.kind == ItemDefinition.Kind.EQUIPMENT and item.quantity > 0:
		var tail := "x%d" % item.quantity
		if s.ends_with(tail):
			s = s.substr(0, s.length() - tail.length()).trim_suffix(", ")
		s += (", " if s != "" else "") + "%d PER MISSION" % item.quantity
	return s.to_upper()


## Who can carry an item, in words.
static func carriers(item: ItemDefinition) -> String:
	var who := ""
	if item.fits_player() and item.fits_ai():
		who = "YOU AND SQUADMATES"
	elif item.fits_player():
		who = "YOU ONLY"
	elif item.fits_ai():
		who = "SQUADMATES ONLY"
	else:
		who = "NOBODY YET"
	if not item.chassis_whitelist.is_empty():
		var frames := PackedStringArray()
		for id in item.chassis_whitelist:
			frames.append(String(id).to_upper())
		# A turret gun: "SQUADMATES ONLY · ROVER FRAMES" says the same thing twice.
		if not item.fits_player():
			return "%s FRAMES ONLY" % "/".join(frames)
		who += " · %s FRAMES" % "/".join(frames)
	return who


const KIND_NAMES := {
	ItemDefinition.Kind.WEAPON: "WEAPON",
	ItemDefinition.Kind.EQUIPMENT: "GEAR",
	ItemDefinition.Kind.MODULE: "MODULE",
}
