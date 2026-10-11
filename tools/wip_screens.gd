extends SceneTree

# ─────────────────────────────────────────────
# WIP SCREENS — the proposed Factory, Armorer and Squad pages, photographed.
#
# A LOOK, NOT A BUILD. None of the live pages are touched: this draws its own
# Control trees beside them, out of the same ui_kit, the same DS-Digital, the
# same palette and the same icon sheet, so what comes out is what the game
# would look like rather than what a drawing of it would look like. When the
# design is settled the real pages get the same layout and this file goes.
#
#   godot --audio-driver Dummy --path . --script res://tools/wip_screens.gd -- <out dir>
#
# MUST RUN HEADFUL. --headless has no renderer, so a headless run writes
# nothing.
#
# ON SIZE. Shot at 1920x1080 into a SubViewport of its own, NOT the window: the
# project renders 1152x648 and stretches, so a 1152 grab is correct about layout
# and wrong about how big any of it looks — which read as "everything has got
# small" when the shots were opened at full size. Every dimension here goes
# through _s(), so the whole screen is authored at the live UI's numbers and
# scaled once. Change UI_SCALE and nothing else moves.
#
# Loads the catalogue resource and nothing else — no world, no CampaignManager,
# no save. The roster is built here, in memory, one of every buildable frame.
#
# WHAT IS NEW, versus the live pages:
#   - frames and weapons carry STAT BARS, not a sentence
#   - a module's contribution continues its bar in WHITE, and white means THAT
#     AND NOTHING ELSE. A cluster round's bomblets are not a bonus and are not
#     drawn as one; they are in the damage reading, as 40+6x30.
#   - gear gets a FACT LIST, not bars: a smoke canister's 14 seconds and a
#     frag's 100 damage do not share a scale, and a bar across both would be
#     decoration
#   - a module gets ONE LINE, because a module is one number
#   - the damage figure counts submunitions, so the Cluster Launcher reads
#     40+6x30 instead of the 40 the weapon node knows about
#   - slot tiles read WEP / EQUIP / MOD
#   - only POSITIVES are listed: a frame without suppressive fire says nothing
#     about suppressive fire
# ─────────────────────────────────────────────

const Kit := preload("res://Character/hud/squad/ui_kit.gd")
const Icons := preload("res://Character/hud/icons/icons.gd")
const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"

const SHOT := Vector2i(1920, 1080)
## Everything below is written at the live UI's own numbers and multiplied by
## this. 1920/1152 is 1.667, which is exactly what the player's screen does to
## the game's internal resolution — so a shot at this scale is the apparent size
## they actually see, drawn sharp instead of upscaled.
const UI_SCALE := 1.667

## What a module added, drawn as the white part of a bar. One new entry in the
## palette: every colour the game has is spoken for — bright green acts, dim
## green labels, amber is resources, blue is compute, red is wrong — and "this
## part you bolted on" is none of them. Nothing else is ever drawn in it.
const UPGRADE := Color(1.0, 1.0, 1.0)

## Bar scales. Fixed per stat across every card, so two cards side by side can
## be compared by eye. A bar that rescales to its own row is a bar that lies.
const HULL_MAX := 400.0
const SENSOR_MAX := 120.0
const SPEED_MAX := 20.0
const DAMAGE_MAX := 80.0    # one impact, not a whole cluster round — see _item_detail
const FIRE_MAX := 200.0
const RANGE_MAX := 130.0
const MAG_MAX := 120.0

## Metres per second per frame, read off the chassis SCENE: base_speed on the
## definition is 1.00 for all six, so the definition cannot answer this.
const SPEEDS := {
	&"soldier": 6.0, &"mechanic": 6.0, &"reclaimer": 6.0,
	&"rover": 7.0, &"spotter": 18.0, &"walker": 4.2,
}

## Spares in stores, so the shelves and the detail panel can say something true
## about what you own. A mock roster has no save behind it.
const SPARES := {
	&"m4": 2, &"squad_auto": 1, &"heavy_mg": 1, &"machine_gun": 2,
	&"repair_kit": 3, &"frag": 4, &"smoke": 2, &"armor_plating": 1,
	&"cluster_launcher": 1, &"optics": 1,
}

var _cat: ItemCatalogue
var _out := "docs/marketing/wip"
var _roster: Array[SoldierRecord] = []


func _s(n: float) -> int:
	return int(round(n * UI_SCALE))


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://") + _out)
	await process_frame

	_cat = load(CATALOGUE)
	if _cat == null:
		printerr("wip_screens: no catalogue at %s" % CATALOGUE)
		quit(1)
		return
	_build_roster()

	await _capture(_factory_screen(), "wip_factory.png")
	# Deliberately too narrow for six frames, to show what happens when the row
	# does not fit: it scrolls, with a bar, rather than running off the edge.
	await _capture(_factory_screen(), "wip_factory_narrow.png", Vector2i(1120, 1080))
	await _capture(_armorer_screen(&"cluster_launcher"), "wip_armorer_weapon.png")
	await _capture(_armorer_screen(&"emp"), "wip_armorer_equipment.png")
	await _capture(_armorer_screen(&"optics"), "wip_armorer_module.png")
	# Two shelves folded away, which is the point of making them fold: the one
	# you are shopping in gets the screen.
	await _capture(_armorer_screen(&"optics", [ItemDefinition.Kind.WEAPON,
		ItemDefinition.Kind.EQUIPMENT]), "wip_armorer_folded.png")
	await _capture(_squad_screen(0), "wip_squad_walker.png")
	await _capture(_squad_screen(3), "wip_squad_soldier.png")
	quit(0)


# ── CAPTURE ───────────────────────────────────

func _capture(screen: Control, file: String, size: Vector2i = SHOT) -> void:
	# Its own viewport, at the size we want, rather than the window's. The window
	# is whatever this machine opened; the shot should not be.
	var sub := SubViewport.new()
	sub.size = size
	sub.transparent_bg = false
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(sub)

	var ground := ColorRect.new()
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ground.color = Color(0.02, 0.035, 0.03)
	sub.add_child(ground)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub.add_child(screen)

	# Containers settle over a couple of frames; a grab on the first catches
	# everything stacked at the origin.
	for _i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	var path := "res://%s/%s" % [_out, file]
	var err := img.save_png(path)
	if err != OK:
		printerr("wip_screens: could not write %s (%s)" % [path, error_string(err)])
	else:
		print("wrote %s  %dx%d" % [path, img.get_width(), img.get_height()])
	sub.queue_free()
	await process_frame


# ── SHARED CHROME ─────────────────────────────

func _page(tab: String, body: Control) -> Control:
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, _s(14))
	var col := Kit.vbox(_s(10))
	pad.add_child(col)

	var chrome := Kit.hbox(_s(18))
	var tabs := Kit.hbox(_s(22))
	for name in ["SQUAD", "FACTORY", "ARMORER", "SOFTWARE"]:
		var lit: bool = str(name) == tab
		tabs.add_child(Kit.label(str(name), Kit.BRIGHT if lit else Kit.DIM, _s(20), lit))
	chrome.add_child(tabs)
	chrome.add_child(Kit.fill())
	chrome.add_child(Kit.label("COMPUTE 4", Kit.COMPUTE, _s(21), true))
	chrome.add_child(Kit.label("RESOURCES 540", Kit.MONEY, _s(21), true))
	col.add_child(chrome)
	var rule := Panel.new()
	rule.custom_minimum_size.y = 1
	var line := StyleBoxFlat.new()
	line.bg_color = Kit.LINE
	rule.add_theme_stylebox_override("panel", line)
	col.add_child(rule)

	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	return pad


## LABEL | track | value. `total` above `base` paints the difference in white,
## which is reserved for what a MODULE added. Everything else passes base and
## total equal and gets one solid bar.
func _bar(label: String, base: float, total: float, scale: float, reading: String,
		label_w: float = 58.0, value_w: float = 62.0) -> Control:
	var row := Kit.hbox(_s(6))
	var key := Kit.label(label, Kit.DIM, _s(Kit.SMALL))
	key.custom_minimum_size.x = _s(label_w)
	row.add_child(key)

	var track := Panel.new()
	track.custom_minimum_size = Vector2(0, _s(9))
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.add_theme_stylebox_override("panel", Kit.box(Kit.FAINT, Color(0, 0, 0, 0), 1, 0.0))
	# Anchored fills rather than sized children: the row's width is not known
	# until the container lays out, and fractions survive that.
	var base_f := ColorRect.new()
	base_f.color = Kit.BRIGHT
	base_f.set_anchors_preset(Control.PRESET_FULL_RECT, true)
	base_f.anchor_right = clampf(base / scale, 0.0, 1.0)
	base_f.offset_right = 0.0
	track.add_child(base_f)
	if total > base:
		var up := ColorRect.new()
		up.color = UPGRADE
		up.set_anchors_preset(Control.PRESET_FULL_RECT, true)
		up.anchor_left = clampf(base / scale, 0.0, 1.0)
		up.anchor_right = clampf(total / scale, 0.0, 1.0)
		up.offset_left = 0.0
		up.offset_right = 0.0
		track.add_child(up)
	row.add_child(track)

	var val := Kit.label(reading, UPGRADE if total > base else Kit.BRIGHT, _s(Kit.SMALL), true)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.custom_minimum_size.x = _s(value_w)
	row.add_child(val)
	return row


## One tile per slot, filled ones lit. WEP / EQUIP / MOD — three kinds rather
## than the five words the live row uses, because the mount line above already
## says which kind of weapon it takes.
func _tiles(wep: int, wep_filled: int, equip: int, equip_filled: int,
		mod: int, mod_filled: int) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", _s(4))
	row.add_theme_constant_override("v_separation", _s(3))
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	for spec in [["WEP", wep, wep_filled, 46.0], ["EQUIP", equip, equip_filled, 52.0],
			["MOD", mod, mod_filled, 40.0]]:
		for i in int(spec[1]):
			var lit: bool = i < int(spec[2])
			var tile := PanelContainer.new()
			tile.add_theme_stylebox_override("panel",
				Kit.box(Kit.BRIGHT if lit else Kit.FAINT, Color(0, 0, 0, 0), 1, _s(4)))
			tile.custom_minimum_size.x = _s(float(spec[3]))
			var t := Kit.label(str(spec[0]), Kit.BRIGHT if lit else Kit.DIM, _s(Kit.SMALL))
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tile.add_child(t)
			row.add_child(tile)
	return row


func _badges(words: Array, wrap: bool = false) -> Control:
	if wrap:
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", _s(4))
		flow.add_theme_constant_override("v_separation", _s(3))
		flow.alignment = FlowContainer.ALIGNMENT_CENTER
		for w in words:
			flow.add_child(_chip_word(str(w)))
		return flow
	var row := Kit.hbox(_s(4))
	for w in words:
		row.add_child(_chip_word(str(w)))
	return row


func _chip_word(word: String) -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", Kit.box(Kit.FAINT, Color(0, 0, 0, 0), 1, _s(4)))
	chip.add_child(Kit.label(word.to_upper(), Kit.BRIGHT, _s(Kit.SMALL)))
	return chip


## A spacer that eats the leftover HEIGHT. Kit.fill() only expands horizontally,
## which left every BUILD button floating under its tiles with the bottom half
## of the card empty beneath it.
func _vfill() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## A gear icon in a bordered square, the way the live squad card carries them.
## This is the one thing the first pass dropped that was worth most: a roster of
## names tells you who is in the squad, a roster of icons tells you what the
## squad can do.
func _gear_mini(item: ItemDefinition, box: float = 30.0) -> Control:
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel",
		Kit.box(Kit.FAINT if item == null else Kit.LINE, Kit.PANEL, 1, _s(2)))
	var side := _s(box)
	tile.custom_minimum_size = Vector2(side, side)
	if item == null:
		var empty := Kit.label("-", Kit.DIM, _s(Kit.SMALL))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tile.add_child(empty)
	else:
		tile.add_child(Kit.icon(Icons.item(item, "s"), Kit.BRIGHT,
			Vector2(side - _s(6), side - _s(6)), true))
	return tile


# ── CLASSIFICATION ────────────────────────────
#
# Every tag is a rule over fields the resources already carry, so a new frame or
# gun gets its badges by being defined. Nothing is authored twice.

func _frame_badges(f: ChassisDefinition) -> Array:
	var out: Array = []
	if f.turret:
		out.append("Turret")
	if f.vehicle:
		out.append("Vehicle frame")
	if not f.vehicle and not f.drives and not f.turret:
		out.append("Infantry")
	if f.built_in == "WELDER" and f.weapon_replaces_built_in:
		out.append("Articulated arm")
	# A welder it still HAS. The enemy mortar track carries one and starts with
	# the mortar in its place, so it is not a medic.
	if f.built_in == "WELDER" and f.starting_weapon_id == &"":
		out.append("Medic")
	return out


func _mount_line(f: ChassisDefinition) -> String:
	if f.weapon_slots == 0:
		return "BUILT-IN %s" % f.built_in if f.built_in != "" else ""
	if f.turret:
		return "%d x TURRET" % f.weapon_slots
	if f.built_in == "WELDER" and f.weapon_replaces_built_in:
		return "%d x ARM" % f.weapon_slots
	# Not "infantry": that is the FRAME's class, and the slot is a pair of hands.
	return "%d x SMALL ARMS" % f.weapon_slots


func _weapon_class(item: ItemDefinition) -> String:
	if item.chassis_whitelist.is_empty():
		return "INFANTRY WEAPON"
	if item.chassis_whitelist.has(&"reclaimer"):
		return "ARTICULATED ARM"
	return "TURRET"


## One shot's damage, counting what the round breaks up into. Asks the weapon
## scene, which is the only thing that knows: a launcher's damage is on its
## round, and a cluster round carries six more inside that.
func _shot(item: ItemDefinition) -> Dictionary:
	var blank := {"impact": 0, "submunitions": 0, "each": 0, "total": 0,
		"range": 0.0, "cooldown": 0.0, "magazine": 0, "reload": 0.0}
	if item.ai_scene == null:
		return blank
	var w = item.ai_scene.instantiate()
	if not (w is AIWeapon):
		w.free()
		return blank
	var d: Dictionary = w.shot_damage() if w.has_method("shot_damage") \
		else {"impact": w.base_damage, "submunitions": 0, "each": 0, "total": w.base_damage}
	d["range"] = w.max_effective_range
	d["cooldown"] = w.fire_cooldown
	d["magazine"] = w.magazine_size
	d["reload"] = w.reload_time
	w.free()
	return d


func _damage_reading(d: Dictionary) -> String:
	if int(d["submunitions"]) > 0:
		return "%d+%dx%d" % [d["impact"], d["submunitions"], d["each"]]
	return str(d["impact"])


func _firepower(d: Dictionary) -> float:
	var cd: float = float(d["cooldown"])
	if cd <= 0.0:
		return 0.0
	return float(d["total"]) / cd


## Who in the squad is carrying one, by name. The live Armorer prints this and
## the first pass replaced it with a hardcoded FITTED 0, which is the single
## most useful line on the panel: it answers "do I need another".
func _fitted_with(id: StringName) -> PackedStringArray:
	var who := PackedStringArray()
	for r in _roster:
		if r.weapon_ids.has(id) or r.equipment_ids.has(id) or r.module_ids.has(id):
			who.append(r.display_name)
	return who


# ── FACTORY ───────────────────────────────────

func _factory_screen() -> Control:
	var col := Kit.vbox(_s(10))

	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", Kit.box(Kit.LINE, Kit.PANEL, 1, _s(9)))
	var srow := Kit.hbox(_s(12))
	strip.add_child(srow)
	srow.add_child(Kit.label("HANGAR", Kit.BRIGHT, _s(20), true))
	srow.add_child(Kit.seats(6, 8))
	srow.add_child(Kit.label("8 SEATS - 2 FREE", Kit.DIM, _s(Kit.BODY)))
	srow.add_child(Kit.fill())
	srow.add_child(Kit.button("REMOVE A SEAT", Kit.DIM, _s(Kit.BODY)))
	srow.add_child(Kit.button("ADD A SEAT", Kit.BRIGHT, _s(Kit.BODY)))
	srow.add_child(Kit.label("HOLDS 1 COMPUTE", Kit.COMPUTE, _s(Kit.BODY), true))
	col.add_child(strip)

	var row := Kit.hbox(_s(8))
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for f in _buildable():
		row.add_child(_frame_card(f))
	# AUTO, and said out loud rather than left to the default: when more frames
	# are unlocked than fit, the row has to scroll with a bar you can see — a
	# card clipped at the right edge with no bar under it reads as a bug, and
	# there is no way to reach the frames past it.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(row)
	col.add_child(scroll)
	return _page("FACTORY", col)


## Cheapest first, left to right. The row is a ladder: a player reads it as "what
## can I afford next", and that question runs in one direction. Sorted the other
## way the Walker led and the Soldier — the thing you actually buy early — was
## the one pushed off the end when the row overflowed.
func _buildable() -> Array:
	var out: Array = []
	for f in _cat.chassis:
		if f.purchasable:
			out.append(f)
	out.sort_custom(func(a, b): return a.cost < b.cost)
	return out


func _frame_card(f: ChassisDefinition) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Kit.box(Kit.LINE, Kit.PANEL, 1, _s(10)))
	card.custom_minimum_size.x = _s(178)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := Kit.vbox(_s(6))
	card.add_child(col)

	# The frame, big. The live card gives this 128 points and it is the fastest
	# thing on the screen to read; shrinking it was the first pass's worst trade.
	var art := Kit.icon(Icons.chassis(f, "l"), Kit.BRIGHT, Vector2(_s(96), _s(96)), true)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(art)
	var name := Kit.label(Kit.frame_word(f).to_upper(), Kit.BRIGHT, _s(24), true)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name)

	# The two prices, each in its own currency. A frame's supply IS its compute
	# cost, because compute is what holds seats — so it belongs beside the
	# resource price, not down among the badges where it read as a trait.
	var price := Kit.hbox(_s(8))
	price.alignment = BoxContainer.ALIGNMENT_CENTER
	price.add_child(Kit.label(str(f.cost), Kit.MONEY, _s(22), true))
	price.add_child(Kit.label("%d SEAT%s" % [f.supply, "" if f.supply == 1 else "S"],
		Kit.COMPUTE, _s(Kit.SMALL), true))
	col.add_child(price)

	col.add_child(_badges(_frame_badges(f), true))
	col.add_child(_bar("HULL", f.base_health, f.base_health, HULL_MAX, str(f.base_health), 52.0, 48.0))
	var mps: float = float(SPEEDS.get(f.id, 6.0))
	col.add_child(_bar("SPEED", mps, mps, SPEED_MAX, "%.1f" % mps, 52.0, 48.0))
	col.add_child(_bar("SENSOR", f.base_sensor_range, f.base_sensor_range, SENSOR_MAX,
		"%.0f M" % f.base_sensor_range, 52.0, 48.0))

	var mount := _mount_line(f)
	if mount != "":
		var m := Kit.label(mount, Kit.DIM, _s(Kit.SMALL))
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Wraps rather than widening. A label is as wide as its text unless told
		# otherwise, and one long line stretched the whole card.
		m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		m.custom_minimum_size.x = _s(100)
		col.add_child(m)
	col.add_child(_tiles(f.weapon_slots, f.weapon_slots, f.equipment_slots, 0, f.module_slots, 0))

	col.add_child(_vfill())
	var buy := Kit.hbox(_s(10))
	buy.alignment = BoxContainer.ALIGNMENT_CENTER
	buy.add_child(Kit.button("BUILD", Kit.BRIGHT, _s(Kit.HEADING)))
	buy.add_child(Kit.label(str(f.cost), Kit.MONEY, _s(Kit.HEADING), true))
	col.add_child(buy)
	var where := Kit.label("JOINS THE SQUAD" if f.supply <= 2 else "WAITS ON THE BENCH",
		Kit.DIM, _s(Kit.SMALL))
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	where.custom_minimum_size.x = _s(100)
	col.add_child(where)
	return card


# ── ARMORER ───────────────────────────────────

## `folded` lists the kinds whose shelves are closed. Same idea as the Squad
## page's teams: click the header and the shelf rolls up, so the kind you are
## shopping in gets the screen instead of scrolling past two you are not.
## EQUIPMENT, not GEAR — the slot on every frame is called EQUIP, the item kind
## is ItemDefinition.Kind.EQUIPMENT, and the shop was the only place using a
## third word for the same thing.
func _armorer_screen(selected: StringName, folded: Array = []) -> Control:
	var split := Kit.hbox(_s(16))

	var left := Kit.vbox(_s(10))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in [[ItemDefinition.Kind.WEAPON, "WEAPONS"],
			[ItemDefinition.Kind.EQUIPMENT, "EQUIPMENT"], [ItemDefinition.Kind.MODULE, "MODULES"]]:
		var kind := int(entry[0])
		var open: bool = not folded.has(kind)
		var shelf := Kit.vbox(_s(5))

		var stock: Array = []
		for item in _cat.items_of_kind(kind):
			if item.in_shop:
				stock.append(item)

		var header := PanelContainer.new()
		header.add_theme_stylebox_override("panel", Kit.box(Kit.FAINT, Kit.PANEL, 1, _s(5)))
		var hrow := Kit.hbox(_s(8))
		header.add_child(hrow)
		hrow.add_child(Kit.caret(open, Kit.BRIGHT))
		hrow.add_child(Kit.label(str(entry[1]), Kit.BRIGHT, _s(Kit.BODY), true))
		hrow.add_child(Kit.fill())
		# The count stays on a folded shelf. A closed row that says only its name
		# hides how much is behind it, which is the thing that stops people
		# opening it again.
		hrow.add_child(Kit.label("%d IN THE SHOP" % stock.size(), Kit.DIM, _s(Kit.SMALL)))
		shelf.add_child(header)

		if open:
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", _s(6))
			flow.add_theme_constant_override("v_separation", _s(6))
			for item in stock:
				flow.add_child(_chip(item, item.id == selected))
			if stock.is_empty():
				# EVERY EMPTY LIST SAYS WHY. A blank shelf with no line under it
				# reads as a layout bug rather than as an empty shop.
				flow.add_child(Kit.label("NOTHING OF THIS KIND IS IN THE SHOP",
					Kit.DIM, _s(Kit.SMALL)))
			shelf.add_child(flow)
		left.add_child(shelf)
	left.add_child(_vfill())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(left)
	split.add_child(scroll)

	var side := PanelContainer.new()
	var edge := StyleBoxFlat.new()
	edge.bg_color = Color(0, 0, 0, 0)
	edge.border_color = Kit.LINE
	edge.border_width_left = 1
	edge.content_margin_left = _s(16)
	side.add_theme_stylebox_override("panel", edge)
	side.custom_minimum_size.x = _s(340)
	var item := _cat.item(selected)
	if item == null:
		side.add_child(Kit.label("NO SUCH ITEM: %s" % selected, Kit.PROBLEM, _s(Kit.BODY), true))
	else:
		side.add_child(_item_detail(item))
	split.add_child(side)
	return _page("ARMORER", split)


## Icon, name, price, and how many are spare. The icon is the point: a shelf of
## names is a list, a shelf of silhouettes is a shop you can shop in.
func _chip(item: ItemDefinition, lit: bool) -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel",
		Kit.box(Kit.BRIGHT if lit else Kit.FAINT, Kit.PANEL, 1, _s(6)))
	chip.custom_minimum_size.x = _s(132)
	var col := Kit.vbox(_s(3))
	chip.add_child(col)
	var wide := item.kind == ItemDefinition.Kind.WEAPON
	var art := Kit.icon(Icons.item(item, "m"), Kit.BRIGHT,
		Vector2(_s(104), _s(40)) if wide else Vector2(_s(40), _s(40)), true)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(art)
	var nm := Kit.label(item.short_label().to_upper(), Kit.BRIGHT, _s(Kit.SMALL), true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nm)
	var row := Kit.hbox(_s(6))
	row.add_child(Kit.label(str(item.cost), Kit.MONEY, _s(Kit.SMALL)))
	row.add_child(Kit.fill())
	var spare: int = int(SPARES.get(item.id, 0))
	row.add_child(Kit.label("x%d" % spare if spare > 0 else "-", Kit.DIM, _s(Kit.SMALL)))
	col.add_child(row)
	return chip


func _item_detail(item: ItemDefinition) -> Control:
	var col := Kit.vbox(_s(7))
	var wide := item.kind == ItemDefinition.Kind.WEAPON
	var art := Kit.icon(Icons.item(item, "l"), Kit.BRIGHT,
		Vector2(_s(240), _s(90)) if wide else Vector2(_s(96), _s(96)), true)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(art)
	col.add_child(Kit.label(item.display_name.to_upper(), Kit.BRIGHT, _s(24), true))

	match item.kind:
		ItemDefinition.Kind.WEAPON:
			col.add_child(Kit.label(_weapon_class(item), Kit.DIM, _s(Kit.BODY), true))
			var d := _shot(item)
			if int(d["total"]) == 0:
				col.add_child(Kit.label("NO AI WEAPON SCENE, SO NO FIGURES TO SHOW",
					Kit.PROBLEM, _s(Kit.SMALL)))
			else:
				# ONE SOLID BAR, at the impact. The bomblets are in the reading,
				# not in the bar: white means "a module added this" everywhere
				# else on these screens, and a cluster round's submunitions are
				# not a bonus — drawing them the same way made one colour mean
				# two things.
				col.add_child(_bar("DAMAGE", d["impact"], d["impact"], DAMAGE_MAX,
					_damage_reading(d), 66.0, 86.0))
				var fp := _firepower(d)
				col.add_child(_bar("FIREPOWER", fp, fp, FIRE_MAX, "%.0f/S" % fp, 66.0, 86.0))
				col.add_child(_bar("RANGE", d["range"], d["range"], RANGE_MAX,
					"%.0f M" % d["range"], 66.0, 86.0))
				col.add_child(_bar("MAGAZINE", d["magazine"], d["magazine"], MAG_MAX,
					str(d["magazine"]), 66.0, 86.0))
				var tail: Array = []
				if float(d["reload"]) > 0.0:
					tail.append("RELOAD %.1f S" % d["reload"])
				if int(d["submunitions"]) > 0:
					tail.append("%d A ROUND IF EVERY BOMBLET LANDS" % d["total"])
				if not tail.is_empty():
					col.add_child(Kit.label(" - ".join(tail), Kit.DIM, _s(Kit.SMALL)))
		ItemDefinition.Kind.EQUIPMENT:
			col.add_child(Kit.label("GEAR", Kit.DIM, _s(Kit.BODY), true))
			col.add_child(_fact_list(item))
		_:
			col.add_child(Kit.label("MODULE", Kit.DIM, _s(Kit.BODY), true))
			# A module is one number, so it gets one line. A bar over a single
			# value is a bar with one entry.
			var effect := Kit.effect_text(item)
			col.add_child(Kit.label(effect if effect != "" else "NO MEASURED EFFECT",
				Kit.BRIGHT if effect != "" else Kit.PROBLEM, _s(20), true))

	var badges := _item_badges(item)
	if not badges.is_empty():
		col.add_child(_badges(badges, true))
	if item.description != "":
		col.add_child(Kit.text_block(item.description, Kit.DIM, _s(Kit.SMALL)))

	col.add_child(_vfill())
	# WHO HAS ONE, by name, and how many are spare. This is the line that
	# answers "do I need to buy another", and it is worth more than any bar on
	# the panel.
	var spare: int = int(SPARES.get(item.id, 0))
	col.add_child(Kit.label("IN STORES %d" % spare, Kit.BRIGHT if spare > 0 else Kit.DIM,
		_s(Kit.BODY), true))
	var fitted := _fitted_with(item.id)
	var who := Kit.label("FITTED: %s" % ", ".join(fitted) if not fitted.is_empty()
		else "NOT FITTED TO ANYONE", Kit.DIM, _s(Kit.SMALL))
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(who)

	var buy := Kit.hbox(_s(10))
	buy.add_child(Kit.button("BUY", Kit.BRIGHT, _s(Kit.HEADING)))
	buy.add_child(Kit.label(str(item.cost), Kit.MONEY, _s(Kit.HEADING), true))
	buy.add_child(Kit.spacer(_s(10), 0))
	if spare > 0:
		buy.add_child(Kit.button("SELL ONE", Kit.DIM, _s(Kit.BODY)))
	col.add_child(buy)
	return col


## Gear, as the two or three figures that matter. Not bars: fourteen seconds of
## smoke and a hundred points of blast share no scale.
func _fact_list(item: ItemDefinition) -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", _s(12))
	grid.add_theme_constant_override("v_separation", _s(3))
	for pair in _facts(item):
		grid.add_child(Kit.label(str(pair[0]), Kit.DIM, _s(Kit.SMALL)))
		var v := Kit.label(str(pair[1]), Kit.BRIGHT, _s(Kit.SMALL), true)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(v)
	return grid


## Figures read out of each piece of gear's own scene, checked against the file
## named beside it. Every label says what the number MEANS — "YOUR OWN TAKE: A
## QUARTER" was a riddle, because it never said a quarter of what.
func _facts(item: ItemDefinition) -> Array:
	var rows: Array = []
	match item.id:
		&"frag":
			rows = [["DAMAGE", "100"], ["BLAST RADIUS", "2.5 M"], ["FUSE", "3.0 S"]]
		&"emp":
			rows = [["BLAST RADIUS", "9 M"], ["KILLS SIGNAL FOR", "3.5 S AT THE CENTRE"],
				["AT THE EDGE", "0.6 S"], ["HURTS FRIENDLIES", "25% AS MUCH"]]
		&"smoke":
			rows = [["CLOUD RADIUS", "7 M"], ["LASTS", "14 S"], ["DAMAGE", "NONE"]]
		&"drone_pack":
			rows = [["RELEASES", "2 DIVERS"], ["EACH HULL", "50"],
				["THEY PICK", "PRICIEST FRAME SEEN"]]
		&"repair_kit":
			rows = [["PATCHES", "A FRAME NEARBY"], ["REVIVES DOWNED", "NO"]]
		&"repair_tool":
			rows = [["PATCHES", "A FRAME NEARBY"], ["REVIVES DOWNED", "YES"]]
		_:
			var effect := Kit.effect_text(item)
			rows = [["EFFECT", effect if effect != "" else "NOT MEASURED HERE"]]
	if item.quantity > 0:
		rows.append(["CARRIES", "%d PER SLOT" % item.quantity])
	return rows


## POSITIVES ONLY. A frame with no suppressive fire says nothing about
## suppressive fire — a row of NO THIS and NO THAT is a card telling you what it
## is not, which is the longest way to say nothing.
func _item_badges(item: ItemDefinition) -> Array:
	var out: Array = []
	if item.one_per_robot:
		out.append("One per robot")
	if not item.usable_by_ai:
		out.append("Yours only")
	elif not item.usable_by_player:
		out.append("Robots only")
	if not item.fits_vehicles and item.kind != ItemDefinition.Kind.WEAPON:
		out.append("No vehicles")
	if item.id == &"mortar":
		out.append("Indirect")
	if item.id == &"repair_lance":
		out.append("Medic")
	return out


# ── SQUAD ─────────────────────────────────────

func _build_roster() -> void:
	# One of every buildable frame, kitted the way a player would by mid
	# campaign, so the screens are photographed with real contents rather than
	# an empty roster.
	var plan := [
		[&"walker", "CANNON", [&"autocannon", &"heavy_mg"], [], [&"armor_plating", &"optics", &"overclock_servos"], 12, 4],
		[&"rover", "VESNA", [&"machine_gun"], [], [&"armor_plating"], 7, 4],
		[&"reclaimer", "ANVIL", [&"mortar"], [], [&"optics", &"hardened_uplink"], 3, 3],
		[&"soldier", "BRICK", [&"squad_auto"], [&"frag", &"repair_kit"], [&"armor_plating", &"nanite_reboot"], 9, 4],
		[&"mechanic", "TOOLBOX", [], [&"repair_kit"], [&"armor_plating"], 0, 4],
		[&"spotter", "SPARROW", [], [&"scanner"], [&"optics"], 0, 2],
	]
	for p in plan:
		var f := _cat.chassis_def(p[0])
		if f == null:
			push_warning("wip_screens: no chassis '%s' in the catalogue, so it is left out of the roster." % p[0])
			continue
		var r := SoldierRecord.new()
		r.id = StringName(str(p[1]).to_lower())
		r.display_name = p[1]
		r.chassis_id = f.id
		r.weapon_ids.assign(p[2])
		r.equipment_ids.assign(p[3])
		r.module_ids.assign(p[4])
		r.confirmed_kills = p[5]
		r.missions_survived = p[6]
		r.rank = mini(int(p[6]), 5)
		r.recompute_stats(_cat)
		_roster.append(r)


func _squad_screen(index: int) -> Control:
	var split := Kit.hbox(_s(16))
	var left := Kit.vbox(_s(8))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(Kit.label("DEPLOYING - 6 OF 8 SEATS", Kit.DIM, _s(Kit.BODY), true))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", _s(6))
	flow.add_theme_constant_override("v_separation", _s(6))
	for i in _roster.size():
		flow.add_child(_squad_chip(_roster[i], i == index))
	left.add_child(flow)
	left.add_child(_vfill())
	split.add_child(left)

	var side := PanelContainer.new()
	var edge := StyleBoxFlat.new()
	edge.bg_color = Color(0, 0, 0, 0)
	edge.border_color = Kit.LINE
	edge.border_width_left = 1
	edge.content_margin_left = _s(16)
	side.add_theme_stylebox_override("panel", edge)
	side.custom_minimum_size.x = _s(340)
	side.add_child(_robot_detail(_roster[index]))
	split.add_child(side)
	return _page("SQUAD", split)


## Mugshot, name, hull — and the gear strip, which is what the roster is for.
## Without it the list says who is in the squad; with it the list says what the
## squad is carrying, which is the question you open this page to answer.
func _squad_chip(r: SoldierRecord, lit: bool) -> Control:
	var f := _cat.chassis_def(r.chassis_id)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel",
		Kit.box(Kit.BRIGHT if lit else Kit.FAINT, Kit.PANEL, 1, _s(7)))
	chip.custom_minimum_size.x = _s(228)
	var col := Kit.vbox(_s(5))
	chip.add_child(col)

	var top := Kit.hbox(_s(8))
	top.add_child(Kit.icon(Icons.chassis(f, "m"), Kit.BRIGHT, Vector2(_s(44), _s(44)), true))
	var who := Kit.vbox(_s(1))
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(Kit.label(r.display_name, Kit.BRIGHT, _s(20), true))
	who.add_child(Kit.label("%s - %d HP" % [Kit.frame_word(f).to_upper(), r.max_health],
		Kit.DIM, _s(Kit.SMALL)))
	top.add_child(who)
	top.add_child(Kit.label("READY", Kit.BRIGHT, _s(Kit.SMALL)))
	col.add_child(top)

	var strip := Kit.hbox(_s(3))
	if f.weapon_slots == 0 and f.built_in != "":
		var b := PanelContainer.new()
		b.add_theme_stylebox_override("panel", Kit.box(Kit.LINE, Kit.PANEL, 1, _s(2)))
		b.add_child(Kit.icon(Icons.built_in(f.built_in, "s"), Kit.BRIGHT,
			Vector2(_s(24), _s(24)), true))
		strip.add_child(b)
	for id in r.weapon_ids:
		strip.add_child(_gear_mini(_cat.item(id)))
	for i in f.equipment_slots:
		var eq: ItemDefinition = _cat.item(r.equipment_ids[i]) if i < r.equipment_ids.size() else null
		strip.add_child(_gear_mini(eq, 26.0))
	for i in f.module_slots:
		var md: ItemDefinition = _cat.item(r.module_ids[i]) if i < r.module_ids.size() else null
		strip.add_child(_gear_mini(md, 26.0))
	col.add_child(strip)
	return chip


func _robot_detail(r: SoldierRecord) -> Control:
	var f := _cat.chassis_def(r.chassis_id)
	var col := Kit.vbox(_s(7))
	var head := Kit.hbox(_s(12))
	head.add_child(Kit.icon(Icons.chassis(f, "l"), Kit.BRIGHT, Vector2(_s(76), _s(76)), true))
	var who := Kit.vbox(_s(2))
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(Kit.label(r.display_name, Kit.BRIGHT, _s(26), true))
	# The frame's name alone. Its class badges live on the Factory card, where
	# you are choosing between frames; here you already own this one and the
	# tags were three words of furniture above the thing you came to read.
	var line := Kit.hbox(_s(6))
	line.add_child(Kit.label(Kit.frame_word(f).to_upper(), Kit.DIM, _s(Kit.BODY)))
	line.add_child(Kit.chevrons(r.rank))
	who.add_child(line)
	who.add_child(Kit.label("%d KILLS - %d OPS" % [r.confirmed_kills, r.missions_survived],
		Kit.DIM, _s(Kit.SMALL)))
	head.add_child(who)
	col.add_child(head)

	col.add_child(Kit.label("STATS", Kit.DIM, _s(Kit.BODY), true))
	# Base from the frame, final from the record. The white part of each bar is
	# the difference, which is what the modules bought — no attribution text,
	# the module tiles are right underneath.
	col.add_child(_bar("HULL", f.base_health, r.max_health, HULL_MAX, str(r.max_health), 70.0, 76.0))
	var base_mps: float = float(SPEEDS.get(f.id, 6.0))
	var mps: float = base_mps * r.effective_speed
	col.add_child(_bar("SPEED", base_mps, mps, SPEED_MAX, "%.1f" % mps, 70.0, 76.0))
	col.add_child(_bar("SENSOR", f.base_sensor_range, r.effective_sensor_range, SENSOR_MAX,
		"%.0f M" % r.effective_sensor_range, 70.0, 76.0))
	col.add_child(_bar("ACCURACY", f.base_accuracy * 100.0, r.effective_accuracy * 100.0,
		100.0, "%.0f%%" % (r.effective_accuracy * 100.0), 70.0, 76.0))
	if r.effective_signal_resistance_bonus > 0.0:
		var cut: float = 1.0 - 1.0 / (1.0 + r.effective_signal_resistance_bonus)
		col.add_child(_bar("JAM RES", 0.0, cut * 100.0, 100.0, "-%.0f%%" % (cut * 100.0), 70.0, 76.0))

	# POSITIVES ONLY. Nothing says NO SUPPRESSIVE FIRE.
	var extras: Array = []
	if r.effective_suppressive:
		extras.append("SUPPRESSIVE FIRE")
	if r.effective_self_revive > 0.0:
		extras.append("SELF-REVIVE %.0f S" % r.effective_self_revive)
	if not extras.is_empty():
		col.add_child(Kit.label(" - ".join(extras), Kit.BRIGHT, _s(Kit.BODY), true))

	for group in [["WEAPONS", r.weapon_ids, f.weapon_slots],
			["EQUIPMENT", r.equipment_ids, f.equipment_slots],
			["MODULES", r.module_ids, f.module_slots]]:
		var slots: int = int(group[2])
		if slots == 0:
			continue
		col.add_child(Kit.label(str(group[0]), Kit.DIM, _s(Kit.BODY), true))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", _s(5))
		row.add_theme_constant_override("v_separation", _s(5))
		var ids: Array = group[1]
		for i in slots:
			var it: ItemDefinition = _cat.item(ids[i]) if i < ids.size() else null
			var tile := PanelContainer.new()
			tile.add_theme_stylebox_override("panel",
				Kit.box(Kit.BRIGHT if it != null else Kit.FAINT, Kit.PANEL, 1, _s(5)))
			var inner := Kit.hbox(_s(5))
			if it == null:
				# An empty slot says it is empty, not nothing at all: a gap in
				# the row reads as a missing icon rather than as a free slot.
				inner.add_child(Kit.label("EMPTY", Kit.DIM, _s(Kit.SMALL)))
			else:
				inner.add_child(Kit.icon(Icons.item(it, "s"), Kit.BRIGHT,
					Vector2(_s(26), _s(26)), true))
				inner.add_child(Kit.label(it.short_label().to_upper(), Kit.BRIGHT, _s(Kit.SMALL)))
			tile.add_child(inner)
			row.add_child(tile)
		col.add_child(row)

	col.add_child(_vfill())
	col.add_child(Kit.label("CLICK A SLOT FOR WHAT FITS IT", Kit.DIM, _s(Kit.SMALL)))
	return col
