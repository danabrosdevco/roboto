extends PlayerEquipment

# BY PATH, NOT class_name: a brand-new class_name is not resolvable until the
# editor rescans, and that rescan must not be run with the editor open. The
# scene references this script by path, which needs no registration.

# ─────────────────────────────────────────────
# THE DESIGNATOR — telling the squad to spend ITS OWN kit, at a point.
#
# WHAT PROBLEM IT SOLVES. The squad will use smoke, mines and drone packs on its
# own judgement, but judgement is not command: the moment you want a cloud is
# the moment you have decided to cross a street, and no `can_use()` rule can
# know that. The missing verb was "there".
#
# WHY IT IS A TOOL AND NOT A KEY. The command wheel it replaces carried five
# entries that were really two questions — WHERE and HOW — and the crosshair
# already answers WHERE. A wheel for equipment would repeat that mistake with
# more entries. A held object instead: it has a screen that says what the squad
# is actually carrying, so the vocabulary is discovered by picking it up rather
# than memorised from a menu.
#
# WHY IT COSTS NO SUPPLY. An earlier design had the player carry smoke so the
# squad would throw smoke, which was rejected flat: a squad capability must not
# depend on the commander's shopping. So this is a BUILT-IN, like the repair
# tool on key 3 — never bought, never fitted, always there.
#
# THE INTERACTION, and the reasoning behind each number:
#
#   RELOAD CYCLES THE MODE. A bind everyone already has, physical, and it cannot
#   be fat-fingered mid-firefight the way a scroll wheel can. The model has a
#   visible button under the thumb for exactly this.
#
#   HOLD TO DESIGNATE, with a LIVE preview. The mark follows the crosshair while
#   held, so you scrub onto the right spot and release when it is right. That
#   preview — not the duration — is what makes this usable at range.
#
#   1.2 SECONDS, not the 2.5-3 first sketched. `T` is instant; twenty times
#   slower is unusable under fire, and a verb that fails exactly when you need it
#   is a verb nobody learns. Long enough to be deliberate, short enough to use
#   while being shot at.
#
#   SOME MODES FIRE ON THE PRESS. A Drone Carrier Pack releases units that climb
#   and pick their own target, so pointing at a spot for them is ceremony. Those
#   modes (`ordered_at_point = false` on the AI scene) are a confirm, and are the
#   one order you can give instantly — which fits the pack being the emergency
#   answer to armour.
#
# IT MUST SAY WHY IT REFUSES. Nobody carrying it, everyone out, out of throw
# range, no squad in command. A key that does nothing is worse than a key that
# says no, and the reasons come back from the robots that were actually asked.
# ─────────────────────────────────────────────

## The baked line art for the weapon bar's chip. By path rather than as an
## ext_resource on the scene: the PNG has no .import until the editor next
## scans, and a scene that hard-references an unimported texture fails to load
## outright — which would take the whole tool with it. Icons._load returns null
## for a file that is not there yet, so the chip is simply blank until it is.
const _Icons := preload("res://Character/hud/icons/icons.gd")

## What the designator pulls the view in to while the aim button is held.
##
## It is a sighting instrument, so it aims like one. The reason the hold has a
## live preview at all is that picking a spot at range is the hard part, and at
## the default field of view a doorway sixty metres away is a few pixels wide.
## Gentler than a rifle's: this is for reading ground, not for shooting.
@export var zoom_fov: float = 48.0

## Seconds of hold before the mark is committed.
@export var designate_seconds: float = 1.2
## Seconds before the same mode can be ordered again. Not a reload — the
## robots have their own cooldowns — but a guard against a held button firing
## the same order on consecutive frames.
@export var repeat_delay: float = 1.0
## How often the dial re-reads the squad while the tool is in hand. See tick().
@export var refresh_interval: float = 0.3
## The readout on the slab. Left null and the tool still works; you just cannot
## see what mode you are on without the HUD.
@export var screen: MeshInstance3D
## A little kick as the mark commits, so the release is felt and not only seen.
@export var commit_sound: AudioStreamPlayer3D

## Where the preview and the order agree the mark is. Read by the screen.
var mark: Vector3 = Vector3.ZERO
## 0..1 while the trigger is held on a point mode.
var charge: float = 0.0
var _hold_t: float = 0.0
var _repeat_t: float = 0.0
## The squad's kit, as the commander reports it. Rebuilt when the tool comes up
## and after every order, never per frame — it instantiates to read
## `ordered_at_point`.
var _modes: Array = []
var _mode: int = 0
var _refresh_t: float = 0.0
var _commander: Node = null

signal modes_changed
signal charge_changed


func _on_initialize() -> void:
	# IN CODE RATHER THAN THE SCENE, deliberately. These five are what make it a
	# built-in: it is not ordnance, so nothing is consumed, nothing reverts, and
	# it must come up when the squad is carrying nothing at all — that empty
	# screen is how the player learns the shop sells smoke.
	slot = Slot.EQUIPMENT
	consumes_charge = false
	reverts_when_empty = false
	equippable_when_empty = true
	_commander = _find_commander()
	_wire_screen()
	# A BUILT-IN HAS NO CATALOGUE ENTRY to hang an icon on, which is why key 2
	# drew an empty chip. WeaponBar._icon_for checks the held item's own `icon`
	# before it goes looking in the catalogue, so filling it in here is the whole
	# fix. Only if nothing authored one.
	if icon == null:
		icon = _Icons.built_in("designator", "m")


## Put the live readout onto the slab's screen.
##
## THE MATERIAL IS DUPLICATED FIRST. designator_model.tscn declares its screen
## material as a sub-resource, which is shared — writing a texture into the
## original would put this tool's readout on every other instance of that model,
## the mock-up shots included.
##
## Both maps get the texture, not just albedo: the material is emissive so the
## screen is lit from within, and an emission that is a flat colour while the
## albedo is a readout glows a uniform green over the top of the text.
func _wire_screen() -> void:
	if screen == null:
		return
	var readout := screen.get_node_or_null("../Readout") as SubViewport
	if readout == null:
		# EVERY EARLY RETURN WARNS. A designator with a dead screen still
		# functions — the HUD readout says the same things — so this must not be
		# fatal, but silently holding a blank slab is the kind of bug that gets
		# filed as "the designator does nothing".
		push_warning("%s: no Readout SubViewport beside the screen; the slab will be blank." % display_name)
		return
	readout.tool_node = self
	var mat := screen.material_override
	if mat == null:
		push_warning("%s: the screen mesh has no material_override to draw into." % display_name)
		return
	var own := mat.duplicate() as BaseMaterial3D
	if own == null:
		return
	var tex := readout.get_texture()
	own.albedo_texture = tex
	own.emission_texture = tex
	# MULTIPLY, NOT ADD, and this is the whole difference between a screen and a
	# green slab. The operator defaults to ADD, which adds the material's base
	# emission colour across the ENTIRE surface before the texture is considered
	# — so the readout's near-black ground glowed as brightly as its text and the
	# screen came out a solid bright green with the words barely legible on it.
	# Multiplied, the ground stays dark and only the lit pixels emit.
	own.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	# ...and with the operator multiplying, the colour has to be white or it
	# tints the readout a second time on top of the colours it already drew.
	own.emission = Color.WHITE
	# AND BRIGHT ENOUGH TO READ IN A LIT ROOM. The model authors 0.9, which is
	# right for a panel photographed against a dark background and nowhere near
	# enough in a depot with the ceiling lights on — through the CRT filter the
	# readout was there and simply could not be made out. This is a screen, so it
	# should be the brightest thing on the tool by a distance.
	own.emission_energy_multiplier = 3.0
	own.albedo_color = Color.WHITE
	screen.material_override = own


## Always. A designator with nothing to designate still has to come up and say
## so — see the note above.
func can_equip() -> bool:
	return true


func has_charge() -> bool:
	return true


func _on_equip() -> void:
	_hold_t = 0.0
	charge = 0.0
	refresh_modes()


func _on_unequip() -> void:
	# A half-finished hold does not survive putting the tool away. Carrying the
	# accumulated time across would make the NEXT draw fire an order on the
	# first frame the trigger happened to be down, and would leave a ghost on the
	# ground for an order nobody gave.
	_hold_t = 0.0
	charge = 0.0
	_hide_ghost()
	charge_changed.emit()


# ─────────────────────────────────────────────
# MODES — what the squad is carrying
# ─────────────────────────────────────────────
func refresh_modes() -> void:
	var was: StringName = current_mode_id()
	_modes = []
	if _commander == null:
		_commander = _find_commander()
	if _commander != null and _commander.has_method("command_modes"):
		_modes = _commander.command_modes()
	# Keep the player on the mode they had chosen if it is still there. A squad
	# throwing its last canister must not silently move the selection under the
	# player's thumb to something else they then order by accident.
	_mode = 0
	if was != &"":
		for i in _modes.size():
			if _modes[i]["item_id"] == was:
				_mode = i
				break
	modes_changed.emit()


func has_modes() -> bool:
	return not _modes.is_empty()


func current_mode() -> Dictionary:
	if _mode < 0 or _mode >= _modes.size():
		return {}
	return _modes[_mode]


func current_mode_id() -> StringName:
	var m := current_mode()
	return m.get("item_id", &"") if not m.is_empty() else &""


## What the screen prints. One place, so the slab and the HUD never disagree.
func mode_label() -> String:
	var m := current_mode()
	if m.is_empty():
		# IT USED TO SAY "NO KIT", which was right when the dial was equipment
		# only. ADVANCE and FOLLOW ME are always on it now, so the one way it
		# can be empty is having nobody to command — in the depot, or after the
		# squad is wiped.
		return "NO SQUAD"
	return str(m["label"]).to_upper()


## How many throws the squad has LEFT, across everyone carrying one. Distinct
## from mode_holders(), which is how many can answer this instant.
func mode_remaining() -> int:
	var m := current_mode()
	return int(m.get("remaining", 0)) if not m.is_empty() else 0


func mode_holders() -> int:
	var m := current_mode()
	return int(m.get("holders", 0)) if not m.is_empty() else 0


## Does this order need the hold, or does it go on the press?
##
## Spending a finite canister deserves a second and a half of deliberation.
## Moving the squad does not — T has always been instant, and routing the same
## order through a nicer interface must not make it slower.
func mode_deliberate() -> bool:
	var m := current_mode()
	return bool(m.get("deliberate", true)) if not m.is_empty() else true


## The one line of words under the name. Here rather than in the screen so the
## slab and the HUD readout can never disagree about what the tool is doing.
##
## It says what the ORDER DOES, not which button to press. The control legend
## that used to live here was read once, on the first draw, and was noise on
## every one after — this line changes with the state, so it earns its place.
func mode_status() -> String:
	if not has_modes():
		return "NOBODY IN COMMAND"
	if is_queued():
		return "STANDING BY"
	match current_mode_id():
		&"@advance":
			return "GO THERE AND HOLD"
		&"@follow":
			return "FORM ON YOU"
	if mode_holders() > 0:
		return "%d CAN ANSWER" % mode_holders()
	# NOBODY RIGHT NOW is not the same as NOTHING LEFT, and the player does a
	# different thing about each: wait a moment, or stop planning around it.
	return "NONE LEFT" if mode_remaining() <= 0 else "RELOADING"


## True for the two movement verbs, which are not spent and so have no count.
func mode_is_movement() -> bool:
	var id_value := current_mode_id()
	return id_value == &"@advance" or id_value == &"@follow"


func mode_wants_point() -> bool:
	var m := current_mode()
	return bool(m.get("wants_point", true)) if not m.is_empty() else true


func mode_count() -> int:
	return _modes.size()


## True when THIS mode's order is being held by the commander because everyone
## who carries it is between uses. The screen says so rather than showing a
## holder count of zero, which would read as "you have none".
func is_queued() -> bool:
	if _commander == null or not _commander.has_method("queued_item_id"):
		return false
	var waiting: StringName = _commander.queued_item_id()
	return waiting != &"" and waiting == current_mode_id()


func mode_index() -> int:
	return _mode


func reload_pressed() -> void:
	# Re-read before cycling: a squadmate may have spent their last one since
	# the tool came up, and cycling onto a mode that no longer exists would
	# leave the screen showing kit nobody has.
	refresh_modes()
	if _modes.size() <= 1:
		# EVERY REFUSAL SAYS WHY. One mode and a cycle key that appears to do
		# nothing is the exact shape of a bug report.
		denied.emit("%s: NOTHING TO CYCLE TO" % display_name.to_upper())
		return
	_mode = (_mode + 1) % _modes.size()
	_hold_t = 0.0
	charge = 0.0
	modes_changed.emit()
	charge_changed.emit()


# ─────────────────────────────────────────────
# DESIGNATING
# ─────────────────────────────────────────────
func primary_pressed() -> void:
	if is_raising():
		return
	if not _ready_to_order():
		return
	# IT GOES NOW only for the two MOVEMENT orders, which have always been
	# instant on T and must not get slower for being routed through a nicer
	# interface. Everything the squad SPENDS charges down first, whether or not
	# it is aimed — releasing two Divers is as committing as throwing a cloud,
	# and the bar is the only thing that says so.
	if not mode_deliberate():
		_commit(mode_wants_point())
		return
	_hold_t = 0.0
	if mode_wants_point():
		mark = _aim_mark()
		_show_ghost()


func primary_held(delta: float) -> void:
	# NOT GATED ON wants_point ANY MORE, and that gate was a real bug rather than
	# a design: a confirm mode charged nothing, reached no commit, and so could
	# NEVER BE ORDERED AT ALL. The Drone Carrier Pack and the Hatchling Charge
	# were on the dial, selectable, and inert — you held the trigger and nothing
	# ever happened. Only the AIM is conditional on there being a point; the hold
	# itself belongs to anything that spends something.
	if is_raising() or not mode_deliberate():
		return
	if not _ready_to_order():
		return
	if mode_wants_point():
		# The mark tracks the crosshair the whole way. THIS is what makes the
		# tool usable at range; the timer only stops it being a tap. And the
		# ghost follows from the first frame, which makes the hold an aim rather
		# than a wait.
		mark = _aim_mark()
		_show_ghost()
	_hold_t += delta
	var next: float = clampf(_hold_t / maxf(designate_seconds, 0.01), 0.0, 1.0)
	if not is_equal_approx(next, charge):
		charge = next
		charge_changed.emit()
	if _hold_t >= designate_seconds:
		_commit(mode_wants_point())


func primary_released() -> void:
	_hide_ghost()
	# Released short. No order, no complaint — letting go early is how you
	# ABORT, so saying "refused" here would punish the player for changing
	# their mind.
	_hold_t = 0.0
	if charge != 0.0:
		charge = 0.0
		charge_changed.emit()


func tick(delta: float) -> void:
	if _repeat_t > 0.0:
		_repeat_t = maxf(0.0, _repeat_t - delta)
	# A LIVE READOUT.
	#
	# The dial used to be read only on draw, on cycle and on commit, so the
	# holder count was a SNAPSHOT: order smoke, and the screen said RELOADING
	# from that instant until you happened to cycle — long after the cooldown
	# had passed and the squad could answer again. A number on a screen you are
	# holding has to be the number now.
	#
	# Cheap enough to do on a timer: the commander keeps the static half of each
	# entry per squad, so this is a walk over the squad's slots with nothing
	# instantiated.
	_refresh_t += delta
	if _refresh_t >= refresh_interval:
		_refresh_t = 0.0
		refresh_modes()


## Cheap pre-checks, said out loud. Run on the press rather than at commit so
## the player is told before spending a second and a half holding a button.
func _ready_to_order() -> bool:
	if _repeat_t > 0.0:
		return false
	if _modes.is_empty():
		# The dial is only ever empty with no squad in command: the two movement
		# orders are always on it, so "carries no kit" is no longer the reason.
		denied.emit("%s: NO SQUAD IN COMMAND" % display_name.to_upper())
		return false
	# IT NO LONGER REFUSES ON THE HOLDER COUNT.
	#
	# Holders is who can answer THIS INSTANT, and it is zero both when the squad
	# is out and when everyone who carries one is simply between uses — which,
	# with the squad's own spacing rule, is most of the ten seconds after anyone
	# threw anything. Refusing here called both of those "NONE LEFT", so a squad
	# with three canisters left read as a squad with none, and the designator
	# read as a tool with ammo.
	#
	# The commander already tells the three apart properly and HOLDS the order
	# when it is only timing (see _attempt_equipment_order). So the press goes
	# through and the right thing happens, with the right words.
	return true


func _commit(use_point: bool) -> void:
	var m := current_mode()
	if m.is_empty():
		return
	if _commander == null or not _commander.has_method("issue_dial_order"):
		# Not survivable silently: the tool is in the player's hands and the
		# thing it talks to is missing, which is a wiring fault and not a
		# situation the player can do anything about.
		push_warning("%s: no SquadCommander, so nothing can be ordered." % display_name)
		denied.emit("%s: NO COMMAND LINK" % display_name.to_upper())
		return
	if use_point:
		mark = _aim_mark()
	# The commander emits the toast and the refusal reason either way, so this
	# does not report success itself — one voice for one event.
	# ONE ENTRY POINT for the whole dial. The commander sorts an equipment order
	# from a movement one; the tool deliberately does not know the difference,
	# so adding a verb later is a change in one file.
	var sent: bool = _commander.issue_dial_order(m, mark)
	_hold_t = 0.0
	charge = 0.0
	charge_changed.emit()
	_repeat_t = repeat_delay
	# The real marker replaces the ghost; both at once would draw two.
	_hide_ghost()
	if sent:
		if commit_sound != null:
			commit_sound.play()
		used.emit()
	# Holders have changed whether it worked or not — a refusal for "none left"
	# still means the count on screen was stale.
	refresh_modes()


## The same ray the orders use, asked of the commander. Computing it here from
## our own camera would put the preview somewhere the order then does not land
## the moment either side changed its ray length or its mask.
## Put the ghost down, or move it. Only for a mode that lands somewhere: a
## confirm order has no point to show, and a marker for one would sit on ground
## the order has nothing to do with.
func _show_ghost() -> void:
	if _commander == null or not _commander.has_method("show_mark_preview"):
		return
	if not mode_wants_point():
		return
	_commander.show_mark_preview(mark, mode_label())


func _hide_ghost() -> void:
	if _commander != null and _commander.has_method("clear_mark_preview"):
		_commander.clear_mark_preview()


func _aim_mark() -> Vector3:
	if _commander != null and _commander.has_method("aim_mark"):
		return _commander.aim_mark()
	return aim_point(200.0)


func _find_commander() -> Node:
	if player == null:
		return null
	for child in player.get_children():
		if child is SquadCommander:
			return child
	return null


# ─────────────────────────────────────────────
# HUD
# ─────────────────────────────────────────────
## Aimed like a sight. PlayerEquipment returns 0 for "cannot be aimed", which
## is what every tool but the launcher does — this one has a reason not to.
func ads_fov() -> float:
	return zoom_fov


## COUNT, not COOLDOWN: the number that decides whether to press this is how
## many robots can answer, and the hold progress is on the tool's own screen
## where the player is already looking while they hold it.
func get_readout() -> Readout:
	var r := Readout.new(ReadoutMode.COUNT)
	r.label = mode_label()
	r.primary = mode_holders()
	r.secondary = mode_count()
	r.fraction = charge
	r.warn = mode_holders() <= 0
	return r
