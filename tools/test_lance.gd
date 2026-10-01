extends SceneTree

# ─────────────────────────────────────────────
# THE LANCE HAS TO CONNECT, AND HAS TO SAY WHEN IT DOES NOT.
#
# Reported as "I can't get it to actually hit anything to either repair or
# attack". The ray itself turned out to be fine — it connects from 1m to its full
# 3.4m across a wide spread of aim. What was wrong was everything around it:
#
#   * The hit was decided on ONE frame, at swing_time * impact_at. That was
#     survivable at the old 0.62 of 1.1s, which gave you two thirds of a second
#     to walk into something after committing; retiming the stroke to 0.154s made
#     it almost instant, so closing the last half metre no longer counted.
#   * Mending an ally who was not damaged did NOTHING — no charge spent, no
#     sound, no message. An undamaged ally is the most likely thing to be pointed
#     at, so "it does not repair" was the honest reading of a working lance.
#   * The scene had no AudioStreamPlayer at all, so a thrust that connected
#     sounded exactly like one that did not.
#
#   godot --headless --path . --script res://tools/test_lance.gd
# ─────────────────────────────────────────────

const LANCE := "res://Character/weapon/repair_lance_hud_weapon.tscn"
const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"

var _fails: int = 0
var _level: Node = null
var _player: Node3D = null
var _cam: Camera3D = null
var _gy: float = 0.0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _find(n: Node, cls: String) -> Node:
	if n.get_script() != null and n.get_script().get_global_name() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 90:
		await physics_frame
	_player = _find(root, "Player")
	_level = _player.get_parent()
	_level.add_child(load("res://maps/valley_level.tscn").instantiate())
	for _i in 30:
		await physics_frame
	# SETTLED ON THE GROUND. Two bodies falling at different speeds slide past
	# each other's capsules and every ray in here reads as a miss for reasons that
	# have nothing to do with the lance.
	var space := _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(300, 300, 250), Vector3(300, -300, 250))
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q)
	_gy = hit.position.y if hit else 0.0
	_player.global_position = Vector3(300, _gy + 1.2, 250)
	for _i in 120:
		await physics_frame
	_cam = _player.get("cam")

	await _test_reach()
	await _test_closing()
	await _test_mend()
	await _test_audio()

	print("")
	print("ALL LANCE CHECKS PASS" if _fails == 0 else "%d LANCE CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


func _lance() -> Node3D:
	var l: Node3D = load(LANCE).instantiate()
	_cam.add_child(l)
	l.initialize(_player, _cam, _player.get("ammo"))
	l.equip()
	return l


## Run the lance for `frames`, driving the two things the game drives.
func _run(l: Node3D, frames: int) -> void:
	var d := 1.0 / 60.0
	for _f in frames:
		l.tick(d)
		l.update_view(d, 0.0, false, false)
		await physics_frame


func _bot(dist: float, faction: int, hp: int) -> Node3D:
	var b: Node3D = load(RIFLE).instantiate()
	b.faction = faction
	_level.add_child(b)
	var fwd: Vector3 = -_cam.global_transform.basis.z.normalized()
	var want: Vector3 = _cam.global_position + fwd * dist
	b.global_position = Vector3(want.x, _gy + 1.0, want.z)
	b.health = hp
	b.max_health = maxi(hp, 1)
	return b


# ── IT REACHES WHAT IT SAYS IT REACHES ───────
func _test_reach() -> void:
	var l := _lance()
	await _run(l, 40)                      # past the raise
	var bot := _bot(2.4, Enums.Factions.ENEMY, 100000)
	await _run(l, 60)
	var hp0: int = int(bot.health)
	l.primary_pressed()
	await _run(l, 90)
	_check("a thrust at an enemy in reach lands its damage",
		int(bot.health) == hp0 - l.damage, "hp %d -> %d, damage %d" % [hp0, int(bot.health), l.damage])
	bot.free()
	l.free()


# ── CLOSING INTO THE TARGET STILL COUNTS ─────
# The one that was actually broken. Swing at nothing, then arrive.
func _test_closing() -> void:
	var l := _lance()
	await _run(l, 40)
	var bot := _bot(9.0, Enums.Factions.ENEMY, 100000)   # far out of reach
	await _run(l, 60)
	var hp0: int = int(bot.health)
	l.primary_pressed()
	# One frame after committing, well before the window closes, it comes into
	# reach — which is what walking onto something looks like.
	await _run(l, 6)
	var fwd: Vector3 = -_cam.global_transform.basis.z.normalized()
	var want: Vector3 = _cam.global_position + fwd * 2.2
	bot.global_position = Vector3(want.x, _gy + 1.0, want.z)
	await _run(l, 90)
	_check("a target that arrives just after the swing is still hit",
		int(bot.health) == hp0 - l.damage,
		"hp %d -> %d (window %.2fs)" % [hp0, int(bot.health), float(l.strike_window)])

	# ...but a swing at thin air is still a miss, or the window has turned the
	# lance into a thing that always hits eventually.
	var l2 := _lance()
	await _run(l2, 40)
	var far := _bot(40.0, Enums.Factions.ENEMY, 100000)
	await _run(l2, 30)
	var hp1: int = int(far.health)
	l2.primary_pressed()
	await _run(l2, 120)
	_check("...and a swing at nothing is still a miss", int(far.health) == hp1,
		"hp %d -> %d" % [hp1, int(far.health)])
	bot.free()
	far.free()
	l.free()
	l2.free()


# ── MENDING SAYS WHAT IT IS DOING ────────────
func _test_mend() -> void:
	var l := _lance()
	await _run(l, 40)
	var charges0: int = int(l.charges)

	# An ally at FULL health. This did nothing at all before — no charge, no
	# sound, no message — which is what "it won't repair" was.
	var whole := _bot(2.2, Enums.Factions.PLAYER, 60)
	# PINNED. A healthy ally has working AI and walks out of reach before the
	# swing, and the test then measures an empty thrust.
	whole.set_physics_process(false)
	await _run(l, 20)
	var said := []
	l.denied.connect(func(reason: String): said.append(reason))
	l.primary_pressed()
	await _run(l, 90)
	_check("mending an undamaged ally spends no charge", int(l.charges) == charges0,
		"%d -> %d" % [charges0, int(l.charges)])
	_check("...and says so rather than doing nothing silently", said.size() > 0, str(said))
	_check("...exactly once, not once per frame of the window", said.size() == 1,
		"%d message(s)" % said.size())
	whole.free()

	# A hurt ally. This is the case that has to actually work.
	var hurt := _bot(2.2, Enums.Factions.PLAYER, 60)
	hurt.health = 10
	hurt.set_physics_process(false)
	await _run(l, 20)
	l.primary_pressed()
	await _run(l, 90)
	_check("a hurt ally is mended and it costs a charge",
		int(hurt.health) > 10 and int(l.charges) == charges0 - 1,
		"hp 10 -> %d, charges %d -> %d" % [int(hurt.health), charges0, int(l.charges)])
	hurt.free()
	l.free()


# ── IT MAKES A NOISE ─────────────────────────
# The scene had no AudioStreamPlayer at all, so every one of these was null and a
# landed thrust was indistinguishable from a whiff.
func _test_audio() -> void:
	var l := _lance()
	_check("the lance has a swing sound", l.swing_sound != null)
	_check("...and a hit sound", l.hit_sound != null)
	if l.swing_sound != null and l.hit_sound != null:
		_check("...and they are not the same sample, so a hit reads differently",
			l.swing_sound.stream != l.hit_sound.stream)
	l.free()
