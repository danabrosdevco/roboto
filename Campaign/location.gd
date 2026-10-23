extends Resource
class_name Location

# ─────────────────────────────────────────────
# A LOCATION — a place on the board, which is NOT the same thing as a mission.
#
# docs/briefs/CAMPAIGN_REWORK.md §2: "A LOCATION IS A THING. A MISSION IS
# SOMETHING YOU DO TO IT." The location owns the economy — what it pays, what
# compute it carries, how hard it is to take. The mission owns the fight.
#
# That split is the whole point of the rework. Today `reward_resources` on a
# MissionDefinition IS the economy, which means the only way to get paid is to
# do a mission again, and holding ground is worth nothing. A location pays for
# being HELD, every turn, whether or not you went anywhere near it.
#
# OWNERSHIP IS Enums.Factions, not an enum of its own. PLAYER, SWARM, HOME and
# ARGUS already exist there and already mean exactly this; a second vocabulary
# for the same four answers is how the two drift apart.
#
# RESISTANCE IS MEASURED, NEVER TYPED. It is the total enemy SUPPLY defending
# the place, read off the authored force by tools/measure_resistance.gd. Once
# force generation lands (§4) it is computed at deploy time and this field
# becomes the seed rather than the truth.
# ─────────────────────────────────────────────

@export var id: StringName = &""
@export var display_name: String = ""

## The operation fought over this ground. One today; §10 splits a place into
## ATTACK and DEFEND variants of itself, and then this becomes a pair.
@export var mission_id: StringName = &""

## THE DEFENCE OF THE SAME GROUND (Phase 5). One place, two operations — §10.
## Both resolve to this Location, so a defence is budgeted, paid and owned by
## exactly the same numbers as the attack that took it.
@export var defend_mission_id: StringName = &""

## Who holds it when the campaign opens. SWARM for everything in Act 1 — §3
## has what changes hands in Acts 2 and 3.
@export var start_owner: Enums.Factions = Enums.Factions.SWARM

## PAID EVERY TURN YOU HOLD IT. This is the economy (§2). Seeded from the old
## one-off rewards so the nine that exist were not invented from nothing.
@export var resources_per_turn: int = 0

## ALL OR NOTHING, exactly as compute_held already works. Yours in full while
## you hold the place and gone in full the turn you lose it — which can put you
## over your supply cap, and is meant to.
@export var compute: int = 0

## Total enemy supply defending it. MEASURED — see the header.
@export var resistance: int = 0

## The board edges: the id of every location this one leads to (§16.3). A
## connection is an authored edge marker on the map promoted to an edge here,
## so `connects_to.size()` should not exceed the map's tagged approaches.
@export var connects_to: Array[StringName] = []


## Whether this place can be attacked from somewhere you already hold — the
## frontier rule from §6, as a route rather than a rule.
func reachable_from(held: Array) -> bool:
	for n in connects_to:
		if held.has(n):
			return true
	return false
