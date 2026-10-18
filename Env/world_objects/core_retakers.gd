extends Node
class_name CoreRetakers

# ─────────────────────────────────────────────
# SOMEBODY HAS TO ACTUALLY COME AND STAND ON IT.
#
# HoldableCore._reverse_tick lets the enemy take a core back by standing in its
# circle, which is the mirror of how the player took it. On its own that is a
# rule nothing exercises: hostiles contest a core only when they happen to be
# near one, so a site could be captured and then held forever by walking away.
#
# This is the intent behind the rule. When a core becomes the player's, the
# nearest hostile squad is told to go and retake it — and `retake_hostiles` of
# them have to arrive, because that is the number the core is counting.
#
# WHY A SQUAD AND NOT N BODIES. Ordering individuals would pull two robots out
# of a fight they are in the middle of and walk them across the map on their
# own, which reads as a bug rather than as a counter-attack. A squad already
# knows how to move as a unit and how to stop and fight on the way; it arrives
# as a group or it does not arrive, and either is legible.
#
# WHY NOT EVERY SQUAD. A site has several cores and the player can only stand
# on one. Sending everything to the first one taken leaves the rest of the map
# empty and turns a defence into a single scripted rush. One squad per core,
# nearest first, is enough to make holding ground a thing you have to do.
#
# NOTHING HERE TOUCHES THE PLAYER'S SQUADS, obviously, and nothing here spawns:
# it re-tasks what is already on the map. Reinforcements are EnemyCommander's
# job and they arrive on their own schedule.
# ─────────────────────────────────────────────

## How far a squad can be and still be sent. Beyond this they are somebody
## else's problem and walking them over would empty the map.
@export var call_radius: float = 120.0
## Re-task at most this often, so a core changing hands twice in a second does
## not send the same squad twice.
@export var cooldown_seconds: float = 8.0

## The pace an advancing squad actually keeps, in m/s. Same number and same
## reasoning as EnemyForceSpawner.ADVANCE_PACE, which measured it over open
## ground with shooting: it only sets how long a culling exemption lasts, and
## being generous costs one brain ticking a little past its arrival.
const ADVANCE_PACE := 2.0

var _last_call: Dictionary = {}   # core instance id -> msec at last call

## WHERE TO LOOK FOR CORES. Set by SiteSlice before add_child, the same way it
## hands SiteOperation its search_root and for the same reason.
##
## IT USED TO WALK `get_tree().current_scene`, which is set only by the engine
## loading a main scene. Any `--script` harness leaves it NULL, so the scan fell
## through to `self` — a node with no children — connected to nothing, and
## every capture after it was silent. A live suite found 0 of 7 cores wired.
## The real game happened to work because Master IS its current scene, which is
## the worst kind of correct: true by coincidence and untestable.
var search_root: Node = null


func _ready() -> void:
	# EVERY CORE ON THE MAP, found once. Cores are built by SiteSlice at level
	# load and do not come and go, so a scan here is enough and a per-frame
	# search would be waste.
	var from: Node = search_root
	if from == null:
		from = get_parent()   # the slice, whose parent is the level
	if from == null:
		from = self
	var n := 0
	for core in _cores(from):
		if core.has_signal("holder_changed"):
			core.holder_changed.connect(_on_holder_changed.bind(core))
			n += 1
	# NOT SILENT WHEN IT HEARS NOTHING. A CoreRetakers wired to no cores looks
	# exactly like one that is working right up until the player takes ground
	# and nobody ever comes for it.
	if n == 0:
		push_warning("CoreRetakers: found no cores under '%s', so no capture will ever call a counter-attack and any ground the player takes is theirs for good." % (from.name if from != null else "nothing"))


## A core changed hands. If it went to the player, somebody is coming for it.
func _on_holder_changed(_h, core) -> void:
	if core == null or not is_instance_valid(core):
		return
	if not core.has_method("is_held_by_player") or not core.is_held_by_player():
		return
	var id: int = core.get_instance_id()
	var now: int = Time.get_ticks_msec()
	if now - int(_last_call.get(id, -999999)) < int(cooldown_seconds * 1000.0):
		return
	_last_call[id] = now
	_send_retakers(core)


## THE NEAREST HOSTILE SQUAD, SENT TO STAND ON IT.
##
## `retake_hostiles` is read off the core rather than repeated here — it is the
## core that counts them, so it is the core that says how many are needed, and
## a second number here would be a squad sent to do a job that cannot be done.
func _send_retakers(core) -> void:
	var at: Vector3 = core.global_position
	if "interactible" in core and core.interactible != null \
			and is_instance_valid(core.interactible):
		at = core.interactible.global_position
	var want: int = int(core.retake_hostiles) if "retake_hostiles" in core else 2

	var best = null
	var best_d: float = call_radius
	for s in get_tree().get_nodes_in_group(&"squads"):
		if s == null or not is_instance_valid(s):
			continue
		# NOT THE PLAYER'S. player_commandable is the same test
		# EnemyForceSpawner._clear_level_hostiles uses, rather than reading a
		# faction off a squad that may not carry one.
		if "player_commandable" in s and s.player_commandable:
			continue
		if not s.has_method("get_center") or not s.has_method("set_objective"):
			continue
		var alive: int = _alive_in(s)
		if alive < want:
			continue   # cannot satisfy the count, so sending them is theatre
		var d: float = (s.get_center() as Vector3).distance_to(at)
		if d < best_d:
			best_d = d
			best = s
	if best == null:
		# Nobody close enough or nobody big enough. Said once per call rather
		# than silently, because "the enemy never came back for it" is exactly
		# the kind of thing that reads as a broken rule.
		print("[CoreRetakers] %s is held and no hostile squad within %.0fm can field %d — it stays taken." % [
			core.name, call_radius, want])
		return
	best.set_objective(Squad.SquadObjective.ADVANCE, at, true)
	_let_them_walk_in(best, at)
	print("[CoreRetakers] %s taken — sending %d from %.0fm to stand on it." % [
		core.name, _alive_in(best), best_d])


## LET THEM ACTUALLY GET THERE.
##
## Distance culling freezes a hostile more than activation_distance (75 m) from
## the player, and it deliberately ignores `always_active` — so an ADVANCE order
## across open ground is given, accepted, and then never walked. This is the
## same bug EnemyForceSpawner._let_them_walk_in exists to stop for
## reinforcements, and a retaker squad is in exactly that position: told to go
## somewhere, with a long way to go, and no reason to be near the player.
##
## IT WAS REAL HERE, NOT THEORETICAL. tools/test_core_retake_live.gd ordered a
## squad to a core from 32 m and found all three members still at 34.2 / 31.6 /
## 31.0 m after seventy seconds of simulation. The order was perfect; nobody
## moved. The player had walked away, so the whole map was frozen.
##
## NARROW, the same way the original is: only a squad ordered to cross ground
## it is not already standing on, and only for as long as the walk takes.
func _let_them_walk_in(squad, destination: Vector3) -> void:
	if squad == null or not is_instance_valid(squad):
		push_warning("CoreRetakers: asked to exempt a squad that is not there, so the counter-attack may freeze where it stands.")
		return
	var walk: float = (squad.get_center() as Vector3).distance_to(destination)
	for member in squad.get_orderable_soldiers():
		if member == null or not is_instance_valid(member):
			continue
		if not member.has_method("exempt_from_culling"):
			continue
		# Already inside the radius: it was never going to be culled on the way,
		# and an exemption it does not need is a brain running for the rest of
		# the mission for nothing.
		if ("activation_distance" in member) and walk <= float(member.activation_distance):
			continue
		member.exempt_from_culling(maxf(Enemy.CULL_EXEMPT_SECONDS, walk / ADVANCE_PACE))


## How many of this squad could actually walk to a core and stand there.
##
## get_orderable_soldiers() rather than a `members` field, which does not
## exist — it is the same list the squad uses when it gives its own orders, so
## a body that cannot be ordered is not counted as one that will arrive.
func _alive_in(squad) -> int:
	var n := 0
	for m in squad.get_orderable_soldiers():
		if m != null and is_instance_valid(m) and ("alive" in m) and m.alive:
			n += 1
	return n


func _cores(n: Node, out: Array = []) -> Array:
	var s = n.get_script()
	if s != null and String(s.resource_path).ends_with("holdable_core.gd"):
		out.append(n)
	for c in n.get_children():
		_cores(c, out)
	return out
