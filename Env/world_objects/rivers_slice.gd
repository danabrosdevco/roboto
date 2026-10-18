extends "res://Env/world_objects/site_slice.gd"

# ─────────────────────────────────────────────
# THREE RIVERS, AS A SITE.
#
# THE DEFENCE MAP, and the one to build a defence for first after the basin.
# Six approaches converging on five cores spread over a kilometre is exactly
# the shape §11 says a defence wants and says none of the nine maps have. This
# one has it — §12.6's claim that it has four entrances undercounts it.
#
# It is also the hub: loc_three_rivers borders six other sites, so it is the
# site the enemy turn will reach for most often once raids are live.
# ─────────────────────────────────────────────


func _init() -> void:
	# ALL FIVE ARE SMALL PREFABS, so all five are tier 0. The tier MUST match
	# the prefab instanced: _fit_reach() overwrites the prefab's reach_size
	# from a tier table, and a tier 2 on a small core builds a 6.4 x 12.4 m
	# volume the player ends up standing inside, where the interact ray reports
	# nothing at all.
	cores_by_node = {"RelayDam": 0, "RelayShore": 0, "RelayStrip": 0,
		"RelayFurnace": 0, "RelayPort": 0}

	# THE BUNKER — the east pad.
	#
	# BY THE EXIT NODE ITSELF, unusually. There is no ground-level post within
	# 100 m of the pad: Pitt_ExitGuard is 19.9 m up a cliff above it, which
	# would put the way down on a clifftop the extraction never used. There is
	# exactly one LevelExit node in this file and none in pittsburgh_art.tscn,
	# so the name resolves unambiguously.
	bunker_marker = &"LevelExit"
	bunker_fallback = Vector3(505.0, -0.8, 20.0)
	bunker_tier = 1

	# SIX WAYS IN, which is the whole point of this map. Four of them sit 7-20 m
	# above the river floor — they are plateau and bluff tops — so if a wave
	# ever fails to arrive, these are the first thing to re-measure against the
	# navmesh rather than the terrain.
	entry_markers_named = [&"Pitt_InEast", &"Pitt_InNW", &"Pitt_InNE",
		&"Pitt_InMon", &"Pitt_InShore", &"Pitt_InSouth"] as Array[StringName]

	resistance = 171
	# 1034 m EAST TO WEST, 462 m NORTH TO SOUTH. A squad ordered from Pitt_InNW
	# to RelayStrip walks about 560 m. The basin's 240 s would empty the pool
	# before the first wave crossed half the map.
	defence_assault_seconds = 480.0
	stand_down_seconds = 45.0
