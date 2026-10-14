extends SceneTree

# ─────────────────────────────────────────────
# ITEM FACTS — the figures a gear card prints, read off the gear's own scenes.
#
# The point of ItemFacts is that there is no second copy of a blast radius to go
# stale. This suite is what makes that claim checkable: it pins the readings for
# the gear whose numbers are known, so retuning smoke_volume.gd or emp_blast.gd
# fails here rather than silently changing what the shop advertises.
#
# It also pins the two things that are easy to get wrong in a reader like this:
#   - a mine's 99999-second fuse is not a fuse, and must not be printed
#   - an override left at 0 means "keep the round's own" and is not a reading
#
# Instances item scenes only. No world, no save, nothing written.
# ─────────────────────────────────────────────

const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"
const ItemFacts := preload("res://Campaign/item_facts.gd")

var _fails := 0
var _cat: ItemCatalogue


func _check(label: String, got, want) -> void:
	if got == want:
		print("  ok   %-46s %s" % [label, str(got)])
	else:
		_fails += 1
		print("  FAIL %-46s got %s, wanted %s" % [label, str(got), str(want)])


## The value against a label, or "" when the card would not print that row.
func _row(id: StringName, label: String) -> String:
	var item := _cat.item(id)
	if item == null:
		_fails += 1
		print("  FAIL no item '%s' in the catalogue" % id)
		return ""
	for pair in ItemFacts.of(item):
		if str(pair[0]) == label:
			return str(pair[1])
	return ""


func _labels(id: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	var item := _cat.item(id)
	if item == null:
		return out
	for pair in ItemFacts.of(item):
		out.append(str(pair[0]))
	return out


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	_cat = load(CATALOGUE)
	if _cat == null:
		printerr("test_item_facts: no catalogue at %s" % CATALOGUE)
		quit(1)
		return

	print("SMOKE — radius and duration off smoke_volume.gd")
	_check("smoke radius", _row(&"smoke", "RADIUS"), "7 M")
	# FROM THE SCENE, not typed here. The whole job of item_facts is that the
	# card reads the figure off the thing that will actually be thrown, so a test
	# that hardcodes the number tests nothing and breaks on every tuning pass.
	var cloud = load("res://Character/weapon/smoke_volume.tscn").instantiate()
	var lasts: float = float(cloud.duration)
	cloud.free()
	_check("smoke duration", _row(&"smoke", "LASTS"), "%d S" % int(round(lasts)))
	_check("smoke does no damage, so says nothing about damage",
		_labels(&"smoke").has("DAMAGE"), false)

	print("EMP — three scenes down, on emp_blast.gd")
	_check("emp radius", _row(&"emp", "RADIUS"), "9 M")
	_check("emp peak jam", _row(&"emp", "KILLS SIGNAL FOR"), "3.5 S AT THE CENTRE")
	_check("emp edge jam", _row(&"emp", "AT THE EDGE"), "0.6 S")
	_check("emp friendly fire", _row(&"emp", "HURTS FRIENDLIES"), "25% AS MUCH")

	print("FRAG — damage off the explosion, radius off its damage sphere")
	_check("frag damage", _row(&"frag", "DAMAGE"), "100")
	var frag_blast := _row(&"frag", "BLAST RADIUS")
	_check("frag blast radius is read, not invented", frag_blast != "", true)

	print("REPAIR KIT — off ai_repair_kit.tscn")
	_check("repair kit heals", _row(&"repair_kit", "REPAIRS"), "20 A TIME")
	_check("repair kit reach", _row(&"repair_kit", "REACH"), "6 M")
	_check("repair kit recharge", _row(&"repair_kit", "RECHARGE"), "14 S")

	print("MINES — a trigger, and a fuse that is not one")
	_check("heavy mine trips at", _row(&"mine_heavy", "TRIPS AT"), "2.2 M")
	_check("heavy mine arms in", _row(&"mine_heavy", "ARMS IN"), "1.5 S")
	# fuse_time 99999 is "never": it waits to be stepped on. Printing it would
	# be true and useless, which is the kind of row that teaches people to stop
	# reading the card.
	_check("a 99999s fuse is not printed as a fuse",
		_labels(&"mine_heavy").has("FUSE"), false)

	print("EVERY SHOP ITEM — nothing throws, nothing invents")
	for item in _cat.items:
		if item == null:
			continue
		var rows := ItemFacts.of(item)
		for pair in rows:
			if str(pair[1]).strip_edges() == "":
				_fails += 1
				print("  FAIL %s has an empty value against '%s'" % [item.id, pair[0]])
		# Equipment is rationed per deployment and the Armorer says so. The
		# squad manager suite reads that line, so it is pinned here too.
		if item.kind == ItemDefinition.Kind.EQUIPMENT and item.quantity > 0:
			var carries := ""
			for pair in rows:
				if str(pair[0]) == "CARRIES":
					carries = str(pair[1])
			if not carries.ends_with("PER MISSION"):
				_fails += 1
				print("  FAIL %s does not say how many per mission (got '%s')" % [item.id, carries])
	print("  ok   every catalogue item read without error")

	print("CACHE — asked twice, built once")
	var first := ItemFacts.of(_cat.item(&"smoke"))
	var again := ItemFacts.of(_cat.item(&"smoke"))
	_check("second call is the same array", first == again, true)

	if _fails == 0:
		print("PASS")
	else:
		print("FAIL — %d check(s)" % _fails)
	quit(1 if _fails > 0 else 0)
