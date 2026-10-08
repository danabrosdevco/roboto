extends Node
class_name AIManager

@export var world: World
@export var player: Player
@export var stimulus_manager: StimulusManager

# All registered AI bodies in the current level
var all_ai: Array[AI] = []

## Relayed from every robot in the level. Enemy emits its own `ekilled` on the
## frame it goes down; this is the one place that sees all of them, so the HUD
## and the playtest log can each connect once instead of chasing bodies that
## spawn and die throughout a mission.
signal ekilled(victim: Node, by: Node)

## Built once at startup so no robot ever pays for a CSG rebuild mid-mission.
## See csg_bake.gd: a reserve wave of 40 soldiers cost 336 ms on the frame it
## landed and 10 ms with the CSG gone, and the rover carries five times as much
## of it as a soldier. Preloaded by path because a new class_name is not
## resolvable headless until the editor rescans.
const _CsgBake := preload("res://Character/characters/ai/csg_bake.gd")


func _ready() -> void:
	# ─────────────────────────────────────────────
	# THE GROUP NOBODY WAS IN.
	#
	# Three things look the manager up this way — mine.gd, squad_commander.gd and
	# hatchling_payload.gd — and NOTHING had ever joined the group, so all three
	# silently took their fallback path forever. Every one of those fallbacks is
	# "walk the enemies group and re-test hostility per node", which is the work
	# hostiles_for() exists to do once per faction per tick and cache.
	#
	# It showed up as the most expensive thing in the game. In-editor profile of
	# a real firefight: Mine._physics_process 68.56 ms of a 128.16 ms script
	# total, with Mine._faction called 2686 times and Enums.are_hostile 2735 —
	# the per-node signature of the fallback, from ~232 mines that each believed
	# there was no AI manager in the level.
	#
	# BEFORE the await below. Anything after it happens a frame later at best,
	# and a mine that scans in between would miss the group and cache the miss.
	add_to_group(&"ai_manager")
	# At boot rather than per level: the cache is static and keyed by scene path,
	# so one pass covers every mission in the run and none of it lands during play.
	await _CsgBake.warm(self)


func register_enemy(new_enemy: AI) -> void:
	if new_enemy in all_ai:
		return
	all_ai.append(new_enemy)
	new_enemy.player = player
	if new_enemy.has_signal(&"ekilled") and not new_enemy.ekilled.is_connected(_relay_ekill):
		new_enemy.ekilled.connect(_relay_ekill)
	new_enemy.ai_manager = self
	if stimulus_manager != null:
		new_enemy.stimulus_manager = stimulus_manager
		stimulus_manager.register_ai(new_enemy)
	# Spread their think-frames. A squad spawned in one loop otherwise ticks in
	# lockstep forever.
	if new_enemy.has_method("_stagger_ai_timers"):
		new_enemy._stagger_ai_timers()

func deregister_enemy(enemy: AI) -> void:
	all_ai.erase(enemy)
	# REGISTER IMPLIES DEREGISTER, and this registry holds hard references to
	# bodies that are usually on their way out of the tree — the same mistake
	# all_ai made for months. _poll_frozen would drop it on its own pass, but
	# only when the round-robin reached it.
	#
	# Cast rather than passed straight through: _frozen is Array[Enemy] and
	# this takes an AI, and erase() on a typed array with the wrong type is the
	# kind of failure that does nothing and says nothing.
	var frozen_entry := enemy as Enemy
	if frozen_entry != null:
		_frozen.erase(frozen_entry)
	# The cache holds hard references to the bodies it listed. Leaving it intact
	# after removing one meant it kept handing out a node that was about to be
	# freed — and on level unload that is EVERY node, for up to
	# HOSTILE_CACHE_LIFETIME. Any robot that ticked vision in that window
	# dereferenced a corpse: "Invalid access to property 'global_position' on a
	# base object of type 'previously freed'". A cache must never outlive the
	# roster it was built from.
	_hostile_cache.clear()
	_cover_cached = false
	if stimulus_manager != null:
		stimulus_manager.deregister_ai(enemy)

func _relay_ekill(victim: Node, by: Node) -> void:
	ekilled.emit(victim, by)

func reset_all_reg_enemies() -> void:
	all_ai = []
	_frozen.clear()
	_frozen_cursor = 0
	_hostile_cache.clear()
	_cover_cached = false
	if stimulus_manager != null:
		stimulus_manager.clear()

# ─────────────────────────────────────────────
# FACTION QUERY
# Called by Enemy to find the nearest hostile body.
# Returns the closest living CharacterBody3D that
# is hostile to the requesting AI's faction.
# ─────────────────────────────────────────────
# Called by reconsider_target, _check_close_threat and the vision scan — several
# times per AI per second, each one a full pass over every registered body. With
# 35 AI that is well over a thousand iterations a second before anything useful
# happens.
#
# The list is cached per faction and rebuilt on a short timer instead. Callers
# still get an exact nearest; they just don't each re-filter the whole world.
var _hostile_cache: Dictionary = {}     # faction -> Array[CharacterBody3D]
var _hostile_cache_age: float = 0.0
const HOSTILE_CACHE_LIFETIME: float = 0.4

# ── COVER ────────────────────────────────────
# COVER IS LEVEL GEOMETRY. It does not move, spawn or die during a mission, and
# every soldier looking for cover was asking the SceneTree to rebuild the whole
# group array first — on a map the size of Three Rivers that array is hundreds
# of nodes, and it was the single most expensive thing a soldier in contact
# did.
#
# The POSITIONS are cached alongside it, because the distance filter that
# rejects almost all of them reads global_position per node, and that is a call
# into the engine per candidate. Against a PackedVector3Array the same filter
# is arithmetic.
#
# Aged rather than permanent so a level that streams cover in is picked up.
var _cover_cache: Array = []
var _cover_positions := PackedVector3Array()
var _cover_cached: bool = false
var _cover_cache_age: float = 0.0
const COVER_CACHE_LIFETIME: float = 2.0


func _process(delta: float) -> void:
	_hostile_cache_age -= delta
	if _hostile_cache_age <= 0.0:
		_hostile_cache.clear()
		_hostile_cache_age = HOSTILE_CACHE_LIFETIME
		_prune_contacts()
	_cover_cache_age -= delta
	if _cover_cache_age <= 0.0:
		_cover_cached = false
	_tick_overlay()


## Every cover point in the level, and their positions at the same indices.
func cover_points() -> Array:
	_rebuild_cover()
	return _cover_cache


func cover_positions() -> PackedVector3Array:
	_rebuild_cover()
	return _cover_positions


func _rebuild_cover() -> void:
	if _cover_cached:
		return
	_cover_cache = get_tree().get_nodes_in_group(&"cover_points")
	_cover_positions.resize(_cover_cache.size())
	for i in _cover_cache.size():
		var n := _cover_cache[i] as Node3D
		_cover_positions[i] = n.global_position if n != null else Vector3.INF
	_cover_cached = true
	_cover_cache_age = COVER_CACHE_LIFETIME




# ─────────────────────────────────────────────
# CONTACTS — who we know about, how fresh, and who is already shooting it
# ─────────────────────────────────────────────
# One table per faction, maintained INCREMENTALLY. Nothing here sweeps every
# frame: positions are written when something is seen, claims when a target is
# assigned, and decay is computed on READ from `seen_at`. The vision tick is
# already LOD'd because it was expensive, and a per-frame pass over contacts
# would undo that for nothing.
#
# WHY IT LIVES HERE. hostiles_for() already builds and caches one living-hostile
# list per faction, and this is the same shape of answer about the same bodies.
# Putting the table beside it means eviction is free: anything that stops being
# `alive` falls out of the hostile list, and the prune below drops its row on
# the same 0.4 s tick.
#
# IT IS NOT EVICTED ON `ekilled`. An e-killed robot is STUNNED, not dead — alive
# stays true and it recovers at 0.08 signal a second. Forgetting it would drop
# the squad's attention at the exact moment the thing is helpless, so e-kill is
# a priority BONUS in the score instead.
#
# faction -> { instance_id: { body, pos, seen_at, by, incoming, designated_to } }
var _contacts: Dictionary = {}

## How long a sighting counts as current. Past this a contact is STALE: you know
## roughly where it was, not where it is.
@export var contact_fresh_seconds: float = 3.0

## How far ahead "already dying" looks, in seconds of committed fire. Raising it
## makes robots spread sooner.
@export var ttk_window: float = 2.0

## Score weights. Distance is the baseline — everything else nudges it — so
## these are all in metres-of-apparent-distance, which is the only unit that
## makes them comparable to each other.
@export var w_saturation: float = 45.0   ## pushed AWAY from an already-dying target
@export var w_ekill: float = 30.0        ## pulled TOWARD a stunned one
@export var w_designated: float = 60.0   ## pulled toward what the player called
@export var w_fresh: float = 10.0        ## mild preference for something someone can see
@export var w_in_range: float = 15.0     ## prefer what this weapon can actually reach
@export var w_sticky: float = 18.0       ## hysteresis: do not re-aim every tick


func _contacts_for(faction) -> Dictionary:
	if not _contacts.has(faction):
		_contacts[faction] = {}
	return _contacts[faction]


func _row(faction, body: Node) -> Dictionary:
	var table: Dictionary = _contacts_for(faction)
	var id: int = body.get_instance_id()
	if not table.has(id):
		table[id] = {
			"body": body,
			"pos": (body as Node3D).global_position if body is Node3D else Vector3.ZERO,
			"seen_at": -INF,
			"by": 0,
			"incoming": 0.0,
			"designated_to": 0.0,
		}
	return table[id]


## A confirmed sighting, from a robot's own eyes or from a squadmate's callout.
## O(1), and the only thing that makes a contact fresh.
func note_seen(faction, body: Node) -> void:
	if body == null or not is_instance_valid(body) or not (body is Node3D):
		return
	var row: Dictionary = _row(faction, body)
	row["pos"] = (body as Node3D).global_position
	row["seen_at"] = _now()


## The player pointed at something. Holds for `seconds` — the same window the
## HUD marker uses, so what you see and what the tubes believe agree.
func designate(faction, body: Node, seconds: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	var row: Dictionary = _row(faction, body)
	row["designated_to"] = _now() + seconds
	row["pos"] = (body as Node3D).global_position if body is Node3D else row["pos"]
	row["seen_at"] = _now()


## Claim/release, called ONLY from Enemy.change_combat_target — the single funnel
## every target assignment in the game passes through. If anything else learns to
## assign a target without going through there, `by` and `incoming` drift and
## every decision downstream is quietly wrong.
func claim(faction, body: Node, dps: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	var row: Dictionary = _row(faction, body)
	row["by"] = int(row["by"]) + 1
	row["incoming"] = float(row["incoming"]) + maxf(dps, 0.0)


func release(faction, body: Node, dps: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	var table: Dictionary = _contacts_for(faction)
	var id: int = body.get_instance_id()
	if not table.has(id):
		return
	var row: Dictionary = table[id]
	row["by"] = maxi(int(row["by"]) - 1, 0)
	row["incoming"] = maxf(float(row["incoming"]) - maxf(dps, 0.0), 0.0)


## The row for a body, or an empty dictionary. Callers treat "we have never
## heard of it" and "we have not seen it lately" as different things, so this
## does not invent a row for a stranger.
func contact_for(faction, body: Node) -> Dictionary:
	if body == null or not is_instance_valid(body):
		return {}
	var table: Dictionary = _contacts_for(faction)
	return table.get(body.get_instance_id(), {})


func is_fresh(faction, body: Node) -> bool:
	var row: Dictionary = contact_for(faction, body)
	if row.is_empty():
		return false
	return (_now() - float(row["seen_at"])) <= contact_fresh_seconds


func is_designated(faction, body: Node) -> bool:
	var row: Dictionary = contact_for(faction, body)
	if row.is_empty():
		return false
	return _now() < float(row["designated_to"])


## Every live contact for a faction, for the debug overlay. Not used by the AI —
## the AI only ever asks about a body it already has in hand.
func contacts_snapshot(faction) -> Array:
	var out: Array = []
	for id in _contacts_for(faction):
		var row: Dictionary = _contacts_for(faction)[id]
		var body = row["body"]
		if body == null or not is_instance_valid(body):
			continue
		out.append(row)
	return out


func _now() -> float:
	return float(Time.get_ticks_msec()) * 0.001


## Drop rows for bodies that are gone or out of the fight. Runs on the same
## 0.4 s tick that clears the hostile cache — not per frame — and is bounded by
## the number of things that have ever been seen this mission.
func _prune_contacts() -> void:
	for faction in _contacts:
		var table: Dictionary = _contacts[faction]
		var dead: Array = []
		for id in table:
			var body = table[id]["body"]
			if body == null or not is_instance_valid(body) or not body.alive:
				dead.append(id)
		for id in dead:
			table.erase(id)
func hostiles_for(faction) -> Array:
	if _hostile_cache.has(faction):
		return _hostile_cache[faction]
	var list: Array = []
	for other in all_ai:
		if other == null or not is_instance_valid(other) or not other.alive:
			continue
		if not Enums.are_hostile(faction, other.faction):
			continue
		if other is Player and not other.is_targetable():
			continue
		list.append(other)
	if player != null and player.alive and player.is_targetable() \
			and Enums.are_hostile(faction, player.faction) and not list.has(player):
		list.append(player)
	_hostile_cache[faction] = list
	return list


func get_nearest_hostile(requesting_ai: AI) -> CharacterBody3D:
	# THE SHARED LIST, NOT EVERY ROBOT ON THE MAP.
	#
	# This used to walk all_ai and re-test hostility per entry, for every
	# caller, every time — so with 300 robots in a level each AI asking "who is
	# nearest" paid for 300 checks, most of them its own side. hostiles_for()
	# already builds that answer once per faction and caches it for
	# HOSTILE_CACHE_LIFETIME, filtered to living, targetable, hostile bodies:
	# for an enemy in a fight against a ten-robot squad that is ten entries
	# instead of three hundred.
	#
	# It is also the squad sharing its knowledge, which is the honest framing:
	# one list per side per tick, read by everyone on it.
	var best: CharacterBody3D = null
	var best_dist: float = INF
	var from: Vector3 = requesting_ai.global_position
	for body in hostiles_for(requesting_ai.faction):
		if body == requesting_ai or body == null or not is_instance_valid(body):
			continue
		# The cache can outlive a death inside its window.
		if not body.alive:
			continue
		var prio := 1.0
		if body is Enemy:
			prio = maxf((body as Enemy).target_priority, 0.01)
		# Squared distance, so the priority goes in squared too.
		var d: float = from.distance_squared_to((body as Node3D).global_position) / (prio * prio)
		if d < best_dist:
			best_dist = d
			best = body
	return best

# ─────────────────────────────────────────────
# Get all living hostiles within a radius
# ─────────────────────────────────────────────


## Who this robot should be shooting — nearest, adjusted for everything the
## faction collectively knows.
##
## SAME SCAN, SAME CACHED LIST, SAME COST as get_nearest_hostile(). Only the
## comparison changes. That is the whole reason distribution is affordable: the
## walk over hostiles_for() already happens every targeting tick.
##
## SATURATION, NOT HEADCOUNT. Subtracting a fixed amount per robot already
## shooting would stop five riflemen correctly focusing a Walker. What matters
## is whether the target is ALREADY GOING TO DIE: a Rifle Trooper is 60 HP and
## one Squad Automatic is ~164 DPS, so a single shooter is already overkill and
## the second should look elsewhere — while five Soldiers on a 320 HP Walker is
## only just enough and they should all stay. One rule, both behaviours, and
## counting claims could never tell a mortar (20 DPS) from a Heavy MG (183).
func get_best_hostile(requesting_ai: AI) -> CharacterBody3D:
	if not distribution_enabled(requesting_ai):
		return get_nearest_hostile(requesting_ai)

	var faction = requesting_ai.faction
	var from: Vector3 = requesting_ai.global_position
	var current = requesting_ai.get("combat_target")
	var reach: float = 0.0
	if requesting_ai.has_method("weapon_max_range"):
		reach = float(requesting_ai.weapon_max_range())

	var best: CharacterBody3D = null
	var best_score: float = -INF
	for body in hostiles_for(faction):
		if body == requesting_ai or body == null or not is_instance_valid(body):
			continue
		# The cache can outlive a death inside its 0.4 s window.
		if not body.alive:
			continue

		var prio := 1.0
		if body is Enemy:
			prio = maxf((body as Enemy).target_priority, 0.01)
		var dist: float = from.distance_to((body as Node3D).global_position)
		# Distance is the baseline and every other term is a nudge in metres,
		# which is the only unit that makes them comparable. target_priority
		# divides it exactly as it did before, so existing per-frame tuning
		# keeps meaning what it meant.
		var score: float = -(dist / prio)

		var row: Dictionary = contact_for(faction, body)
		if not row.is_empty():
			var health: float = maxf(float(body.health) if "health" in body else 1.0, 1.0)
			var overkill: float = clampf(
					float(row["incoming"]) * ttk_window / health, 0.0, 2.0)
			score -= w_saturation * overkill
			if is_designated(faction, body):
				score += w_designated
			if (_now() - float(row["seen_at"])) <= contact_fresh_seconds:
				score += w_fresh

		# STUNNED IS A BONUS, NOT AN EVICTION. An e-killed robot cannot shoot
		# back and climbs out at 0.08 signal a second, so it is the best thing
		# on the field to be finishing.
		if body is Enemy and (body as Enemy).get_signal_state() == Enemy.SignalState.EKILL:
			score += w_ekill

		if reach > 0.0 and dist <= reach:
			score += w_in_range
		# Hysteresis. Without it a score flipping between two near-equal
		# candidates re-aims every targeting tick and the robot hits nothing —
		# which is the same reason aim_settle_time exists.
		if body == current:
			score += w_sticky

		if score > best_score:
			best_score = score
			best = body
	return best


## Whether this robot distributes at all. Two switches: one for the whole
## system, one that leaves it on for your side and off for theirs, so the
## difficulty change can be separated from the behaviour change.
func distribution_enabled(requesting_ai: AI) -> bool:
	if not Settings.debug_tools_enabled():
		return true
	if not bool(Settings.get_value("debug.contact_distribution")):
		return false
	if requesting_ai != null and requesting_ai.faction == Enums.Factions.ENEMY \
			and not bool(Settings.get_value("debug.contact_enemy_distribution")):
		return false
	return true
func get_hostiles_in_radius(requesting_ai: AI, radius: float) -> Array:
	var result: Array = []
	var radius_sq = radius * radius
	var req_faction = requesting_ai.faction

	if player != null and player.is_targetable():
		if Enums.are_hostile(req_faction, Enums.Factions.PLAYER):
			if requesting_ai.global_position.distance_squared_to(player.global_position) <= radius_sq:
				result.append(player)

	for ai in all_ai:
		if ai == null or not is_instance_valid(ai):
			continue
		if ai == requesting_ai or not ai.alive or not ai is Enemy:
			continue
		if Enums.are_hostile(req_faction, (ai as Enemy).faction):
			if requesting_ai.global_position.distance_squared_to(ai.global_position) <= radius_sq:
				result.append(ai)

	return result

func on_sound_emitted(_location: Vector3, _meter_distance: float) -> void:
	pass


# ─────────────────────────────────────────────
# ACTIVATION SOURCES — what makes a robot worth running.
# ─────────────────────────────────────────────
# Distance culling used to measure to the PLAYER, which quietly said the player
# is the only thing in the world worth reacting to. Order a squad 300 m up the
# road and it walked into a garrison that was frozen solid, because you were
# still at the insertion point: your robots fought statues, and the fight only
# started when you caught up. What should wake a robot is anything it would
# SHOOT — the player, and every ally the player sent — so this is the same
# question hostiles_for() already answers, asked positionally.
#
# The positions are snapshotted once per physics frame per faction rather than
# read per robot: with 142 hostiles asking about 20 player-side bodies that is
# twenty transform reads a frame instead of nearly three thousand, and the
# comparison itself is float work on a packed array.
var _act_positions: Dictionary = {}     # faction -> PackedVector3Array
var _act_frame: int = -1


## Where everything hostile to `faction` is, this physics frame.
func activation_sources(faction) -> PackedVector3Array:
	var frame := Engine.get_physics_frames()
	if _act_frame != frame:
		_act_frame = frame
		_act_positions.clear()
	if _act_positions.has(faction):
		return _act_positions[faction]
	var out := PackedVector3Array()
	for body in hostiles_for(faction):
		if body != null and is_instance_valid(body):
			out.append(body.global_position)
	_act_positions[faction] = out
	return out


## Distance squared from `at` to the nearest thing hostile to `faction`, or INF
## when there is nothing left to fight — a robot with no enemies in the world
## has nothing to wake up for.
func nearest_hostile_distance_sq(faction, at: Vector3) -> float:
	var best := INF
	for p in activation_sources(faction):
		var d := at.distance_squared_to(p)
		if d < best:
			best = d
	return best


# ─────────────────────────────────────────────
# WAKING THE FROZEN — the outside half of the distance cull.
# ─────────────────────────────────────────────
# A culled robot now switches its own `_physics_process` off rather than
# early-returning out of it every frame: on Qamareen that is 176 of 186
# hostiles, and it is worth ~2.8 ms of a 26 ms physics frame (bench_qamareen,
# three runs each way) with Jolt reporting zero active bodies either way. See
# Enemy.cull_frozen.
#
# THE WHOLE RISK LIVES HERE. A robot whose tick is off cannot notice that the
# player has walked towards it, so if nothing outside it looks, it sleeps for
# the rest of the mission and the level quietly stops fighting back. Enemy
# thaws itself from wake(), exempt_from_culling() and trigger_combat(), all of
# which are called from outside its tick — but closing the DISTANCE is nobody's
# event, so it is polled, here, and this poll is the only thing standing
# between the saving and a dead level.
#
# Round-robin rather than all of them: polling 176 robots a frame would hand
# back most of what freezing them earned. The slice is sized so the whole list
# is swept in FROZEN_SWEEP_SECONDS however long it is, which bounds the latency
# instead of the cost — 12 robots a frame on Qamareen.
var _frozen: Array[Enemy] = []
var _frozen_cursor: int = 0

## Worst case between a robot becoming worth running and it running. Everything
## that is an EVENT (being shot, a squadmate making contact, walking into a
## sensor cone) thaws immediately and does not wait for this; what waits is the
## player closing the distance on his own. At 75 m activation and a few m/s of
## closing speed a quarter of a second is a couple of metres of approach.
const FROZEN_SWEEP_SECONDS: float = 0.25


## Called by Enemy._freeze_for_cull. Nothing else should call it: a robot in
## this list and still ticking would be polled for no reason, and one that is
## frozen and NOT in it never wakes.
func watch_frozen(enemy: Enemy) -> void:
	if enemy == null or enemy in _frozen:
		return
	_frozen.append(enemy)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_poll_frozen(delta)


func _poll_frozen(delta: float) -> void:
	if _frozen.is_empty():
		# Nothing to watch. CLAUDE.md's "disable it when idle" applies to this
		# tick as much as to the robots'; watch_frozen() turns it back on.
		set_physics_process(false)
		_frozen_cursor = 0
		return
	# Ceil, so a list of one is still swept and the cursor always advances.
	var slice: int = clampi(
		ceili(float(_frozen.size()) * delta / FROZEN_SWEEP_SECONDS),
		1, _frozen.size())
	for _i in slice:
		if _frozen.is_empty():
			return
		if _frozen_cursor >= _frozen.size():
			_frozen_cursor = 0
		var e: Enemy = _frozen[_frozen_cursor]
		# Gone from under us. deregister_enemy normally gets these first.
		if e == null or not is_instance_valid(e):
			_frozen.remove_at(_frozen_cursor)
			continue
		# Not ours any more. Something outside the cull gave the tick back — a
		# revive, a repair, reset() on a respawn, a test rig — or the robot
		# died, in which case die()/destroy()/_tick_settle own its tick and
		# handing it back here would restart a wreck's brain. Drop the flag so
		# the robot can be culled and frozen again cleanly from its own tick.
		if not e.cull_frozen or e.is_physics_processing() or not e.alive or e.downed:
			e.cull_frozen = false
			_frozen.remove_at(_frozen_cursor)
			continue
		var dist_sq: float = nearest_hostile_distance_sq(e.faction, e.global_position)
		if e.cull_wake_wanted(dist_sq):
			_frozen.remove_at(_frozen_cursor)
			e.thaw_from_cull()
			continue
		_frozen_cursor += 1


# ─────────────────────────────────────────────
# THE OVERLAY
# ─────────────────────────────────────────────
# Built and torn down from the debug switch rather than wired into hud.tscn:
# three lanes share this checkout and that scene is busy, and a readout that
# needs a scene edit to exist is one nobody turns on. See contact_overlay.gd.
const _ContactOverlay := preload("res://Character/hud/contact_overlay.gd")

var _overlay: Control = null
var _overlay_layer: CanvasLayer = null


func _tick_overlay() -> void:
	var want: bool = Settings.debug_tools_enabled() \
			and bool(Settings.get_value("debug.contact_overlay"))
	if want == (_overlay != null and is_instance_valid(_overlay)):
		return
	if want:
		_overlay_layer = CanvasLayer.new()
		_overlay_layer.layer = 64
		add_child(_overlay_layer)
		_overlay = _ContactOverlay.new()
		_overlay.manager = self
		_overlay_layer.add_child(_overlay)
	else:
		if _overlay_layer != null and is_instance_valid(_overlay_layer):
			_overlay_layer.queue_free()
		_overlay_layer = null
		_overlay = null
