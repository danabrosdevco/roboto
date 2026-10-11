extends RefCounted

# ─────────────────────────────────────────────
# ROSTER ART — the picture of what a robot IS and what it CARRIES.
#
# The roster lists robots by callsign, and a callsign says nothing about the
# machine: teams are arranged by hand, so ROVER-3 can sit under SUPPORT and
# MECHANIC-1 under INFANTRY, and both read as mistakes rather than choices.
#
# These are the SAME baked icons the factory, the armoury and the debrief use
# (res://icons/chassis and res://icons/items, via Icons). A letter in the
# roster and a picture everywhere else for the same machine is two vocabularies
# for one thing, and the letter is the one nobody can read at a glance.
#
# Both lookups go through what the robot actually is at runtime rather than
# anything authored per level: the frame comes off KillKinds (the `chassis_id`
# meta the spawner stamps, or the scene name), and the weapon is matched back
# to its catalogue entry by the AI scene it was built from. An icon that has
# not been baked comes back null and the row simply has a gap — never a crash,
# and never a wrong picture.
# ─────────────────────────────────────────────

const _Kinds := preload("res://Campaign/kill_kinds.gd")
const _Icons := preload("res://Character/hud/icons/icons.gd")

# Catalogue lookups walk every item, so the answers are kept. Keyed by the AI
# weapon scene's path, which is what a robot in the field can actually be
# asked for.
static var _by_ai_scene: Dictionary = {}
static var _catalogue_seen: ItemCatalogue = null


## The frame a robot is built on, as its baked icon (40x40 line art).
static func frame_icon(body: Node) -> Texture2D:
	return _Icons.chassis(_frame_of(body), "s")


## What it is holding, as the catalogue's icon for that weapon. Falls back to
## the frame's built-in tool, because a Mechanic carrying nothing is still
## carrying a welder.
static func weapon_icon(body: Node) -> Texture2D:
	if body == null:
		return null
	var cat := _catalogue()
	if cat == null:
		return null
	var gun = body.get("weapon")
	if gun != null and is_instance_valid(gun):
		var item := _item_for_scene(cat, str((gun as Node).scene_file_path))
		if item != null:
			return _Icons.item(item, "s")
	# No weapon node: a frame that works with something built into its body.
	var frame := _frame_of(body)
	if frame == null:
		return null
	if frame.starting_weapon_id != &"":
		return _Icons.item(cat.item(frame.starting_weapon_id), "s")
	# Its tool, then. A Mechanic carrying nothing is still carrying a welder,
	# and an empty hand in a row where everyone else shows a rifle reads as a
	# robot that has lost its gun rather than one that never had one.
	return _Icons.built_in(frame.built_in, "s")


static func _frame_of(body: Node) -> ChassisDefinition:
	if body == null:
		return null
	return _Kinds.frame_of(_Kinds.kind_of(body))


# The catalogue is the only place that knows an AI weapon scene belongs to an
# item, so the map is built from it once and reused.
static func _item_for_scene(cat: ItemCatalogue, scene_path: String) -> ItemDefinition:
	if scene_path == "":
		return null
	if cat != _catalogue_seen:
		_catalogue_seen = cat
		_by_ai_scene.clear()
		for item in cat.items:
			if item != null and item.ai_scene != null:
				_by_ai_scene[item.ai_scene.resource_path] = item
	return _by_ai_scene.get(scene_path)


## A catalogue entry by its id, or null when there is no campaign in the tree.
##
## Public and living here rather than being asked of the catalogue directly,
## because reaching the catalogue at all means the "campaign" group walk below —
## and a piece of HUD that hard-wires its own copy of that walk is one more
## place to fix when the wiring changes. The designator's screen uses it to turn
## a squadmate's equipment slot into an icon.
static func item_by_id(item_id: StringName) -> ItemDefinition:
	if item_id == &"":
		return null
	var cat := _catalogue()
	return cat.item(item_id) if cat != null else null


static func _catalogue() -> ItemCatalogue:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var campaign := tree.get_first_node_in_group("campaign")
	if campaign == null or not ("catalogue" in campaign):
		return null
	return campaign.catalogue as ItemCatalogue
