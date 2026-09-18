extends Control
class_name WeaponBar

# ─────────────────────────────────────────────
# WEAPON BAR — what each number key will do, before you press it.
#
# The problem it solves is not "what am I holding" — the viewmodel answers that.
# It is "I have no idea what happens when I hit 4". So the bar's real job is the
# STATES, not the names: a slot with nothing in it, or with something you cannot
# currently use, has to look wrong BEFORE you commit to the key.
#
#   current    bright, filled       the thing in your hands
#   available  dim                  press this and it happens
#   unusable   dim + warning        an item is there but has no charges
#   empty      barely there         nothing is bound to this key
#
# CHIPS ARE BUILT ONCE, never rebuilt. The slot set is fixed at six, so the
# refresh only ever changes text and colour. That sidesteps the deferred
# queue_free() trap that has bitten every other rebuilding panel in this HUD.
#
# ICON-READY, TEXT-FIRST. PlayerEquipment already has an `icon` field and
# nothing in the project assigns one yet, so every chip reserves the box and
# hides it until there is art. Dropping textures in later changes no layout.
#
# PRESENCE: it rests at almost nothing and flashes to full on a switch or a
# refused press, holding a beat before fading back. Never hidden outright —
# the ghost of the row keeps the bar's position learnable, so the flash lands
# somewhere your eye already knows to look instead of appearing from nowhere.
# ─────────────────────────────────────────────

@export var player: Player
## Bottom-CENTRE, and lifted clear of the health bar, which spans the full
## width of the screen. The bottom-left corner already carries that readout and
## the squad panel, and this is the third thing that wanted to live there.
@export var bottom_margin: float = 104.0
@export var chip_size: Vector2 = Vector2(132, 44)
@export var chip_gap: float = 8.0
@export var icon_size: Vector2 = Vector2(28, 28)

@export_group("Presence")
## Resting opacity. Barely there on purpose: the bar answers a question you
## only ask at the moment you touch a number key, so at rest it should be a
## suggestion of shape rather than something competing with the squad readout
## and the health bar for the same corner of your attention.
@export_range(0.0, 1.0) var idle_alpha: float = 0.12
## Opacity right after a switch or a refused press.
@export_range(0.0, 1.0) var active_alpha: float = 1.0
## Seconds at FULL brightness before fading. A flash that starts decaying on
## frame one never reads as bright — you need a beat to actually look at it.
@export var highlight_hold: float = 1.15
## Seconds to fade from full back down to idle.
@export var highlight_fade: float = 1.05
## How long a refused slot stays lit red.
@export var deny_seconds: float = 0.9

@export_group("Text")
@export var font_size_key: int = 15
@export var font_size_name: int = 15
@export var font_size_ammo: int = 14

const COL_BRIGHT := HUDPalette.BRIGHT
const COL_DIM := HUDPalette.DIM
const COL_WARN := HUDPalette.WARN
const COL_CRIT := HUDPalette.CRIT

var _loadout: EquipmentLoadout = null
var _row: HBoxContainer = null
var _chips: Array[Dictionary] = []
var _highlight: float = 0.0
var _deny_slot: int = -1
var _deny_time: float = 0.0
var _wired: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	modulate.a = idle_alpha


func _build() -> void:
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", int(chip_gap))
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	for i in 6:
		_chips.append(_make_chip(i))


func _make_chip(index: int) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = chip_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.45)
	style.border_color = COL_DIM
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)
	_row.add_child(panel)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	var key := Label.new()
	key.text = str(index + 1)
	key.add_theme_font_size_override("font_size", font_size_key)
	key.add_theme_color_override("font_color", COL_BRIGHT)
	key.custom_minimum_size = Vector2(12, 0)
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(key)

	# Reserved even when empty — see ICON-READY above.
	var icon := TextureRect.new()
	icon.custom_minimum_size = icon_size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.visible = false
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(text)

	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", font_size_name)
	name_label.add_theme_color_override("font_color", COL_DIM)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(name_label)

	var ammo_label := Label.new()
	ammo_label.add_theme_font_size_override("font_size", font_size_ammo)
	ammo_label.add_theme_color_override("font_color", COL_DIM)
	ammo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(ammo_label)

	return {
		"panel": panel, "style": style, "key": key, "icon": icon,
		"name": name_label, "ammo": ammo_label,
	}


# ─────────────────────────────────────────────
# WIRING
# The loadout lives on the player, which is built after the HUD. Polled until
# it answers, then the signals do the work.
# ─────────────────────────────────────────────
func _wire() -> void:
	if _wired:
		return
	if player == null or not is_instance_valid(player):
		# The HUD already holds the reference, so ask it first. The "player"
		# group is NOT reliable in this project — tutorial_label.gd carries the
		# same warning — so it is a fallback, with a tree search behind that.
		var host := get_parent()
		if host != null:
			player = host.get("player") as Player
		if player == null:
			player = get_tree().get_first_node_in_group("player") as Player
		if player == null:
			player = _find_player(get_tree().root)
		if player == null:
			return
	var l = player.get("loadout")
	if l == null or not is_instance_valid(l):
		return
	_loadout = l as EquipmentLoadout
	if _loadout == null:
		return
	if not _loadout.equipped.is_connected(_on_equipped):
		_loadout.equipped.connect(_on_equipped)
	if not _loadout.denied.is_connected(_on_denied):
		_loadout.denied.connect(_on_denied)
	_wired = true


func _on_equipped(_item) -> void:
	_highlight = highlight_hold + highlight_fade


# A refused press is the most informative moment the bar has: it is the exact
# instant the player discovered a key did not do what they expected. Light the
# slot they asked for rather than just flashing the whole bar.
func _on_denied(_reason: String) -> void:
	_highlight = highlight_hold + highlight_fade
	_deny_time = deny_seconds
	_deny_slot = _slot_for_reason(_reason)


func _slot_for_reason(reason: String) -> int:
	if _loadout == null:
		return -1
	var head := reason.split(" ")[0].strip_edges().to_upper()
	for i in _chips.size():
		var item = _loadout.item_for_slot(i)
		if item != null and is_instance_valid(item):
			if item.display_name.to_upper().begins_with(head):
				return i
	return -1


# ─────────────────────────────────────────────
# TICK
# ─────────────────────────────────────────────
func _process(delta: float) -> void:
	# LAYOUT FIRST, unconditionally. This used to sit behind the wiring check,
	# so a bar that had not found the loadout yet never positioned itself and
	# sat in the top-left corner where the HBoxContainer defaulted to.
	_layout()
	if not _wired:
		_wire()
		if not _wired:
			# Nothing to describe yet — better blank than six dead slots.
			visible = false
			return
		visible = true
	if _highlight > 0.0:
		_highlight = maxf(0.0, _highlight - delta)
	if _deny_time > 0.0:
		_deny_time = maxf(0.0, _deny_time - delta)
		if _deny_time <= 0.0:
			_deny_slot = -1
	# Hold, THEN fade. _highlight counts down through the fade window first, so
	# anything above it is still inside the hold and sits at full.
	var t: float = 1.0
	if _highlight <= highlight_fade:
		t = clampf(_highlight / maxf(highlight_fade, 0.01), 0.0, 1.0)
		# Eased so it lingers legible and then drops away, rather than spending
		# the whole fade at the half-lit value that reads as neither.
		t = t * t
	modulate.a = lerpf(idle_alpha, active_alpha, t)
	_refresh()


func _layout() -> void:
	# FORCE THE FULL RECT EVERY FRAME. An anchors preset in the .tscn does not
	# touch offsets, so this Control came out 40px tall and the bar laid itself
	# out along the TOP of the screen — the same trap squad_hud documents.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	var width: float = _chips.size() * chip_size.x + (_chips.size() - 1) * chip_gap
	_row.position = Vector2((size.x - width) * 0.5, size.y - bottom_margin - chip_size.y)
	_row.size = Vector2(width, chip_size.y)


func _refresh() -> void:
	var current = _loadout.current
	for i in _chips.size():
		var chip: Dictionary = _chips[i]
		var item = _loadout.item_for_slot(i)
		var style: StyleBoxFlat = chip["style"]
		var name_label: Label = chip["name"]
		var ammo_label: Label = chip["ammo"]
		var key_label: Label = chip["key"]
		var icon: TextureRect = chip["icon"]

		if item == null or not is_instance_valid(item):
			# EMPTY. Deliberately still drawn: a gap would just move the other
			# chips around and teach nothing. A visible dead slot says "this
			# key is bound to nothing", which is the actual fact.
			name_label.text = "—"
			ammo_label.text = ""
			icon.visible = false
			_paint(style, key_label, name_label, ammo_label, COL_DIM, 0.40, 0.30)
			continue

		name_label.text = item.display_name.to_upper()
		var ammo := _ammo_text(item)
		# A knife's readout label IS its name, so the chip printed it twice.
		ammo_label.text = "" if ammo.to_upper() == name_label.text else ammo
		icon.texture = item.icon
		icon.visible = item.icon != null

		var is_current: bool = item == current
		var usable: bool = item.can_equip()
		if i == _deny_slot and _deny_time > 0.0:
			_paint(style, key_label, name_label, ammo_label, COL_CRIT, 0.80, 1.0)
		elif is_current:
			_paint(style, key_label, name_label, ammo_label, COL_BRIGHT, 0.80, 1.0)
		elif not usable:
			# There IS something here, and pressing the key will refuse. That
			# has to look different from both "ready" and "empty".
			_paint(style, key_label, name_label, ammo_label, COL_WARN, 0.62, 0.70)
		else:
			_paint(style, key_label, name_label, ammo_label, COL_DIM, 0.62, 0.85)


func _paint(style: StyleBoxFlat, key_label: Label, name_label: Label,
		ammo_label: Label, col: Color, bg: float, text: float) -> void:
	style.border_color = Color(col.r, col.g, col.b, clampf(text + 0.1, 0.0, 1.0))
	# A DARK backing, not a tinted one. Tinting the background with the state
	# colour left pale chips sitting on pale terrain, and the bar was unreadable
	# over anything bright. The colour belongs on the border and the text.
	style.bg_color = Color(0.02, 0.03, 0.04, bg)
	var c := Color(col.r, col.g, col.b, text)
	key_label.add_theme_color_override("font_color", c)
	name_label.add_theme_color_override("font_color", c)
	ammo_label.add_theme_color_override("font_color", Color(col.r, col.g, col.b, text * 0.8))


func _ammo_text(item) -> String:
	if item == null or not item.has_method("get_readout"):
		return ""
	var r = item.get_readout()
	if r == null:
		return ""
	match r.mode:
		PlayerEquipment.ReadoutMode.MAGAZINE:
			return "%d / %d" % [r.primary, r.secondary]
		PlayerEquipment.ReadoutMode.COUNT:
			return "x%d" % r.primary
		PlayerEquipment.ReadoutMode.COOLDOWN, PlayerEquipment.ReadoutMode.CHANNEL:
			return r.label if r.label != "" else "%d%%" % int(round(r.fraction * 100.0))
	return r.label


# Depth-first search for the player body. Last resort behind the HUD's own
# reference and the group, both of which can legitimately be empty.
func _find_player(node: Node) -> Player:
	if node is Player:
		return node as Player
	for c in node.get_children():
		var found := _find_player(c)
		if found != null:
			return found
	return null
