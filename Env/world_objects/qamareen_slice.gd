extends "res://Env/world_objects/site_slice.gd"

# ─────────────────────────────────────────────
# QAMAREEN, AS A SITE.
#
# Possibly the second-best defence shape after Three Rivers: five cores, four
# cardinal entries, 850 x 730 m, and five bridges that make the middle
# contestable from four sides.
#
# SITE_CONVERSION.md had this map down as "unresolved — do not write a brief
# until it is". That was a wrong-file probe: it surveyed heliostat_level.tscn
# and reported a degenerate 228 x 0 m extent, but loc_qamareen points at
# mutaha_2_city, which points at maps/mutaha_wip_level.tscn — 20,282 lines with
# five capture points, four edge entries and a working extraction. The brief's
# own guess that "the mission points at a different level than the probe
# assumed" was the right one.
# ─────────────────────────────────────────────


func _init() -> void:
	# ALL FIVE SMALL, so all five tier 0 — see rivers_slice.gd on why the tier
	# must match the prefab.
	#
	# RelayCompute is the prize by authoring (a 15 s channel against the
	# others' 6-8, and 110 resources), and the basin's equivalent is a tier 2.
	# It stays 0 here because it IS a small instance standing in a courtyard;
	# raising the tier without swapping the prefab is the reach-volume trap.
	# Swap the prefab first if it should feel like an anchor.
	cores_by_node = {"RelayGate": 0, "RelayServer": 0, "RelayCompute": 0,
		"RelayClock": 0, "RelayFair": 0}

	# THE BUNKER — past the last bridge.
	#
	# NOT Mutaha_InNorth, which sits almost on the exit but is the entry the
	# commander walks reinforcements in on; using one marker for both would
	# make the way down the same door the counter-attack comes through.
	# Mutaha_Road is the authored spot the extraction's own description names,
	# and the extract's 30 m radius already reaches it.
	bunker_marker = &"Mutaha_Road"
	bunker_fallback = Vector3(9.0, -0.25, -376.5)
	bunker_tier = 1

	entry_markers_named = [&"Mutaha_InNorth", &"Mutaha_InSouth",
		&"Mutaha_InEast", &"Mutaha_InWest"] as Array[StringName]

	resistance = 250
	# 850 x 730 m of dense city with five bridges in it. Longer than the basin,
	# shorter than Three Rivers.
	defence_assault_seconds = 420.0
	stand_down_seconds = 45.0
