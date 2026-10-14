extends RefCounted
class_name ForceGenerator

# ─────────────────────────────────────────────
# WHAT IS DEFENDING THIS PLACE, THIS TURN.
#
# docs/briefs/CAMPAIGN_REWORK.md §10 and Phase 4. `enemy_force` stops being a
# constant authored once and becomes compose(budget, roster, posture, site):
# the same ground fields a different army in Act 1 and Act 3, and a site Home
# Command holds is defended by Home Command's own frames.
#
# THE SHAPE STAYS AUTHORED. ONLY THE COMPOSITION SCALES.
#
# This is the whole mitigation and it is not negotiable. Generated encounters
# are reliably worse than authored ones — Coast Road's "bombers for the bridge,
# armour for the craters" is good because a person wrote it, and no budget
# function will ever invent that. So every authored EnemySquadSpec is KEPT, with
# its tags, its posture, its wake triggers and its callsign. What is replaced is
# only the four fields that say WHAT is standing there:
#
#     roster · count · forced_weapons · kit_variance
#
# A squad authored to garrison the north trench still garrisons the north
# trench. It is simply made of different robots.
#
# AND THE BUDGET IS SHARED OUT IN PROPORTION. A spec authored at 4 supply
# against one authored at 30 keeps that 1:7 ratio whatever the total becomes —
# so a picket stays a picket and the hard point stays the hard point. Scaling
# every squad to the same size would flatten the map's own pacing, which is the
# second way this could have gone wrong.
# ─────────────────────────────────────────────

# ── Rosters ──────────────────────────────────────────────────────────────────
# BY PATH AND LOADED LAZILY, NOT PRELOADED.
#
# campaign.gd names EnemyForceSpawner, the spawner names this file, and this
# file would name the chassis resources — whose script is ChassisDefinition,
# which campaign.gd also names. A preload closes that loop at PARSE time and
# every file in it fails to compile with an error pointing at none of them.
# (enemy_commander.gd hits the same wall from the other side and solves it with
# DirAccess, which does not survive an export. This does.)
#
# Loaded once on first use and cached. The .tres filename and the frame's id do
# not always agree — the Leaper's resource is chassis_hopper.tres, named before
# the frame was — so the id is the key and the path is written out.
const SWARM_PATHS := {
	&"rifleman": "res://Campaign/chassis/chassis_rifleman.tres",
	&"chaser": "res://Campaign/chassis/chassis_chaser.tres",
	&"leaper": "res://Campaign/chassis/chassis_hopper.tres",
	&"shotgunner": "res://Campaign/chassis/chassis_shotgunner.tres",
	&"marksman": "res://Campaign/chassis/chassis_marksman.tres",
	&"rifleman_armoured": "res://Campaign/chassis/chassis_rifleman_armoured.tres",
	&"rover_gl": "res://Campaign/chassis/chassis_rover_gl.tres",
	&"mortar_track": "res://Campaign/chassis/chassis_mortar_track.tres",
	&"brood": "res://Campaign/chassis/chassis_brood.tres",
	&"bastion": "res://Campaign/chassis/chassis_bastion.tres",
	&"see_engine": "res://Campaign/chassis/chassis_see_engine.tres",
}

## THE SWARM, by tech tier. Tier 1 is what a site fields on its own; tier 3 is
## what turns up once the campaign has escalated. Act decides which tiers are
## drawn from, so Act 2 and Act 3 feel different without a number being tuned
## twice.
const SWARM_TIERS := {
	1: [&"rifleman", &"chaser", &"leaper", &"shotgunner", &"marksman"],
	2: [&"rifleman_armoured", &"rover_gl", &"mortar_track", &"brood"],
	3: [&"bastion", &"see_engine"],
}

static var _cache: Dictionary = {}


## One Swarm frame, loaded on first ask.
static func swarm_frame(id: StringName):
	if _cache.has(id):
		return _cache[id]
	var path: String = String(SWARM_PATHS.get(id, ""))
	if path == "":
		push_warning("ForceGenerator: no path for Swarm frame '%s', so it cannot be fielded." % id)
		return null
	var res = load(path)
	if res == null:
		push_warning("ForceGenerator: '%s' did not load, so '%s' cannot be fielded." % [path, id])
		return null
	_cache[id] = res
	return res

## HOME COMMAND FIELDS THE PLAYER'S OWN CATALOGUE.
##
## Free to implement — the frames already exist and are already balanced — and
## the most chilling thing in Act 2: the professionals you meet are built out
## of exactly what you are built out of, and the first time a Walker is on the
## other side the player understands the act change without a line of dialogue.
##
## Resolved from the catalogue at call time rather than preloaded, because
## which frames the PLAYER can field is a campaign question, not a constant.
const HOME_PREFERRED := [&"soldier", &"mechanic", &"lance", &"rover", &"picket",
	&"drayman", &"kite", &"reclaimer", &"spotter", &"walker", &"bulwark", &"vessel"]

## How much harder a site gets as the campaign turns. Act 1 is the authored
## number exactly, so the maps as they ship are the Act 1 experience and
## nothing about them has to be re-tuned.
const ACT_SCALE := {1: 1.0, 2: 1.15, 3: 1.35}

## Who holds it changes what it costs to take. Home Command garrisons properly;
## Argus spends without caring what it spends.
const HOLDER_SCALE := {
	Enums.Factions.SWARM: 1.0,
	Enums.Factions.ENEMY: 1.0,
	Enums.Factions.HOME: 1.1,
	Enums.Factions.ARGUS: 1.25,
}


# ── The budget ───────────────────────────────────────────────────────────────

## WHAT THIS PLACE CAN FIELD, in supply.
##
## Rooted in the location's MEASURED resistance (tools/measure_resistance.gd),
## so the starting point is what the map actually ships with rather than a
## number somebody picked. Act and holder scale it from there.
static func budget(location, act: int, holder: int) -> int:
	if location == null:
		push_warning("ForceGenerator: no Location, so there is no budget and the authored force is left alone.")
		return 0
	var base: float = float(location.resistance)
	base *= float(ACT_SCALE.get(clampi(act, 1, 3), 1.0))
	base *= float(HOLDER_SCALE.get(holder, 1.0))
	return int(round(base))


## Which tiers an act may draw from.
static func tiers_for(act: int) -> Array:
	match clampi(act, 1, 3):
		1: return [1]
		2: return [1, 2]
		_: return [1, 2, 3]


# ── Composing ────────────────────────────────────────────────────────────────

## The force for one operation: the authored specs, refilled.
##
## RETURNS NEW SPECS, never mutating the authored resources — a MissionDefinition
## is a .tres shared across every play of that operation, and writing a
## generated roster into it would persist into the next one and into the editor.
## This is the `duplicate()` rule from CLAUDE.md, and it bites hardest here.
static func compose(authored: Array, location, act: int, holder: int,
		catalogue: ItemCatalogue, seed_key: String = "") -> Array:
	var out: Array = []
	if authored.is_empty():
		return out
	var total := budget(location, act, holder)
	if total <= 0:
		# No location, or a site worth nothing. Hand back the authored force
		# untouched rather than an empty map.
		for spec in authored:
			out.append(spec)
		return out

	# ── the authored shape, as weights ──────────
	var weights: Array[float] = []
	var sum := 0.0
	for spec in authored:
		var w := 0.0
		if spec != null:
			for c in spec.roster:
				if c != null:
					w += float(c.supply)
			if w <= 0.0:
				w = float(maxi(spec.count, 1))
		weights.append(w)
		sum += w
	if sum <= 0.0:
		push_warning("ForceGenerator: the authored force has no supply in it, so the shape cannot be weighted and it is left alone.")
		for spec in authored:
			out.append(spec)
		return out

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key if seed_key != "" else str(location.id))
	var pool := _pool(holder, act, catalogue)
	if pool.is_empty():
		push_warning("ForceGenerator: no frames for faction %d, so the authored force is left alone." % holder)
		for spec in authored:
			out.append(spec)
		return out

	for i in authored.size():
		var spec = authored[i]
		if spec == null:
			continue
		var share: int = int(round(total * (weights[i] / sum)))
		out.append(_refill(spec, share, pool, rng))
	return out


## One squad, rebuilt to a supply share. Everything that says WHERE it is and
## WHAT IT DOES is carried over untouched.
static func _refill(spec, share: int, pool: Array, rng: RandomNumberGenerator):
	var made = spec.duplicate()
	# POSITION, POSTURE AND TRIGGERS ARE THE MAP'S. duplicate() carries them;
	# this is here to say so, because the next person to touch this file will
	# wonder why they are not being set.
	#   callsign · route_tag · post_tag · spawn_tag · spawn_offset
	#   posture · always_active · wake_after_kills · wake_after_seconds
	#   reinforcement_tag · faction
	var roster: Array[ChassisDefinition] = []
	var spent := 0
	# Biggest-first, so a share of 12 is a Bastion and two riflemen rather than
	# twelve riflemen — which is the difference between a hard point and a mob.
	var sorted := pool.duplicate()
	sorted.sort_custom(func(a, b): return int(a.supply) > int(b.supply))
	# One pass placing what fits, then fill the remainder with the cheapest.
	for frame in sorted:
		if roster.size() >= 24:
			break   # a sanity ceiling; 24 bodies on one post is already a lot
		var cost: int = maxi(int(frame.supply), 1)
		# Never let one frame take the whole share unless it is all that fits.
		while spent + cost <= share and roster.size() < 24 \
				and (cost <= 1 or spent + cost <= share - 1 or roster.is_empty()):
			roster.append(frame)
			spent += cost
			if rng.randf() < 0.45:
				break   # move on, so a squad is mixed rather than six of one
	var cheapest = sorted[sorted.size() - 1]
	var cheap_cost: int = maxi(int(cheapest.supply), 1)
	while spent + cheap_cost <= share and roster.size() < 24:
		roster.append(cheapest)
		spent += cheap_cost
	if roster.is_empty():
		# A share too small for anything. One of the cheapest, because a post
		# the map says is defended must not come up empty.
		roster.append(cheapest)
	made.roster = roster
	# count is ignored in roster form, but a stale 3 sitting next to a roster of
	# eleven is a lie the next reader has to work out. Keep them agreeing.
	made.count = roster.size()
	made.kit_variance = 0.35
	return made


## The frames a faction can field in this act.
static func _pool(holder: int, act: int, catalogue: ItemCatalogue) -> Array:
	var out: Array = []
	if holder == Enums.Factions.HOME or holder == Enums.Factions.ARGUS:
		# THE PLAYER'S OWN CATALOGUE. Act gates it by supply rather than by a
		# tier table, because the player's frames have no tiers — supply is the
		# only measure of weight they carry.
		var ceiling: int = 1 if act <= 1 else (2 if act == 2 else 3)
		if catalogue == null:
			push_warning("ForceGenerator: Home Command needs the item catalogue to field the player's frames, and there is none.")
			return out
		for id in HOME_PREFERRED:
			var f := catalogue.chassis_def(id)
			if f != null and int(f.supply) <= ceiling and int(f.supply) >= 1:
				out.append(f)
		return out
	for tier in tiers_for(act):
		for id in SWARM_TIERS[tier]:
			var f = swarm_frame(id)
			if f != null:
				out.append(f)
	return out


# ── THE PLAYER'S GARRISON ────────────────────────────────────────────────────
#
# §6: GARRISONS ARE FREE AND COME WITH THE GROUND. No pool, no distribution, no
# build cost, no screen. Take a site and it is defended — the player can never
# have a bad campaign because they forgot to garrison something.
#
# FLAT STRENGTH ACROSS SITES, which §6 is emphatic about. If garrison strength
# tracked site value your richest sites would be your safest and your poorest
# would churn: no tension where it matters, irritation where it does not. So it
# is sized on COMPUTE — a player-wide number — and every site you hold is
# defended exactly as well as every other. The enemy then picks its target by
# value, which is where the decisions are.
#
# AND IT IS BUILT OUT OF WHAT YOU HAVE OPENED. A garrison fielding frames you
# have never unlocked would be the campaign handing you kit through the back
# door, right after Phase 3 made you pay for it at the front. It also reads:
# the ground you hold is defended by your own programme, and it gets better
# because YOU got better.

## What a garrison is worth at zero compute — a token guard, enough that a site
## is never simply undefended.
const GARRISON_BASE := 8
## Supply per point of compute earned. The campaign pays 32 compute in total
## (§6), so a finished campaign garrisons every site at roughly 40 supply.
##
## BALANCE, not design: these two numbers are the entire difficulty curve of
## every defence in the game and they belong in one place for that reason.
const GARRISON_PER_COMPUTE := 1.0


## How much supply the player's garrison is worth, anywhere.
static func garrison_supply(state) -> int:
	if state == null:
		return GARRISON_BASE
	var compute: int = int(state.compute_earned) if "compute_earned" in state else 0
	return GARRISON_BASE + int(round(float(compute) * GARRISON_PER_COMPUTE))


## The frames the player has actually opened, cheapest last so the filler at
## the end of a share is the small stuff.
##
## FALLS BACK TO THE STARTING FRAME. A campaign that has opened nothing would
## otherwise garrison with an empty list, and a site the game says is defended
## coming up empty is worse than a weak guard.
static func unlocked_frames(state, catalogue: ItemCatalogue) -> Array:
	var out: Array = []
	if catalogue == null:
		push_warning("ForceGenerator: no catalogue, so the garrison has no frames to field.")
		return out
	for f in catalogue.chassis:
		if f == null or not f.purchasable:
			continue
		if state != null and state.has_method("is_unlocked") and not state.is_unlocked(f.id):
			continue
		out.append(f)
	if out.is_empty():
		var fallback := catalogue.chassis_def(&"soldier")
		if fallback != null:
			out.append(fallback)
		else:
			push_warning("ForceGenerator: nothing is unlocked and there is no soldier frame, so the garrison is empty.")
	return out


## The player's garrison for a site, as specs the ordinary spawner understands.
##
## ONE SQUAD PER POST, GARRISON POSTURE. They dig in where the map says a
## garrison stands rather than wandering — these are the defenders, and the
## player's own squad is the mobile half.
static func garrison(state, catalogue: ItemCatalogue, post_tags: Array,
		seed_key: String = "garrison") -> Array:
	var out: Array = []
	if post_tags.is_empty():
		push_warning("ForceGenerator: no posts to garrison, so the site is defended by nobody.")
		return out
	var pool := unlocked_frames(state, catalogue)
	if pool.is_empty():
		return out
	var total := garrison_supply(state)
	var share: int = maxi(1, int(round(float(total) / float(post_tags.size()))))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key)
	var spec_script := load("res://Campaign/enemy_squad_spec.gd")
	for i in post_tags.size():
		var spec = spec_script.new()
		spec.callsign = "GARRISON-%d" % (i + 1)
		# THE PLAYER'S OWN. hostiles_for() decides by faction, and
		# register_enemy only means "is an AI the manager knows about" — so a
		# friendly squad travels the authored road exactly like a hostile one.
		spec.faction = Enums.Factions.PLAYER
		spec.posture = 1   # EnemySquadSpec.Posture.GARRISON
		spec.post_tag = StringName(post_tags[i])
		spec.spawn_tag = StringName(post_tags[i])
		spec.always_active = true
		var built = _refill(spec, share, pool, rng)
		out.append(built)
	return out


## WHO COMES FOR YOUR GROUND, by act. §3: Act 1 is a war with the Swarm over
## ground, Act 2 is the same war against Home Command's professionals, Act 3 is
## Argus itself.
##
## THIS IS NOT THE SAME QUESTION AS WHO HOLDS A SITE, and conflating them was a
## real bug: an ATTACK generates the force from whoever HOLDS the place, but a
## DEFENCE must generate it from whoever is coming to take it — and on a
## defence the holder is the player. Passing the holder there would have built
## the attacking army out of the player's own catalogue.
static func attacker_for_act(act: int) -> int:
	match clampi(act, 1, 3):
		1: return Enums.Factions.SWARM
		2: return Enums.Factions.HOME
		_: return Enums.Factions.ARGUS
