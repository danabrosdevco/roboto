extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# THE WIN IS CAUSAL, AND THE GAME CAN NOW BE LOST.
#
# Two things this project has never had, tested without a level or a campaign:
#
#   1. An operation that ENDS — won by holding the bunker through a stand-down,
#      lost when the frame the player was running on is destroyed.
#   2. Pressure that the player's own choices turn up and down. Heat is emitted
#      by cores still in enemy hands, so clearing them is what makes the
#      stand-down survivable — not a checklist, a cause.
#
# docs/briefs/CAMPAIGN_REWORK.md §12.4 and §12.7.
#
#   godot --headless --path . --script res://tools/test_site_operation.gd
# ─────────────────────────────────────────────

const _Point := preload("res://Env/world_objects/holdable_core.gd")
const _Op := preload("res://Env/world_objects/site_operation.gd")
const _Heat := preload("res://Env/world_objects/site_heat.gd")

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


## A core that can be flipped without channelling it, so these tests are about
## the operation rather than about capture.
func _core(host: Node, tier: int = 1):
	var p = _Point.new()
	p.size_tier = tier
	host.add_child(p)
	return p


func _hold(p) -> void:
	p._set_holder(p.Holder.PLAYER)


func _init() -> void:
	await process_frame

	var player := Node3D.new()
	player.name = "FakePlayer"
	# `died` is what SiteOperation listens for — the real player emits it.
	# Declared WITH an argument to match the real one — test_character.gd emits
	# `died(global_position)`, and a handler bound to a 0-arg version would not
	# accept it.
	player.add_user_signal("died", [{"name": "where", "type": TYPE_VECTOR3}])
	root.add_child(player)
	player.add_to_group("player")

	var site := Node3D.new()
	site.name = "Site"
	root.add_child(site)

	var a = _core(site, 0)
	var b = _core(site, 1)
	var c = _core(site, 2)
	var bunker = _core(site, 1)
	bunker.name = "Bunker"

	var op = _Op.new()
	op.bunker = bunker
	op.stand_down_seconds = 0.6
	site.add_child(op)
	await physics_frame

	_check("the operation found the cores, and not the bunker among them",
		op.cores.size() == 3 and not op.cores.has(bunker),
		"%d cores" % op.cores.size())
	_check("all three start hostile", op.hostile_cores() == 3)
	_check("...and nothing is running yet", not op.is_standing_down())

	# ── taking the bunker starts the stand-down ──
	var started := [false]
	op.stand_down_started.connect(func(): started[0] = true)
	_hold(bunker)
	await physics_frame
	_check("taking the bunker starts the stand-down", started[0] and op.is_standing_down())
	_check("...even with every core still theirs — nothing is gated",
		op.hostile_cores() == 3,
		"the cost of rushing is the fight, not a locked door")

	# ── losing it interrupts, and progress survives ──
	var broke := [false]
	op.stand_down_interrupted.connect(func(): broke[0] = true)
	for _i in 10:
		await physics_frame
	var banked: float = op.stand_down_fraction()
	bunker._set_holder(bunker.Holder.NEUTRAL)
	await physics_frame
	_check("losing the bunker interrupts it", broke[0] and not op.is_standing_down())
	_check("...and the progress is kept, not wiped",
		op.stand_down_fraction() >= banked and banked > 0.0,
		"%.2f banked" % banked)

	# ── holding it through wins ──
	var won := [false]
	op.operation_complete.connect(func(): won[0] = true)
	_hold(bunker)
	for _i in 120:
		await physics_frame
		if won[0]:
			break
	_check("holding the bunker through the stand-down wins it", won[0])
	_check("...and it stops processing once settled", not op.is_standing_down())

	# ── the failstate ───────────────────────────
	var site2 := Node3D.new()
	root.add_child(site2)
	var bunker2 = _core(site2, 1)
	var op2 = _Op.new()
	op2.bunker = bunker2
	op2.stand_down_seconds = 30.0
	site2.add_child(op2)
	await physics_frame

	var lost := [""]
	op2.operation_failed.connect(func(r): lost[0] = r)
	_hold(bunker2)
	await physics_frame
	player.emit_signal("died", Vector3.ZERO)
	await physics_frame
	_check("losing the frame fails the operation", lost[0] != "", "reason = %s" % lost[0])
	_check("...and a settled operation cannot then be won",
		not op2.is_standing_down())

	# ── heat ────────────────────────────────────
	var site3 := Node3D.new()
	root.add_child(site3)
	var h1 = _core(site3, 2)
	var h2 = _core(site3, 2)
	var bunker3 = _core(site3, 1)
	var op3 = _Op.new()
	op3.bunker = bunker3
	site3.add_child(op3)
	await physics_frame

	var heat = _Heat.new()
	heat.operation = op3
	heat.resistance = 12
	heat.packet_supply = 4
	heat.commit_threshold = 2.0
	site3.add_child(heat)
	await physics_frame

	var hot: float = heat._rate()
	_check("two hostile cores emit heat", hot > 0.0, "%.2f a second" % hot)

	_hold(h1)
	_hold(h2)
	await physics_frame
	var cool: float = heat._rate()
	_check("CLEARING CORES TURNS THE PRESSURE DOWN", cool < hot,
		"%.2f -> %.2f a second" % [hot, cool])
	_check("...but incursion keeps it above zero, so standing off is not free",
		cool > 0.0, "%.6f a second, ramping to %.2f" % [cool, heat.incursion_heat])

	# ── the pool is finite ──────────────────────
	var sent: Array = []
	heat.committed.connect(func(s, _at): sent.append(s))
	var done := [false]
	heat.pool_spent.connect(func(): done[0] = true)
	h1._set_holder(h1.Holder.HOSTILE)
	h2._set_holder(h2.Holder.HOSTILE)
	for _i in 300:
		await physics_frame
		if done[0]:
			break
	var total := 0
	for s in sent:
		total += int(s)
	_check("heat commits squads from the pool", sent.size() > 0,
		"%d commitment(s), %d supply" % [sent.size(), total])
	_check("...and the pool is FINITE — a site can be ground down",
		done[0] and total <= 12 and heat.remaining() == 0,
		"spent %d of 12" % total)
	_check("...and it stops processing when spent", not heat.is_physics_processing())

	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
