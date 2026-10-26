extends SceneTree
# REPORTS: prints the table Reference/Economy.md asserts, and asserts nothing

# ─────────────────────────────────────────────
# WHAT THE ECONOMY ACTUALLY IS, MEASURED OFF THE REAL SEED AND THE REAL TABLE.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_economy_facts.gd
#
# The vault note `Reference/Economy.md` is written from this and names it in
# its `verified-by`. Re-run it before trusting the note.
#
# TWO CURRENCIES, TWO LEDGERS, AND THEY ARE NOT THE SAME SHAPE.
#
#   RESOURCES  CampaignState.allocations  — allocate() / _allocate_quiet()
#   COMPUTE    CampaignState.compute_held — install_software() / buy_supply()
#
# allocate() is the RESOURCE ledger. Nothing that holds compute goes through
# it. A brief once listed it under compute; this probe prints both key sets
# side by side so that cannot happen quietly again.
#
# A REAL SEED, NOT A GUESS AT ONE. The CampaignManager's values are read out
# of Env/world.tscn as packed data (a scene value beats a script default, and
# starting_resources/starting_compute/starting_stock are all set there), put
# on a DETACHED campaign.gd instance that is never added to the tree — so its
# _ready never runs, it never opens the player's most recent profile, and it
# has no save path. Then the real _seed_new_campaign() and _adopt_state() run
# on it, which is the same sequence reset_campaign() and new_profile() use.
#
# Everything after the boot section mutates SCRATCH copies of that state, to
# make every key format appear once and to measure two things the code does
# that nothing else reports:
#
#   SITE COMPUTE   site_compute() is derived from held ground and has no
#                  caller. This takes a site and reads compute_free() either
#                  side of it.
#   THE REWIND     what a failed run undoes. It snapshots, adopts a mark,
#                  restores, and reads both ledgers back. Until 2026-10-26 it
#                  was measuring restore_from() dropping line_marks and
#                  line_modules, so a dead run kept the mark it had bought —
#                  now the lines rewind with everything else (Backlog SV1) and
#                  the rows below should agree with the snapshot.
#
# Writes nothing. Never the player's save: the state has save_path "" and the
# manager has autosave off before anything runs.
# ─────────────────────────────────────────────

const WORLD := "res://Env/world.tscn"
const _Pricing := preload("res://Campaign/pricing.gd")
const _SoftwareTree := preload("res://Campaign/software_tree.gd")
const _CampaignScript := preload("res://Campaign/campaign.gd")

var _catalogue: ItemCatalogue
var _locations: Resource


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var props := _campaign_props()
	if props.is_empty():
		push_warning("probe_economy_facts: no CampaignManager node in %s, so there is no seed to read." % WORLD)
		quit(1)
		return
	_catalogue = props.get("catalogue")
	_locations = props.get("locations")
	if _catalogue == null or _locations == null:
		push_warning("probe_economy_facts: CampaignManager has no catalogue (%s) or no locations (%s); nothing can be priced." % [_catalogue, _locations])
		quit(1)
		return

	var cm := _detached_manager(props)
	_report_seed(props, cm.state)
	_report_site_compute(cm.state)
	_report_keys(cm.state)
	_report_rewind(cm.state)
	_report_items()
	_report_frames()
	_report_locations()
	_report_missions(props.get("missions", []))
	_report_loss(cm.state)
	cm.free()
	print("")
	print("probe_economy_facts: done")
	quit(0)


# ── The seed ─────────────────────────────────────────────────────────────────

func _campaign_props() -> Dictionary:
	var out := {}
	var defaults: Node = _CampaignScript.new()
	for p in defaults.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out[String(p["name"])] = defaults.get(p["name"])
	defaults.free()
	var st: SceneState = (load(WORLD) as PackedScene).get_state()
	for i in st.get_node_count():
		if st.get_node_name(i) != "CampaignManager":
			continue
		for j in st.get_node_property_count(i):
			out[String(st.get_node_property_name(i, j))] = st.get_node_property_value(i, j)
		return out
	return {}


## A CampaignManager with world.tscn's values on it, seeded and adopted the
## way a new campaign is, and never in the tree.
func _detached_manager(props: Dictionary) -> Node:
	var cm: Node = _CampaignScript.new()
	for k in props:
		if k == "script" or not (k in cm):
			continue
		cm.set(k, props[k])
	cm.autosave = false
	cm.state = _fresh_state()
	cm._seed_new_campaign()
	cm._adopt_state("")
	return cm


func _fresh_state() -> CampaignState:
	var s := CampaignState.new()
	s.catalogue = _catalogue
	s.locations = _locations
	s.save_path = ""   # nowhere to write: save_to_disk refuses
	return s


## A scratch copy of `s`, put through the one path that reads a save.
##
## DEEP, and that is not fussiness. to_dict() hands out `allocations` itself,
## not a copy, so a restore_from(to_dict()) copy SHARES the resource ledger
## with the state it came from and every purchase on it lands on both. The
## first cut of this probe did exactly that and measured its own leak.
## The seven fields this used to put back by hand — line_marks, line_modules,
## turn, sites and three more — are carried by restore_from itself as of
## 2026-10-26, so copying them here would only be copying them twice. Backlog
## SV1.
func _copy(s: CampaignState) -> CampaignState:
	var c := _fresh_state()
	c.restore_from(s.to_dict().duplicate(true))
	return c


func _report_seed(props: Dictionary, s: CampaignState) -> void:
	print("")
	print("══ THE SEED — a new campaign, off Env/world.tscn ══════════════════")
	print("world.tscn  starting_resources %d   starting_compute %d   starting_squad_size %d" % [
		int(props.get("starting_resources", 0)), int(props.get("starting_compute", 0)),
		int(props.get("starting_squad_size", 0))])
	print("world.tscn  starting_stock %s" % str(props.get("starting_stock", [])))
	print("after boot  turn %d   earned %d   available() %d   compute_earned %d   compute_free() %d" % [
		s.turn, s.earned, s.available(), s.compute_earned, s.compute_free()])
	print("after boot  supply_cap %d   supply_used %d   roster %d   BASE_SEATS %d" % [
		s.supply_cap, s.supply_used(), s.roster.size(), CampaignState.BASE_SEATS])
	print("after boot  income_per_turn() %d   site_compute() %d   held_sites %s" % [
		s.income_per_turn(), s.site_compute(), str(s.held_sites())])
	print("")
	print("RESOURCE LEDGER (allocations) after boot — %d keys:" % s.allocations.size())
	for k in s.allocations:
		print("   %-28s %d" % [k, int(s.allocations[k])])
	print("COMPUTE LEDGER (compute_held) after boot — %d keys:" % s.compute_held.size())
	for k in s.compute_held:
		print("   %-28s %d" % [k, int(s.compute_held[k])])
	print("COMPUTE CLAIMS (compute_claimed) after boot — %d: %s" % [s.compute_claimed.size(), str(s.compute_claimed)])
	print("ARMOURY after boot: %s" % str(s.armoury.to_dict()))
	var loaded := []
	for e in _SoftwareTree.CARRY:
		if _SoftwareTree.is_loaded(s, e["item"]):
			loaded.append("%s(is_installed %s)" % [e["item"], s.is_installed(e["item"])])
	print("MEMORY loaded after boot: %s" % ", ".join(PackedStringArray(loaded)))
	print("player carries  weapons %s  equipment %s" % [str(s.player_record.weapon_ids), str(s.player_record.equipment_ids)])


# ── Does held ground pay compute? ────────────────────────────────────────────

func _report_site_compute(base: CampaignState) -> void:
	print("")
	print("══ SITE COMPUTE — does holding a Location raise compute_free()? ════")
	var s := _copy(base)
	var l = _locations.all()[0] if not _locations.all().is_empty() else null
	if l == null:
		push_warning("probe_economy_facts: the location catalogue is empty; nothing to take.")
		return
	var free_before := s.compute_free()
	var income_before := s.income_per_turn()
	s.set_site_owner(l.id, Enums.Factions.PLAYER)
	print("take %-14s (compute %d, %d/turn)" % [l.id, int(l.compute), int(l.resources_per_turn)])
	print("   compute_free()     %d -> %d" % [free_before, s.compute_free()])
	print("   site_compute()     %d" % s.site_compute())
	print("   income_per_turn()  %d -> %d" % [income_before, s.income_per_turn()])
	var earned_before := s.earned
	s.advance_turn()
	print("   advance_turn()     earned %d -> %d, turn %d" % [earned_before, s.earned, s.turn])


# ── Every key format, made to appear ─────────────────────────────────────────

func _report_keys(base: CampaignState) -> void:
	print("")
	print("══ EVERY KEY FORMAT — each mutation run once on a scratch copy ══════")
	var s := _copy(base)
	s.award(100000)
	var before := s.allocations.keys()
	var held_before := s.compute_held.keys()
	var did := []

	var soldier := _catalogue.chassis_def(&"soldier")
	var r1 := s.recruit(soldier)
	did.append(["recruit(soldier)", r1 != null])
	var bolt := _catalogue.item(&"bolt")
	did.append(["unlock_item(bolt)", s.unlock_item(bolt)])
	var rover := _catalogue.chassis_def(&"rover")
	did.append(["unlock_chassis(rover)", s.unlock_chassis(rover)])
	var marked := _first_markable(s)
	if marked != null:
		did.append(["adopt_mark(%s)" % marked.id, s.adopt_mark(marked)])
		# A REPLACEMENT IS BUILT TO WHAT THE LINE BUILDS NOW. Losing a robot and
		# building another must not hand you the old mark back.
		var spec = marked.mark_spec(s.mark_of(marked.id))
		var fresh := s.recruit(marked)
		if fresh != null and spec != null:
			print("   a %s built on a Mk %d line: mark_level %d, weapons %s, equipment %s  (the Mk %d spec: %s, %s)" % [
				marked.id, s.mark_of(marked.id), fresh.mark_level, str(fresh.weapon_ids), str(fresh.equipment_ids),
				s.mark_of(marked.id), str(spec.weapon_ids), str(spec.equipment_ids)])
		var mod := _first_module(s, marked)
		if mod != null:
			did.append(["unlock_item(%s)" % mod.id, s.unlock_item(mod)])
			did.append(["adopt_module(%s, %s)" % [marked.id, mod.id], s.adopt_module(marked, mod)])
	if r1 != null:
		r1.damage = 10
		did.append(["repair_soldier(%s)" % r1.id, s.repair_soldier(r1)])
		r1.damage = 10
		r1.status = SoldierRecord.Status.DESTROYED
		did.append(["scrap_soldier(%s) -> %d" % [r1.id, s.scrap_soldier(r1)], true])
	# THE DEAD SHOP. No production caller; run here only so its keys are on
	# the list a reader might find in an old ledger.
	var frag := _catalogue.item(&"frag")
	did.append(["buy_item(frag)  [no production caller]", s.buy_item(frag)])
	did.append(["sell_item(frag) [no production caller]", s.sell_item(frag)])
	did.append(["buy_chassis(soldier) [no production caller]", s.buy_chassis(soldier)])
	# COMPUTE. compute_held, never allocations.
	s.award_compute(10)
	did.append(["buy_supply()", s.buy_supply()])
	did.append(["SoftwareTree.install(command_1a)", _SoftwareTree.install(s, &"command_1a")])
	did.append(["SoftwareTree.load_item(bolt)", _SoftwareTree.load_item(s, &"bolt")])
	did.append(["claim_compute(clear:<op>)", s.claim_compute(CampaignState.clear_compute_key(&"some_op"), 1) == 1])

	for e in did:
		print("   %-48s %s" % [e[0], "ok" if e[1] else "REFUSED"])
	print("new RESOURCE keys:")
	for k in s.allocations:
		if not before.has(k):
			print("   %-28s %d" % [k, int(s.allocations[k])])
	print("new COMPUTE keys:")
	for k in s.compute_held:
		if not held_before.has(k):
			print("   %-28s %d" % [k, int(s.compute_held[k])])
	print("compute_claimed: %s" % str(s.compute_claimed))
	print("is_installed(&\"bolt\") %s   is_installed(&\"carry_bolt\") %s   SoftwareTree.is_loaded(bolt) %s" % [
		s.is_installed(&"bolt"), s.is_installed(&"carry_bolt"), _SoftwareTree.is_loaded(s, &"bolt")])


func _first_markable(s: CampaignState) -> ChassisDefinition:
	for f in _catalogue.chassis:
		if f != null and f.purchasable and f.top_mark() >= 1 and s.is_unlocked(f.id) and s.mark_of(f.id) < f.top_mark():
			return f
	return null


func _first_module(s: CampaignState, frame: ChassisDefinition) -> ItemDefinition:
	for m in s.modules_for(frame):
		return m
	return null


# ── The rewind ───────────────────────────────────────────────────────────────

## WHAT A FAILED RUN ACTUALLY PUTS BACK, for things bought while in the field.
## The squad manager opens on TAB mid-mission and nothing on the Factory or
## the squad page asks in_field(), so all three of these are reachable there.
##
## Run twice: once with the snapshot exactly as Campaign.begin_deploy takes it
## (`_pre_run = state.to_dict()`), once with a deep copy of it. The difference
## between the two rows is the whole finding.
func _report_rewind(base: CampaignState) -> void:
	print("")
	print("══ THE REWIND — a failed run restore_from()s the deploy snapshot ════")
	print("in the field: recruit a soldier, repair a robot, adopt a mark — then die")
	print("%-34s %9s %9s %7s %8s %7s %9s" % ["snapshot", "avail snp", "avail now", "roster", "unit key", "repair", "line mk"])
	for deep in [false, true]:
		var s := _copy(base)
		var frame := _first_markable(s)
		if frame == null or s.roster.is_empty():
			push_warning("probe_economy_facts: no open frame with a mark, or no roster, so the rewind cannot be measured.")
			return
		var snap: Dictionary = s.to_dict().duplicate(true) if deep else s.to_dict()
		var avail_snap := s.available()
		var roster_snap := s.roster.size()
		var bought := s.recruit(frame)
		var hurt: SoldierRecord = s.roster[0]
		hurt.damage = 10
		s.repair_soldier(hurt)
		s.adopt_mark(frame)
		s.restore_from(snap)
		var repaired := false
		for k in s.allocations:
			if String(k).begins_with("repair:"):
				repaired = true
		print("%-34s %9d %9d %3d->%-3d %8s %7s %9d" % [
			"to_dict().duplicate(true)" if deep else "to_dict()  <- what begin_deploy keeps",
			avail_snap, s.available(), roster_snap, s.roster.size(),
			"kept" if bought != null and s.allocations.has("unit:%s" % bought.id) else "gone",
			"kept" if repaired else "gone", s.mark_of(frame.id)])
		# _next_id rewinds with the roster, so the next robot is minted under
		# the id the vanished one had — and its unit: key may already exist.
		var avail_before := s.available()
		var again := s.recruit(frame)
		print("   then recruit again: id %s   charged %d   (chassis_buy %d)" % [
			again.id if again != null else "-", avail_before - s.available(), _Pricing.chassis_buy(frame)])
	# READ OUT OF to_dict(), not a list typed in here. The line it replaces was
	# a hardcoded array of the seven fields presented as "by reading it", which
	# would have gone on printing them after they were fixed.
	var carried := CampaignState.new().to_dict().size() - 1
	print("restore_from() now carries all %d of to_dict()'s fields — tools/test_restore_from.gd asserts it" % carried)


# ── The price table ──────────────────────────────────────────────────────────

func _report_items() -> void:
	print("")
	print("══ ITEMS — every one in the live catalogue, priced by pricing.gd ═══")
	print("%-20s %-9s %-9s %4s %6s %5s %4s %5s %6s %s" % ["id", "kind", "band", "sale", "unlock", "buy", "shop", "cost", "memory", "notes"])
	var kinds := ItemDefinition.Kind.keys()
	for it in _catalogue.items:
		if it == null:
			continue
		var notes := []
		if not _Pricing.ITEM_BAND.has(it.id):
			notes.append("NOT IN ITEM_BAND (defaults to standard)")
		var carry := _SoftwareTree.carry_entry(it.id)
		print("%-20s %-9s %-9s %4s %6d %5d %4s %5d %6s %s" % [
			it.id, String(kinds[int(it.kind)]).to_lower(), _Pricing.band_of(it),
			"yes" if _Pricing.for_sale(it) else "no",
			_Pricing.item_unlock(it), _Pricing.item_buy(it),
			"yes" if it.in_shop else "no", int(it.cost),
			str(int(carry["cost"])) if not carry.is_empty() else "-",
			"; ".join(PackedStringArray(notes))])
	var stale := []
	for id in _Pricing.ITEM_BAND:
		if _catalogue.item(id) == null:
			stale.append(String(id))
	print("ITEM_BAND ids with no item in the live catalogue: %s" % (", ".join(PackedStringArray(stale)) if not stale.is_empty() else "none"))


func _report_frames() -> void:
	print("")
	print("══ FRAMES — every chassis, with its line prices ═══════════════════")
	print("%-20s %6s %4s %4s %5s %6s %4s %5s %5s %6s %5s" % ["id", "supply", "buy?", "sale", "buy", "unlock", "mks", "mk1", "mk2", "module", "cost"])
	for f in _catalogue.chassis:
		if f == null:
			continue
		print("%-20s %6d %4s %4s %5d %6d %4d %5d %5d %6d %5d" % [
			f.id, int(f.supply), "yes" if f.purchasable else "no",
			"yes" if _Pricing.chassis_for_sale(f) else "no",
			_Pricing.chassis_buy(f), _Pricing.chassis_unlock(f), f.top_mark(),
			_Pricing.mark_buy(f, 1), _Pricing.mark_buy(f, 2), _Pricing.module_buy(f), int(f.cost)])


# ── Where the other numbers live ─────────────────────────────────────────────

func _report_locations() -> void:
	print("")
	print("══ LOCATIONS — location_catalogue.tres, in catalogue order ═════════")
	print("%-14s %-22s %7s %7s %-6s %s" % ["id", "mission", "res/trn", "compute", "owner", "defence"])
	var res := 0
	var cpu := 0
	var factions := Enums.Factions.keys()
	for l in _locations.all():
		res += int(l.resources_per_turn)
		cpu += int(l.compute)
		print("%-14s %-22s %7d %7d %-6s %s" % [l.id, l.mission_id, int(l.resources_per_turn), int(l.compute),
			String(factions[int(l.start_owner)]), l.defend_mission_id])
	print("TOTAL %d locations: %d resources/turn and %d compute if every one is held" % [_locations.all().size(), res, cpu])


func _report_missions(missions: Array) -> void:
	print("")
	print("══ MISSIONS — world.tscn's list, what clearing each pays once ═══════")
	print("%-24s %4s %4s %6s %6s %8s %8s" % ["id", "sim", "def", "res", "cpu", "obj res", "obj cpu"])
	for m in missions:
		if m == null:
			continue
		var pay := _objective_pay(m)
		print("%-24s %4s %4s %6d %6d %8d %8d" % [m.id, "yes" if m.sim else "", "yes" if m.defence else "",
			int(m.reward_resources), int(m.compute_reward), int(pay["resources"]), int(pay["compute"])])
	print("obj = authored on objectives the mission KEEPS (active_objectives), top level and one map deep.")


## What the mission's KEPT objectives pay, read as packed data. Anything not in
## active_objectives is freed at load and pays nothing.
func _objective_pay(m: MissionDefinition) -> Dictionary:
	var out := {"resources": 0, "compute": 0}
	if m.level_scene == null:
		return out
	_pay_from(m, m.level_scene, 0, out)
	return out


func _pay_from(m: MissionDefinition, packed: PackedScene, depth: int, out: Dictionary) -> void:
	var st: SceneState = packed.get_state()
	for i in st.get_node_count():
		var sub := st.get_node_instance(i)
		if sub != null and depth < 1:
			var p := str(sub.resource_path)
			if p.begins_with("res://maps/") and not p.get_basename().ends_with("_art"):
				_pay_from(m, sub, depth + 1, out)
		var id := ""
		var res := 0
		var cpu := 0
		for j in st.get_node_property_count(i):
			match String(st.get_node_property_name(i, j)):
				"id": id = str(st.get_node_property_value(i, j))
				"reward_resources": res = int(st.get_node_property_value(i, j))
				"compute_reward": cpu = int(st.get_node_property_value(i, j))
		if id != "" and m.active_objectives.has(StringName(id)):
			out["resources"] += res
			out["compute"] += cpu


func _report_loss(s: CampaignState) -> void:
	print("")
	print("══ REPAIR AND SCRAP — the constants, off a fresh CampaignState ═════")
	print("repair_cost_per_hp %d   rebuild_cost_multiplier %.1f   allow_rebuild %s   scrap_divisor %d   sale_value = paid / 2" % [
		s.repair_cost_per_hp, s.rebuild_cost_multiplier, s.allow_rebuild, s.scrap_divisor])
	if s.roster.is_empty():
		return
	var c := _copy(s)
	var r: SoldierRecord = c.roster[0]
	r.status = SoldierRecord.Status.DESTROYED
	r.damage = 10
	print("a STARTING %s, destroyed: scrap_value %d (no unit: allocation, so priced at today's chassis_buy %d / %d, credited to earned)" % [
		r.chassis_id, c.scrap_value(r), _Pricing.chassis_buy(_catalogue.chassis_def(r.chassis_id)), c.scrap_divisor])
	print("   kit it carries %s — _kit_payout rows %d (only item:<id>:<n> allocations pay)" % [str(r.all_fitted_ids()), c._kit_payout(r).size()])
