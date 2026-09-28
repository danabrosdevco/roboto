extends "res://tools/probe_place_mutaha_wip.gd"

# ─────────────────────────────────────────────
# MUTAHA OBJECTIVES — the district anchors the WIP copy was missing, as node
# text to append to maps/mutaha_wip_level.tscn.
#
#   godot --headless --path . --script res://tools/probe_place_mutaha_objs.gd
#   → scratchpad/mutaha_obj_nodes.txt
#
# WHAT THIS IS AND IS NOT. A SquadObjectivePoint is a named place with a tag;
# it carries no mission logic. Missions reference these BY TAG, never by node
# path (see squad_objective_point.gd), so a tag is a contract: once one exists
# it must keep existing, and moving the node is free. This writes the places.
# What happens at them — who defends, which is a capture, what order they come
# in — is the mission, and the mission is GAMEPLAY's.
#
# The WIP copy inherited its anchors from the level it was copied from, and
# then the ground under half of them moved: the south bridge went, the town
# grew a quarter, a crossing appeared at z = 316 and the island was relaid.
# Those are moved in place (tags kept); these are the districts that had no
# anchor at all.
#
# Every one is checked for being on dry land with the ground sampled under it.
# Whether the squad can actually WALK to each is a separate question and
# tools/probe_reach_mutaha.gd answers it.
# ─────────────────────────────────────────────

const OUT_OBJS := "C:/Users/User/AppData/Local/Temp/claude/D--Godot-Games-roboto/adb53eea-3f20-4c1a-a10d-7b2d1903ab73/scratchpad/mutaha_obj_nodes.txt"

## node name, tag suffix, display name, x, z.
const ANCHORS: Array = [
	["Mutaha_CrossEast", "cross_east", "South Crossing East", -70.0, 316.0],
	["Mutaha_CrossWest", "cross_west", "South Crossing Gate", -150.0, 314.0],
	["Mutaha_WestPlain", "w_plain", "West Plain", -210.0, 268.0],
	["Mutaha_StageSW", "stage_sw", "South West Staging", -228.0, 252.0],
	["Mutaha_SWSouth", "sw_south", "South Quarter", -250.0, 215.0],
	["Mutaha_SWEstates", "sw_estates", "The Estates", -331.0, 160.0],
	["Mutaha_SWNorth", "sw_north", "South Quarter North", -296.0, 112.0],
	["Mutaha_Quay", "quay", "West Quay", -163.0, 172.0],
	["Mutaha_WestBridgehead", "w_bridgehead", "West Bridgehead", -176.0, -50.0],
	["Mutaha_CorePower", "core_power", "Power Yard", -24.0, -135.0],
	["Mutaha_CorePlaza", "core_plaza", "The Plaza", -36.0, -30.0],
	["Mutaha_CoreDocks", "core_docks", "Drone Docks", -30.0, 79.0],
	["Mutaha_IsleSouth", "isle_south", "Factory Tip", -50.0, 170.0],
]


func _initialize() -> void:
	data = load(DATA)
	if data == null or data.cells_x == 0:
		print("FAIL  no terrain at %s — bake it first" % DATA)
		quit(1)
		return
	n = data.cells_x + 1
	half = data.cells_x * data.cell_size * 0.5
	var out: PackedStringArray = []
	var bad := 0
	for a: Array in ANCHORS:
		var x := float(a[3])
		var z := float(a[4])
		var y := ground(x, z)
		var note := ""
		if wet(x, z):
			note = "  IN THE WATER"
			bad += 1
		elif relief(x, z, 3.0) > 1.2:
			note = "  on broken ground"
			bad += 1
		print("   %-24s %-22s (%7.1f, %7.1f) y %6.2f%s" % [a[0], a[1], x, z, y, note])
		out.append("")
		out.append("[node name=\"%s\" parent=\"EnemySquadObjs\" instance=ExtResource(\"mut_sqpoint\")]" % a[0])
		out.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.1f, %.2f, %.1f)" % [x, y, z])
		out.append("objective_name = \"%s\"" % a[2])
		out.append("tag = &\"obj_mutaha_%s\"" % a[1])
		out.append("show_debug_label = false")
	# A patrol through the new quarter, so the south-west is not the only
	# district in the level with nothing moving in it.
	out.append("")
	out.append("[node name=\"PatrolSouthWest\" parent=\"EnemySquadObjs\" node_paths=PackedStringArray(\"points\") instance=ExtResource(\"mut_path\")]")
	out.append("tag = &\"patrol_mutaha_sw\"")
	out.append("points = [NodePath(\"PatrolPoint\"), NodePath(\"PatrolPoint2\"), NodePath(\"PatrolPoint3\"), NodePath(\"PatrolPoint4\")]")
	out.append("ping_pong = true")
	out.append("arrow_size = 2.0")
	var route: Array = [[-208.0, 240.0], [-290.0, 200.0], [-310.0, 128.0], [-208.0, 128.0]]
	for i in route.size():
		var px := float(route[i][0])
		var pz := float(route[i][1])
		var py := ground(px, pz)
		if wet(px, pz):
			print("   patrol point %d IS IN THE WATER at (%.0f, %.0f)" % [i, px, pz])
			bad += 1
		out.append("")
		out.append("[node name=\"PatrolPoint%s\" parent=\"EnemySquadObjs/PatrolSouthWest\" instance=ExtResource(\"mut_point\")]"
				% ("" if i == 0 else str(i + 1)))
		out.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.1f, %.2f, %.1f)" % [px, py, pz])
		out.append("display_index = %d" % i)

	var f := FileAccess.open(OUT_OBJS, FileAccess.WRITE)
	if f == null:
		print("FAIL  could not write %s" % OUT_OBJS)
		quit(1)
		return
	f.store_string("\n".join(out) + "\n")
	f.close()
	print("   %d anchor(s) and one patrol written, %d on ground that will not do" % [
			ANCHORS.size(), bad])
	quit()
