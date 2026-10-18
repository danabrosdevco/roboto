extends "res://Env/world_objects/site_slice.gd"

# ─────────────────────────────────────────────
# THE CAUSEWAY, AS A SITE.
#
# Seven cores and the richest ground on the board — 55 a turn against Valley
# Basin's 13. A superb attack and a poor defence: two ways in, and a site whose
# last three cores are up a tower.
# ─────────────────────────────────────────────


func _init() -> void:
	# ALL THREE TOWER CORES MUST STAY TIER 0, and this is a hard constraint
	# rather than a preference. Quoted from the ops file: the floors are 6 m
	# apart and each plate is 0.75 thick, so a data hall has about 5.25 m of
	# clear height. A tier 1 core is 6.97 m tall and would come up through the
	# floor above it.
	cores_by_node = {"RelayStaging": 0, "RelayCrossing": 0,
		"RelayCheckpoint": 1, "RelayYard": 2, "RelayBasement": 0,
		"RelayTwelfth": 0, "RelayUplink": 0}

	# THE BUNKER — the built redoubt at the causeway's east end.
	#
	# CW_Bunker is the POST, not the eliminate objective of the same idea.
	# bunker_marker only supplies a position: _build_bunker makes its own pad,
	# portal, Interactible and Hold, so it does not matter that the authored
	# "Bunker" here is an eliminate rather than a holdable.
	# BEHIND THE FORT, in the east yard.
	#
	# CW_Bunker is a post INSIDE the authored sandbag redoubt — the entrance
	# came up buried 3.3 m there with its doorway packed. Nudging it 12 m west
	# cleared that but left the way down in front of the fort, on the side the
	# player attacks from, which is the wrong side of a thing you take and then
	# leave through. CW_YardEast is 70 m east of the tower, behind everything
	# the assault has to get past.
	bunker_marker = &"CW_YardEast"
	bunker_fallback = Vector3(590.0, 10.0, 60.0)
	bunker_tier = 1

	entry_markers_named = [&"CW_Terrace", &"CW_SangarEast",
		&"CW_FloodEast"] as Array[StringName]

	resistance = 351
	defence_assault_seconds = 360.0
	stand_down_seconds = 45.0
	# A VERTICAL SITE: RelayTwelfth is at y 72 and RelayUplink at y 138, inside
	# halls with 5.25 m of clearance. The default 34 m beacon would spear six
	# floors. This is the map note F in the recon was written for.
	beacon_height = 4.5
