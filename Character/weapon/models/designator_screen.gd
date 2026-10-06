extends SubViewport

# BY PATH, NOT class_name: a brand-new class_name is not resolvable until the
# editor rescans, and that rescan must not be run with the editor open. The
# scene references this script by path, which needs no registration.

# ─────────────────────────────────────────────
# THE DESIGNATOR'S READOUT — what the squad is carrying, on the tool.
#
# The screen is the reason the designator is a held object rather than a key.
# Everything the player needs to know is on it: which mode, how many robots can
# answer, and how far through the hold they are.
#
# WHAT IS ON IT, AND WHAT CAME OFF.
#
# It carried a line of instructions — "HOLD TO MARK · R CYCLES" — and that line
# is gone. A readout glanced at mid-firefight has room for ONE idea, and a
# control legend is not it: it is read once, on the first draw, and is noise on
# every one after. That space went to the thing that actually changes.
#
# So the middle of the screen is now most of the screen. At arm's length,
# through the CRT filter, on a plane raked thirty degrees away, the mode name is
# the only text that is reliably legible — so it gets the size, and the icon
# beside it does the work when the glance is too short to read at all.
#
# WHAT IS LEFT is four things, in the order they are needed:
#   SQUAD KIT / n of m   which dial position, so cycling has a sense of place
#   icon + NAME          what you are about to order — the whole middle
#   n CAN ANSWER         or STANDING BY while the order is held, or NONE LEFT
#   the fill bar         how far through the hold
#
# BUILT IN CODE, not laid out in a .tscn. A SubViewport's contents are read at a
# fixed pixel size and then stretched over 17.8 x 13.1 cm of raked plane — there
# is no editor view that shows what it will look like in the player's hand, so a
# .tscn layout would be guessed anyway. In code the sizes are arithmetic on one
# number.
#
# THREE THINGS ALREADY HANDLED ELSEWHERE, noted so they are not re-fixed here:
#   * The screen mesh is a PlaneMesh. A BoxMesh gives every face its own slice
#     of the UV rectangle, so a texture on one is CROPPED rather than mapped.
#   * designator_model.tscn flips the UVs on its own material
#     (uv1_scale = (-1, -1, 1)), because a plane raked back toward the player
#     reads mirrored and upside down. Nothing here compensates.
#   * player_designator.gd sets emission_operator to MULTIPLY when it wires this
#     on. Left at the default ADD, the base emission is added across the whole
#     surface and the screen renders as a solid green slab.
# ─────────────────────────────────────────────

## Pixels. 1.36 aspect, matching the screen mesh (0.178 x 0.131) exactly — a
## mismatch here stretches the font, which is the first thing that makes a
## readout look fake.
const SIZE := Vector2i(256, 188)

## THESE ARE DELIBERATELY MORE SATURATED THAN THE HUD'S OWN GREENS, and it is
## not a style choice — it is the emission.
##
## player_designator wires this viewport onto the screen material with
## emission_operator MULTIPLY and emission_energy_multiplier 3.0, which is what
## makes the readout legible in a lit room. Everything drawn here is therefore
## TRIPLED before it reaches the eye, and a channel that lands above 1.0 clips.
##
## The HUD's BRIGHT is (0.62, 0.95, 0.66): tripled that is (1.86, 2.85, 1.98),
## so all three channels clip to 1.0 and the text renders WHITE. Any pale green
## does the same — the greener it looks in a colour picker, the whiter it comes
## out here. Only a colour whose red and blue stay under about a third survives
## the multiply as green.
##
## DIM has to clear the same bar from the other side: at a green of 0.5 it
## tripled to 1.5, clipped to 1.0, and came out exactly as bright as BRIGHT — so
## the header and the page counter shouted as loudly as the mode name. Under a
## third keeps it genuinely quieter.
const COL_GROUND := Color(0.035, 0.055, 0.045, 1.0)
const COL_BRIGHT := Color(0.11, 0.98, 0.17, 1.0)
const COL_DIM := Color(0.03, 0.18, 0.05, 1.0)
const COL_WARN := Color(0.33, 0.3, 0.05, 1.0)

const _Icons := preload("res://Character/hud/icons/icons.gd")
const _Glyphs := preload("res://Character/hud/hud_glyphs.gd")

## The tool whose state is drawn. Assigned by player_designator.gd at
## initialize, because the tool owns the screen rather than the other way round.
var tool_node: Node = null

var _label: Label
var _status: Label
var _icon: TextureRect
var _bar: ColorRect
var _bar_track: ColorRect
var _page: Label
var _last_signature: String = ""


func _ready() -> void:
	size = SIZE
	# ALWAYS, not ONCE and not WHEN_VISIBLE. The content changes while the
	# player holds the trigger — the fill bar is the whole point — and
	# UPDATE_ONCE would show them a frozen bar.
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	transparent_bg = false
	disable_3d = true
	_build()


func _build() -> void:
	var pad := 12.0

	var ground := ColorRect.new()
	ground.color = COL_GROUND
	# ANCHORS AND OFFSETS, not anchors alone. set_anchors_preset leaves the
	# offsets where they were, so a fresh Control stays zero-sized and paints
	# nothing. The same trap weapon_bar and squad_hud both document.
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ground)

	# ── the header, deliberately small ──────────
	# It is orientation, not information: it says where you are on the dial and
	# then gets out of the way.
	var head := Label.new()
	# "SQUAD KIT" was right when the dial was equipment only. It carries the two
	# movement orders now as well, so the heading is the whole vocabulary rather
	# than one half of it.
	head.text = "COMMAND"
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", COL_DIM)
	head.position = Vector2(pad, 6.0)
	add_child(head)

	_page = Label.new()
	_page.add_theme_font_size_override("font_size", 13)
	_page.add_theme_color_override("font_color", COL_DIM)
	_page.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_page.position = Vector2(pad, 6.0)
	_page.size = Vector2(SIZE.x - pad * 2.0, 18.0)
	add_child(_page)

	var rule := ColorRect.new()
	rule.color = COL_DIM
	rule.position = Vector2(pad, 26.0)
	rule.size = Vector2(SIZE.x - pad * 2.0, 1.0)
	add_child(rule)

	# ── the middle, which is now most of it ─────
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.position = Vector2(pad, 38.0)
	_icon.size = Vector2(74.0, 74.0)
	_icon.modulate = COL_BRIGHT
	add_child(_icon)

	# CENTRED VERTICALLY AGAINST THE ICON. The names wrap to one, two or three
	# lines depending on the item, and a top-aligned label leaves "SMOKE"
	# floating at the icon's forehead while "DRONE CARRIER PACK" fills the block.
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", COL_BRIGHT)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector2(pad + 80.0, 34.0)
	_label.size = Vector2(SIZE.x - pad * 2.0 - 80.0, 84.0)
	add_child(_label)

	# ── the one line that is still words ────────
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", COL_DIM)
	_status.position = Vector2(pad, SIZE.y - pad - 44.0)
	_status.size = Vector2(SIZE.x - pad * 2.0, 24.0)
	add_child(_status)

	_bar_track = ColorRect.new()
	_bar_track.color = Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.28)
	_bar_track.position = Vector2(pad, SIZE.y - pad - 8.0)
	_bar_track.size = Vector2(SIZE.x - pad * 2.0, 6.0)
	add_child(_bar_track)

	_bar = ColorRect.new()
	_bar.color = COL_BRIGHT
	_bar.position = _bar_track.position
	_bar.size = Vector2(0.0, 6.0)
	add_child(_bar)


func _process(_delta: float) -> void:
	if tool_node == null or not is_instance_valid(tool_node):
		return
	# The fill moves every frame it is held, so it is written unconditionally.
	# Everything else is behind a signature compare: rebuilding the labels and
	# re-resolving an icon sixty times a second to draw the same two words is
	# waste, and resolving the icon means a texture load.
	var charge: float = float(tool_node.charge)
	_bar.size.x = _bar_track.size.x * clampf(charge, 0.0, 1.0)

	var label: String = tool_node.mode_label()
	var status: String = tool_node.mode_status()
	var signature := "%s|%s|%d|%d" % [label, status, tool_node.mode_index(),
		tool_node.mode_count()]
	if signature == _last_signature:
		return
	_last_signature = signature
	_redraw(label, status)


func _redraw(label: String, status: String) -> void:
	var empty: bool = not tool_node.has_modes()
	_label.text = label
	_label.add_theme_color_override("font_color", COL_DIM if empty else COL_BRIGHT)
	_status.text = status
	# HELD IS BRIGHT, OUT IS AMBER, everything else is quiet. "STANDING BY" is a
	# state the player is waiting on, so it has to read as live rather than as
	# the dim caption it sits in the position of.
	# BRIGHT FOR ANYTHING LIVE. "3 CAN ANSWER" and "STANDING BY" are both the
	# squad about to do something and belong with the name; only being OUT is a
	# problem, and only that gets the warning colour.
	var tone := COL_BRIGHT
	if status == "NONE LEFT":
		tone = COL_WARN
	elif status == "NOBODY IN COMMAND":
		tone = COL_DIM
	_status.add_theme_color_override("font_color", tone)

	if empty:
		_page.text = ""
	else:
		_page.text = "%d/%d" % [tool_node.mode_index() + 1, tool_node.mode_count()]
	_set_icon(null if empty else _icon_for(tool_node.current_mode_id()))


## Show the icon, or give its space to the name.
##
## The two movement orders have no baked art — they are verbs, not things you
## bought — and leaving an empty 74px square beside "ADVANCE" reads as an icon
## that failed to load. Dropping it instead lets the name run the full width,
## which is what a two-word verb wants anyway.
func _set_icon(tex: Texture2D) -> void:
	var pad := 12.0
	_icon.texture = tex
	_icon.visible = tex != null
	var left: float = pad + 80.0 if tex != null else pad
	_label.position = Vector2(left, 34.0)
	_label.size = Vector2(SIZE.x - pad - left, 84.0)
	var align := HORIZONTAL_ALIGNMENT_LEFT if tex != null else HORIZONTAL_ALIGNMENT_CENTER
	_label.horizontal_alignment = align


## The same baked line art the armoury and the factory use, so an item looks the
## same here as where it was bought. Comes back null when it has not been baked,
## and the name alone carries the screen — a picture is never the only way to
## tell what something is.
func _icon_for(item_id: StringName) -> Texture2D:
	if item_id == &"":
		return null
	var item := _Glyphs.item_by_id(item_id)
	return _Icons.item(item, "m") if item != null else null
