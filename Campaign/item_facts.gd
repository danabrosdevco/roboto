extends RefCounted

# ─────────────────────────────────────────────
# WHAT A PIECE OF GEAR ACTUALLY DOES, read off the thing that does it.
#
# A smoke canister's seven metres and fourteen seconds are not on
# item_smoke.tres. They are on smoke_volume.gd, two scenes down, and the shop
# item has no field that could hold them. So the Armorer either shows nothing,
# or someone types the numbers into the .tres by hand and they quietly go stale
# the first time anybody retunes a blast — which is exactly how the Cluster
# Launcher came to advertise 40 damage for a round that delivers 220.
#
# This asks the scene instead. There is one copy of every figure, and it is the
# copy the game fires.
#
# HOW IT FINDS THEM. Not by hunting for a property called `radius`: half the
# nodes in a scene have one and most of them are collision shapes. It matches
# on distinctive SETS — a node carrying `peak_signal_damage` is an EMP blast, a
# node carrying `duration` and `fade_seconds` is a smoke volume — so a reading
# is only taken from a node that could not be anything else.
#
# DEPTH. An EMP is three scenes deep: the item names a grenade, the grenade
# names a projectile, the projectile names the blast. So nested PackedScene
# properties are followed, twice, with a visited set — a scene that names itself
# would otherwise spin forever.
#
# INSTANTIATING IS SAFE HERE. instantiate() does not call _ready; nothing enters
# the tree, nothing ticks, and every node built is freed before this returns.
# The answer is cached per item, because the shop asks on every redraw.
#
# WHAT IT WILL NOT DO is invent a figure. An item whose scene does not carry a
# number gets no row for it — a card missing a line can be fixed, a card with a
# made-up blast radius cannot be spotted.
#
# BY PATH, NOT class_name. A brand-new class_name is not resolvable until the
# editor rescans, and that rescan must not be run with the editor open — the
# same reason weapon_audio.gd and analytics.gd are preloaded this way. Callers
# take it as:
#
#   const _Facts := preload("res://Campaign/item_facts.gd")
# ─────────────────────────────────────────────

## How many layers of nested PackedScene to follow. Two reaches the EMP's blast,
## which is the deepest thing in the game that a card needs to read.
const MAX_DEPTH := 2
## A scene with a cycle in it would walk forever; this is the belt to the
## visited set's braces, and it is far above any real gear scene.
const MAX_NODES := 400

static var _cache: Dictionary = {}


## [[label, value], ...] for one item, in reading order. Empty when its scenes
## carry nothing worth printing, which is the honest answer for gear whose
## behaviour is all in code.
static func of(item: ItemDefinition) -> Array:
	if item == null:
		return []
	if _cache.has(item.id):
		return _cache[item.id]

	var found: Dictionary = {}
	var scene: PackedScene = item.ai_scene if item.ai_scene != null else item.player_scene
	if scene != null:
		var seen: Dictionary = {}
		var budget := [MAX_NODES]
		var root := scene.instantiate()
		_scan(root, 0, found, seen, budget)
		root.free()

	var rows := _rows(found)
	# Every piece of equipment is rationed per deployment, and that is the one
	# fact that is on the ITEM rather than in a scene. It goes last because it is
	# the least interesting and the most universal.
	if item.kind == ItemDefinition.Kind.EQUIPMENT and item.quantity > 0:
		rows.append(["CARRIES", "%d PER MISSION" % item.quantity])
	_cache[item.id] = rows
	return rows


## Forget everything read so far. For a tool that reloads resources mid-run; the
## game never needs it, because gear scenes do not change while it is playing.
static func clear_cache() -> void:
	_cache.clear()


# ── READING ───────────────────────────────────

static func _scan(node: Node, depth: int, found: Dictionary, seen: Dictionary,
		budget: Array) -> void:
	if node == null or budget[0] <= 0:
		return
	budget[0] -= 1

	_take(node, found)

	# The damage AREA is a sphere on a collision shape, not a property anybody
	# wrote down — the explosion's reach is literally the size of that shape, so
	# that is where it has to be read from.
	if node is CollisionShape3D:
		var shape = (node as CollisionShape3D).shape
		if shape is SphereShape3D and not found.has("blast_radius"):
			found["blast_radius"] = (shape as SphereShape3D).radius

	if depth < MAX_DEPTH:
		for prop in node.get_property_list():
			if not str(prop.get("name", "")).ends_with("_scene"):
				continue
			var nested = node.get(str(prop["name"]))
			if not (nested is PackedScene):
				continue
			var path: String = (nested as PackedScene).resource_path
			if path != "" and seen.has(path):
				continue
			if path != "":
				seen[path] = true
			var child := (nested as PackedScene).instantiate()
			_scan(child, depth + 1, found, seen, budget)
			child.free()

	for kid in node.get_children():
		_scan(kid, depth, found, seen, budget)


## One node's contribution. Matched on sets, never on a lone property name, and
## an override left at zero is not a reading — the codebase's own convention is
## that 0 on a `*_override` or `blast_damage` field means "keep what the round
## already has", so taking it would report a blast of nothing.
static func _take(node: Node, found: Dictionary) -> void:
	if "peak_signal_damage" in node:                       # an EMP blast
		_put(found, "radius", node.get("radius"))
		_put(found, "jam_peak", node.get("peak_lock"))
		_put(found, "jam_edge", node.get("edge_lock"))
		_put(found, "friendly", node.get("friendly_multiplier"))
	if "duration" in node and "fade_seconds" in node:      # a smoke volume
		_put(found, "radius", node.get("radius"))
		_put(found, "lasts", node.get("duration"))
	if "heal_amount" in node:                              # a repair kit or tool
		_put(found, "repairs", node.get("heal_amount"))
		_put(found, "heal_range", node.get("heal_range"))
		_put(found, "recharge", node.get("cooldown"))
	if "trigger_radius" in node:                           # a mine
		_put(found, "trips_at", node.get("trigger_radius"))
		_put(found, "arms_in", node.get("arm_seconds"))
	if "submunitions" in node:                             # anything that breaks up
		_put(found, "submunitions", node.get("submunitions"))
		_put(found, "each", node.get("submunition_damage"))
	if "damage_value" in node:
		_put(found, "damage", node.get("damage_value"))
	if "blast_damage" in node:
		_put(found, "damage", node.get("blast_damage"))
	if "blast_radius" in node:
		_put(found, "blast_radius", node.get("blast_radius"))
	if "fuse_time" in node:
		# A mine's fuse is 99999: it is not on a timer, it waits to be stepped
		# on. Printing "FUSE 99999 S" would be true and useless.
		var fuse := float(node.get("fuse_time"))
		if fuse > 0.0 and fuse < 600.0:
			_put(found, "fuse", fuse)


## First reading wins, and a zero never counts. Depth-first means the OUTER
## scene is read first, which is the right way round: a launcher that overrides
## its round's blast is describing what it will actually fire.
static func _put(found: Dictionary, key: String, value) -> void:
	if value == null or found.has(key):
		return
	var f := float(value)
	if is_zero_approx(f):
		return
	found[key] = f


# ── WORDING ───────────────────────────────────
#
# Every label says what the number MEANS. "YOUR OWN TAKE: A QUARTER" was a
# riddle because it never said a quarter of what.

static func _rows(found: Dictionary) -> Array:
	var rows: Array = []
	if found.has("damage"):
		if found.has("submunitions"):
			rows.append(["DAMAGE", "%d + %d x %d" % [int(found["damage"]),
				int(found["submunitions"]), int(found.get("each", 0))]])
		else:
			rows.append(["DAMAGE", str(int(found["damage"]))])
	if found.has("blast_radius"):
		rows.append(["BLAST RADIUS", _metres(found["blast_radius"])])
	if found.has("radius"):
		rows.append(["RADIUS", _metres(found["radius"])])
	if found.has("lasts"):
		rows.append(["LASTS", _seconds(found["lasts"])])
	if found.has("jam_peak"):
		rows.append(["KILLS SIGNAL FOR", "%s AT THE CENTRE" % _seconds(found["jam_peak"])])
	if found.has("jam_edge"):
		rows.append(["AT THE EDGE", _seconds(found["jam_edge"])])
	if found.has("friendly"):
		rows.append(["HURTS FRIENDLIES", "%d%% AS MUCH" % int(round(float(found["friendly"]) * 100.0))])
	if found.has("repairs"):
		rows.append(["REPAIRS", "%d A TIME" % int(found["repairs"])])
	if found.has("heal_range"):
		rows.append(["REACH", _metres(found["heal_range"])])
	if found.has("recharge"):
		rows.append(["RECHARGE", _seconds(found["recharge"])])
	if found.has("trips_at"):
		rows.append(["TRIPS AT", _metres(found["trips_at"])])
	if found.has("arms_in"):
		rows.append(["ARMS IN", _seconds(found["arms_in"])])
	if found.has("fuse"):
		rows.append(["FUSE", _seconds(found["fuse"])])
	return rows


static func _metres(v) -> String:
	var f := float(v)
	return ("%d M" % int(round(f))) if is_equal_approx(f, round(f)) else ("%.1f M" % f)


static func _seconds(v) -> String:
	var f := float(v)
	return ("%d S" % int(round(f))) if is_equal_approx(f, round(f)) else ("%.1f S" % f)


## A FRAME'S REAL SPEED, in metres per second, off its own scene.
##
## ChassisDefinition.base_speed is 1.00 on every buildable frame — it is a
## MULTIPLIER that modules scale, not a speed — so a card drawn from the
## definition shows six identical bars. The figure only exists on the chassis
## scene, as move_speed. Same deal as the gear facts: one copy, and it is the
## one the robot walks at.
##
## 0.0 when the frame has no scene or its scene does not carry the field, which
## a caller should read as "do not draw a speed bar" rather than as "stationary".
static func chassis_speed(frame: ChassisDefinition) -> float:
	if frame == null or frame.scene == null:
		return 0.0
	var key := "chassis:%s" % frame.id
	if _cache.has(key):
		return _cache[key]
	var node := frame.scene.instantiate()
	var speed := 0.0
	if "move_speed" in node:
		speed = float(node.get("move_speed"))
	else:
		push_warning("ItemFacts: '%s' has no move_speed on its scene, so no speed can be shown for it." % frame.id)
	node.free()
	_cache[key] = speed
	return speed
