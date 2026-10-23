extends SceneTree

# ─────────────────────────────────────────────
# SALIENT — "OVER THE TOP". Written, not hand-authored.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/build_salient_mission.gd
#
# WHY A BUILDER. Forty-one squads is about nine hundred lines of .tres, every
# one of them an ExtResource index and a SubResource id that has to agree with
# a load_steps count at the top of the file. Hand-written, the first mistake is
# silent — Godot drops a property it cannot parse and the mission loads with an
# empty force, which is exactly how Valley Siege once shipped as an empty
# valley. Written from a script, the counts cannot disagree.
#
# Re-runnable: it overwrites the mission in place, so retuning the force is an
# edit here and one command rather than a thousand-line diff.
#
# ── WHAT THIS MISSION IS ─────────────────────
# The hardest thing in the game, deliberately, and the only trench assault.
#
# The map is an axis: spawn at x -468, out at x +470, and the eleven squad
# posts are lines across it. So the force is built in DEPTH rather than spread
# over ground — four held lines, each heavier than the last, and reinforcement
# waves that arrive behind whichever one you are currently on.
#
# The difficulty is NOT a stat multiplier. It is:
#   - every garrison squad at kit_variance 1.0, so every body is upgraded
#   - heavy frames at the back where you reach them tired
#   - quadcopter flights on timers, so the clock is a threat by itself
#   - mortar tracks with Sensor Relays, which under the contact rules means
#     they fire on what the infantry can see rather than needing their own eyes
#   - waves keyed to kill count, so clearing faster brings them faster
# ─────────────────────────────────────────────

const OUT := "res://Campaign/missions/mission_salient_1_overthetop.tres"
const LEVEL := "res://maps/salient_level.tscn"
const CHASSIS := "res://Campaign/chassis/chassis_%s.tres"

var _frames: Dictionary = {}


func _init() -> void:
	var m := MissionDefinition.new()
	m.id = &"salient_1_overthetop"
	m.display_name = "Over The Top"
	m.briefing = "The salient has been held for nine weeks and shelled for six. Four lines, dug in depth, with the tubes that have been ranging on us sat behind the last of them.\n\nThere is no flank. The ground is nine hundred metres wide and every metre of it is observed. You will go up the middle, you will take the lines in order, and you will do it with whatever you still have when you get there.\n\nBring everything."
	m.level_scene = load(LEVEL)
	m.map_position = Vector2(0.62, 0.38)
	m.replace_level_enemies = true
	m.squad_size = -1
	m.repeatable = true
	m.reward_resources = 900
	m.compute_reward = 4
	# UNGATED ON PURPOSE, for now. It belongs after causeway_1_tower in the
	# ladder and is left selectable so it can be played without clearing the
	# campaign first. Put `causeway_1_tower` in `requires` to seat it properly.
	m.requires = []
	m.unlocks = []
	m.active_objectives = [
		&"sal_first_line", &"sal_support", &"sal_guns", &"sal_back", &"sal_extract",
	]

	var force: Array[EnemySquadSpec] = []

	# ══ THE FIRST LINE ════════════════════════
	# The saps flank the approach rather than sit on it. Walking up the middle
	# is punished by the two positions you did not clear.
	force.append(_garrison("ZASEKA", "obj_salient_sap_north", 1.0, [
		["rifleman", 8], ["shotgunner", 3], ["marksman", 1], ["mechanic", 1]]))
	force.append(_garrison("KOLCHUGA", "obj_salient_sap_south", 1.0, [
		["rifleman", 8], ["shotgunner", 3], ["marksman", 1], ["mechanic", 1]]))
	# The crater is forward of the line, in no-man's-land. Chasers, so it
	# cannot be ignored on the way past.
	force.append(_garrison("SHCHIT", "obj_salient_crater", 0.8, [
		["rifleman", 5], ["chaser", 4]]))
	# The trench itself. Two lobber rovers, both with a Sensor Relay — see
	# forced_modules: this is a set-piece, not a roll.
	var front := _garrison("OPLOT", "obj_salient_front", 1.0, [
		["rifleman", 10], ["shotgunner", 4], ["marksman", 2], ["mechanic", 2],
		["rover_gl", 2]])
	front.forced_modules = [&"optics"]
	force.append(front)

	# ══ THE SUPPORT LINE ══════════════════════
	# Where the heavy frames start. A Bulwark is 400 hp behind a Heavy MG and
	# there is no getting round it on this map.
	force.append(_garrison("TIELI", "obj_salient_support", 1.0, [
		["rifleman", 10], ["shotgunner", 2], ["mechanic", 2],
		["bulwark", 2], ["walker", 1], ["mortar_track", 2]]))
	# The redoubt is 140 m off the axis to the north. Leave it and it shoots
	# into the flank of everything you do on the support line.
	force.append(_garrison("JINGANG", "obj_salient_redoubt", 1.0, [
		["rifleman", 6], ["marksman", 3], ["bulwark", 1], ["rover", 1]]))

	# ══ THE GUN LINE ══════════════════════════
	# Mortar tracks with Relays. Under the contact rules a tube with eyes on
	# the net fires at what the infantry can see, so these are ranging on you
	# from the moment anything in front of them has line of sight.
	# FIVE tubes, because the art now has five mortar pits on the gun line at
	# x 330, spaced z -160 to +160. Four put a track in a pit and left one
	# empty, which on a map this deliberate reads as a mistake.
	var guns := _garrison("LEIYU", "obj_salient_guns", 1.0, [
		["mortar_track", 5], ["rifleman", 6], ["bulwark", 1], ["mechanic", 2]])
	guns.forced_modules = [&"optics"]
	force.append(guns)
	force.append(_garrison("SHUANGYAN", "obj_salient_railhead", 1.0, [
		["rifleman", 6], ["rover_gl", 2], ["mechanic", 1]]))

	# ══ THE BACK POSITIONS ════════════════════
	force.append(_garrison("BAITA", "obj_salient_church", 1.0, [
		["marksman", 4], ["rifleman", 5], ["bulwark", 1]]))
	force.append(_garrison("HEILONG", "obj_salient_village", 1.0, [
		["rifleman", 7], ["shotgunner", 2], ["walker", 1], ["rover", 1]]))

	# ══ THE OBSERVATION TOWER ═════════════════
	# Alone in no-man's-land at (-14, -122), between the player's nest line at
	# x -160 and the enemy's at x +70. Marksmen and a Relay: it exists to SEE,
	# and under the contact rules what it sees the gun line shoots at.
	#
	# Small on purpose. Four bodies on open ground is not a position to grind
	# through, it is a decision about whether to go and silence it before the
	# mortars start walking onto you.
	var tower := _garrison("DOZOR", "obj_salient_op_tower", 1.0, [
		["marksman", 3], ["rifleman", 1]])
	tower.forced_modules = [&"optics"]
	force.append(tower)

	# ══ INFANTRY WAVES ════════════════════════
	# Keyed to KILL COUNT, not to objectives, so clearing faster brings them
	# faster. The push is the pressure; there is no pausing to reorganise.
	var waves := [
		["NABEG", "obj_salient_front", 18, [["rifleman", 9], ["shotgunner", 3]]],
		["PRILIV", "obj_salient_support", 34, [["rifleman", 10], ["chaser", 4]]],
		["SHKVAL", "obj_salient_front", 52, [["rifleman", 8], ["shotgunner", 4], ["marksman", 2]]],
		["TARAN", "obj_salient_support", 70, [["rifleman", 10], ["chaser", 5], ["leaper", 3]]],
		["OBVAL", "obj_salient_guns", 90, [["rifleman", 12], ["mechanic", 2]]],
		["POTOK", "obj_salient_support", 110, [["rifleman", 10], ["shotgunner", 5]]],
		["KLIN", "obj_salient_guns", 132, [["rifleman", 9], ["chaser", 6]]],
		["SHTURM", "obj_salient_village", 155, [["rifleman", 12], ["shotgunner", 4], ["marksman", 2]]],
		["HEICHAO", "obj_salient_guns", 180, [["rifleman", 14], ["mechanic", 2]]],
		["JULANG", "obj_salient_village", 210, [["rifleman", 12], ["chaser", 6], ["leaper", 4]]],
	]
	for w in waves:
		force.append(_wave(w[0], w[1], int(w[2]), 0.0, w[3], 0.75))

	# ══ ARMOUR COUNTER-ATTACKS ════════════════
	# On kill count as well, and heavier each time.
	force.append(_wave("TIELIU", "obj_salient_support", 60, 0.0, [
		["walker", 1], ["rifleman", 6]], 1.0))
	force.append(_wave("XUEBENG", "obj_salient_guns", 120, 0.0, [
		["bulwark", 1], ["walker", 1], ["rifleman", 6]], 1.0))
	force.append(_wave("LONGJUAN", "obj_salient_village", 190, 0.0, [
		["walker", 2], ["bulwark", 1], ["mechanic", 2]], 1.0))

	# ══ QUADCOPTER FLIGHTS ════════════════════
	# ON A CLOCK, not on kills. Everything else in the mission answers how well
	# you are doing; this answers how long you have been here, which is the one
	# pressure a careful player cannot play around by going slowly.
	#
	# spawn_offset lifts them clear and puts them out at distance: a tag in
	# this level marks ground, because every tag was written for infantry.
	var flights := [
		["KOBCHIK", "obj_salient_front", 150.0, Vector3(-60, 45, -80)],
		["SAPSAN", "obj_salient_support", 270.0, Vector3(-40, 45, 90)],
		["STREKOZA", "obj_salient_guns", 400.0, Vector3(60, 50, -70)],
		["TIEYI", "obj_salient_support", 530.0, Vector3(0, 50, 100)],
		["JIUTIAN", "obj_salient_village", 660.0, Vector3(40, 55, -60)],
	]
	for fl in flights:
		var f := _wave(fl[0], fl[1], 0, float(fl[2]), [["gunship", 3]], 1.0)
		f.spawn_offset = fl[3]
		force.append(f)

	m.enemy_force = force

	var bodies := 0
	for s in force:
		bodies += s.body_count()
	var err := ResourceSaver.save(m, OUT)
	if err != OK:
		printerr("build_salient_mission: could not write %s (%s)" % [OUT, error_string(err)])
		quit(1)
		return
	print("wrote %s — %d squads, %d bodies" % [OUT, force.size(), bodies])
	quit(0)


## A dug-in squad on `post`, present from the first frame.
func _garrison(callsign: String, post: String, variance: float, roster: Array) -> EnemySquadSpec:
	var s := EnemySquadSpec.new()
	s.callsign = callsign
	s.posture = EnemySquadSpec.Posture.GARRISON
	s.post_tag = StringName(post)
	s.spawn_tag = StringName(post)
	s.faction = Enums.Factions.ENEMY
	s.kit_variance = variance
	s.count = 0
	s.roster = _roster(roster)
	return s


## A reinforcement, held back until `after_kills` of the force are down or
## `after_seconds` of mission time have passed.
func _wave(callsign: String, post: String, after_kills: int, after_seconds: float,
		roster: Array, variance: float) -> EnemySquadSpec:
	var s := EnemySquadSpec.new()
	s.callsign = callsign
	s.posture = EnemySquadSpec.Posture.RESERVE
	s.post_tag = StringName(post)
	s.spawn_tag = StringName(post)
	s.faction = Enums.Factions.ENEMY
	s.kit_variance = variance
	s.count = 0
	s.roster = _roster(roster)
	# The tag still has to be set even when a count or a clock is what fires
	# it: it is what the wave is called in the log.
	s.reinforcement_tag = StringName(callsign.to_lower() + "_wave")
	s.wake_after_kills = after_kills
	s.wake_after_seconds = after_seconds
	# A reinforcement crossing open ground has to be let to walk — see the
	# note on _let_them_walk_in in the spawner.
	s.always_active = true
	return s


func _roster(spec: Array) -> Array[ChassisDefinition]:
	var out: Array[ChassisDefinition] = []
	for pair in spec:
		var frame := _frame(String(pair[0]))
		if frame == null:
			push_warning("build_salient_mission: no chassis '%s'." % pair[0])
			continue
		for _i in int(pair[1]):
			out.append(frame)
	return out


## Chassis by id. Indexed from the directory rather than guessed from the
## filename: the Leaper and the Quadcopter Bomber are in files named something
## else, and chassis_<id>.tres does not hold for them.
func _frame(id: String) -> ChassisDefinition:
	if _frames.is_empty():
		var d := DirAccess.open("res://Campaign/chassis")
		for fn in d.get_files():
			if not fn.ends_with(".tres"):
				continue
			var c: ChassisDefinition = load("res://Campaign/chassis/" + fn)
			if c != null:
				_frames[String(c.id)] = c
	return _frames.get(id)
