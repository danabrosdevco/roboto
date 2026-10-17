extends Node3D

# ─────────────────────────────────────────────
# THE TRAVELLING PULSE on an F2 RAFT compute core.
#
# Lives on the root of compute_core_f2{_small,,_large}.tscn, which
# tools/build_core_f2.gd generates. It drives ONE thing: the
# emission_energy_multiplier of the materials under the core's "Lit" node, so
# that a bright band climbs the tower bottom to top and the core reads as
# PROCESSING rather than as a lamp.
#
# IT IS NOT core_signal.gd AND MUST NOT BECOME IT. That script is the capture
# state machine and owns the beacon, the collar and the beam; this owns the
# model's own idle animation and nothing else. A core photographed on an empty
# stage, with no wrapper, no Terminal and no CoreSignal, still pulses — which is
# how it is shot and how it will first be dropped into a level.
#
# ─────────────────────────────────────────────
# WHY A TWEEN AND NOT _process
#
# CLAUDE.md: "No new `_process`." And the harder rule behind it — a coroutine
# that outlives the tree segfaults in cleanup, which this project has already
# paid for. A Tween is killed with the node that created it, so quitting mid-
# cycle is a free operation, and every tweener here interpolates ONE float
# engine-side. There is no GDScript running per frame at all: _ready builds the
# tweens and the script never executes again.
#
# COST. One Tween per height bucket, ~4 tweeners each. The 12.4 m core is the
# worst case at 13 buckets / 14 materials; the 4.2 m one is 6 and 8. That is a
# few dozen float lerps a frame for a whole core, against the 0.12 ms a single
# robot costs just to exist.
#
# ─────────────────────────────────────────────
# HOW A PIECE JOINS THE PULSE
#
# The generator puts every lit mesh under "Lit" and writes ONE piece of
# metadata on it:
#
#   pulse_y : float   the height the pulse reaches that piece at
#
# A lit mesh WITHOUT that meta is deliberately constant — that is the console
# plate, and it is constant because it is the thing the player walks up and
# presses. An interface that goes dark for two seconds of every three is a
# worse interface, however good it looks.
#
# Grouping is by height bucket (BUCKET metres), so the eight rack strips that
# share a segment are one Tween, not eight. Each bucket's delay is its mean
# height divided by SPEED, so the pulse climbs at a CONSTANT METRES PER SECOND:
# the 12.4 m core takes 1.9 s to traverse and the 4.2 m one 0.5 s, from the same
# code, and a tall core therefore visibly breathes slower than a short one. That
# is the whole reason this effect was chosen over a single sine — it scales into
# "this is a bigger machine" for free.
#
# THE HUE NEVER MOVES ON ITS OWN. Only energy is animated here. Faction colour
# is the gameplay-critical read ("who owns this"), so a core that strobed
# through colours would be answering the wrong question. The 19 painted fins
# and lips hold a CONSTANT faction glow throughout, which also gives the
# travelling band a fixed reference to be brighter and dimmer than.
#
# WHAT CHANGES THE HUE IS CAPTURE, and only capture — `set_faction_colour()`
# at the bottom of this file. Before that existed a captured core stayed amber
# forever: every material's `emission` is baked at HUDPalette.FAC_ADVERSARY by
# the generator, the beacon and collar recoloured on capture because
# core_signal.gd owns those, and the machine the player had just taken went on
# advertising itself as the enemy's. That is the one thing the colour is for.
# ─────────────────────────────────────────────

## Metres per second the band climbs. 6.0 is fast enough to read as a signal
## rather than as weather, and slow enough that the travel is legible on the
## 4.2 m core where there is only ~3 m of tower to cross.
const SPEED := 6.0
## Height bucket, in metres. Pieces within one bucket fire together on one Tween.
const BUCKET := 0.5
## The band's leading edge is sharp and its trail is long — a rise that matches
## the fall reads as breathing, which is the dull version of this.
const RISE := 0.24
const FALL := 0.80
## Dead time after the last bucket has fallen, so the cycle has a rest in it.
const TAIL := 0.55
## Floor on the cycle, so a short core does not flicker.
const MIN_CYCLE := 2.6

## Peak energy, as a multiple of whatever rest energy the generator baked into
## each material. Rest is the single source of truth for brightness (see
## LIT_GLOW in tools/build_core_f2.gd) and this script only owns the swing.
## 2.4 WAS PHOTOGRAPHED, AT 2.1 AND 2.6 AS WELL. 0.40 x 2.4 = 0.96 at the crest,
## which is the arithmetic that matters: emission here is ADDED to the glitch
## texture (see build_core_f2.gd), so a mid texel sits at about (1.03, 0.88,
## 0.35) before energy, and 0.96 puts the red channel just at the ceiling. At
## 2.1 the band did not beat the painted fins' constant 0.95 and the travel was
## hard to find; at 2.6 the crest lines photographed white-yellow, which is the
## pale-amber fault PAINT_GLOW's note was written about. 2.4 is the last value
## where the crest is still amber.
const PEAK_GAIN := 2.4


func _ready() -> void:
	_watch_for_capture()
	var lit := get_node_or_null(^"Lit")
	if lit == null:
		# Every early return warns. A core with no Lit node is a core built by
		# an older build_core_f2.gd, and it will sit there looking fine and
		# static while nobody can work out why only some cores pulse.
		push_warning("core_pulse: %s has no 'Lit' node, so nothing on this core pulses." % name)
		return

	# bucket key -> [materials], plus the summed height and the PIECE count that
	# make its mean. The count is tracked separately from the material list on
	# purpose: eight rack strips at one height share one material, so dividing
	# the height sum by the material count multiplied every delay by eight and
	# the 12.4 m core came back with a fifteen-second cycle.
	var groups := {}
	var sums := {}
	var counts := {}
	var constant := 0
	for child in lit.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			push_warning("core_pulse: lit piece '%s' has no StandardMaterial3D override, so it cannot pulse." % mi.name)
			continue
		if not mi.has_meta(&"pulse_y"):
			constant += 1          # the console plate, on purpose. See the header.
			continue
		var y: float = mi.get_meta(&"pulse_y")
		var key: int = int(round(y / BUCKET))
		if not groups.has(key):
			groups[key] = []
			sums[key] = 0.0
			counts[key] = 0
		# THE MATERIALS ARE SHARED WITHIN A SEGMENT, by the generator, so the
		# same StandardMaterial3D arrives here up to eight times. Tweening one
		# material twice in parallel is a fight between two tweeners over one
		# float, so it is filtered here rather than trusted upstream.
		if not (groups[key] as Array).has(mat):
			(groups[key] as Array).append(mat)
		sums[key] = (sums[key] as float) + y
		counts[key] = (counts[key] as int) + 1

	if groups.is_empty():
		push_warning("core_pulse: no lit piece on %s carries pulse_y, so the core stays static." % name)
		return

	var keys: Array = groups.keys()
	keys.sort()
	# Mean height per bucket, and the delay that follows from it.
	var delays := {}
	var longest := 0.0
	for key: int in keys:
		var mean: float = (sums[key] as float) / float(maxi(1, counts[key] as int))
		# Heights are measured from the raft plate's top, not from the origin,
		# so the lowest band fires at t = 0 rather than a third of the way in.
		var d: float = maxf(0.0, mean - 0.52) / SPEED
		delays[key] = d
		longest = maxf(longest, d)
	var cycle: float = maxf(MIN_CYCLE, longest + RISE + FALL + TAIL)

	# ── THE DIAGNOSTIC HATCH, and it is why a still can prove a moving thing.
	# CORE_PHASE=0.35 freezes every bucket at the energy it would have 35% of
	# the way through the cycle, so tools/mockup_shots.gd — which takes one
	# frame and does not know this script exists — can photograph the sequence.
	# Unset in any normal run, so this costs a getenv at load and nothing else.
	var phase_env := OS.get_environment("CORE_PHASE")
	if not phase_env.is_empty() and phase_env.is_valid_float():
		var phase: float = fposmod(phase_env.to_float(), 1.0)
		for key: int in keys:
			var e: float = _energy_at(phase * cycle, delays[key], _rest(groups[key]))
			for m: StandardMaterial3D in groups[key]:
				m.emission_energy_multiplier = e
		print("core_pulse: %s frozen at phase %.2f of a %.2f s cycle (%d buckets, %d constant)"
				% [name, phase, cycle, keys.size(), constant])
		return

	for key: int in keys:
		_band_tween(groups[key], delays[key], cycle)


## Rest energy for a bucket, taken from the material the generator baked. The
## script never hard-codes a brightness; see PEAK_GAIN.
func _rest(mats: Array) -> float:
	return (mats[0] as StandardMaterial3D).emission_energy_multiplier


## ONE LOOPING TWEEN FOR ONE HEIGHT BUCKET.
##
## Every bucket's loop is exactly `cycle` long — delay + rise + fall + whatever
## is left — so the buckets stay in lockstep forever instead of drifting apart
## by the length of their own delay, which is what a naive set_delay() does on
## the second lap.
func _band_tween(mats: Array, delay: float, cycle: float) -> void:
	var rest: float = _rest(mats)
	var peak: float = rest * PEAK_GAIN
	var t := create_tween().set_loops()
	if delay > 0.0:
		t.tween_interval(delay)
	var first := true
	for m: StandardMaterial3D in mats:
		var tw := t.tween_property(m, ^"emission_energy_multiplier", peak, RISE)
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if not first:
			# parallel() applies to the tweener BEFORE it, so the first of the
			# group is the one that follows the interval and the rest join it.
			t.parallel()
		first = false
	first = true
	for m: StandardMaterial3D in mats:
		var tw := t.tween_property(m, ^"emission_energy_multiplier", rest, FALL)
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		if not first:
			t.parallel()
		first = false
	var tail: float = cycle - delay - RISE - FALL
	if tail > 0.0:
		t.tween_interval(tail)


## The curve the tween above describes, evaluated by hand. Only the CORE_PHASE
## hatch uses it, and it must stay in step with _band_tween or the photographs
## stop being evidence about the thing that ships.
func _energy_at(at: float, delay: float, rest: float) -> float:
	var peak: float = rest * PEAK_GAIN
	var u: float = at - delay
	if u < 0.0 or u > RISE + FALL:
		return rest
	if u < RISE:
		# TRANS_SINE / EASE_OUT is sin(x * PI/2).
		return lerpf(rest, peak, sin(u / RISE * PI * 0.5))
	# TRANS_SINE / EASE_IN is 1 - cos(x * PI/2).
	return lerpf(peak, rest, 1.0 - cos((u - RISE) / FALL * PI * 0.5))


# ─────────────────────────────────────────────
# WHO OWNS THIS CORE, as a colour.
# ─────────────────────────────────────────────

## Both lit groups the generator writes: the travelling band and the constant
## painted fins. Tinting only "Lit" leaves the fins amber on a captured core,
## which reads as half-taken — and the fins are the brighter of the two.
const LIT_GROUPS: Array[StringName] = [&"Lit", &"Paint"]

## What this core is currently advertising. Starts at the baked amber so a
## core that is never captured is never written to at all.
var _faction_colour := Color(0.91, 0.63, 0.23)


## RE-TINT EVERY LIT MATERIAL ON THIS CORE.
##
## EMISSION ONLY — never `emission_energy_multiplier`. That float is the pulse,
## it is mid-tween on a dozen materials at any moment, and `_rest()` reads it
## back as the single source of truth for brightness. Writing it here would
## fight the tween and permanently re-base the rest energy to whatever the
## crest happened to be when the player pressed the terminal.
##
## SAFE PER-INSTANCE because every one of these materials carries
## `resource_local_to_scene = true` — 142 of them across the six core scenes,
## checked rather than assumed. Without that, capturing one core would recolour
## every core in the level, including the ones still held against you.
## If a future generator drops that flag this turns into exactly that bug, so
## the flag is the thing to protect.
func set_faction_colour(c: Color) -> void:
	_faction_colour = c
	var touched := 0
	for group in LIT_GROUPS:
		var node := get_node_or_null(NodePath(group))
		if node == null:
			continue
		for child in node.get_children():
			var mi := child as MeshInstance3D
			if mi == null:
				continue
			var mat := mi.material_override as StandardMaterial3D
			if mat == null:
				continue
			mat.emission = c
			touched += 1
	if touched == 0:
		# Every early return warns. A core that cannot be recoloured still
		# captures perfectly well and simply keeps flying the enemy's colour,
		# which is invisible as a bug and obvious as a complaint.
		push_warning("core_pulse: %s has no lit material to recolour, so capturing it will not change its colour." % name)


## The colour this core is showing. For probes and shot tools.
func faction_colour() -> Color:
	return _faction_colour


## FIND THE OBJECTIVE THIS CORE IS THE BODY OF, and recolour when it completes.
##
## WHY IT SEARCHES UPWARD instead of being wired in the scene. This script is
## on the "Signal" node INSIDE maps/blocks/compute/compute_core*.tscn, which
## tools/build_core_relay.gd REBUILDS FROM SCRATCH on every geometry change —
## an exported NodePath into the parent scene would be erased by the next
## rebuild and would be pointing out of this scene anyway. The same reason
## fit_ops_table.gd exists. Searching costs one walk at ready and survives.
##
## Two owners, because there are two capture systems and a core can be under
## either:
##   - Campaign/interact_objective.gd — a capture point placed straight in a
##     level, which is what hillfort_wip and the other maps instance. It has
##     `objective_completed` and no notion of faction at all: completing it
##     means the PLAYER took it, so it goes to HELD.
##   - Env/world_objects/holdable_core.gd — the campaign site system, which
##     does have a holder. That one is driven by core_signal.gd calling
##     set_faction_colour() directly, so nothing is connected here.
##
## FOUR LEVELS because the chain is Signal -> ComputeCore -> Core -> the
## objective root, and a slice or a future wrapper may add one more.
func _watch_for_capture() -> void:
	var n: Node = get_parent()
	for _i in 4:
		if n == null:
			break
		if n.has_signal(&"objective_completed"):
			if not n.is_connected(&"objective_completed", _on_objective_completed):
				n.connect(&"objective_completed", _on_objective_completed)
			# ALREADY TAKEN WHEN WE LOADED. A level restored mid-mission, or a
			# core completed before this node readied, would otherwise sit amber
			# having missed the only signal it was listening for.
			if "completed" in n and n.completed:
				set_faction_colour(HUDPalette.HELD)
			return
		n = n.get_parent()
	# NOT A WARNING. A core photographed on an empty stage, or dropped into a
	# level as scenery, has no objective above it and is not broken — the same
	# case the header makes for the pulse running with no wrapper at all.


func _on_objective_completed(_objective: Variant = null) -> void:
	set_faction_colour(HUDPalette.HELD)
