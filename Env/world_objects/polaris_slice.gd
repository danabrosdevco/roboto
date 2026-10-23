extends "res://Env/world_objects/site_slice.gd"

# ─────────────────────────────────────────────
# POLARIS, AS A SITE — and read this before using it.
#
# THIS IS THE ONE MAP ALREADY DRAWN AS A DEFENCE, and converting it is the
# least obviously right thing in this pass. Its own briefing: "Not an advance.
# You go in, you start the drain, and then you hold." Its five pol_wave_*
# objectives are a hand-built wave director that predates SiteHeat and does by
# hand what SiteHeat now does generically, wired into the mission's own win
# condition.
#
# EVERY SITE GETS A DEFENCE, decided 2026-10-14, this one included. So the
# collision has to be resolved rather than avoided, and it resolves one way:
# ON A DEFENCE, SITEHEAT OWNS THE MAP. The pol_wave_* director is authored into
# polaris_1_siege's objective list and stays there for the attack; the defence
# does not name those objectives, so MissionObjective._ready frees them and only
# one commander is ever committing reinforcements at these cores.
#
# Worth watching in play all the same: this is the one map where the generic
# system is replacing something hand-built that already worked.
#
# RelayCinema and RelayDeck were added on 2026-10-14; before that Polaris had
# exactly one capture point, because pol_cinema and pol_garage are eliminate
# objectives with no Interactible.
# ─────────────────────────────────────────────


func _init() -> void:
	cores_by_node = {"Breach": 0, "RelayCinema": 0, "RelayDeck": 0}

	# THE BUNKER — the dock, which is the one piece of this map that reads as a
	# way out rather than a position to hold.
	# 8 m BACK OFF THE DOCK. The marker itself had a wall 2 m in front of the
	# opening — not visible in a screenshot, found by casting. Measured by
	# tools/scan_bunker_spot.gd.
	bunker_offset = Vector3(0.0, 0.0, -8.0)
	bunker_marker = &"POL_Dock"
	bunker_fallback = Vector3(-40.0, 0.0, -42.0)
	bunker_tier = 1

	# THE RING ROAD, read off the level rather than guessed. The first cut of
	# this named POL_SouthLot, which does not exist — the markers are
	# POL_LotSouth and POL_Ring{N,S,E,W}. tools/probe_slices.gd caught it,
	# which is the entire reason that probe exists: a name that resolves to
	# nothing produces no error, just a site with no reinforcement routes.
	entry_markers_named = [&"POL_RingN", &"POL_RingS", &"POL_RingE",
		&"POL_RingW", &"POL_Dock"] as Array[StringName]

	resistance = 266
	defence_assault_seconds = 360.0
	stand_down_seconds = 45.0
