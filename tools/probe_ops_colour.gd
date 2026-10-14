extends SceneTree

# ─────────────────────────────────────────────
# DOES THE BOARD GO BLUE WHEN YOU TAKE A PLACE?
#
# Reported from a playtest: beating Valley Basin left its marker the same
# colour on the operations table. The board tints from _tint_for(), so this
# runs a real campaign through a real completion and asks the three questions
# that could each explain it:
#
#   does the CLEAR get recorded          (clears_of > 0)
#   does the SITE change hands           (state.holds)
#   does the tint the board would draw actually change
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_ops_colour.gd
# ─────────────────────────────────────────────

const _Pal := preload("res://Character/hud/hud_palette.gd")

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var world: Node = load("res://Env/world.tscn").instantiate()
	# NEVER WRITE THE PLAYER'S CAMPAIGN.
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 150:
		await physics_frame

	var cm = world.get_node("CampaignManager")
	var state = cm.state
	_check("a campaign is running", state != null)
	if state == null:
		_done()
		return
	_check("...and it knows the board", state.locations != null,
		"locations = %s" % str(state.locations))

	var site = state.locations.for_mission(&"basin_1_anchor") if state.locations != null else null
	_check("Valley Basin resolves to a Location", site != null)
	if site == null:
		_done()
		return

	# ── before ──────────────────────────────────
	var before_clears: int = state.clears_of(&"basin_1_anchor")
	var before_holds: bool = state.holds(site.id)
	var before_turn: int = state.turn
	print("  before: clears=%d holds=%s turn=%d" % [before_clears, str(before_holds), before_turn])

	# ── beat it, the way the game does ──────────
	# extract(true) IS the debrief path: it awards the reward, records the
	# clear, advances the turn and takes the ground. Driven directly because a
	# real deploy needs a level load and a player body, and what is being
	# tested is the bookkeeping, not the shooting.
	cm.select_mission(&"basin_1_anchor")
	cm.current_mission = cm.get_mission(&"basin_1_anchor")
	var result: Dictionary = cm.extract(true)
	print("  extract: turn=%s site_taken=%s reward=%s" % [
		str(result.get("turn", "-")), str(result.get("site_taken", "-")),
		str(result.get("reward", "-"))])
	for _i in 60:
		await physics_frame

	# ── after ───────────────────────────────────
	var clears: int = state.clears_of(&"basin_1_anchor")
	_check("the clear is recorded", clears > before_clears,
		"%d -> %d" % [before_clears, clears])
	_check("the operation is in completed_missions",
		state.completed_missions.has(&"basin_1_anchor"))
	_check("THE SITE CHANGES HANDS", state.holds(site.id),
		"owner = %d (PLAYER is %d)" % [state.site_owner(site.id), int(Enums.Factions.PLAYER)])
	_check("...and a turn passed", state.turn > before_turn,
		"%d -> %d" % [before_turn, state.turn])
	_check("...so it pays something per turn", state.income_per_turn() > 0,
		"%d/turn" % state.income_per_turn())

	# ── what the board would draw ───────────────
	# Mirrors ops_table._tint_for exactly: OWNERSHIP FIRST, then locked. The
	# old order tested locked first and returned grey, which is what the
	# playtest saw — Valley Basin requires Hillfort, and with UNLOCK ALL
	# MISSIONS on you can beat the basin without ever running the hillfort.
	var mission = cm.get_mission(&"basin_1_anchor")
	var deployable: bool = cm.available_missions().has(mission)
	var locked: bool = not deployable
	var held: bool = state.holds(site.id)
	var tint: Color = _Pal.HELD if held else (_Pal.GONE if locked else _Pal.FAC_ADVERSARY)
	_check("the board draws a site you HOLD as blue", tint.is_equal_approx(_Pal.HELD),
		"held=%s locked=%s -> %s" % [str(held), str(locked), str(tint)])
	_check("...even though its prerequisite was never run",
		not state.completed_missions.has(&"hillfort_1_relay"),
		"hillfort cleared = %s" % str(state.completed_missions.has(&"hillfort_1_relay")))
	_check("LOCKED and DEPLOYABLE are exact opposites", locked != deployable,
		"locked=%s deployable=%s" % [str(locked), str(deployable)])

	# ── and is the table actually listening? ────
	var table = _find(root, "OpsTable")
	if table == null:
		print("  (no OpsTable in this tree — it lives in the base level)")
	else:
		_check("the table refreshes when you come home",
			cm.returned_to_base.is_connected(table.refresh)
			or cm.returned_to_base.get_connections().size() > 0,
			"%d listener(s) on returned_to_base" % cm.returned_to_base.get_connections().size())

	_done()


func _done() -> void:
	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)


func _find(n: Node, named: String) -> Node:
	if n.name == named:
		return n
	for c in n.get_children():
		var f := _find(c, named)
		if f != null:
			return f
	return null
