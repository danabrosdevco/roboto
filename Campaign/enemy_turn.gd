extends RefCounted
class_name EnemyTurn

# ─────────────────────────────────────────────
# THE OTHER SIDE PLAYS TOO.
#
# docs/briefs/CAMPAIGN_REWORK.md Phase 6. Everything built in Stages 2–5 is
# invisible without this: income accrues but no turn passes, acts never change,
# and the defence on Valley Basin is a mission you pick from a menu rather than
# something that happens TO you.
#
# A TURN IS AN OPERATION. Nothing else advances it — not time, not a button —
# which is what closes §5's farming hole: you cannot sit at base earning
# income, because income only arrives when you go and do something.
#
# THE FRONTIER RULE, AND IT IS THE WHOLE DEFENSIVE GAME (§6):
#
#     A site can only be attacked if it borders ground you do not hold.
#
# Interior sites are untouchable. Two things fall out with no new data and
# nothing to explain: consolidating is a real strategy because a compact
# holding has a short frontier, and the map's existing shape becomes
# meaningful — the Causeway is the richest site on the board and sits behind
# Polaris as a dead end, so taking Polaris makes it untouchable forever.
#
# MOST ATTACKS AUTO-RESOLVE. The player is one robot; they cannot be at every
# site every turn, and a campaign that demanded it would be unplayable. The
# garrison fights it out on paper and the player is only pulled in when the
# result is actually in doubt — or when they choose to take it.
# ─────────────────────────────────────────────

const _Gen := preload("res://Campaign/force_generator.gd")

## How often the other side moves. §5: every 2–3 turns, so there is a rhythm
## without it being a metronome.
const ACTS_EVERY_MIN := 2
const ACTS_EVERY_MAX := 3

## How close an auto-resolve has to be before the player is offered the fight
## instead. A garrison at 0.8–1.25 of what it faces is "in doubt"; outside that
## the paper result stands.
const DOUBT_LOW := 0.8
const DOUBT_HIGH := 1.25

enum Outcome {
	QUIET,       ## the other side did not move this turn
	HELD,        ## the garrison won on paper; nothing changed hands
	LOST,        ## the garrison lost; the site is theirs
	IN_DOUBT,    ## too close to call — offer the player the defence
}


# ── When ─────────────────────────────────────────────────────────────────────

## Does the other side move on this turn? Seeded on the turn number so a
## reloaded save does not reroll it into a different campaign.
static func acts_on(turn: int) -> bool:
	if turn <= 1:
		return false   # the opening move is the player's; being hit on turn 1 reads as unfair
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("enemy_turn/%d" % turn)
	# Counts turns since the last move rather than rolling per turn, so the gap
	# is always 2 or 3 and never six by bad luck.
	var since := 0
	for t in range(2, turn + 1):
		since += 1
		var r := RandomNumberGenerator.new()
		r.seed = hash("enemy_turn/%d" % t)
		var gap: int = r.randi_range(ACTS_EVERY_MIN, ACTS_EVERY_MAX)
		if since >= gap:
			if t == turn:
				return true
			since = 0
	return false


# ── Where ────────────────────────────────────────────────────────────────────

## THE FRONTIER: sites you hold that border ground you do not.
##
## This is the only thing that can be attacked, and it is also the thing the
## player shapes by choosing what to take. A sprawling grab has a long frontier
## and bleeds; a compact holding has a short one.
static func frontier(state) -> Array[StringName]:
	var out: Array[StringName] = []
	if state == null or state.locations == null:
		push_warning("EnemyTurn: no board, so nothing can be attacked and the other side never moves.")
		return out
	for id in state.held_sites():
		var l = state.locations.of(id)
		if l == null:
			continue
		for n in l.connects_to:
			if not state.holds(n):
				out.append(id)
				break
	return out


## Which site they go for. BY VALUE, because garrisons are flat (§6) — every
## site you hold is defended equally well, so the enemy going for the throat is
## what makes losing one actually cost something. Ties break on the longest
## held, so a place you just took is not instantly taken back.
static func pick_target(state) -> StringName:
	var open := frontier(state)
	if open.is_empty():
		return &""
	var best: StringName = &""
	var best_worth: int = -1
	for id in open:
		var l = state.locations.of(id)
		if l == null:
			continue
		var worth: int = int(l.resources_per_turn) * 2 + int(l.compute) * 10
		if worth > best_worth:
			best_worth = worth
			best = id
		elif worth == best_worth and best != &"":
			if state.site_since(id) < state.site_since(best):
				best = id
	return best


# ── How it goes ──────────────────────────────────────────────────────────────

## WHAT A COUNTER-RAID IS WORTH, by act.
##
## FLAT, NOT PROPORTIONAL TO THE SITE — and that is the fix for a real problem.
## This used to pit the garrison against the site's full resistance: the 82
## supply it took to capture Valley Basin, or Over The Top's 365. Against that
## a finished campaign's 40-supply garrison sits at odds of 0.49 and LOSES
## EVERYTHING, every time, for the whole game.
##
## §6 settled that garrisons are flat so the enemy can target by value. The
## other half of that has to be true as well: the raid is a standard force and
## VALUE DECIDES WHICH SITE THEY HIT, not how hard they hit it. Otherwise your
## richest ground is also your least defensible and the two rules fight.
##
## Against a garrison of 8 (no compute) to 40 (a finished campaign, §6), this
## gives: early you cannot hold and bleed ground, mid-campaign it is genuinely
## in doubt and you get offered defences, late you hold comfortably — until the
## act turns over and it is in doubt again.
const RAID_BY_ACT := {1: 18, 2: 30, 3: 46}


## The paper fight: the garrison against what the raid commits.
##
## Returns the RATIO of defence to attack. Above DOUBT_HIGH the garrison holds
## comfortably, below DOUBT_LOW it is overrun, and between them the result is
## in doubt and the player should be offered the fight.
static func odds(state, location, act: int) -> float:
	var defence: float = float(_Gen.garrison_supply(state))
	var attack: float = float(RAID_BY_ACT.get(clampi(act, 1, 3), 18))
	if attack <= 0.0:
		return 99.0   # nothing is coming; the garrison cannot lose to it
	return defence / attack


## Play the other side's turn. Returns {outcome, site, odds}.
##
## IT DOES NOT MUTATE ON ITS OWN when the result is in doubt — that outcome is
## an INVITATION, and the caller decides whether to offer the player the
## defence or settle it on paper. Everything else is applied here.
static func play(state, act: int = 1) -> Dictionary:
	var result := {"outcome": Outcome.QUIET, "site": &"", "odds": 0.0}
	if state == null:
		return result
	if not acts_on(int(state.turn)):
		return result
	var target := pick_target(state)
	if target == &"":
		# Nothing of yours borders anything of theirs. Interior holdings are
		# untouchable and that is the frontier rule working, not a bug.
		return result
	var l = state.locations.of(target)
	var ratio := odds(state, l, act)
	result["site"] = target
	result["odds"] = ratio
	if ratio >= DOUBT_HIGH:
		result["outcome"] = Outcome.HELD
	elif ratio <= DOUBT_LOW:
		result["outcome"] = Outcome.LOST
		state.set_site_owner(target, _Gen.attacker_for_act(act))
	else:
		result["outcome"] = Outcome.IN_DOUBT
	return result


## Settle an in-doubt site on paper rather than playing it — what happens when
## the player declines the defence. Seeded on the site and turn so declining
## twice cannot be rerolled into a better answer.
static func settle(state, site: StringName, act: int) -> int:
	var l = state.locations.of(site) if state != null and state.locations != null else null
	if l == null:
		return Outcome.QUIET
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("settle/%s/%d" % [site, int(state.turn)])
	var ratio := odds(state, l, act)
	# Inside the doubt band, the ratio IS the chance. At 1.0 it is a coin toss.
	var held: bool = rng.randf() < clampf(ratio, 0.0, 1.0)
	if held:
		return Outcome.HELD
	state.set_site_owner(site, _Gen.attacker_for_act(act))
	return Outcome.LOST
