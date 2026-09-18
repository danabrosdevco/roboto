extends Node

# ─────────────────────────────────────────────
# ANALYTICS — what happened in a play session, written down as it happens.
#
# ONE EVENT LOG, A FEW CHOKE POINTS. Everything that says how someone plays
# already funnels through a handful of places: apply_damage on robots and on
# the player, the two weapon fire paths, the player's ammo pool, healing,
# squad orders, grenade throws, objectives, and the campaign's deploy and
# extract. Each calls one static function here. A new enemy, gun, module or
# mission shows up in the data with no extra work — only a new MECHANIC needs
# a hook.
#
# OUTPUT, per session, in user://analytics/<date_time>/:
#   events.jsonl  one JSON object per line: the raw record, for parsing
#   report.md     a readable summary, rewritten after every mission and at quit
# tools/analytics.sh merges any number of session folders into one report.
# Local files only; nothing leaves the machine.
#
# OFF for headless runs and --script harnesses, so the test suites never write
# into the folder playtest data is collected from.
#
# Game code reaches this by preload, never by class_name — see the note on
# open-editor clobbering in tutorial_label.gd.
# ─────────────────────────────────────────────

const _Report := preload("res://Managers/analytics_report.gd")

const ROOT := "user://analytics"
const FLUSH_SECONDS := 2.0
## How far back "what hit you before you died" looks, in mission seconds.
const RECENT_HITS_SECONDS := 6.0

# The recorder, while one is running. Every static entry point is a no-op
# without it, so game code never has to ask.
static var _active: Node = null
# Set around a blast's damage calls, so a grenade that lands after you have
# switched back to your rifle is not scored as a rifle kill.
static var _cause: String = ""
## Tests only: record even under a harness, into dir_override.
static var force_enable: bool = false
static var dir_override: String = ""

## Every event as it is written. The laboratory listens to score its fights.
signal recorded(e: Dictionary)

var _file: FileAccess = null
var _dir: String = ""
# Set while a laboratory fight runs: it stands in for the mission id.
var _lab_label: String = ""
var _events: Array = []
var _session_start_ms: int = 0
var _flush_t: float = 0.0
var _campaign: Node = null

# ── the current attempt ──
var _attempt: int = 0
var _mission: MissionDefinition = null
var _in_mission: bool = false
# Play time: this node pauses with the tree, so menus, the briefing and the
# squad manager are not counted as time spent on the mission.
var _mission_time: float = 0.0
var _died: bool = false
var _squad_pending: bool = false
var _shots: Dictionary = {}           # attacker key -> rounds fired
var _hits: Dictionary = {}            # attacker key -> rounds that connected
var _last_shot_frame: Dictionary = {}
var _last_hit_frame: Dictionary = {}
var _order_time: Dictionary = {}      # squad callsign -> {ORDER: seconds}
var _order_state: Dictionary = {}     # squad instance id -> {callsign, order, since}
var _watched_squads: Array = []
var _recent_player_hits: Array = []
var _objectives_seen: Dictionary = {}


# ─────────────────────────────────────────────
# STATIC ENTRY POINTS — called from game code
# ─────────────────────────────────────────────
static func damage(victim: Node, raw: int, applied: int, source: Node, lethal: bool) -> void:
	if _active != null:
		_active._on_damage(victim, raw, applied, source, lethal)


static func shot(shooter: Node, weapon: String = "") -> void:
	if _active != null:
		_active._on_shot(shooter, weapon)


static func heal(target: Node, amount: int, healer: Node, revived: bool = false) -> void:
	if _active != null and amount > 0:
		_active._on_heal(target, amount, healer, revived)


## "ran_out" (a reserve hit zero), "dry_fire" (trigger on an empty magazine),
## "no_reserve" (reload with nothing to load).
static func ammo(kind: String, ammo_type: StringName, weapon: String = "") -> void:
	if _active != null:
		_active._emit("ammo", {"kind": kind, "type": String(ammo_type), "w": weapon})


static func throw(thrower: Node, item: String) -> void:
	if _active != null:
		_active._emit("throw", {"by": _active._describe(thrower), "item": item})


static func self_revive(robot: Node) -> void:
	if _active != null:
		_active._emit("revive", {"vic": _active._describe(robot),
			"by": {"side": "self", "kind": "nanite", "name": ""}})


static func objective(o: Node) -> void:
	if _active != null:
		_active._on_objective(o)


## Campaign calls this once the level, the squad and the enemy force are all in.
static func level_loaded() -> void:
	if _active != null:
		_active._on_level_loaded()


static func set_cause(label: String) -> void:
	_cause = label


static func clear_cause() -> void:
	_cause = ""


## "res://.../emp_grenade_projectile.tscn" -> "EMP". The thrown things are
## named by their scenes, so this keeps a frag a frag in every table.
static func label_for_scene(path: String) -> String:
	var base := path.get_file().get_basename().to_lower()
	if base.contains("emp"):
		return "EMP"
	if base.contains("hatchling"):
		return "Hatchling"
	if base.contains("grenade") or base.contains("frag"):
		return "Frag"
	return _pretty(base)


static func _pretty(base: String) -> String:
	var words: PackedStringArray = []
	for w in base.replace("-", "_").split("_", false):
		if w == "enemy" or w == "ai" or w == "tscn":
			continue
		words.append(w.capitalize())
	return " ".join(words) if not words.is_empty() else base


static func _should_record() -> bool:
	if force_enable:
		return true
	if DisplayServer.get_name() == "headless":
		return false
	var args := OS.get_cmdline_args()
	return not (args.has("--script") or args.has("-s"))


## Where this machine's playtest data lives, for the pause menu's button.
static func folder() -> String:
	return ProjectSettings.globalize_path(ROOT)


# ─────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if not _should_record():
		set_process(false)
		return
	_open()
	_active = self
	_emit("session_start", {
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"date": Time.get_datetime_string_from_system(),
		"os": OS.get_name(),
		"fov": Settings.get_float("display.fov"),
		"sensitivity": Settings.get_float("controls.mouse_sensitivity"),
	})
	_hook_campaign.call_deferred()


func _exit_tree() -> void:
	if _active != self:
		return
	if _in_mission:
		# Quit mid-mission: close it out so its time and orders are not lost.
		_end_attempt("quit", {})
	_emit("session_end", {})
	_write_report()
	if _file != null:
		_file.flush()
		_file = null
	_active = null


func _process(delta: float) -> void:
	if _in_mission:
		_mission_time += delta
	_flush_t += delta
	if _flush_t >= FLUSH_SECONDS:
		_flush_t = 0.0
		if _file != null:
			_file.flush()


func _open() -> void:
	var root := dir_override if dir_override != "" else ROOT
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	_dir = "%s/%s" % [root, stamp]
	var n := 2
	while DirAccess.dir_exists_absolute(_dir):
		_dir = "%s/%s_%d" % [root, stamp, n]
		n += 1
	DirAccess.make_dir_recursive_absolute(_dir)
	_file = FileAccess.open(_dir + "/events.jsonl", FileAccess.WRITE)
	_session_start_ms = Time.get_ticks_msec()


func _hook_campaign() -> void:
	_campaign = get_tree().get_first_node_in_group("campaign")
	if _campaign == null:
		return
	_campaign.deployed.connect(_on_deployed)
	_campaign.extracted.connect(_on_extracted)


func session_dir() -> String:
	return _dir


# ─────────────────────────────────────────────
# RECORDING
# ─────────────────────────────────────────────
func _emit(ev: String, data: Dictionary) -> void:
	var e := data.duplicate()
	e["t"] = snappedf(float(Time.get_ticks_msec() - _session_start_ms) / 1000.0, 0.01)
	e["ev"] = ev
	if _in_mission:
		e["a"] = _attempt
		e["m"] = String(_mission.id) if _mission != null else ("lab:" + _lab_label if _lab_label != "" else "")
		e["mt"] = snappedf(_mission_time, 0.01)
	_events.append(e)
	if _file != null:
		_file.store_line(JSON.stringify(e))
	recorded.emit(e)


# ─────────────────────────────────────────────
# LABORATORY — a lab fight is an attempt with no mission behind it
# ─────────────────────────────────────────────
func lab_begin(label: String, info: Dictionary) -> void:
	if _in_mission:
		_end_attempt("abandoned", {})
	_attempt += 1
	_mission = null
	_lab_label = label
	_in_mission = true
	_died = false
	_mission_time = 0.0
	_shots.clear()
	_hits.clear()
	_last_shot_frame.clear()
	_last_hit_frame.clear()
	_order_time.clear()
	_order_state.clear()
	_emit("lab_start", info)


## Closes the fight and hands back its shot counts, keyed as in mission_end.
func lab_end(outcome: String, info: Dictionary) -> Dictionary:
	var counts := {"shots": _shots.duplicate(), "hits": _hits.duplicate()}
	var e := info.duplicate()
	e["result"] = outcome
	e["duration"] = snappedf(_mission_time, 0.01)
	e["shots"] = counts["shots"]
	e["hits"] = counts["hits"]
	_emit("lab_end", e)
	_in_mission = false
	_lab_label = ""
	return counts


func _on_deployed(mission: MissionDefinition) -> void:
	if _in_mission:
		_end_attempt("abandoned", {})
	_attempt += 1
	_mission = mission
	_in_mission = true
	_died = false
	_mission_time = 0.0
	_shots.clear()
	_hits.clear()
	_last_shot_frame.clear()
	_last_hit_frame.clear()
	_order_time.clear()
	_order_state.clear()
	_recent_player_hits.clear()
	_objectives_seen.clear()
	_squad_pending = true
	var bodies := 0
	for spec in mission.enemy_force:
		if spec != null:
			bodies += spec.body_count()
	var player_kit := {}
	if _campaign != null and _campaign.state != null:
		player_kit = _kit_of(_campaign.state.player_record)
	_emit("mission_start", {
		"name": mission.display_name,
		"cap": mission.squad_size,
		"enemy_squads": mission.enemy_squad_count(),
		"enemy_bodies": bodies,
		"player": player_kit,
	})


# The squad is only on the map once the level has loaded, well after deploy.
func _on_level_loaded() -> void:
	if not _in_mission or not _squad_pending:
		return
	_squad_pending = false
	var allies: Array = []
	var spawner = _campaign.get("spawner") if _campaign != null else null
	if spawner != null:
		for body in spawner._spawned.keys():
			var record = spawner._spawned[body]
			if record == null or not is_instance_valid(body):
				continue
			var kit := _kit_of(record)
			kit["name"] = str(body.get("soldier_name")) if "soldier_name" in body else record.display_name
			allies.append(kit)
			var squad = body.get("squad")
			if squad is Squad and not _watched_squads.has(squad):
				_watch_squad(squad)
	_emit("squad", {"allies": allies})


func _on_extracted(_mission_def: MissionDefinition, result: Dictionary) -> void:
	if not _in_mission:
		return
	var outcome := "success"
	if not bool(result.get("success", true)):
		outcome = "death" if _died else "failed"
	_end_attempt(outcome, result)


func _end_attempt(outcome: String, result: Dictionary) -> void:
	for id in _order_state.keys():
		var st: Dictionary = _order_state[id]
		_add_order_time(st["callsign"], st["order"], _mission_time - float(st["since"]))
	var player := _player()
	var ammo := {}
	if player != null and player.get("ammo") != null:
		var pool = player.ammo
		for stock in pool.starting_ammo:
			if stock != null and stock.ammo_type != &"":
				ammo[String(stock.ammo_type)] = [pool.get_count(stock.ammo_type), pool.get_capacity(stock.ammo_type)]
	_emit("mission_end", {
		"result": outcome,
		"duration": snappedf(_mission_time, 0.01),
		"reward": int(result.get("reward", 0)),
		"bonus": int(result.get("objective_reward", 0)),
		"survivors": int(result.get("survivors", 0)),
		"lost": int(result.get("lost", 0)),
		"won": bool(result.get("won", false)),
		"hp": int(player.health) if player != null else 0,
		"max_hp": int(player.max_health) if player != null else 0,
		"ammo": ammo,
		"shots": _shots.duplicate(),
		"hits": _hits.duplicate(),
		"orders": _order_time.duplicate(true),
	})
	for squad in _watched_squads:
		if is_instance_valid(squad) and squad.objective_changed.is_connected(_on_order):
			squad.objective_changed.disconnect(_on_order)
	_watched_squads.clear()
	_in_mission = false
	_mission = null
	_write_report()


func _on_damage(victim: Node, raw: int, applied: int, source: Node, lethal: bool) -> void:
	var atk := _describe(source)
	var vic := _describe(victim)
	var w := _weapon_of(source)
	var e := {"atk": atk, "w": w, "vic": vic, "raw": raw, "dmg": applied, "lethal": lethal}
	if "health" in victim:
		e["hp"] = int(victim.health)
	var ao := _order_of(source)
	if ao != "":
		e["ao"] = ao
	var vo := _order_of(victim)
	if vo != "":
		e["vo"] = vo
	_emit("damage", e)

	# A round that connected. Hitscan and melee land in the same physics frame
	# as the shot, so one hit per shot — a shotgun's eight pellets are one.
	if _cause == "":
		var key := _shot_key(source, atk, w)
		var frame := Engine.get_physics_frames()
		if int(_last_shot_frame.get(key, -1)) == frame and int(_last_hit_frame.get(key, -2)) != frame:
			_hits[key] = int(_hits.get(key, 0)) + 1
			_last_hit_frame[key] = frame

	if vic["side"] == "player":
		_recent_player_hits.append({"kind": atk["kind"], "side": atk["side"], "w": w,
			"dmg": applied, "mt": snappedf(_mission_time, 0.01)})
		while not _recent_player_hits.is_empty() \
				and _mission_time - float(_recent_player_hits[0]["mt"]) > RECENT_HITS_SECONDS:
			_recent_player_hits.pop_front()
		if lethal and not _died:
			_died = true
			var pos: Vector3 = (victim as Node3D).global_position if victim is Node3D else Vector3.ZERO
			_emit("player_death", {"killer": atk, "w": w, "recent": _recent_player_hits.duplicate(),
				"pos": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1), snappedf(pos.z, 0.1)]})


func _on_shot(shooter: Node, weapon: String) -> void:
	if not _in_mission:
		return
	var atk := _describe(shooter)
	var w := weapon if weapon != "" else _weapon_of(shooter)
	var key := _shot_key(shooter, atk, w)
	_shots[key] = int(_shots.get(key, 0)) + 1
	_last_shot_frame[key] = Engine.get_physics_frames()


func _on_heal(target: Node, amount: int, healer: Node, revived: bool) -> void:
	var by := _describe(healer) if healer != null else {"side": "world", "kind": "pickup", "name": ""}
	_emit("heal", {"vic": _describe(target), "by": by, "amt": amount, "revive": revived})


func _on_objective(o: Node) -> void:
	if o == null or not _in_mission:
		return
	var state := ""
	if bool(o.get("completed")):
		state = "complete"
	elif bool(o.get("failed")):
		state = "failed"
	if state == "":
		return
	var id := str(o.get("id"))
	if _objectives_seen.has(id):
		return
	_objectives_seen[id] = true
	_emit("objective", {"id": id, "state": state})


# ── squad orders ─────────────────────────────
func _watch_squad(squad: Squad) -> void:
	_watched_squads.append(squad)
	squad.objective_changed.connect(_on_order)
	_order_state[squad.get_instance_id()] = {"callsign": _callsign(squad),
		"order": _order_name(squad), "since": _mission_time}


func _on_order(squad: Squad) -> void:
	if not _in_mission:
		return
	var id := squad.get_instance_id()
	var order := _order_name(squad)
	var st: Dictionary = _order_state.get(id, {})
	if not st.is_empty():
		if st["order"] == order:
			return
		_add_order_time(st["callsign"], st["order"], _mission_time - float(st["since"]))
	_order_state[id] = {"callsign": _callsign(squad), "order": order, "since": _mission_time}
	_emit("order", {"squad": _callsign(squad), "from": st.get("order", ""), "to": order,
		"by_player": bool(squad.get("player_ordered"))})


func _add_order_time(callsign: String, order: String, seconds: float) -> void:
	if seconds <= 0.0:
		return
	if not _order_time.has(callsign):
		_order_time[callsign] = {}
	_order_time[callsign][order] = snappedf(float(_order_time[callsign].get(order, 0.0)) + seconds, 0.01)


static func _order_name(squad: Squad) -> String:
	return String(Squad.SquadObjective.keys()[squad.objective])


static func _callsign(squad: Squad) -> String:
	return squad.callsign if squad.callsign != "" else String(squad.name)


# The standing order of the ally's squad at the moment it hit or was hit.
func _order_of(n: Node) -> String:
	if n == null or not is_instance_valid(n) or not ("squad" in n):
		return ""
	var squad = n.get("squad")
	if squad is Squad and bool(squad.player_commandable):
		return _order_name(squad)
	return ""


# ─────────────────────────────────────────────
# WHO IS WHO
# ─────────────────────────────────────────────
## {"side": player | ally | enemy | world, "kind": what it is, "name": who}
func _describe(n: Node) -> Dictionary:
	if n == null or not is_instance_valid(n):
		return {"side": "world", "kind": "unknown", "name": ""}
	if n is Player:
		return {"side": "player", "kind": "player", "name": "player"}
	if "faction" in n and "soldier_name" in n:
		var who := str(n.get("soldier_name"))
		# A hatchling is its thrower's weapon.
		var owner = n.get("credit_kills_to") if "credit_kills_to" in n else null
		if owner != null and is_instance_valid(owner):
			var d := _describe(owner)
			return {"side": d["side"], "kind": "hatchling", "name": d["name"]}
		if Enums.are_hostile(Enums.Factions.PLAYER, n.get("faction")):
			return {"side": "enemy", "kind": _enemy_kind(n), "name": who}
		return {"side": "ally", "kind": _ally_kind(n), "name": who}
	return {"side": "world", "kind": _pretty(String(n.name).to_lower()), "name": ""}


func _enemy_kind(n: Node) -> String:
	if n.has_meta(&"analytics_kind"):
		return str(n.get_meta(&"analytics_kind"))
	return _pretty(n.scene_file_path.get_file().get_basename()) if n.scene_file_path != "" else String(n.name)


func _ally_kind(n: Node) -> String:
	# Lab fighters and spawned enemies carry their chassis name directly.
	if n.has_meta(&"analytics_kind"):
		return str(n.get_meta(&"analytics_kind"))
	var record = _record_of(n)
	if record != null and _catalogue() != null:
		var frame = _catalogue().chassis_def(record.chassis_id)
		if frame != null:
			return frame.display_name
	return "Soldier"


func _weapon_of(n: Node) -> String:
	if _cause != "":
		return _cause
	if n == null or not is_instance_valid(n):
		return "unknown"
	if n is Player:
		var loadout = n.get("loadout")
		if loadout != null and loadout.current != null:
			return loadout.current.display_name
		return "unarmed"
	if "credit_kills_to" in n and n.get("credit_kills_to") != null:
		return "Hatchling"
	var record = _record_of(n)
	if record != null and not record.weapon_ids.is_empty():
		return _item_name(record.weapon_ids[0])
	# A robot with no record is its chassis: the chassis decides the weapon.
	if n.has_meta(&"analytics_kind"):
		return str(n.get_meta(&"analytics_kind"))
	if "faction" in n and Enums.are_hostile(Enums.Factions.PLAYER, n.get("faction")):
		return _enemy_kind(n)
	return "unknown"


func _shot_key(n: Node, desc: Dictionary, weapon: String) -> String:
	match desc["side"]:
		"player":
			return "player|%s" % weapon
		"ally":
			return "ally|%s|%s" % [desc["name"], weapon]
		"enemy":
			return "enemy|%s" % desc["kind"]
	return "world|%s" % weapon


func _record_of(n: Node):
	var spawner = _campaign.get("spawner") if _campaign != null else null
	if spawner == null:
		return null
	return spawner._spawned.get(n)


func _kit_of(record) -> Dictionary:
	if record == null:
		return {}
	var names := func(ids: Array) -> Array:
		var out: Array = []
		for id in ids:
			if id != &"":
				out.append(_item_name(id))
		return out
	return {
		"record": record.display_name,
		"chassis": String(record.chassis_id),
		"rank": int(record.rank),
		"weapons": names.call(record.weapon_ids),
		"equipment": names.call(record.equipment_ids),
		"modules": names.call(record.module_ids),
	}


func _item_name(id: StringName) -> String:
	var cat = _catalogue()
	if cat != null:
		var item = cat.item(id)
		if item != null:
			return item.display_name
	return String(id)


func _catalogue():
	return _campaign.get("catalogue") if _campaign != null else null


func _player() -> Node:
	# Not in a group: World holds it, and World is the campaign's parent.
	var world = _campaign.get_parent() if _campaign != null else null
	if world != null and "player" in world:
		return world.get("player")
	return null


# ─────────────────────────────────────────────
# THE REPORT
# ─────────────────────────────────────────────
func _write_report() -> void:
	if _dir == "":
		return
	var text: String = _Report.build(_events, "Session %s" % _dir.get_file())
	var f := FileAccess.open(_dir + "/report.md", FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
