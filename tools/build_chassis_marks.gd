extends SceneTree

# ─────────────────────────────────────────────
# AUTHOR MK 1 AND MK 2 ONTO EVERY PURCHASABLE LINE.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/build_chassis_marks.gd [-- --dry]
#
# Step 1 of docs/briefs/MARK_SYSTEM_SPEC.md. Writes ChassisMark sub-resources
# into the twelve purchasable Campaign/chassis/*.tres files.
#
# A TOOL RATHER THAN TWELVE HAND EDITS. A typed array of a custom Resource is
# fiddly to write into a .tres by hand — sub_resource blocks, ext_resource ids
# and the array's own type annotation all have to agree, and getting one wrong
# produces a file that loads with a null in it rather than an error. Letting
# Godot serialise it is the only way to be sure the shape is right, and it is
# the pattern the other build_*.gd tools already follow.
#
# MK 0 IS NEVER WRITTEN. It is the frame's own starting_weapon_id and
# coax_weapon_id; ChassisDefinition.mark_spec(0) synthesises it. Writing it
# here would create the second source of truth the spec exists to avoid.
#
# IDEMPOTENT. Re-running replaces the marks rather than appending, so this can
# be edited and re-run while the table is being tuned.
#
# EVERY MARK IS VERIFIED BEFORE IT IS SAVED — ChassisMark.verify() against the
# frame's real slot counts. Nothing is written if anything fails, because a
# Mark with one weapon too many silently drops it at apply time and reads as
# the tier simply not being worth its price.
#
# THE CONTENTS ARE PROPOSED, NOT FINAL. Which gun belongs at which tier is a
# balance judgement; this file is where it gets changed.
# ─────────────────────────────────────────────

const DIR := "res://Campaign/chassis/"
## Preloaded, not named: see the note on ChassisDefinition.marks — a new
## class_name is not in the global list until the editor rescans, and this has
## to run headlessly.
const _Mark := preload("res://Campaign/chassis_mark.gd")

## line id -> [Mk 1, Mk 2], each a Dictionary of ChassisMark fields.
## Only keys that differ from the default are listed.
const TABLE := {
	"soldier": [
		{"weapon_ids": ["bolt"], "equipment_ids": ["frag"],
		 "health_bonus": 10, "accuracy_bonus": 0.05},
		{"weapon_ids": ["bolt"], "equipment_ids": ["frag", "frag"],
		 "health_bonus": 20, "accuracy_bonus": 0.08},
	],
	"rover": [
		{"weapon_ids": ["heavy_mg"], "health_bonus": 20},
		{"weapon_ids": ["autocannon"], "health_bonus": 40, "sensor_bonus": 5.0},
	],
	"walker": [
		{"weapon_ids": ["autocannon", "heavy_mg"], "health_bonus": 30},
		{"weapon_ids": ["light_cannon", "heavy_mg"],
		 "health_bonus": 60, "accuracy_bonus": 0.05},
	],
	"bulwark": [
		{"weapon_ids": ["autocannon"], "health_bonus": 50},
		{"weapon_ids": ["light_cannon"], "health_bonus": 100, "accuracy_bonus": 0.05},
	],
	"kite": [
		{"weapon_ids": ["heavy_mg"], "health_bonus": 15},
		{"weapon_ids": ["rocket_pods"], "health_bonus": 25, "sensor_bonus": 10.0},
	],
	"picket": [
		{"weapon_ids": ["cluster_launcher"], "sensor_bonus": 10.0},
		{"weapon_ids": ["mortar"], "health_bonus": 25, "sensor_bonus": 20.0},
	],
	"lance": [
		{"weapon_ids": ["light_cannon"], "equipment_ids": ["repair_kit"],
		 "health_bonus": 15},
		{"weapon_ids": ["autocannon"], "equipment_ids": ["repair_kit"],
		 "health_bonus": 30, "accuracy_bonus": 0.05},
	],
	"vessel": [
		{"weapon_ids": ["hatchling_launcher"], "equipment_ids": ["hatchling"],
		 "health_bonus": 30, "tuning": {"reload_rate": 1.4}},
		{"weapon_ids": ["hatchling_launcher"], "equipment_ids": ["hatchling"],
		 "health_bonus": 60, "sensor_bonus": 10.0, "tuning": {"reload_rate": 2.0}},
	],
	# UNARMED ON PURPOSE, both of them. These two have a mount, but
	# `weapon_replaces_built_in` is true: a fitted weapon takes the place of
	# what the frame came with. Arming the Drayman costs it the BOOM it plants
	# and lifts with, and arming the Reclaimer costs it the WELDER it stands
	# squadmates up with — which is trading away the thing the frame is FOR.
	# The first cut of this table armed both and probe_chassis_marks caught it;
	# nothing about slots or item ids would have.
	"drayman": [
		{"equipment_ids": ["repair_kit", "repair_kit", "repair_kit"],
		 "health_bonus": 25},
		{"equipment_ids": ["repair_kit", "repair_kit", "mine_heavy", "mine_heavy"],
		 "health_bonus": 50, "sensor_bonus": 10.0},
	],
	"reclaimer": [
		{"health_bonus": 25, "tuning": {"salvage_rate": 1.5}},
		{"health_bonus": 50, "sensor_bonus": 15.0, "tuning": {"salvage_rate": 1.9}},
	],
	# NO WEAPON MOUNT AT ALL. Both of these progress by tuning alone, which is
	# the whole reason ChassisMark carries stat fields as well as kit.
	"mechanic": [
		{"equipment_ids": ["repair_tool"], "health_bonus": 15,
		 "tuning": {"repair_rate": 1.4}},
		{"equipment_ids": ["repair_tool"], "health_bonus": 30,
		 "speed_multiplier": 1.1, "tuning": {"repair_rate": 1.9}},
	],
	"spotter": [
		{"equipment_ids": ["scanner"], "sensor_bonus": 36.0},
		{"equipment_ids": ["scanner"], "sensor_bonus": 72.0, "speed_multiplier": 1.1},
	],
}


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var dry := OS.get_cmdline_user_args().has("--dry")

	# ── BUILD AND VERIFY EVERYTHING FIRST ──────
	# Nothing is saved until the whole table passes, so a typo cannot leave
	# half the lines authored and half not.
	var planned := {}
	var bad: Array[String] = []
	for id in TABLE:
		var path: String = DIR + "chassis_%s.tres" % id
		var frame = load(path)
		if frame == null:
			bad.append("%s: no such chassis resource" % id)
			continue
		if not frame.purchasable:
			bad.append("%s: not purchasable, so it has no line to advance" % id)
		var marks: Array[Resource] = []
		for spec in TABLE[id]:
			var m := _Mark.new()
			m.weapon_ids = _names(spec.get("weapon_ids", []))
			m.equipment_ids = _names(spec.get("equipment_ids", []))
			m.health_bonus = int(spec.get("health_bonus", 0))
			m.speed_multiplier = float(spec.get("speed_multiplier", 1.0))
			m.sensor_bonus = float(spec.get("sensor_bonus", 0.0))
			m.accuracy_bonus = float(spec.get("accuracy_bonus", 0.0))
			m.tuning = spec.get("tuning", {})
			for problem in m.verify(frame):
				bad.append("%s Mk %d: %s" % [id, marks.size() + 1, problem])
			marks.append(m)
		planned[path] = [frame, marks]

	if not bad.is_empty():
		print("NOTHING WRITTEN — %d problem(s):" % bad.size())
		for b in bad:
			print("  %s" % b)
		quit(1)
		return

	# ── EVERY ID HAS TO EXIST ──────────────────
	# A weapon or equipment id that is not in the catalogue resolves to null
	# at apply time and the robot is built holding nothing.
	# THE REAL ONE, which is not the one that looks canonical.
	# res://Campaign/item_catalogue.tres is a nine-item stub; the catalogue the
	# game and every suite actually use is this, via test_ledger.real_catalogue.
	var cat := load("res://Campaign/items & catalogue/test_item_catalogue.tres")
	if cat != null:
		var missing: Array[String] = []
		for path in planned:
			for m in planned[path][1]:
				for wid in m.weapon_ids + m.equipment_ids:
					if cat.item(wid) == null:
						missing.append("%s: no item '%s'" % [path.get_file(), String(wid)])
		if not missing.is_empty():
			print("NOTHING WRITTEN — %d unknown item id(s):" % missing.size())
			for m in missing:
				print("  %s" % m)
			quit(1)
			return

	# ── WRITE ──────────────────────────────────
	var wrote := 0
	for path in planned:
		var frame = planned[path][0]
		frame.marks = planned[path][1]
		if dry:
			print("would write %s" % path.get_file())
			continue
		var err := ResourceSaver.save(frame, path)
		if err != OK:
			print("FAIL  %s (%d)" % [path, err])
			quit(1)
			return
		wrote += 1

	print("")
	print("%s %d line(s)" % ["would write" if dry else "wrote", wrote if not dry else planned.size()])
	print("Mk 0 is NOT written — it is each frame's starting_weapon_id and coax.")
	quit(0)


func _names(a: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for v in a:
		out.append(StringName(v))
	return out
