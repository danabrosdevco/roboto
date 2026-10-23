extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# MEMORY — THE PLAYER'S OWN WEAPONS AND EQUIPMENT.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/test_memory_screen.gd
#
# The screen that replaced SOFTWARE and the Armorer's half of the job. What is
# actually new, and what each check exists to stop:
#
#   ONE COST, NOT TWO. Loading HOLDS compute and unloading returns all of it.
#   If a load ever spent compute instead of holding it, every one of these
#   would still pass except the refund — so the refund is checked by amount,
#   not by "it went up".
#
#   ISSUED IS NEVER IN THE LEDGER. The Ancient Rifle and the Frag are cost 0,
#   and install_software() refuses a zero cost on purpose. That means "is it
#   loaded" cannot be answered with is_installed(), and a caller that asks the
#   wrong one finds the player unarmed.
#
#   CARRYING IS NOT AN ARMOURY TRANSACTION. fit_item() takes a copy out of
#   stores; carry_weapon() must not, or every gun you ever carried prints a
#   free copy into the pool.
#
#   THE LIST MUST RESOLVE. A CARRY entry naming an item the catalogue does not
#   have renders no card at all, which looks exactly like a design decision.
#   The Recoilless Rifle is the live example: its FILE is item_rocket.tres but
#   its id is "recoilless".
# ─────────────────────────────────────────────

const _Programs := preload("res://Campaign/software_tree.gd")
const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var cat: ItemCatalogue = load(CATALOGUE)
	var state := CampaignState.new()
	state.armoury = Armoury.new()
	state.catalogue = cat
	state.player_record = SoldierRecord.new()
	var frame: ChassisDefinition = cat.chassis_def(&"soldier")
	_check("(setup) the player has a frame to hang slots on", frame != null)
	state.player_record.set_chassis(frame, cat)

	# ── THE LIST RESOLVES, EVERY ENTRY ──────────
	var missing: Array = []
	for entry in _Programs.CARRY:
		if cat.item(entry["item"]) == null:
			missing.append(String(entry["item"]))
	_check("every carryable item is in the catalogue", missing.is_empty(), str(missing))

	var bad_kind: Array = []
	for entry in _Programs.CARRY:
		var item: ItemDefinition = cat.item(entry["item"])
		if item == null:
			continue
		var want: int = ItemDefinition.Kind.WEAPON if entry["kind"] == _Programs.CARRY_WEAPON \
			else ItemDefinition.Kind.EQUIPMENT
		if item.kind != want or not item.fits_player():
			bad_kind.append("%s (%s)" % [item.id, item.display_name])
	_check("...on the right row, and carryable by the player at all", bad_kind.is_empty(), str(bad_kind))

	# ── AND WHAT IS DELIBERATELY NOT IN IT ──────
	# Stubs wearing the Ancient Rifle's gun, and a scanner with nothing to read.
	for cut in [&"carbine", &"dmr", &"scanner"]:
		_check("%s is not offered" % cut, _Programs.carry_entry(cut).is_empty())

	# ── THE BANDS THE HUMAN SET ─────────────────
	var costs := {}
	for entry in _Programs.CARRY:
		costs[entry["item"]] = int(entry["cost"])
	_check("the Ancient Rifle is free", costs.get(&"m4", -1) == 0)
	_check("...and so is the Frag", costs.get(&"frag", -1) == 0)
	_check("the Squad Automatic is 2", costs.get(&"squad_auto", -1) == 2)
	_check("the Cluster Launcher is 2", costs.get(&"cluster_launcher", -1) == 2)
	_check("the two tabs together are 22 compute", _total_cost() == 22, "%d" % _total_cost())

	# ── ISSUED IS LOADED, AND NOT IN THE LEDGER ──
	state.award_compute(4)
	var before := state.compute_free()
	_check("the issued rifle is loaded with nothing earned for it",
		_Programs.is_loaded(state, &"m4"))
	_check("...but holds no compute", state.compute_free() == before
		and not state.is_installed(&"carry_m4"),
		"a zero cost never reaches the ledger, by design")
	_check("...and cannot be unloaded", not _Programs.unload_item(state, &"m4"))
	_check("...which the screen can say in words", _Programs.unload_block(state, &"m4") == "ISSUED")
	_check("CampaignState and the tree agree on which gun is issued",
		_Programs.is_issued(CampaignState.ISSUED_WEAPON_ID),
		"two files name m4; if they drift you are unarmed on an unload")

	# ── ONE COST, NOT TWO ───────────────────────
	_check("loading the Mark One succeeds", _Programs.load_item(state, &"bolt"))
	_check("...and holds EXACTLY its cost", state.compute_free() == before - 1,
		"%d free, was %d" % [state.compute_free(), before])
	_check("...and loading it twice does nothing", not _Programs.load_item(state, &"bolt"))
	_check("unloading it returns EXACTLY its cost", _Programs.unload_item(state, &"bolt")
		and state.compute_free() == before,
		"a partial refund here is a one-way purchase wearing a switch's clothes")

	# ── THE COST IS THE WHOLE GATE ──────────────
	_check("a 3-cost item is refused on 4 free", _Programs.load_item(state, &"hatchling"))
	_check("...and the next one is refused for want of compute",
		not _Programs.load_item(state, &"drone_pack")
		and _Programs.load_block(state, &"drone_pack") == "NEEDS 3 COMPUTE",
		"%d free" % state.compute_free())
	_check("unloading frees it again", _Programs.unload_item(state, &"hatchling")
		and _Programs.load_block(state, &"drone_pack") == "")

	# ── CARRYING TAKES NOTHING FROM STORES ──────
	# This is the whole difference from fit_item(), and the expensive one to
	# get wrong: a loaded weapon is a program, not a copy in the pool.
	_check("(setup) stores hold no Mark One", state.armoury.spare(&"bolt") == 0)
	_Programs.load_item(state, &"bolt")
	_check("carrying it works with an empty pool", state.carry_weapon(cat.item(&"bolt")))
	_check("...and the pool is still empty", state.armoury.spare(&"bolt") == 0,
		"fit_item() would have taken one; this must not")
	_check("...and it is actually in your hands", state.player_record.weapon_ids[0] == &"bolt")

	# ── UNLOADING TAKES IT OUT OF YOUR HANDS ────
	_check("unloading a carried weapon succeeds", _Programs.unload_item(state, &"bolt"))
	_check("...and falls back to the issued rifle, not to nothing",
		state.player_record.weapon_ids[0] == CampaignState.ISSUED_WEAPON_ID,
		str(state.player_record.weapon_ids[0]))

	# ── EQUIPMENT: THE SLOTS ARE THE LIMIT ──────
	var slots: int = state.player_record.equipment_ids.size()
	_check("(setup) the player has at least two equipment slots", slots >= 2, "%d" % slots)
	state.player_record.equipment_ids.fill(&"")
	_check("the free Frag can be carried", state.carry_equipment(cat.item(&"frag")))
	_check("...and not twice into two slots", not state.carry_equipment(cat.item(&"frag")))
	_Programs.load_item(state, &"smoke")
	_check("a second, different thing fills the row", state.carry_equipment(cat.item(&"smoke")))
	_Programs.load_item(state, &"emp")
	_check("...and a third is refused: loading buys the option, not the slot",
		not state.carry_equipment(cat.item(&"emp")))
	_check("dropping one makes room", state.drop_equipment(0)
		and state.carry_equipment(cat.item(&"emp")))
	_check("unloading what you carry puts it down",
		_Programs.unload_item(state, &"emp")
		and not state.player_record.equipment_ids.has(&"emp"))

	# ── A LOAD SURVIVES A SAVE ──────────────────
	# release_unknown_software() refunds anything the tree no longer knows.
	# Leave the carry ids out of ids() and every gun you own unloads itself on
	# the next load, quietly and with a refund that looks like free compute.
	var known: Array = _Programs.ids()
	var orphans: Array = []
	for id in _Programs.carry_ids():
		if not known.has(id):
			orphans.append(String(id))
	_check("the tree's id list knows the carry list", orphans.is_empty(), str(orphans))
	state.player_record.equipment_ids.fill(&"")
	_Programs.load_item(state, &"smoke")
	var dropped := state.release_unknown_software(known)
	_check("...so a load survives a reload", state.is_installed(&"carry_smoke")
		and dropped.is_empty(), str(dropped))

	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)


func _total_cost() -> int:
	var n := 0
	for entry in _Programs.CARRY:
		n += int(entry["cost"])
	return n
