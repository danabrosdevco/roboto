extends RefCounted

# ─────────────────────────────────────────────
# SOFTWARE TREE — the player's upgrades, as programs.
#
# Weapons, gear, modules and frames are HARDWARE, bought with resources.
# Software is the drone's own code, and it runs on COMPUTE: an installed program
# holds its compute, exactly as a seat does. So every point of compute is one
# question — another robot in the field, or a better mind commanding them —
# and because installing only HOLDS compute, uninstalling gives all of it back
# at any time. Respec freely; the choice is what you run right now.
#
# THE SHAPE. Four branches, three tiers each:
#   tier 1   1 compute   three programs per branch
#   tier 2   2 compute   two
#   tier 3   3 compute   one
# A tier opens once the branch has a program installed in the tier below, and
# a program that another one in the branch stands on cannot be uninstalled
# until that one is.
#
# BLANK FOR NOW. Every program is a placeholder ("UNWRITTEN"): the costs, the
# gating and the refunds are real, the effects are not written yet. Fill in a
# title and an `about` and give it an effect; keep the id, or a save that has
# it installed gets its compute back on load (Campaign.release_unknown_software).
# ─────────────────────────────────────────────

const BRANCHES := [
	{"id": &"command", "title": "COMMAND", "about": "How the squad takes orders."},
	{"id": &"signal", "title": "SIGNAL", "about": "The link between you and them."},
	{"id": &"combat", "title": "COMBAT", "about": "You, in the fight."},
	{"id": &"fabrication", "title": "FABRICATION", "about": "What the base can make."},
]

## Compute a program holds, by tier.
const TIER_COST := {1: 1, 2: 2, 3: 3}
## Programs per tier in each branch.
const TIER_SLOTS := {1: 3, 2: 2, 3: 1}

## Titles and descriptions as they get written: id -> {"title", "about"}.
## Anything not in here is a blank placeholder.
const WRITTEN := {}


## Every program, branch by branch, tier by tier: {id, branch, tier, cost,
## title, about}.
static func nodes() -> Array:
	var out: Array = []
	for branch in BRANCHES:
		for tier in [1, 2, 3]:
			for i in TIER_SLOTS[tier]:
				var id := StringName("%s_%d%s" % [branch["id"], tier, "abc"[i]])
				var words: Dictionary = WRITTEN.get(id, {})
				out.append({
					"id": id,
					"branch": branch["id"],
					"tier": tier,
					"cost": TIER_COST[tier],
					"title": words.get("title", "UNWRITTEN"),
					"about": words.get("about", ""),
				})
	return out


## Every id the tree knows: branch programs AND the player's own carry list.
## Campaign.release_unknown_software() refunds anything installed that is not
## in here, so leaving the carry ids out would quietly unload your gun on the
## next load.
static func ids() -> Array:
	var out: Array = []
	for n in nodes():
		out.append(n["id"])
	out.append_array(carry_ids())
	return out


static func node(id: StringName) -> Dictionary:
	for n in nodes():
		if n["id"] == id:
			return n
	return {}


static func branch_title(branch_id: StringName) -> String:
	for b in BRANCHES:
		if b["id"] == branch_id:
			return b["title"]
	return String(branch_id).to_upper()


## Installed programs in one branch at one tier.
static func installed_at(state: CampaignState, branch_id: StringName, tier: int) -> int:
	var n := 0
	for other in nodes():
		if other["branch"] == branch_id and other["tier"] == tier and state.is_installed(other["id"]):
			n += 1
	return n


## Why `id` cannot be installed right now, in words, or "" if it can.
static func install_block(state: CampaignState, id: StringName) -> String:
	var n := node(id)
	if n.is_empty():
		return "NO SUCH PROGRAM"
	if state.is_installed(id):
		return "INSTALLED"
	if n["tier"] > 1 and installed_at(state, n["branch"], n["tier"] - 1) == 0:
		return "NEEDS A TIER %d %s PROGRAM FIRST" % [n["tier"] - 1, branch_title(n["branch"])]
	if state.compute_free() < n["cost"]:
		return "NEEDS %d COMPUTE" % n["cost"]
	return ""


## Why `id` cannot be uninstalled right now, or "" if it can: the last program
## of its tier cannot go while the tier above it in the branch has one.
static func uninstall_block(state: CampaignState, id: StringName) -> String:
	var n := node(id)
	if n.is_empty() or not state.is_installed(id):
		return "NOT INSTALLED"
	if n["tier"] < 3 and installed_at(state, n["branch"], n["tier"] + 1) > 0 \
			and installed_at(state, n["branch"], n["tier"]) == 1:
		return "UNINSTALL THE TIER %d %s PROGRAM FIRST" % [n["tier"] + 1, branch_title(n["branch"])]
	return ""


static func install(state: CampaignState, id: StringName) -> bool:
	if install_block(state, id) != "":
		return false
	return state.install_software(id, node(id)["cost"])


static func uninstall(state: CampaignState, id: StringName) -> bool:
	if uninstall_block(state, id) != "":
		return false
	return state.uninstall_software(id)


# ─────────────────────────────────────────────
# MEMORY — THE PLAYER'S OWN WEAPONS AND EQUIPMENT.
#
# A SEPARATE SPACE FROM THE BRANCHES. A branch is a build you commit to; a
# rifle is not. These sit beside the branches on the MEMORY screen rather than
# inside them, which is also why they do not care which set of branches the
# tree ends up with.
#
# ONE COST, NOT TWO. Loading a thing HOLDS its compute for as long as it is
# loaded, and unloading returns all of it. There is no separate unlock price:
# the holding IS the price, which is the same rule the branches already run on
# and the reason the screen is called MEMORY.
#
# LOADED IS NOT CARRIED. The player has one weapon slot and two equipment
# slots; what is loaded is what you may CHOOSE from, and choosing is free and
# reversible at base. See CampaignState.carry_weapon().
#
# ISSUED COSTS NOTHING AND NEVER LEAVES. The Ancient Rifle and the Frag are
# cost 0: they are never written to the ledger at all (install_software
# refuses a zero cost, deliberately), so they cannot be unloaded and they
# cannot be lost to an Argus requisition. A player who spends nothing here
# still has a gun and still has something to throw.
#
# NAMES AND DESCRIPTIONS ARE THE CATALOGUE'S, not copies kept here. A second
# description of the same weapon is how two descriptions of the same weapon
# end up disagreeing — the page reads ItemDefinition.
#
# NOT IN THE LIST, ON PURPOSE:
#   carbine / dmr   weapon_damage 0, ammo_type "", in_shop false, and both
#                   point player_scene at m4_hud_weapon.tscn. They are stubs
#                   wearing the Ancient Rifle's gun, so loading one would
#                   charge compute for the free rifle's behaviour.
#   scanner         one charge, one use, and nothing on screen to read it on.
# ─────────────────────────────────────────────

const CARRY_WEAPON := &"weapon"
const CARRY_KIT := &"kit"

## item is the catalogue id; id is what the ledger holds. Costs are the same
## 1/2/3 bands as the branches, so there is one scale on the screen and not two.
const CARRY := [
	{"id": &"carry_m4", "item": &"m4", "kind": CARRY_WEAPON, "cost": 0},
	{"id": &"carry_bolt", "item": &"bolt", "kind": CARRY_WEAPON, "cost": 1},
	{"id": &"carry_repair_lance", "item": &"repair_lance", "kind": CARRY_WEAPON, "cost": 1},
	{"id": &"carry_squad_auto", "item": &"squad_auto", "kind": CARRY_WEAPON, "cost": 2},
	{"id": &"carry_cluster_launcher", "item": &"cluster_launcher", "kind": CARRY_WEAPON, "cost": 2},
	{"id": &"carry_frag", "item": &"frag", "kind": CARRY_KIT, "cost": 0},
	{"id": &"carry_smoke", "item": &"smoke", "kind": CARRY_KIT, "cost": 1},
	{"id": &"carry_emp", "item": &"emp", "kind": CARRY_KIT, "cost": 2},
	{"id": &"carry_mine_heavy", "item": &"mine_heavy", "kind": CARRY_KIT, "cost": 2},
	{"id": &"carry_mine_cluster", "item": &"mine_cluster", "kind": CARRY_KIT, "cost": 2},
	# The FILE is item_rocket.tres and the icon is rocket_m.png, but the id is
	# "recoilless". A lookup written from the filename finds nothing, quietly.
	{"id": &"carry_recoilless", "item": &"recoilless", "kind": CARRY_KIT, "cost": 3},
	{"id": &"carry_drone_pack", "item": &"drone_pack", "kind": CARRY_KIT, "cost": 3},
	{"id": &"carry_hatchling", "item": &"hatchling", "kind": CARRY_KIT, "cost": 3},
]


## The carry list, or just one kind of it (CARRY_WEAPON / CARRY_KIT).
static func carry(kind: StringName = &"") -> Array:
	var out: Array = []
	for entry in CARRY:
		if kind == &"" or entry["kind"] == kind:
			out.append(entry)
	return out


static func carry_ids() -> Array:
	var out: Array = []
	for entry in CARRY:
		out.append(entry["id"])
	return out


## The entry for a catalogue item id, or {} if that item is not carryable.
static func carry_entry(item_id: StringName) -> Dictionary:
	for entry in CARRY:
		if entry["item"] == item_id:
			return entry
	return {}


## Issued: costs nothing, always loaded, cannot be unloaded.
static func is_issued(item_id: StringName) -> bool:
	var entry := carry_entry(item_id)
	return not entry.is_empty() and int(entry["cost"]) <= 0


## Is this item in memory right now? Issued things always are, and they are
## never in the ledger — so this is the question to ask, not is_installed().
static func is_loaded(state: CampaignState, item_id: StringName) -> bool:
	var entry := carry_entry(item_id)
	if entry.is_empty():
		return false
	if int(entry["cost"]) <= 0:
		return true
	return state != null and state.is_installed(entry["id"])


## Why `item_id` cannot be loaded right now, in words, or "" if it can.
static func load_block(state: CampaignState, item_id: StringName) -> String:
	var entry := carry_entry(item_id)
	if entry.is_empty():
		return "NOT CARRYABLE"
	if is_loaded(state, item_id):
		return "LOADED"
	if state.compute_free() < int(entry["cost"]):
		return "NEEDS %d COMPUTE" % int(entry["cost"])
	return ""


## Why `item_id` cannot be unloaded, or "" if it can.
static func unload_block(state: CampaignState, item_id: StringName) -> String:
	var entry := carry_entry(item_id)
	if entry.is_empty():
		return "NOT CARRYABLE"
	if int(entry["cost"]) <= 0:
		return "ISSUED"
	if not state.is_installed(entry["id"]):
		return "NOT LOADED"
	return ""


static func load_item(state: CampaignState, item_id: StringName) -> bool:
	if load_block(state, item_id) != "":
		return false
	return state.install_software(carry_entry(item_id)["id"], int(carry_entry(item_id)["cost"]))


## Unloading also puts down anything you were carrying out of it — a gun you
## no longer own must not stay in your hands, and the weapon slot falls back
## to the issued rifle rather than to nothing.
static func unload_item(state: CampaignState, item_id: StringName) -> bool:
	if unload_block(state, item_id) != "":
		return false
	if not state.uninstall_software(carry_entry(item_id)["id"]):
		return false
	state.drop_player_item(item_id)
	return true


## Which of a kind the player may actually choose from: loaded, and present in
## the catalogue. Order is the CARRY list's, which is by cost.
static func loaded_items(state: CampaignState, kind: StringName = &"") -> Array:
	var out: Array = []
	if state == null or state.catalogue == null:
		return out
	for entry in carry(kind):
		if not is_loaded(state, entry["item"]):
			continue
		var item: ItemDefinition = state.catalogue.item(entry["item"])
		if item != null:
			out.append(item)
	return out
