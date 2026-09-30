extends SceneTree

# ─────────────────────────────────────────────
# EVERY AMMO STOCK ACTUALLY CARRIES ITS NUMBERS.
#
# A .tres applies its properties in FILE ORDER. Put `script = ...` after the
# values and Godot sets ammo_type/amount/capacity on a bare Resource, which has
# no such properties, and silently drops all three — the stock loads with an
# empty type and AmmoPool.reset() skips it, because skipping empty types is
# correct. Four stocks shipped that way and the symptom was "no ammo at all".
#
# NOTHING ELSE CATCHES THIS. check.sh passes: the file is valid, the load
# succeeds, the resource exists. Only reading the values back finds it.
#
# The second half boots the real player and asks the pool, because a stock that
# loads fine but was never added to test_character.tscn's starting_ammo is the
# same symptom from a different cause.
# ─────────────────────────────────────────────

const DIR := "res://Character/equipment/ammo"

var _fails := 0


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

	var types: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		_check("the ammo folder exists", false, DIR)
		quit(1)
		return
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var stock = load("%s/%s" % [DIR, f])
		var t = stock.get("ammo_type") if stock != null else null
		var a = stock.get("amount") if stock != null else null
		var cap = stock.get("capacity") if stock != null else null
		var ok: bool = t != null and String(t) != "" and int(a) > 0 and int(cap) > 0
		_check("%s carries its values" % f, ok,
			"type=%s amount=%s — properties set before `script =` are discarded" % [str(t), str(a)])
		if ok:
			types.append(t)

	# ── AND THE PLAYER IS ACTUALLY HOLDING THEM ──
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 120:
		await physics_frame
	var player: Node = _find(root, "Player")
	var pool: Node = player.get_node_or_null("AmmoPool") if player != null else null
	_check("the player has an AmmoPool", pool != null)
	if pool == null:
		_report()
		return
	for t in types:
		_check("...and starts with %s" % t, pool.get_count(t) > 0,
			"not in test_character.tscn's starting_ammo")
	_report()


func _report() -> void:
	print("")
	print("AMMO FAILURES: %d" % _fails)
	if _fails == 0:
		print("ALL AMMO CHECKS PASS")
	quit(1 if _fails > 0 else 0)
