extends SceneTree

# ─────────────────────────────────────────────
# A REAL SQUAD, ONE ROBOT PER ITEM, ORDERED THROUGH THE REAL TOOL.
#
# The other two designator suites each cover one end. test_designator builds
# squads by hand and pins the ORDER; test_designator_live boots the world and
# pins the WIRING. Neither touches the join between them, which is the longest
# and least obvious part of the chain:
#
#   catalogue item -> SoldierRecord.equipment_ids -> SquadSpawner -> an
#   AIEquipmentSlot on a deployed Soldier -> SquadCommander.orderable_equipment
#   -> the designator's mode list -> an order -> something in the world
#
# EVERY LINK IN THAT WAS BROKEN UNTIL THIS WEEK, and two of them silently:
#
#   * squad_spawner skipped any item failing fits_ai(), which all four of these
#     did — so you could buy smoke, fit it, deploy, and the slot was simply not
#     there. No warning, no empty slot on the HUD, nothing.
#   * the spawner never set the slot's label or item_id, so even once the slot
#     existed it could not be named or drawn. Enemy falls back to the literal
#     string "EQUIPMENT", which is what the squad HUD printed for every spend.
#
# So the checks below deliberately assert on the NAMES, not just on counts: a
# mode list of four entries all called "EQUIPMENT" would pass a count test and
# be useless in the player's hands.
#
# Part one drives the actual tool with the actual camera — aim, hold, release.
# Part two orders the remaining three through the commander at fixed marks, so
# item coverage does not depend on where a raycast happened to land.
#
# Boots world.tscn with autosave OFF: this reads the save on this machine and
# must never write it.
# ─────────────────────────────────────────────

const ITEMS := [
	# id, what the screen should call it, does an order want a point
	[&"smoke", "SMOKE", true],
	[&"mine_cluster", "CLUSTER MINE", true],
	[&"mine_heavy", "HEAVY MINE", true],
	[&"drone_pack", "DRONE PACK", false],
]

var _fails := 0
var _toasts: Array = []
var _refusals: Array = []
var _queued: Array = []


func _check(label: String, got, want) -> void:
	if got == want:
		print("  ok   %-58s %s" % [label, str(got)])
	else:
		_fails += 1
		print("  FAIL %-58s got %s, wanted %s" % [label, str(got), str(want)])


func _find(node: Node, named: String) -> Node:
	if node.name == named:
		return node
	for kid in node.get_children():
		var hit := _find(kid, named)
		if hit != null:
			return hit
	return null


func _bodies_in(level: Node) -> int:
	var n := 0
	for c in level.get_children():
		if c is RigidBody3D:
			n += 1
	return n


func _init() -> void:
	await process_frame
	var world_scene: Node = load("res://Env/world.tscn").instantiate()
	world_scene.get_node("CampaignManager").autosave = false
	root.add_child(world_scene)
	for _i in 90:
		await physics_frame

	var player: Node3D = get_first_node_in_group("player") as Node3D
	if player == null:
		player = _find(root, "test_character") as Node3D
	var level: Node = player.get_parent()
	var cm = world_scene.get_node("CampaignManager")
	var spawner: SquadSpawner = cm.spawner
	var commander: SquadCommander = _find(root, "SquadCommander")
	var loadout = player.get("loadout")
	var cat: ItemCatalogue = cm.catalogue
	_check("(setup) world, spawner, commander and loadout are all up",
		spawner != null and commander != null and loadout != null and cat != null, true)
	if spawner == null or commander == null or loadout == null:
		print("FAIL — nothing else can be checked")
		quit(1)
		return

	commander.equipment_ordered.connect(func(_s, label: String, count: int):
		_toasts.append("%s x%d" % [label, count]))
	commander.equipment_refused.connect(func(reason: String): _refusals.append(reason))
	commander.equipment_queued.connect(func(label: String): _queued.append(label))

	# ── A ROSTER OF ONE ROBOT PER ITEM ───────────
	# In memory only; autosave is off and nothing here goes home.
	print("A SQUAD CARRYING ONE OF EACH")
	var state = cm.state
	state.roster.clear()
	state.teams.clear()
	state.supply_cap = 400
	var foot: ChassisDefinition = cat.chassis_def(&"soldier")
	var records: Array[SoldierRecord] = []
	for entry in ITEMS:
		var r := SoldierRecord.new()
		r.display_name = String(entry[0]).to_upper()
		r.set_chassis(foot, cat)
		# ALL ON FOOT on purpose: robots are teamed by frame, so four infantry
		# arrive as ONE squad — which is what puts all four items in front of
		# one designator at the same time.
		r.equipment_ids[0] = entry[0]
		r.recompute_stats(cat)
		state.add_soldier(r)
		records.append(r)
	_check("four records, each fitted with its own item", records.size(), 4)
	for i in ITEMS.size():
		var item := cat.item(ITEMS[i][0])
		# The flag that made all of this impossible. Worth asserting here and
		# not only in the catalogue test: if it regresses, everything below
		# fails in a way that looks like the designator is broken.
		_check("%s is fittable to a squadmate at all" % ITEMS[i][0], item.fits_ai(), true)

	spawner.spawn_mode = SquadSpawner.SpawnMode.PLAYER
	spawner.deploy_into(level, records)
	for _i in 20:
		await physics_frame
	commander._refresh_registry_quietly()
	var squad: Squad = commander.get_selected_squad()
	_check("they deploy as one squad", squad != null, true)
	if squad == null:
		print("FAIL — nothing else can be checked")
		quit(1)
		return
	_check("...of four", squad.get_orderable_members().size(), 4)

	# ── THE SLOT SURVIVED THE SPAWN ──────────────
	print("THE SPAWNER BUILT REAL SLOTS, NAMED")
	for i in ITEMS.size():
		var body = spawner.find_body(records[i])
		var slots = body.get("equipment_slots") if body != null else null
		var has_one: bool = slots != null and slots.size() > 0
		_check("%s deployed carrying something" % ITEMS[i][0], has_one, true)
		if has_one:
			# BOTH of these were left unset by the spawner, and a slot that
			# knows neither can be spent by the AI and never named or drawn.
			_check("...and the slot knows its item id", str(slots[0].item_id), str(ITEMS[i][0]))
			_check("...and is not called the word EQUIPMENT",
				slots[0].label != "" and slots[0].label.to_upper() != "EQUIPMENT", true)

	# ── THE DESIGNATOR SEES ALL FOUR ─────────────
	print("THE DESIGNATOR READS THE SQUAD, NOT THE SHOP")
	var tool_node = _find(player, "Designator")
	loadout.equip_slot(1)
	# LONG ENOUGH FOR IT TO COME UP. equip_time is 0.3s and PlayerEquipment
	# refuses every input while is_raising(), so holding the trigger ten physics
	# frames (0.17s) after drawing it does nothing at all — which is correct
	# behaviour and an entirely silent test failure.
	for _i in 40:
		await physics_frame
	_check("the designator is in hand", loadout.current == tool_node, true)
	tool_node.refresh_modes()
	# TWO MOVEMENT ORDERS PLUS ONE PER ITEM. Advance and Follow Me are always on
	# the dial — they cost nothing and need no kit — which is what makes the tool
	# worth drawing for a squad carrying nothing at all.
	_check("the dial carries both movement orders and every item carried",
		tool_node.mode_count(), 6)
	_check("...with ADVANCE first, because it is the one most often wanted",
		str(tool_node._modes[0]["item_id"]), "@advance")
	_check("...and FOLLOW ME second", str(tool_node._modes[1]["item_id"]), "@follow")
	# Neither is spent, so neither waits on a hold. T has always been instant and
	# routing the same order through a nicer interface must not make it slower.
	_check("...and neither movement order needs the hold",
		bool(tool_node._modes[0]["deliberate"]) or bool(tool_node._modes[1]["deliberate"]), false)

	var labels: Array = []
	var seen: Dictionary = {}
	for i in tool_node.mode_count():
		var m = tool_node._modes[i]
		labels.append(str(m["label"]).to_upper())
		seen[m["item_id"]] = m
	for entry in ITEMS:
		_check("%s is on the dial" % entry[0], seen.has(entry[0]), true)
		if seen.has(entry[0]):
			_check("...with exactly the one robot that carries it",
				int(seen[entry[0]]["holders"]), 1)
			# The drone pack is a CONFIRM and the rest are a POINT. Getting this
			# wrong means the player holds the trigger for a second and a half
			# on something that never needed aiming, or taps something that did.
			_check("...and knows whether it wants a point",
				bool(seen[entry[0]]["wants_point"]), bool(entry[2]))
	print("      the dial reads: %s" % ", ".join(labels))

	# ── RELOAD CYCLES IT, AND COMES BACK ROUND ───
	print("RELOAD CYCLES THE DIAL")
	var first: StringName = tool_node.current_mode_id()
	var walked: Array = [first]
	for _i in tool_node.mode_count() - 1:
		tool_node.reload_pressed()
		walked.append(tool_node.current_mode_id())
	_check("every press walks a distinct mode",
		walked.size() == tool_node.mode_count() and _distinct(walked), true)
	tool_node.reload_pressed()
	_check("...and one more comes back to the first", tool_node.current_mode_id(), first)

	# ── PART ONE: THE REAL TOOL, THE REAL CAMERA ─
	print("AIM, HOLD, RELEASE — THE WHOLE VERB")
	# Put the dial on smoke, then look at a patch of ground beside the squad.
	# BOUNDED. reload_pressed() is a no-op when there is one mode or none, so an
	# unbounded while here spins forever on a squad that failed to deploy — a
	# silent hang instead of a failed check, which is the worst way for a test to
	# break.
	for _i in tool_node.mode_count() + 1:
		if tool_node.current_mode_id() == &"smoke":
			break
		tool_node.reload_pressed()
	_check("the dial can be put on smoke", str(tool_node.current_mode_id()), "smoke")
	var cam: Camera3D = _find(player, "Camera3D") as Camera3D
	var aim_at: Vector3 = squad.get_center() + Vector3(0, 0, 14)
	cam.look_at(Vector3(aim_at.x, aim_at.y, aim_at.z), Vector3.UP)
	await process_frame
	var mark: Vector3 = commander.aim_mark()
	_check("the crosshair resolves to a point on the map",
		mark.distance_to(cam.global_position) < 200.0, true)

	var before := _bodies_in(level)
	var smoke_body = spawner.find_body(records[0])
	_check("the tool is up and ready to take input", tool_node.is_raising(), false)
	tool_node.primary_pressed()
	# Held in 1/60ths, exactly as the loadout drives it, rather than handed the
	# whole duration in one call — a hold that only works when it is fed one big
	# delta is not a hold.
	#
	# `rose` is load-bearing: charge is 0.0 both BEFORE the hold starts and after
	# it commits, so breaking on "charge == 0" alone exits on the first iteration
	# and the test passes having ordered nothing.
	var rose := false
	var committed := false
	var ghosted := false
	var ghost_near := false
	for _i in 150:
		tool_node.primary_held(1.0 / 60.0)
		if tool_node.charge > 0.0:
			rose = true
			# THE GHOST, WHILE IT IS CHARGING. A second and a half of hold with
			# nothing on the ground is a wait; with the order drawn where it will
			# land it is an aim. The crosshair alone cannot show this — the mark
			# snaps to the ground and to the feet of anything it hits, so where it
			# RESOLVES to is often not the pixel you are pointing at.
			var g = commander._preview
			if g != null and is_instance_valid(g):
				ghosted = true
				if g.global_position.distance_to(tool_node.mark) < 6.0:
					ghost_near = true
		elif rose:
			committed = true
			break
		await physics_frame
	_check("the hold charged", rose, true)
	_check("...and committed on its own, without a release", committed, true)
	_check("...with the order ghosted on the ground while it charged", ghosted, true)
	_check("...at the mark it was going to land on", ghost_near, true)
	# AND TAKEN AWAY AGAIN. A ghost left behind is a mark on the map for an order
	# that has already happened, which is the same clutter the minimap just lost.
	_check("...and gone once the order went",
		commander._preview == null or not is_instance_valid(commander._preview), true)
	await process_frame
	_check("a canister went into the level", _bodies_in(level) > before, true)
	# INTO THE LEVEL, not into the current scene. current_scene is MASTER in this
	# project — above World, above the level — so ordnance parented there outlives
	# the mission it was fired in, which is how a Drone Carrier Pack thrown near
	# the end of one mission left two Divers flying around in the next.
	#
	# This cannot be caught by counting: a script-run tree has no current_scene,
	# so the old code's fallback happened to be right here and wrong in the game.
	# The parent has to be asserted directly.
	var landed := _newest_rigidbody_in(level)
	_check("...parented to the level, so the mission takes it with it",
		landed != null and landed.get_parent() == level, true)
	_check("the robot that carries smoke is the one that spent it",
		smoke_body.equipment_slots[0].remaining(), smoke_body.equipment_slots[0].quantity - 1)
	# AND THE SQUAD HUD CAN NAME IT. This is the whole point of the slot label:
	# before it, a spend always read as "EQUIPMENT".
	_check("...and what it just did has a name",
		smoke_body._last_equipment_label.to_upper() != "EQUIPMENT"
		and smoke_body._last_equipment_label != "", true)
	print("      the robot reports: %s" % smoke_body._last_equipment_label)
	_check("the HUD was told, once", _toasts.size(), 1)
	print("      the toast reads: %s" % str(_toasts[0] if not _toasts.is_empty() else "<none>"))

	# ── PART TWO: THE OTHER THREE ────────────────
	# Through the commander at fixed marks, so coverage does not ride on where a
	# raycast landed.
	print("EVERY OTHER ITEM ANSWERS TOO")
	for i in range(1, ITEMS.size()):
		var id_value: StringName = ITEMS[i][0]
		var wants_point: bool = ITEMS[i][2]
		var body = spawner.find_body(records[i])
		var had: int = body.equipment_slots[0].remaining()
		var at: Vector3 = body.global_position + Vector3(0, 0, 10)
		var count := _bodies_in(level)
		var sent: bool = commander.issue_equipment_order(id_value, str(ITEMS[i][1]), at, wants_point)
		await process_frame
		_check("%s is ordered and answers" % id_value, sent, true)
		_check("...spending one of its own", body.equipment_slots[0].remaining(), had - 1)
		_check("...and putting something in the level", _bodies_in(level) > count, true)

	# ── IT STILL SAYS NO WHEN IT HAS TO ──────────
	# ── A HELD ORDER, NOT A REFUSAL ──────────────
	# "Everyone who carries it is between uses" is a WAIT, not a no. It used to
	# come back as a refusal, which made the player poll their own squad: press,
	# get told no, count to four, press again. The order was good, it was early.
	print("IT HOLDS AN ORDER RATHER THAN REFUSING IT")
	var was := _refusals.size()
	var held := _queued.size()
	_check("a second smoke order right away does not fire now",
		commander.issue_equipment_order(&"smoke", "SMOKE", mark, true), false)
	_check("...it is held instead", _queued.size(), held + 1)
	_check("...and nothing was refused", _refusals.size(), was)
	print("      it said: %s : STANDING BY" % str(_queued[-1]))
	_check("the designator's screen says it is standing by",
		tool_node.is_queued(), true)

	# ...and it fires on its own the moment the robot is ready again. No second
	# press: that is the whole point of holding it.
	var spent := _toasts.size()
	smoke_body._equipment_cooldowns.clear()
	for _i in 90:
		await physics_frame
		if _toasts.size() > spent:
			break
	_check("...then it goes, on its own, with no second press", _toasts.size(), spent + 1)
	# TWO SPENT, whatever the item's quantity happens to be. This asserted ZERO
	# left, which only held while a smoke canister was two per mission — it was
	# pinning the stock size through a check about queueing.
	_check("...spending a second canister",
		smoke_body.equipment_slots[0].remaining(),
		smoke_body.equipment_slots[0].quantity - 2)
	_check("...and the screen stops saying it", tool_node.is_queued(), false)

	# ── THE THREE THAT ARE STILL A NO ────────────
	# None of these resolves by waiting, so queueing them would be a lie: move,
	# or go to the armoury, or it is gone for the mission.
	print("AND THE REFUSALS THAT WAITING CANNOT FIX ARE STILL REFUSALS")
	# EMPTY IT FIRST. "None left" is the refusal being tested, and how many orders
	# it takes to get there is the item's business, not this test's.
	smoke_body.equipment_slots[0]._quantity_remaining = 0
	smoke_body._equipment_cooldowns.clear()
	was = _refusals.size()
	_check("smoke with none left is refused, not held",
		commander.issue_equipment_order(&"smoke", "SMOKE", mark, true), false)
	_check("...and said why", _refusals.size(), was + 1)
	print("      it said: %s" % (str(_refusals[-1]) if not _refusals.is_empty() else "<nothing>"))

	for who in squad.get_orderable_members():
		who._equipment_cooldowns.clear()
	var mine_body = spawner.find_body(records[1])
	var far_off: Vector3 = mine_body.global_position + Vector3(300, 0, 0)
	was = _refusals.size()
	_check("a mark three hundred metres away is refused",
		commander.issue_equipment_order(&"mine_cluster", "CLUSTER MINE", far_off, true), false)
	_check("...and said why", _refusals.size(), was + 1)
	print("      it said: %s" % (str(_refusals[-1]) if not _refusals.is_empty() else "<nothing>"))

	was = _refusals.size()
	_check("an item nobody in the squad carries is refused",
		commander.issue_equipment_order(&"frag", "FRAG", mark, true), false)
	_check("...and said why", _refusals.size(), was + 1)
	print("      it said: %s" % (str(_refusals[-1]) if not _refusals.is_empty() else "<nothing>"))

	# ── AND A HELD ORDER GIVES UP OUT LOUD ───────
	# Dropping it quietly would leave the player believing smoke is still
	# coming, which is worse than having been told no in the first place.
	print("A HELD ORDER THAT NOBODY EVER ANSWERS ENDS WITH A SENTENCE")
	commander.queue_timeout = 0.6
	mine_body._equipment_cooldowns[0] = 999.0
	held = _queued.size()
	was = _refusals.size()
	var near_mine: Vector3 = mine_body.global_position + Vector3(0, 0, 8)
	_check("it is held to begin with",
		commander.issue_equipment_order(&"mine_cluster", "CLUSTER MINE", near_mine, true), false)
	_check("...held, not refused", _queued.size(), held + 1)
	for _i in 120:
		await physics_frame
		if _refusals.size() > was:
			break
	_check("...and given up on, out loud, once it times out",
		_refusals.size(), was + 1)
	print("      it said: %s" % (str(_refusals[-1]) if not _refusals.is_empty() else "<nothing>"))
	_check("...and the screen is no longer standing by", tool_node.is_queued(), false)

	# ── A CONFIRM MODE CHARGES DOWN AND ACTUALLY RELEASES ─────
	# The Drone Carrier Pack needs no point, and primary_held used to return
	# early on exactly that — so it charged nothing, reached no commit, and could
	# NEVER BE ORDERED. It sat on the dial, selectable and inert.
	print("A CONFIRM MODE CHARGES DOWN, AND SOMETHING COMES OUT")
	for who in squad.get_orderable_members():
		who._equipment_cooldowns.clear()
	tool_node.refresh_modes()
	for _i in tool_node.mode_count():
		if tool_node.current_mode_id() == &"drone_pack":
			break
		tool_node.reload_pressed()
	_check("the dial is on the drone pack", str(tool_node.current_mode_id()), "drone_pack")
	_check("...which needs no point", tool_node.mode_wants_point(), false)
	_check("...and still charges down", tool_node.mode_deliberate(), true)

	var pack_body = spawner.find_body(records[3])
	var pack_had: int = pack_body.equipment_slots[0].remaining()
	var air_before := _bodies_in(level)
	tool_node._repeat_t = 0.0
	tool_node.primary_pressed()
	var pack_rose := false
	var pack_sent := false
	for _i in 150:
		tool_node.primary_held(1.0 / 60.0)
		if tool_node.charge > 0.0:
			pack_rose = true
		elif pack_rose:
			pack_sent = true
			break
		await physics_frame
	_check("the hold charges with nothing to aim at", pack_rose, true)
	_check("...and commits on its own", pack_sent, true)
	await process_frame
	_check("...spending the pack", pack_body.equipment_slots[0].remaining(), pack_had - 1)
	# NOT COUNTING THE CANISTER. It opens on first contact (bounce_before_explode
	# is 0), so it is already gone a frame later and a count taken afterwards says
	# nothing ever happened. The Divers below subsume it anyway: they cannot be in
	# the air unless a canister got there first.

	# AND IT OPENS. A canister that lands and sits there is the half of this the
	# player actually sees — "I am not seeing them release anything".
	var divers := 0
	for _i in 420:
		await physics_frame
		divers = 0
		for n in level.get_children():
			if n is Soldier and str(n.scene_file_path).contains("diver"):
				divers += 1
		if divers > 0:
			break
	_check("...which opens into Divers", divers > 0, true)
	print("      divers in the air: %d" % divers)

	# ── THE DIAL IS NOT AMMO ─────────────────
	# Spend an item to nothing and the squad still BROUGHT it. It used to drop
	# off the dial, which made the designator feel like it had a magazine — play
	# long enough and you were left holding a tool that could only say ADVANCE
	# and FOLLOW. The designator has no ammo. The squad has ammo.
	print("THE DIAL IS THE SQUAD'S LOADOUT, NOT ITS STOCK")
	var dial_before: int = tool_node.mode_count()
	for c in squad.get_orderable_members():
		var si: int = c.equipment_slot_for(&"mine_cluster")
		if si >= 0:
			c.equipment_slots[si]._quantity_remaining = 0
		c._equipment_cooldowns.clear()
	tool_node.refresh_modes()
	_check("an item spent to nothing is still on the dial",
		tool_node.mode_count(), dial_before)
	for _i in tool_node.mode_count():
		if tool_node.current_mode_id() == &"mine_cluster":
			break
		tool_node.reload_pressed()
	_check("...and it is the one we emptied", str(tool_node.current_mode_id()), "mine_cluster")
	_check("...reading NONE LEFT", tool_node.mode_status(), "NONE LEFT")

	# AND BETWEEN USES IS NOT THE SAME AS OUT. Everyone on cooldown is zero
	# holders too, and calling that "NONE LEFT" is what made a squad with three
	# canisters read as a squad with none.
	var heavy = spawner.find_body(records[2])
	heavy._equipment_cooldowns[heavy.equipment_slot_for(&"mine_heavy")] = 999.0
	tool_node.refresh_modes()
	for _i in tool_node.mode_count():
		if tool_node.current_mode_id() == &"mine_heavy":
			break
		tool_node.reload_pressed()
	_check("the mode we put on cooldown is selected",
		str(tool_node.current_mode_id()), "mine_heavy")
	_check("...with nobody able to answer right now", tool_node.mode_holders(), 0)
	_check("...but stock still on the squad", tool_node.mode_remaining() > 0, true)
	_check("...so it says RELOADING, not NONE LEFT", tool_node.mode_status(), "RELOADING")
	# ...and the press is not refused by the tool: the commander holds it.
	var held_now := _queued.size()
	tool_node._repeat_t = 0.0
	tool_node._commit(true)
	await process_frame
	_check("...and pressing it holds the order rather than being refused",
		_queued.size(), held_now + 1)

	# ── IT UNSTICKS ITSELF ────────────────────
	# The dial was read only on draw, on cycle and on commit, so the holder count
	# was a snapshot. Use something, and the screen said RELOADING from that
	# instant until you happened to cycle — long after the squad could answer
	# again. tick() re-reads it now, and this is what that is for.
	print("THE READOUT CATCHES UP ON ITS OWN")
	for who in squad.get_orderable_members():
		who._equipment_cooldowns.clear()
		for sl in who.equipment_slots:
			sl._quantity_remaining = sl.quantity
	tool_node.refresh_modes()
	for _i in tool_node.mode_count():
		if tool_node.current_mode_id() == &"smoke":
			break
		tool_node.reload_pressed()
	# Captured, not typed: how many robots carry smoke is this squad's business.
	var ready_status: String = tool_node.mode_status()
	_check("smoke is ready to begin with", ready_status.contains("CAN ANSWER"), true)

	# Put its carrier on a cooldown and DO NOT cycle: the readout has to notice.
	var sb = spawner.find_body(records[0])
	sb._equipment_cooldowns[sb.equipment_slot_for(&"smoke")] = 999.0
	var caught := false
	for _i in 60:
		tool_node.tick(1.0 / 60.0)
		await physics_frame
		if tool_node.mode_status() == "RELOADING":
			caught = true
			break
	_check("...and goes RELOADING without being cycled", caught, true)

	# Now clear it, still without cycling. This is the half that was stuck.
	sb._equipment_cooldowns.clear()
	var recovered := false
	for _i in 60:
		tool_node.tick(1.0 / 60.0)
		await physics_frame
		if tool_node.mode_status() == ready_status:
			recovered = true
			break
	_check("...and comes back on its own once the cooldown passes", recovered, true)
	# The press debounce is a separate, deliberate 1s guard and the loop above
	# broke as soon as the readout recovered. Drained here so this checks the
	# thing it is about: that nothing STALE is refusing the order.
	tool_node._repeat_t = 0.0
	_check("...so it can be ordered again", tool_node._ready_to_order(), true)

	if _fails == 0:
		print("ALL SQUAD DESIGNATOR CHECKS PASS")
	else:
		print("SQUAD DESIGNATOR FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)


func _distinct(a: Array) -> bool:
	var seen: Dictionary = {}
	for v in a:
		if seen.has(v):
			return false
		seen[v] = true
	return true


## The most recently added RigidBody3D in `where`. Children are appended, so the
## last one is the newest.
func _newest_rigidbody_in(where: Node) -> RigidBody3D:
	var kids := where.get_children()
	for i in range(kids.size() - 1, -1, -1):
		if kids[i] is RigidBody3D:
			return kids[i]
	return null
