extends Node3D

# ─────────────────────────────────────────────
# ENEMY COMMANDER — what heat actually spends its reserve on.
#
# SiteHeat decides WHEN pressure is committed and HOW MUCH (in supply). It has
# no idea what a squad is. This turns a number into bodies on the map:
# it picks a template from the pools below that fits the supply it was handed,
# builds an EnemySquadSpec from it, and hands that to the mission's own
# EnemyForceSpawner. docs/briefs/CAMPAIGN_REWORK.md §12.4.
#
# THROUGH THE AUTHORED SPAWNER, DELIBERATELY. A squad built here travels the
# exact same road as one authored into a mission — spawned onto a post, given a
# callsign and a loadout, registered with the AIManager, counted by the
# eliminate objective, watched for losses. Nothing downstream can tell the
# difference, which is the only way this stays maintainable.
#
# SUPPLY IS THE CURRENCY, NOT HEADCOUNT. Five Walkers and two riflemen are both
# "one squad" and are not remotely the same problem — 15 supply against 2. Every
# template below is priced in supply, and the pool is the site's resistance.
#
# TIERS ARE TECH, NOT DIFFICULTY. Tier 1 is what a site can field on its own;
# tier 3 is what arrives once the campaign has escalated. Act drives which
# tiers are drawn from, so Act 2 and Act 3 feel different without a single
# number being tuned twice.
# ─────────────────────────────────────────────

signal squad_committed(label: String, supply: int, at: Vector3)

## The templates, by tech tier. Each is a list of chassis ids and the supply it
## costs — priced from the chassis themselves, so these cannot drift from the
## catalogue without the check in _price() noticing.
##
## Ids are real and verified against Campaign/chassis/*.tres.
const POOLS := {
	1: [
		{"label": "PICKET", "frames": ["rifleman", "rifleman"], "supply": 2},
		{"label": "RUSH", "frames": ["chaser", "chaser", "leaper"], "supply": 3},
		{"label": "LINE", "frames": ["rifleman", "rifleman", "shotgunner", "marksman"], "supply": 4},
		{"label": "SWEEP", "frames": ["shotgunner", "shotgunner", "chaser", "chaser", "leaper", "leaper"], "supply": 6},
	],
	2: [
		{"label": "PROBE", "frames": ["rifleman_armoured", "rifleman"], "supply": 3},
		{"label": "SECTION", "frames": ["rifleman_armoured", "rifleman_armoured", "marksman"], "supply": 5},
		{"label": "MOTOR", "frames": ["rover", "rifleman", "rifleman"], "supply": 4},
		{"label": "BATTERY", "frames": ["mortar_track", "rifleman_armoured", "rifleman"], "supply": 5},
		{"label": "COLUMN", "frames": ["rover_gl", "rifleman_armoured", "rifleman_armoured", "marksman"], "supply": 7},
	],
	3: [
		{"label": "VANGUARD", "frames": ["walker", "rifleman_armoured"], "supply": 5},
		{"label": "HAMMER", "frames": ["bulwark", "rifleman_armoured", "rifleman_armoured"], "supply": 7},
		{"label": "SPEARHEAD", "frames": ["walker", "rover_gl", "rifleman_armoured"], "supply": 7},
		{"label": "STORM", "frames": ["bulwark", "walker", "mortar_track", "rifleman_armoured"], "supply": 10},
	],
}

## Which tiers an act may draw from. Act 1 fields what the site has; by Act 3
## everything is on the table.
const TIERS_BY_ACT := {1: [1], 2: [1, 2], 3: [1, 2, 3]}

## Wired by whoever fits this.
@export var heat: Node3D
## Found if not set: the mission's own spawner.
@export var spawner: Node
## The act this site is being fought in. Stage 1 fakes it at 1 — the campaign
## supplies it for real from Campaign.act() later.
@export var act: int = 1
## Where spawned squads come on. Empty uses the commander's own position, which
## is wrong for anything but a test — see _entry_point.
@export var entry_markers: Array[Node3D] = []

var committed_squads: int = 0
var committed_supply: int = 0
var _index: Dictionary = {}
var _level: Node = null


func _ready() -> void:
	_level = _find_level()
	if spawner == null:
		spawner = _find_spawner()
	if spawner == null:
		push_warning("EnemyCommander: no EnemyForceSpawner found, so heat will commit supply and nothing will arrive.")
	if heat != null and heat.has_signal(&"committed"):
		heat.committed.connect(_on_committed)
	else:
		push_warning("EnemyCommander: no SiteHeat wired, so nothing will ever ask it for a squad.")


# ── Spending ─────────────────────────────────────────────────────────────────

## Heat hands over a packet of supply and a place to send it. Pick the biggest
## template that fits, build it, spawn it.
func _on_committed(supply: int, at: Vector3) -> void:
	var template := _pick(supply)
	if template.is_empty():
		# Not a warning: a packet smaller than the cheapest template is an
		# ordinary outcome near the end of a pool, and the remainder simply
		# rolls into the next commitment.
		return
	var spec = _build_spec(template, at)
	if spec == null:
		return
	if not _deploy(spec):
		return
	committed_squads += 1
	committed_supply += int(template["supply"])
	squad_committed.emit(String(template["label"]), int(template["supply"]), at)


## The most expensive template this act can field within the supply given.
## Biggest-that-fits rather than random: pressure should escalate as the pool
## is spent in larger packets, not wander.
func _pick(supply: int) -> Dictionary:
	var tiers: Array = TIERS_BY_ACT.get(clampi(act, 1, 3), [1])
	var best: Dictionary = {}
	for tier in tiers:
		for t in POOLS[tier]:
			var cost: int = int(t["supply"])
			if cost > supply:
				continue
			if best.is_empty() or cost > int(best["supply"]):
				best = t
	return best


## An EnemySquadSpec the authored spawner will accept: a `roster`, one body
## built per entry. That is the only form there is — the legacy `count` +
## `chassis` pair this comment used to say was ignored went with H9 on
## 2026-10-24.
func _build_spec(template: Dictionary, at: Vector3):
	var spec = load("res://Campaign/enemy_squad_spec.gd").new()
	spec.callsign = "%s-%d" % [String(template["label"]), committed_squads + 1]
	var roster: Array[ChassisDefinition] = []
	for id in template["frames"]:
		var frame = _chassis(StringName(id))
		if frame == null:
			push_warning("EnemyCommander: no chassis '%s' on disk, so it is left out of %s." % [id, spec.callsign])
			continue
		roster.append(frame)
	if roster.is_empty():
		return null
	spec.roster = roster
	# ADVANCE ON WHERE HEAT POINTED. This is the whole anti-range answer: stand
	# off at 300 m and what the pressure buys walks to 300 m and finds you.
	spec.posture = 2   # EnemySquadSpec.Posture.ADVANCE
	spec.always_active = true
	# NAMED ANCHORS, NOT AN OFFSET. EnemyForceSpawner resolves a squad's position
	# from route_tag / post_tag / spawn_tag and refuses outright without one —
	# "found no anchor" — so a bare spawn_offset puts nothing on the map. The
	# authored squad points are the vocabulary it already speaks.
	var entry := _entry_marker(at)
	if entry != "":
		spec.spawn_tag = StringName(entry)
	var post := _nearest_post(at)
	if post == "":
		push_warning("EnemyCommander: no squad objective point near %v, so %s has nowhere to advance to and is not built." % [at, spec.callsign])
		return null
	spec.post_tag = StringName(post)
	return spec


## Hand it to the mission's own spawner so it travels the authored road.
func _deploy(spec) -> bool:
	if spawner == null or not is_instance_valid(spawner):
		return false
	if not spawner.has_method("_spawn_squad"):
		push_warning("EnemyCommander: the spawner has no _spawn_squad, so reinforcements cannot be built.")
		return false
	var lvl: Node = _level if _level != null else get_tree().current_scene
	if lvl == null:
		return false
	return spawner._spawn_squad(lvl, spec) != null


## Which marker a committed squad comes on from: the FURTHEST from the target,
## so reinforcements arrive out of depth rather than on top of the player.
func _entry_marker(target: Vector3) -> String:
	var best := ""
	var best_d: float = -1.0
	for m in entry_markers:
		if m == null or not is_instance_valid(m):
			continue
		var d: float = m.global_position.distance_to(target)
		if d > best_d:
			best_d = d
			best = String(m.tag) if "tag" in m and String(m.tag) != "" else String(m.name)
	return best


## The authored squad point NEAREST where heat pointed — what the squad
## advances to. Heat aims at the player, who is not a named place, so this is
## the closest named one to them.
func _nearest_post(target: Vector3) -> String:
	var lvl: Node = _level if _level != null else get_tree().current_scene
	if lvl == null:
		return ""
	# COLLECT, THEN CHOOSE. The first cut passed a lambda that wrote to `best`
	# and `best_d` — and GDScript lambdas CAPTURE LOCALS BY VALUE, so every
	# assignment landed on a copy and the function always returned "". Nothing
	# errored; reinforcements simply never had anywhere to go.
	var posts: Array[Node3D] = []
	_scan_posts(lvl, posts)
	var best := ""
	var best_d: float = INF
	for p in posts:
		var d: float = p.global_position.distance_to(target)
		if d < best_d:
			best_d = d
			# THE TAG, NOT THE NODE NAME. EnemyForceSpawner matches a spec's
			# post_tag against the point's `tag` — "obj_basin_trench_n", not
			# "Basin_TrenchN" — and refuses with "found no anchor" otherwise.
			best = String(p.tag)
	return best


func _scan_posts(n: Node, out: Array[Node3D]) -> void:
	# BY TYPE, not by comparing get_script(). These are instances of
	# squad_objective_point.tscn, and a scene instance's script resource is not
	# guaranteed to be the same object as a preload of the same path — the
	# comparison silently found nothing. The class_name is reliable.
	if n is SquadObjectivePoint:
		out.append(n as Node3D)
	for c in n.get_children():
		_scan_posts(c, out)


# ── Finding things ───────────────────────────────────────────────────────────

## EVERY CHASSIS, NOT THE SHOP.
##
## The campaign catalogue lists what the PLAYER can buy, so enemy-only frames
## — rifleman, chaser, leaper, shotgunner, rifleman_armoured — are not in it
## and every lookup for them came back null. The pools need the whole set, so
## this indexes the definitions themselves by their own id.
##
## Built once and cached. DirAccess over res:// is a development path and will
## not enumerate in an exported build; when these pools stop being slice
## scaffolding they should be authored as resource references the way a
## mission references its force, and this goes away.
func _chassis(id: StringName):
	if _index.is_empty():
		_build_index()
	return _index.get(id)


func _build_index() -> void:
	var dir := "res://Campaign/chassis/"
	var d := DirAccess.open(dir)
	if d == null:
		push_warning("EnemyCommander: cannot read %s, so no frame can be resolved and no reinforcement will arrive." % dir)
		return
	for f in d.get_files():
		if not f.ends_with(".tres"):
			continue
		var res = load(dir + f)
		if res != null and "id" in res:
			_index[res.id] = res


## FROM THE ROOT, NOT THE LEVEL. EnemyForceSpawner is a child of World — a
## sibling of the level, not something inside it — so searching down from the
## level finds nothing. A level instantiated on its own has no World at all,
## which is why probes that do that legitimately come up empty.
func _find_spawner() -> Node:
	return _first_with_method(get_tree().root, "_spawn_squad")


func _first_with_method(n: Node, named: String) -> Node:
	if n == null:
		return null
	if n.has_method(named) and n.has_method("deploy_force"):
		return n
	for c in n.get_children():
		var f := _first_with_method(c, named)
		if f != null:
			return f
	return null


func _find_level() -> Node:
	var node: Node = self
	while node != null:
		if node is TrenchBroomLevel:
			return node
		node = node.get_parent()
	return get_tree().current_scene


## Sanity: every template's stated supply should match what its frames actually
## cost. Called by the test rather than at runtime — a mismatch is an authoring
## error, not something to discover mid-mission.
func price_of(template: Dictionary) -> int:
	var total := 0
	for id in template["frames"]:
		var frame = _chassis(StringName(id))
		if frame == null:
			return -1
		total += int(frame.supply)
	return total
