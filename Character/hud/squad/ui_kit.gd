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
## WHAT A MODULE ADDED, and nothing else ever.
##
## The five colours above each had one job and there was no sixth, which is why
## a stat bar could show what a robot is worth and not which part of that was
## bought. White is the sixth: the base of a bar is BRIGHT and the part a module
## put there continues it in this. It is deliberately NOT used for anything that
## merely "stands out" — the moment it means two things it means neither, which
## is exactly what went wrong when a cluster round's bomblets were drawn the
## same way as an armour plate's hull.
const UPGRADE := Color(1, 1, 1)
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
## `fit` scales the art down to the box instead of drawing it at its own size
## and cropping: how a larger icon (the outline cuts, "m" and "l") is shown
## small. Without it a 64px icon in a 40px box loses its edges.
static func icon(tex: Texture2D, tint: Color, size: Vector2, fit: bool = false) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = size
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if fit else TextureRect.STRETCH_KEEP_CENTERED
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


## ONE STAT, AS A BAR: its name, a track, and the figure.
##
## `base` is what the frame or the gun is worth on its own and `total` is what it
## is worth now; the difference is drawn in UPGRADE, so a bar answers "how much
## of this did I buy" without a second line of text saying so. Pass them equal
## for anything that cannot be modified and it draws as one solid bar.
##
## `scale` is the top of the bar and is FIXED PER STAT by the caller, never per
## row — a bar that rescales to its own value cannot be compared with the one
## beside it, which is the entire point of drawing bars instead of printing
## numbers.
##
## The fills are anchored rather than sized: a row's width is not known until the
## container lays out, and a fraction survives that where a pixel count does not.
static func stat_bar(text: String, base: float, total: float, scale: float,
		reading: String, label_width: float = 64.0, value_width: float = 72.0) -> Control:
	var row := hbox(6)
	var key := label(text, DIM, SMALL)
	key.custom_minimum_size.x = label_width
	row.add_child(key)

	var track := Panel.new()
	track.custom_minimum_size = Vector2(0, 9)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.add_theme_stylebox_override("panel", box(FAINT, Color(0, 0, 0, 0), 1, 0.0))
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var safe: float = maxf(scale, 0.001)
	var filled := ColorRect.new()
	filled.color = BRIGHT
	filled.set_anchors_preset(Control.PRESET_FULL_RECT, true)
	filled.anchor_right = clampf(base / safe, 0.0, 1.0)
	filled.offset_right = 0.0
	filled.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(filled)
	if total > base:
		var added := ColorRect.new()
		added.color = UPGRADE
		added.set_anchors_preset(Control.PRESET_FULL_RECT, true)
		added.anchor_left = clampf(base / safe, 0.0, 1.0)
		added.anchor_right = clampf(total / safe, 0.0, 1.0)
		added.offset_left = 0.0
		added.offset_right = 0.0
		added.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(added)
	row.add_child(track)

	var val := label(reading, UPGRADE if total > base else BRIGHT, SMALL, true)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.custom_minimum_size.x = value_width
	row.add_child(val)
	return row


## A section's open/shut mark: a small triangle, pointing down while it is open
## and right while it is shut. Drawn, because the font has no arrows. Only a
## picture: the row it sits in takes the click.
static func caret(open: bool, color: Color = BRIGHT) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(14, 14)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var m := c.size * 0.5
		var tip := PackedVector2Array([m + Vector2(-5, -3), m + Vector2(5, -3), m + Vector2(0, 3)]) if open \
			else PackedVector2Array([m + Vector2(-3, -5), m + Vector2(3, 0), m + Vector2(-3, 5)])
		c.draw_colored_polygon(tip, color))
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


## Who can carry an item, in words — and ONLY when that is a restriction.
##
## It used to append the frame list ("· ROVER/WALKER FRAMES"), which the mount
## class now says better: see mount_class(). And "YOU AND SQUADMATES" is the
## ordinary case, so printing it spends a line of the card saying that nothing
## is unusual. Empty means no restriction worth a word.
static func carriers(item: ItemDefinition) -> String:
	if item.fits_player() and item.fits_ai():
		return ""
	if item.fits_player():
		return "YOU ONLY"
	if item.fits_ai():
		return "SQUADMATES ONLY"
	return "NOBODY YET"


const KIND_NAMES := {
	ItemDefinition.Kind.WEAPON: "WEAPON",
	ItemDefinition.Kind.EQUIPMENT: "EQUIPMENT",
	ItemDefinition.Kind.MODULE: "MODULE",
}


## WEAPON, or WEAPON · TURRET.
##
## "Turret" is the word for a gun that is mounted and aims on its own rather
## than being carried — the Autocannon, the Heavy MG, the Rover's launcher. It
## was going unsaid, and the card instead described the consequence ("ROVER
## FRAMES ONLY"), which tells you where it fits but not what kind of thing it
## is. Those are different questions and the player asks the second one first.
##
## Read off the FRAMES, not off a flag on the item: ChassisDefinition.turret is
## already the one place that knows, and squad_page's fit rules go through it
## too. A weapon counts as a turret gun when every frame it is made for is a
## turret frame — a gun a soldier could also hold is not one.
static func kind_text(item: ItemDefinition) -> String:
	var base: String = KIND_NAMES.get(item.kind, "")
	if item.kind != ItemDefinition.Kind.WEAPON:
		return base
	var mount := mount_class(item)
	return "%s · %s" % [base, mount] if mount != "" else base


## WHAT KIND OF MOUNT A WEAPON IS FOR: TURRET, INFANTRY, or ARTICULATED ARM.
##
## The card used to list the FRAMES instead — "ROVER/WALKER FRAMES ONLY" — which
## answers the wrong question. Where a gun fits is a consequence; what KIND of
## weapon it is, is the fact. And the frame list stops being true the moment a
## new frame is added: a big walker with an arm and two turrets would want the
## Heavy MG on its turrets and the mortar on its arm, and no list of today's
## frame names describes that. The mount class does, and does not change.
##
## Read off the frames rather than a new flag on the item, because
## ChassisDefinition already knows: `turret` is the one place that decides a
## turret takes only what was made for it, and `weapon_replaces_built_in` is the
## Reclaimer's boom. A weapon with no whitelist goes in a pair of hands.
static func mount_class(item: ItemDefinition) -> String:
	if item.kind != ItemDefinition.Kind.WEAPON:
		return ""
	if item.chassis_whitelist.is_empty():
		return "INFANTRY"
	var cat := _catalogue()
	if cat == null:
		return ""
	var all_turret := true
	var all_arm := true
	for frame_id in item.chassis_whitelist:
		var frame := cat.chassis_def(frame_id)
		if frame == null:
			return ""
		if not frame.turret:
			all_turret = false
		if not frame.weapon_replaces_built_in:
			all_arm = false
	if all_turret:
		return "TURRET"
	if all_arm:
		return "ARTICULATED ARM"
	# Made for particular frames that are not all of one kind. Saying nothing is
	# better than naming them: the fit rules still refuse it, with a reason.
	return ""


## The catalogue, found the way the rest of the HUD finds it. Null outside a
## campaign, which is why kind_text falls back rather than failing.
static func _catalogue() -> ItemCatalogue:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var campaign := tree.get_first_node_in_group("campaign")
	if campaign == null or not ("catalogue" in campaign):
		return null
	return campaign.catalogue as ItemCatalogue
