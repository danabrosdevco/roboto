extends "res://Env/world_objects/site_slice.gd"

# ─────────────────────────────────────────────
# COAST ROAD, AS A SITE.
#
# A 700 m line with the cores strung along it. Good attack, mediocre defence —
# two of its three approaches are the same axis and only Coast_NorthIn is a
# genuine flank. Worth a defence anyway because it borders Valley Basin, so it
# is where the frontier actually moves first.
# ─────────────────────────────────────────────


func _init() -> void:
	# NODE NAMES, not tags. See hillfort_slice.gd for why that distinction
	# cost this whole conversion pass a correction.
	#
	# RelayTown is the authored large prefab with a 4 s channel — the prize at
	# the east end — so it is the tier 2. The other two are mediums.
	cores_by_node = {"RelayBridge": 1, "RelayCraters": 1, "RelayTown": 2}

	# THE BUNKER — the town gate.
	#
	# NOT THE OLD EXIT PAD, which is at (505, 0.84, 20) and has no marker on
	# it. Coast_Gate is an authored garrison post 36 m west of it, which means
	# it is somewhere the level already expects a robot to stand — the pad has
	# only ever been walked into, never stood on, and nothing has verified it
	# as navigable ground.
	bunker_marker = &"Coast_Gate"
	bunker_fallback = Vector3(470.0, -0.09, 10.0)
	bunker_tier = 1

	entry_markers_named = [&"Coast_EastIn", &"Coast_NorthIn", &"Coast_Bridge",
		&"Coast_FordNorth"] as Array[StringName]

	resistance = 141
	# 700 m FROM THE EAST ROAD TO THE WEST BRIDGEHEAD. The basin's 240 s is for
	# a 300 m bowl; an attacker entering at Coast_EastIn has nearly 700 m to
	# walk before it reaches the far core, and a pool that empties before they
	# arrive hands the player a win for standing still.
	defence_assault_seconds = 420.0
	stand_down_seconds = 45.0
