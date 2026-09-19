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


static func ids() -> Array:
	var out: Array = []
	for n in nodes():
		out.append(n["id"])
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
