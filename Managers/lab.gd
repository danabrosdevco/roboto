extends Node

# ─────────────────────────────────────────────
# LABORATORY — AI-vs-AI fights in the arena, watched from a ghost camera.
#
# Master runs this instead of the game when lab_mode is ticked. It swaps the
# base for the arena WITHOUT going through the campaign — no deploy, no
# rewards, nothing saved — puts the player in spectator mode, and runs every
# matchup in the plan `repeats` times: spawn both squads, give each its order,
# watch until one side is gone or time runs out, score it, clear up, next.
#
# SCORING comes from the analytics recorder: a lab run is an attempt like a
# mission, so damage, shots and hits are counted by exactly the same hooks the
# playtest data uses. The results go to lab_report.md in the session folder
# (user://lab/<date_time>/), to the Output panel, and to a results screen.
#
# Fly with the usual movement keys, SPACE up, CTRL down, SHIFT fast. ESC pauses
# the fight — paused time is not counted.
#
# Everything here is reached untyped or by preload: LabPlan and LabMatchup are
# new classes, and Master loads this script, so nothing here may depend on the
# editor having registered them yet.
# ─────────────────────────────────────────────

const _Matchup := preload("res://Campaign/lab/lab_matchup.gd")
const SQUAD_SCENE := preload("res://Managers/AI/squad.tscn")
const ARENA := "res://maps/arena_level.tscn"
const POST_TAG := &"obj_arena_hostiles"
const SPREAD := 2.2
const BETWEEN_RUNS := 1.5
## Hostiles far from the ghost would go dormant (distance culling). A lab
## fight has to run wherever the camera happens to be.
const AWAKE_FOR := 1.0e6

signal finished(report_path: String)

## A LabPlan. Untyped on purpose — see the header.
var plan = null
var world: World = null
var recorder: Node = null

var results: Array = []          # [{"m": LabMatchup, "runs": [run, ...]}]
var report_path: String = ""
var _level: Node = null
var _post: Node3D = null
var _anchor: Vector3 = Vector3.ZERO
var _mid: Vector3 = Vector3.ZERO
var _dir: Vector3 = Vector3.BACK
var _run_events: Array = []
var _capturing: bool = false
var _hud_layer: CanvasLayer = null
var _hud: Label = null


# ─────────────────────────────────────────────
# RUN
# ─────────────────────────────────────────────
func run() -> void:
	results.clear()
	if plan == null or world == null:
		push_warning("Laboratory: no plan or no world — nothing to run.")
		finished.emit("")
		return
	if recorder != null and not recorder.recorded.is_connected(_on_recorded):
		recorder.recorded.connect(_on_recorded)
	if _level == null:
		await _enter_arena()
	_become_ghost()
	_build_hud()
	_hud_layer.visible = true
	Engine.time_scale = clampf(float(plan.speed), 0.5, 4.0)

	for m in plan.matchups:
		if m == null:
			continue
		var entry := {"m": m, "runs": []}
		results.append(entry)
		var n: int = plan.repeats_override if plan.repeats_override > 0 else maxi(1, m.repeats)
		for r in n:
			if r == 0:
				_frame_camera(m)
			var outcome: Dictionary = await _fight(m, r, n)
			entry["runs"].append(outcome)
			await _wait(BETWEEN_RUNS)

	Engine.time_scale = 1.0
	_hud_layer.visible = false
	report_path = _write_report()
	print(_summary_text())
	finished.emit(report_path)


# The arena, straight in: no deploy, no campaign, no save. Whatever was
# standing in it — the level's own garrison, the base's squad — is cleared, so
# the only robots in the room are the lab's.
func _enter_arena() -> void:
	PauseHold.take(&"lab")
	var scene: PackedScene = plan.level if plan.level != null else load(ARENA)
	var old = world.current_level
	var level = scene.instantiate()
	if old != null and is_instance_valid(old):
		old.queue_free()
	world.add_child(level)
	world.current_level = level
	await get_tree().process_frame
	await get_tree().process_frame
	_clear_level(level)
	await get_tree().process_frame
	world.register_world_objects(level)
	PauseHold.release(&"lab")
	_level = level
	_find_axis()


func _clear_level(level: Node) -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		if n is Soldier and is_instance_valid(n) and not n.is_queued_for_deletion():
			if world.ai_manager != null:
				world.ai_manager.deregister_enemy(n)
			n.queue_free()
	for s in get_tree().get_nodes_in_group("squads"):
		if is_instance_valid(s) and not s.is_queued_for_deletion() and level.is_ancestor_of(s):
			s.queue_free()


# The line the fights run along: from the hostile post (a garrison position
# with cover) toward the insertion point, down the length of the arena.
func _find_axis() -> void:
	_post = null
	for p in get_tree().get_nodes_in_group("squad_objective_points"):
		if p.get("tag") == POST_TAG and _level.is_ancestor_of(p):
			_post = p
	_anchor = _post.global_position if _post != null else Vector3.ZERO
	var insertion: Vector3 = _anchor + Vector3(0, 0, -40)
	var sp = _level.get("spawn_point")
	if sp != null:
		insertion = sp.global_position
	var d := insertion - _anchor
	d.y = 0.0
	_dir = d.normalized() if d.length() > 1.0 else Vector3.BACK
	_mid = _anchor.lerp(insertion, 0.5)
	# Open ground somewhere else on the map, chosen in the plan. A side told to
	# hold holds where it starts: there is no post out there.
	if plan.site != Vector3.ZERO:
		_post = null
		_mid = plan.site
		_dir = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(plan.site_heading))
		_anchor = _mid


# ─────────────────────────────────────────────
# ONE FIGHT
# ─────────────────────────────────────────────
func _fight(m, r: int, n: int) -> Dictionary:
	var place := _starts(m, r)
	var allies := _spawn_side(m.allies, Enums.Factions.ALLIED, place["ally"], place["hostile"], "ALLY")
	var hostiles := _spawn_side(m.hostiles, Enums.Factions.ENEMY, place["hostile"], place["ally"], "HOSTILE")
	var a_members: Array = allies.squad_members.duplicate() if allies != null else []
	var h_members: Array = hostiles.squad_members.duplicate() if hostiles != null else []
	await get_tree().physics_frame
	await get_tree().physics_frame
	_order(allies, m.ally_order, place["ally"], place["hostile"], hostiles, place["ally_on_post"])
	_order(hostiles, m.hostile_order, place["hostile"], place["ally"], allies, place["hostile_on_post"])

	_run_events.clear()
	_capturing = true
	if recorder != null:
		recorder.lab_begin(m.label, {"run": r + 1, "allies": _names(m.allies), "hostiles": _names(m.hostiles),
			"ally_order": _order_name(m.ally_order), "hostile_order": _order_name(m.hostile_order),
			"distance": m.distance, "swapped": place["swapped"]})

	var t := 0.0
	var outcome := "draw"
	while t < m.time_limit:
		await get_tree().process_frame
		if get_tree().paused:
			continue
		t += get_process_delta_time()
		var a_alive := _alive(a_members)
		var h_alive := _alive(h_members)
		_hud.text = "LAB  %s   RUN %d/%d   %s\nALLIES %d/%d  (%s)     HOSTILES %d/%d  (%s)\nFLY: MOVE KEYS  SPACE UP  CTRL DOWN  SHIFT FAST   ESC PAUSES" % [
			m.label.to_upper(), r + 1, n, _clock(t), a_alive, a_members.size(), _order_name(m.ally_order),
			h_alive, h_members.size(), _order_name(m.hostile_order)]
		if a_alive == 0 or h_alive == 0:
			outcome = "ally" if a_alive > 0 else ("hostile" if h_alive > 0 else "draw")
			break
	_capturing = false

	var counts := {"shots": {}, "hits": {}}
	if recorder != null:
		counts = recorder.lab_end(outcome, {"time": snappedf(t, 0.1)})
	var scored := _score(outcome, t, a_members, h_members, counts)
	await _clear_fight()
	return scored


func _starts(m, r: int) -> Dictionary:
	var a_holds: bool = m.ally_order == _Matchup.Order.HOLD
	var h_holds: bool = m.hostile_order == _Matchup.Order.HOLD
	var out := {"ally_on_post": false, "hostile_on_post": false, "swapped": false}
	if bool(m.hostiles_on_post):
		out["hostile"] = _anchor
		out["ally"] = _anchor + _dir * float(m.distance)
		out["hostile_on_post"] = true
		return out
	if a_holds != h_holds:
		# One defender: it sits on the post, the attacker `distance` down the line.
		var attacker: Vector3 = _anchor + _dir * float(m.distance)
		out["ally"] = _anchor if a_holds else attacker
		out["hostile"] = attacker if a_holds else _anchor
		out["ally_on_post"] = a_holds
		out["hostile_on_post"] = h_holds
		return out
	# Open ground, centred on the middle of the arena: hostiles at the post end,
	# allies at the insertion end, as on a mission — or the other way round on
	# every other run when swap_sides is on.
	var near: Vector3 = _mid - _dir * (float(m.distance) * 0.5)
	var far: Vector3 = _mid + _dir * (float(m.distance) * 0.5)
	out["hostile"] = near
	out["ally"] = far
	if m.swap_sides and r % 2 == 1:
		out["hostile"] = far
		out["ally"] = near
		out["swapped"] = true
	return out


func _spawn_side(roster: Array, faction: int, center: Vector3, facing: Vector3, callsign: String) -> Squad:
	var members: Array[Soldier] = []
	var n := roster.size()
	# The ring turned to face the other side. Laid out in world space it put
	# the same roster slot in front at one end of the line and at the back at
	# the other, so a mirror matchup was not a mirror: in the valley the second
	# robot on the list was always the first one shot on one side only.
	var toward := facing - center
	toward.y = 0.0
	var turn := Basis.looking_at(toward.normalized(), Vector3.UP) if toward.length() > 0.1 else Basis.IDENTITY
	for i in n:
		var frame = roster[i]
		if frame == null or frame.scene == null:
			continue
		var s := frame.scene.instantiate() as Soldier
		if s == null:
			continue
		s.faction = faction
		s.always_active = true
		s.soldier_name = "%s-%d" % [callsign, i + 1]
		# A frame whose scene carries no gun (a rover: its turret takes whatever
		# is fitted, and only shows a stand-in until then) goes in with the one
		# it is issued, as a recruit would. Otherwise it drove into every fight
		# unarmed.
		if frame.starting_weapon_id != &"" and s.weapon_mount != null \
				and not s.weapon_mount.get_children().any(func(c): return c is AIWeapon):
			var issued := _issued_weapon(frame)
			if issued != null:
				s.equip_weapon_scene(issued)
		if world.enemy_spawner != null:
			world.enemy_spawner._apply_frame(s, frame)
		s.set_meta(&"analytics_kind", frame.display_name)
		_level.add_child(s)
		s.global_position = _ground(center + turn * _ring(i, n))
		if world.ai_manager != null:
			world.ai_manager.register_enemy(s)
		s.wake(AWAKE_FOR)
		members.append(s)
	if members.is_empty():
		return null
	var squad := SQUAD_SCENE.instantiate() as Squad
	squad.name = "Lab_%s" % callsign
	squad.callsign = callsign
	squad.player_commandable = false
	squad.squad_members = members
	_level.add_child(squad)
	return squad


func _issued_weapon(frame) -> PackedScene:
	var campaign := get_tree().get_first_node_in_group("campaign")
	var cat = campaign.get("catalogue") if campaign != null else null
	var item = cat.item(frame.starting_weapon_id) if cat != null else null
	if item == null or item.ai_scene == null:
		push_warning("Laboratory: %s is issued '%s', which the catalogue cannot build; it fights unarmed." % [
			frame.display_name, frame.starting_weapon_id])
		return null
	return item.ai_scene


func _order(squad: Squad, order: int, own: Vector3, other: Vector3, enemy: Squad, on_post: bool) -> void:
	if squad == null:
		return
	squad.target_objective = _post if on_post else null
	match order:
		_Matchup.Order.HOLD:
			squad.set_objective(Squad.SquadObjective.DEFEND, own, true)
		_Matchup.Order.ADVANCE:
			squad.set_objective(Squad.SquadObjective.ADVANCE, other, true)
		_Matchup.Order.MOVE_AND_HOLD:
			squad.set_objective(Squad.SquadObjective.DEFEND, other, true)
		_Matchup.Order.ATTACK:
			var target: Node3D = null
			if enemy != null:
				for s in enemy.squad_members:
					if is_instance_valid(s) and s.alive:
						target = s
						break
			if target != null:
				squad.receive_player_order(Squad.SquadObjective.ATTACK, target.global_position, target)
			else:
				squad.set_objective(Squad.SquadObjective.ADVANCE, other, true)


# Everything the fight left behind: both squads, the wrecks, and anything a
# hatchling canister let out.
func _clear_fight() -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		if n is Soldier and is_instance_valid(n) and _level.is_ancestor_of(n):
			if world.ai_manager != null:
				world.ai_manager.deregister_enemy(n)
			n.queue_free()
	for s in get_tree().get_nodes_in_group("squads"):
		if is_instance_valid(s) and _level.is_ancestor_of(s):
			s.queue_free()
	await get_tree().process_frame
	BarkDirector.reset()


# ─────────────────────────────────────────────
# SCORING
# ─────────────────────────────────────────────
func _on_recorded(e: Dictionary) -> void:
	if _capturing and e.get("ev", "") == "damage":
		_run_events.append(e)


func _score(outcome: String, t: float, a_members: Array, h_members: Array, counts: Dictionary) -> Dictionary:
	var out := {"outcome": outcome, "time": t,
		"a_n": a_members.size(), "h_n": h_members.size(),
		"a_alive": _alive(a_members), "h_alive": _alive(h_members),
		"a_hp": _hp_left(a_members), "h_hp": _hp_left(h_members),
		"a_dmg": 0, "h_dmg": 0, "a_ff": 0, "h_ff": 0,
		"a_shots": 0, "a_hits": 0, "h_shots": 0, "h_hits": 0,
		"kinds": {}}
	for s in a_members:
		var ka := _kind(out, "ally", str(s.get_meta(&"analytics_kind", "?")))
		ka["fielded"] += 1
	for s in h_members:
		var kh := _kind(out, "enemy", str(s.get_meta(&"analytics_kind", "?")))
		kh["fielded"] += 1
	for e in _run_events:
		var atk: Dictionary = e.get("atk", {})
		var vic: Dictionary = e.get("vic", {})
		var a_side := str(atk.get("side", ""))
		var v_side := str(vic.get("side", ""))
		var dmg := int(e.get("dmg", 0))
		var lethal := bool(e.get("lethal", false))
		if a_side != "ally" and a_side != "enemy":
			continue
		var p := "a" if a_side == "ally" else "h"
		if v_side == a_side:
			out[p + "_ff"] += dmg
		else:
			out[p + "_dmg"] += dmg
			var k := _kind(out, a_side, str(atk.get("kind", "?")))
			k["dealt"] += dmg
			k["kills"] += 1 if lethal else 0
		if v_side == "ally" or v_side == "enemy":
			var kv := _kind(out, v_side, str(vic.get("kind", "?")))
			kv["taken"] += dmg
			kv["deaths"] += 1 if lethal else 0
	for key in counts.get("shots", {}):
		var p2 := "a" if str(key).begins_with("ally|") else ("h" if str(key).begins_with("enemy|") else "")
		if p2 == "":
			continue
		out[p2 + "_shots"] += int(counts["shots"][key])
		out[p2 + "_hits"] += int(counts.get("hits", {}).get(key, 0))
	return out


func _kind(out: Dictionary, side: String, kind: String) -> Dictionary:
	var key := "%s|%s" % [side, kind]
	if not out["kinds"].has(key):
		out["kinds"][key] = {"side": side, "kind": kind, "fielded": 0, "kills": 0, "deaths": 0, "dealt": 0, "taken": 0}
	return out["kinds"][key]


func _alive(members: Array) -> int:
	var n := 0
	for s in members:
		if is_instance_valid(s) and s.alive:
			n += 1
	return n


# The side's remaining health as a share of what it fielded.
func _hp_left(members: Array) -> float:
	var left := 0.0
	var total := 0.0
	for s in members:
		if not is_instance_valid(s):
			continue
		total += float(s.max_health)
		if s.alive:
			left += float(s.health)
	return left / total if total > 0.0 else 0.0


# ─────────────────────────────────────────────
# THE REPORT
# ─────────────────────────────────────────────
## Per matchup: {label, runs, ally_wins, hostile_wins, draws, time, winner_left, winner_hp, a_dmg, h_dmg, a_acc, h_acc}
func summary() -> Array:
	var rows: Array = []
	for entry in results:
		var m = entry["m"]
		var runs: Array = entry["runs"]
		var s := {"label": m.label, "runs": runs.size(), "ally_wins": 0, "hostile_wins": 0, "draws": 0,
			"time": 0.0, "winner_left": 0.0, "winner_hp": 0.0, "decided": 0,
			"a_dmg": 0, "h_dmg": 0, "a_shots": 0, "a_hits": 0, "h_shots": 0, "h_hits": 0,
			"setup": "%s (%s) vs %s (%s), %dm" % [_roster_text(m.allies), _order_name(m.ally_order),
				_roster_text(m.hostiles), _order_name(m.hostile_order), int(m.distance)]}
		for run in runs:
			s["time"] += float(run["time"])
			s["a_dmg"] += int(run["a_dmg"])
			s["h_dmg"] += int(run["h_dmg"])
			s["a_shots"] += int(run["a_shots"])
			s["a_hits"] += int(run["a_hits"])
			s["h_shots"] += int(run["h_shots"])
			s["h_hits"] += int(run["h_hits"])
			match run["outcome"]:
				"ally":
					s["ally_wins"] += 1
					s["decided"] += 1
					s["winner_left"] += float(run["a_alive"]) / maxf(1, run["a_n"])
					s["winner_hp"] += float(run["a_hp"])
				"hostile":
					s["hostile_wins"] += 1
					s["decided"] += 1
					s["winner_left"] += float(run["h_alive"]) / maxf(1, run["h_n"])
					s["winner_hp"] += float(run["h_hp"])
				_:
					s["draws"] += 1
		rows.append(s)
	return rows


func _write_report() -> String:
	var o: PackedStringArray = []
	o.append("# Laboratory — %s" % str(plan.title))
	o.append("")
	if str(plan.question) != "":
		o.append("> %s" % str(plan.question).replace("\n", "\n> "))
		o.append("")
	o.append("Generated %s on %s. Win rates are from the ALLIES' side; \"winner survivors\" and \"winner HP\" say how close the wins were (100%% = untouched)." % [
		Time.get_datetime_string_from_system(), preload("res://Managers/build_version.gd").label()])
	o.append("")
	o.append("## Results")
	o.append("")
	o.append("| Matchup | Setup | Runs | Ally wins | Hostile wins | Draws | Avg time (s) | Winner survivors | Winner HP left | Dmg dealt A / H | Accuracy A / H |")
	o.append("|---|---|---|---|---|---|---|---|---|---|---|")
	for s in summary():
		var d: float = maxf(1, s["decided"])
		o.append("| %s | %s | %d | %s | %s | %d | %.0f | %s | %s | %d / %d | %s / %s |" % [
			s["label"], s["setup"], s["runs"], _pct(s["ally_wins"], s["runs"]), _pct(s["hostile_wins"], s["runs"]),
			s["draws"], s["time"] / maxf(1, s["runs"]),
			_pct(s["winner_left"], d) if s["decided"] > 0 else "-", _pct(s["winner_hp"], d) if s["decided"] > 0 else "-",
			s["a_dmg"], s["h_dmg"], _pct(s["a_hits"], s["a_shots"]), _pct(s["h_hits"], s["h_shots"])])
	o.append("")
	o.append("## By chassis (all matchups)")
	o.append("")
	var kinds := {}
	for entry in results:
		for run in entry["runs"]:
			for key in run["kinds"]:
				var k: Dictionary = run["kinds"][key]
				if not kinds.has(key):
					kinds[key] = {"side": k["side"], "kind": k["kind"], "fielded": 0, "kills": 0, "deaths": 0, "dealt": 0, "taken": 0}
				for f in ["fielded", "kills", "deaths", "dealt", "taken"]:
					kinds[key][f] += int(k[f])
	o.append("| Chassis | Side | Fielded | Kills | Deaths | Survived | Dmg dealt | Dmg taken | Dmg dealt per body | Kills per body |")
	o.append("|---|---|---|---|---|---|---|---|---|---|")
	for key in kinds:
		var k: Dictionary = kinds[key]
		var f: float = maxf(1, k["fielded"])
		o.append("| %s | %s | %d | %d | %d | %s | %d | %d | %.0f | %.2f |" % [k["kind"], "ally" if k["side"] == "ally" else "hostile",
			k["fielded"], k["kills"], k["deaths"], _pct(k["fielded"] - k["deaths"], k["fielded"]),
			k["dealt"], k["taken"], k["dealt"] / f, k["kills"] / f])
	o.append("")
	o.append("## Every run")
	o.append("")
	o.append("| Matchup | Run | Winner | Time (s) | Allies left | Hostiles left | Dmg A / H | Friendly fire A / H |")
	o.append("|---|---|---|---|---|---|---|---|")
	for entry in results:
		var i := 0
		for run in entry["runs"]:
			i += 1
			o.append("| %s | %d | %s | %.0f | %d/%d | %d/%d | %d / %d | %d / %d |" % [entry["m"].label, i, run["outcome"],
				run["time"], run["a_alive"], run["a_n"], run["h_alive"], run["h_n"], run["a_dmg"], run["h_dmg"],
				run["a_ff"], run["h_ff"]])
	var text := "\n".join(o)

	var dir: String = recorder.session_dir() if recorder != null and recorder.session_dir() != "" else "user://lab"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + "/lab_report.md"
	var f2 := FileAccess.open(path, FileAccess.WRITE)
	if f2 != null:
		f2.store_string(text)
		f2.close()
	return ProjectSettings.globalize_path(path)


func _summary_text() -> String:
	var lines: PackedStringArray = ["", "── LABORATORY: %s ──" % str(plan.title)]
	for s in summary():
		lines.append("%-34s  allies %4s  hostiles %4s  draws %d   avg %3.0fs   winner hp %s" % [
			s["label"], _pct(s["ally_wins"], s["runs"]), _pct(s["hostile_wins"], s["runs"]), s["draws"],
			s["time"] / maxf(1, s["runs"]), _pct(s["winner_hp"], s["decided"]) if s["decided"] > 0 else "-"])
	lines.append("Report: %s" % report_path)
	return "\n".join(lines)


# ─────────────────────────────────────────────
# THE GHOST
# ─────────────────────────────────────────────
func _become_ghost() -> void:
	var p: Player = world.player
	if not p.spectator_mode:
		p._toggle_spectator()
	# A stray frag must not end the experiment with a YOU DIED screen.
	p.damage_taken_scale = 0.0


# Side-on and above the line between the two starts, looking at the middle.
func _frame_camera(m) -> void:
	var place := _starts(m, 0)
	var focus: Vector3 = (place["ally"] + place["hostile"]) * 0.5
	var side := _dir.cross(Vector3.UP).normalized()
	var reach := maxf(18.0, float(m.distance) * 0.9)
	var p: Player = world.player
	p.global_position = focus + side * reach + Vector3.UP * (reach * 0.6)
	var to := focus - p.global_position
	var yaw := atan2(-to.x, -to.z)
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	p.look_direction = Vector3(pitch, yaw, 0.0)
	p.velocity = Vector3.ZERO


func _build_hud() -> void:
	if _hud_layer != null:
		return
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 44
	add_child(_hud_layer)
	_hud = Label.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hud.offset_top = 12
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_theme_font_size_override("font_size", 20)
	_hud.add_theme_color_override("font_color", HUDPalette.BRIGHT)
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_hud.add_theme_constant_override("outline_size", 6)
	_hud_layer.add_child(_hud)


# ─────────────────────────────────────────────
# SMALL THINGS
# ─────────────────────────────────────────────
# Down onto the floor from just above the intended spot. It was cast from 30m
# up, and near the post the first thing under 30m is the building's roof — the
# hostiles started the fight standing on it. From 1m up the ray begins below
# any roof, and a ray that starts inside a cover block passes out through it
# to the floor rather than stopping on top.
func _ground(p: Vector3) -> Vector3:
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.DOWN * 20.0)
	var hit := space.intersect_ray(q)
	return (hit.position + Vector3.UP * 0.3) if hit else p


func _ring(i: int, n: int) -> Vector3:
	if n <= 1:
		return Vector3.ZERO
	var angle := TAU * float(i) / float(n)
	return Vector3(cos(angle), 0.0, sin(angle)) * SPREAD * (1.0 + float(n) / 8.0)


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		if not get_tree().paused:
			t += get_process_delta_time()


func _names(roster: Array) -> Array:
	var out: Array = []
	for f in roster:
		if f != null:
			out.append(f.display_name)
	return out


# "4 Rifle Trooper + 1 Chaser Chassis"
func _roster_text(roster: Array) -> String:
	var counts := {}
	var order: Array = []
	for f in roster:
		if f == null:
			continue
		if not counts.has(f.display_name):
			counts[f.display_name] = 0
			order.append(f.display_name)
		counts[f.display_name] += 1
	var parts: PackedStringArray = []
	for name in order:
		parts.append("%d %s" % [counts[name], name])
	return " + ".join(parts) if not parts.is_empty() else "nobody"


static func _order_name(order: int) -> String:
	match order:
		_Matchup.Order.HOLD:
			return "HOLD"
		_Matchup.Order.ADVANCE:
			return "ADVANCE"
		_Matchup.Order.ATTACK:
			return "ATTACK"
		_Matchup.Order.MOVE_AND_HOLD:
			return "MOVE & HOLD"
	return "?"


static func _pct(a: float, b: float) -> String:
	if b <= 0.0:
		return "-"
	return "%d%%" % int(round(100.0 * a / b))


static func _clock(t: float) -> String:
	return "%d:%02d" % [floori(t / 60.0), int(t) % 60]


func _exit_tree() -> void:
	# Quitting mid-plan must not leave the next launch in fast-forward.
	Engine.time_scale = 1.0
