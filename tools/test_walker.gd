extends SceneTree

# ─────────────────────────────────────────────
# WALKER TESTS
#
# Run with:  bash tools/test.sh
# Directly:  godot --headless --path . --script res://tools/test_walker.gd
#
# Two things about this frame are easy to break and impossible to see in a
# parse check.
#
# 1. IT IS BOUGHT HALF-ARMED. Its price covers the frame and the gun it is
#    built around; the coax mount arrives empty and is a separate purchase,
#    which is the only reason a second mount is interesting. One line in
#    CampaignState.recruit() filling weapon_ids[1] from the chassis would quietly
#    hand it over for free again.
#
# 2. THE LEGS ANSWER FOR DIRECTION. A Walker in combat faces its target and
#    moves wherever the fight sends it, so heading and travel routinely
#    disagree. A gait that only knows the distance covered plays the same
#    forward march for a backpedal and a sidestep, feet scuffing the wrong way.
#    The cycle runs backwards for a reverse step and turns into a sideways
#    shuffle for a strafe, and this pins both.
#
# The gait is driven by hand here: the walker is never added to the tree, its
# position is moved a step at a time and _tick_gait is called for each step. It
# needs no level, no navmesh and no physics — the gait's whole input is how far
# the body moved and in which direction.
# ─────────────────────────────────────────────

const WALKER := "res://Character/characters/ai/walker.tscn"
const STEP := 0.05        # metres per frame, about a Walker's real pace
const DT := 1.0 / 60.0

var _checks: int = 0
var _failures: int = 0
var _spawned: Array[Node] = []


func check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("PASS  %s" % label)
	else:
		print("FAIL  %s  %s" % [label, detail])
		_failures += 1


# ─────────────────────────────────────────────
# 1. HALF-ARMED
# ─────────────────────────────────────────────
func test_it_is_bought_half_armed() -> void:
	var cat: ItemCatalogue = load("res://Campaign/items & catalogue/test_item_catalogue.tres")
	var state := CampaignState.new()
	state.armoury = Armoury.new()
	state.catalogue = cat
	state.award(2000)
	var frame := cat.chassis_def(&"walker")
	if frame == null:
		check("the walker is in the catalogue", false, "no chassis_def(&\"walker\")")
		return
	check("the walker has two weapon mounts", frame.weapon_slots == 2, str(frame.weapon_slots))
	var w := state.recruit(frame)
	check("recruiting one works", w != null)
	if w == null:
		return
	check("it arrives with its main gun fitted", w.weapon_ids.size() == 2 and w.weapon_ids[0] == frame.starting_weapon_id,
		str(w.weapon_ids))
	check("...and the coax mount EMPTY, to be bought", w.weapon_ids[1] == &"", str(w.weapon_ids))
	check("...and the coax was not quietly taken from stores either",
		state.armoury.spare(frame.coax_weapon_id) == 0, str(state.armoury.spare(frame.coax_weapon_id)))
	# The chassis still says what the mount is designed around — the laboratory
	# reads it to field a complete frame. It just is not issued.
	check("the chassis still names the coax it is designed around", frame.coax_weapon_id != &"",
		str(frame.coax_weapon_id))


# ─────────────────────────────────────────────
# 2. THE GAIT
# ─────────────────────────────────────────────
# Walks `steps` frames in `way` (the walker's own local direction) and reports
# the extremes each joint reached, plus how flat the soles stayed.
func _walk(way: Vector3, steps: int = 90) -> Dictionary:
	var walker: Node3D = load(WALKER).instantiate()
	# IN THE TREE, BUT NOT DRIVING ITSELF. Node3D only recomputes a global
	# transform once it is inside the tree, and the gait's whole input is global
	# movement — outside it the body never appears to move at all. So it goes in,
	# and its own _physics_process goes off, leaving the position under this
	# test's control and no navmesh needed.
	root.add_child(walker)
	walker.set_physics_process(false)
	_spawned.append(walker)
	walker.alive = true
	walker.downed = false
	if walker.rig != null:
		walker._rig_rest_y = walker.rig.position.y
	var out := {
		"hip_x": [0.0, 0.0], "hip_z": [0.0, 0.0], "gait_first": 0.0, "gait_last": 0.0,
		"sole_x": 0.0, "sole_z": 0.0,
	}
	for i in steps:
		walker.position += way.normalized() * STEP
		walker._tick_gait(DT)
		if i == 0:
			out["gait_first"] = walker._gait
		var hip: Node3D = walker.hip_left
		var knee: Node3D = walker.knee_left
		var foot: Node3D = walker.foot_left
		out["hip_x"] = [minf(out["hip_x"][0], hip.rotation.x), maxf(out["hip_x"][1], hip.rotation.x)]
		out["hip_z"] = [minf(out["hip_z"][0], hip.rotation.z), maxf(out["hip_z"][1], hip.rotation.z)]
		# The sole is meant to stay parallel to the ground: the foot counters
		# everything above it on both axes.
		out["sole_x"] = maxf(out["sole_x"], absf(hip.rotation.x + knee.rotation.x + foot.rotation.x))
		out["sole_z"] = maxf(out["sole_z"], absf(hip.rotation.z + foot.rotation.z))
	out["gait_last"] = walker._gait
	out["side_swing"] = deg_to_rad(walker.side_swing_degrees)
	out["hip_swing"] = deg_to_rad(walker.hip_swing_degrees)

	return out


func test_walking_forward_strides() -> void:
	var r := _walk(Vector3.FORWARD)
	check("walking forward swings the hips fore and aft",
		r["hip_x"][1] > r["hip_swing"] * 0.8 and r["hip_x"][0] < -r["hip_swing"] * 0.8, str(r["hip_x"]))
	check("...and does not splay them sideways", absf(r["hip_z"][0]) < 0.001 and absf(r["hip_z"][1]) < 0.001,
		str(r["hip_z"]))
	check("...running the cycle forwards", r["gait_last"] > r["gait_first"],
		"%f -> %f" % [r["gait_first"], r["gait_last"]])
	check("...with the soles flat", r["sole_x"] < 0.001 and r["sole_z"] < 0.001,
		"%f / %f" % [r["sole_x"], r["sole_z"]])


func test_backing_up_runs_the_cycle_in_reverse() -> void:
	var r := _walk(Vector3.BACK)
	check("backing up still swings the hips fore and aft",
		r["hip_x"][1] > r["hip_swing"] * 0.8 and r["hip_x"][0] < -r["hip_swing"] * 0.8, str(r["hip_x"]))
	# THE WHOLE POINT: the same stride, played backwards. Hips swing the other
	# way round and the knee bends on the other half of the step.
	check("...but RUNS THE CYCLE BACKWARDS, which is what a reverse step is",
		r["gait_last"] < r["gait_first"], "%f -> %f" % [r["gait_first"], r["gait_last"]])
	check("...with the soles flat", r["sole_x"] < 0.001 and r["sole_z"] < 0.001,
		"%f / %f" % [r["sole_x"], r["sole_z"]])


func test_strafing_shuffles_sideways() -> void:
	var r := _walk(Vector3.RIGHT)
	check("strafing swings the hips OUT TO THE SIDE",
		r["hip_z"][1] > r["side_swing"] * 0.8, str(r["hip_z"]))
	check("...and stops striding fore and aft", absf(r["hip_x"][0]) < 0.001 and absf(r["hip_x"][1]) < 0.001,
		str(r["hip_x"]))
	# A SHUFFLE, NOT A SCISSOR. Stepping right, neither leg ever goes left: the
	# lead foot reaches out and the trailing one closes up behind it. On a plain
	# sine one leg would go out while the other went the opposite way, and the
	# machine would read as standing there doing the splits.
	check("...and NEITHER LEG EVER GOES THE OTHER WAY", r["hip_z"][0] > -0.001, str(r["hip_z"]))
	check("...with the soles flat", r["sole_x"] < 0.001 and r["sole_z"] < 0.001,
		"%f / %f" % [r["sole_x"], r["sole_z"]])


func test_strafing_the_other_way_leans_the_other_way() -> void:
	var r := _walk(Vector3.LEFT)
	check("stepping left, neither leg ever goes right", r["hip_z"][1] < 0.001, str(r["hip_z"]))
	check("...and it still reaches a full sidestep", r["hip_z"][0] < -r["side_swing"] * 0.8, str(r["hip_z"]))


func _init() -> void:
	Settings.path = "user://settings_walker_test.json"
	await process_frame
	test_it_is_bought_half_armed()
	test_walking_forward_strides()
	test_backing_up_runs_the_cycle_in_reverse()
	test_strafing_shuffles_sideways()
	test_strafing_the_other_way_leans_the_other_way()

	# Freeing a robot in the same frame it was spawned takes the process down on
	# exit. Give them a moment first — it costs a fraction of a second and the
	# suite stops ending in a crash report.
	for _i in 60:
		await process_frame
	for w in _spawned:
		if is_instance_valid(w):
			w.free()
	if FileAccess.file_exists("user://settings_walker_test.json"):
		DirAccess.remove_absolute("user://settings_walker_test.json")
	print("")
	if _failures == 0:
		print("PASS  %d checks" % _checks)
	else:
		print("FAILED  %d of %d checks" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)
