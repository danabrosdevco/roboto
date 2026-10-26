extends SceneTree
# REPORTS: prints the table Reference/Your squad.md asserts, and asserts nothing

# ─────────────────────────────────────────────
# WHAT A CAMPAIGN-LAYER ROBOT IS, MEASURED OFF THE REAL SEED.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/probe_squad_facts.gd -- --no-save
#
# The vault note `Reference/Your squad.md` is written from this and names it in
# its `verified-by`. Re-run it before trusting the note.
#
# A SoldierRecord IS NOT A Soldier. The record is the campaign-layer Resource
# that outlives every level; `Soldier` (Character/characters/ai/soldier.gd,
# extends Enemy) is the BODY built from one at deploy. Two layers, one word —
# everything printed here is the RECORD.
#
# WHAT THIS EXISTS TO MEASURE, because none of it is visible in the data:
#
#   §1  THE DERIVED FAMILY. Eleven cached fields — max_health plus ten
#       effective_*. Nothing computes them on read; recompute_stats() writes
#       them and 18 game-code call sites invoke it. Printed per record.
#   §2  IS THE CACHE IDEMPOTENT? A booted campaign has already been through
#       recompute_roster(). Recomputing again must move nothing. If it does,
#       some caller is writing a derived field by hand.
#   §3  TYPED @export ARRAYS. Backlog K1's class of bug: a typed export
#       assigned a plain Array is dropped SILENTLY. Four of them are on this
#       record. This assigns a plain Array to each and reports what survived.
#   §4  WHAT THE SAVE CARRIES. to_dict()'s keys against the record's own
#       export list, derived rather than typed, so the note cannot drift. A
#       derived field IN the save is a field that can load stale.
#   §5  THE MARK AND THE LINE, AND WHETHER THEY AGREE. mark_level lives on the
#       record; the line lives in CampaignState.line_marks. apply_line_spec
#       keeps them in step. Until 2026-10-26 restore_from() did not carry
#       line_marks, so a LOAD left the two disagreeing — the records remembered
#       Mk 2 kit, the line read Mk 0, and the next apply_line_spec revised the
#       whole line DOWN to match the line. Backlog SV1 fixed it; this section
#       is now the measurement that they come back in step.
#   §6  THE ORDER OF PRECEDENCE, as arithmetic. chassis base → mark → module,
#       with the module's health_multiplier landing on the mark's bonus too.
#   §7  can_fit() STILL ANSWERS YES. campaign_state.gd carries an orphaned
#       over-indented `return false` left behind by the Phase 3.7 rank-gate
#       removal. GDScript 4.3 parses it; this proves it is unreachable, so the
#       one live caller (_seed_new_campaign's starting rifle) still works.
#
# A REAL SEED, NOT A GUESS AT ONE. The CampaignManager's values are read out of
# Env/world.tscn as packed data (a scene value beats a script default) and put
# on a DETACHED campaign.gd instance that is never added to the tree — so its
# _ready never runs, it never opens the player's most recent profile, and it
# has no save path. Then the real _seed_new_campaign() and _adopt_state() run,
# which is the sequence new_profile() uses. Borrowed wholesale from
# tools/probe_economy_facts.gd; keep the two in step.
#
# Writes nothing. Never the player's save: every state here has save_path "" and
# the manager has autosave off before anything runs.
# ─────────────────────────────────────────────

const WORLD := "res://Env/world.tscn"
const _CampaignScript := preload("res://Campaign/campaign.gd")

var _catalogue: ItemCatalogue
var _locations: Resource

## The eleven cached fields. max_health first because it is the only one the
## save carries — see §4.
const DERIVED := [
	"max_health", "effective_accuracy", "effective_speed",
	"effective_signal_bonus", "effective_sensor_range",
	"effective_signal_resistance_bonus", "effective_self_revive",
	"effective_equipment_multiplier", "effective_tuning",
	"effective_suppressive",
]


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var props := _campaign_props()
	if props.is_empty():
		push_warning("probe_squad_facts: no CampaignManager node in %s, so there is no seed to read." % WORLD)
		quit(1)
		return
	_catalogue = props.get("catalogue")
	_locations = props.get("locations")
	if _catalogue == null:
		push_warning("probe_squad_facts: the CampaignManager has no catalogue, so no record can be derived.")
		quit(1)
		return

	var cm := _detached_manager(props)
	_report_roster(cm.state)
	_report_idempotent(cm.state)
	_report_typed_arrays()
	_report_save_shape(cm.state)
	_report_mark_vs_line(cm.state)
	_report_precedence()
	_report_can_fit(cm.state)
	_report_mark_vs_takes(cm)
	cm.free()
	print("")
	print("probe_squad_facts: done")
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


## A scratch copy of `s` through the one path that reads a save. The two lines
## that put line_marks and line_modules back by hand are gone: restore_from
## carries them as of 2026-10-26 (Backlog SV1). The deep duplicate stays, and
## for the reason probe_economy_facts.gd gives — to_dict() hands out
## `allocations` itself rather than a copy, so a shallow copy shares the ledger.
func _copy(s: CampaignState) -> CampaignState:
	var c := _fresh_state()
	c.restore_from(s.to_dict().duplicate(true))
	return c


# ── §1 the roster, as the campaign layer holds it ────────────────────────────

func _derived_of(r: SoldierRecord) -> Dictionary:
	var out := {}
	for f in DERIVED:
		var v = r.get(f)
		out[f] = v.duplicate() if v is Dictionary else v
	return out


func _one_line(r: SoldierRecord, label: String, state: CampaignState) -> void:
	var frame := _catalogue.chassis_def(r.chassis_id)
	print("")
	print("%s  %s '%s'  frame %s" % [label, r.id if r.id != &"" else &"(no id)",
		r.display_name, r.chassis_id if r.chassis_id != &"" else &"(none)"])
	print("    line           mark_of(%s) %d   record.mark_level %d%s" % [
		r.chassis_id, state.mark_of(r.chassis_id), r.mark_level,
		"   DISAGREE" if state.mark_of(r.chassis_id) != r.mark_level else ""])
	print("    line module    %s   record.module_ids %s" % [
		state.module_of(r.chassis_id) if state.module_of(r.chassis_id) != &"" else &"(none)",
		str(r.module_ids)])
	print("    fitted         weapons %s  equipment %s" % [str(r.weapon_ids), str(r.equipment_ids)])
	print("    state          %s  benched %s  team '%s'  damage %d/%d  signal %.2f" % [
		SoldierRecord.Status.keys()[int(r.status)], r.benched, r.team_id,
		r.damage, r.max_health, r.signal_integrity])
	print("    career         rank %d (%s)  xp %d/%d  max_rank %d  kills %d  revives %d  missions %d" % [
		r.rank, r.rank_title(), r.xp, r.xp_per_rank, r.max_rank,
		r.confirmed_kills, r.revives, r.missions_survived])
	print("    cosmetic       '%s'  pauldrons %s" % [r.cosmetic_id, r.pauldrons])
	if frame != null:
		print("    frame base     health %d  accuracy %.2f  speed %.2f  sensor %.0fm  slots w%d/e%d/m%d" % [
			frame.base_health, frame.base_accuracy, frame.base_speed,
			frame.base_sensor_range, frame.weapon_slots, frame.equipment_slots,
			frame.module_slots])
	var bits: Array = []
	for f in DERIVED:
		bits.append("%s %s" % [f.trim_prefix("effective_"), str(r.get(f))])
	print("    derived        %s" % "  ".join(PackedStringArray(bits)))


func _report_roster(s: CampaignState) -> void:
	print("")
	print("══ §1 THE ROSTER — a new campaign, off Env/world.tscn ══════════════")
	print("roster %d record(s) + 1 player_record   teams %d (MAX_TEAMS %d)" % [
		s.roster.size(), s.teams.size(), CampaignState.MAX_TEAMS])
	print("supply_cap %d   supply_used() %d   supply_free() %d   deployable() %d" % [
		s.supply_cap, s.supply_used(), s.supply_free(), s.deployable().size()])
	print("teams: %s" % str(s.teams))
	print("line_marks %s   line_modules %s" % [str(s.line_marks), str(s.line_modules)])
	# The player is NOT in `roster`, which is why apply_line_spec never reaches
	# them and their mark_level is 0 for the whole campaign.
	print("player_record in roster: %s" % s.roster.has(s.player_record))
	if s.player_record != null:
		_one_line(s.player_record, "PLAYER ", s)
	for r in s.roster:
		_one_line(r, "RECORD ", s)


# ── §2 is the cache idempotent? ──────────────────────────────────────────────

func _report_idempotent(s: CampaignState) -> void:
	print("")
	print("══ §2 RECOMPUTING AGAIN — does any derived field move? ═════════════")
	print("A booted campaign has been through CampaignState.recompute_roster().")
	print("Calling recompute_stats() a second time must change nothing: every")
	print("derived field has exactly one derivation and no caller may hand-set one.")
	var everyone: Array = s.roster.duplicate()
	everyone.append(s.player_record)
	var moved := 0
	for r in everyone:
		if r == null:
			continue
		var before := _derived_of(r)
		r.recompute_stats(s.catalogue)
		var after := _derived_of(r)
		var diffs: Array = []
		for f in DERIVED:
			if str(before[f]) != str(after[f]):
				diffs.append("%s %s -> %s" % [f, str(before[f]), str(after[f])])
		if diffs.is_empty():
			print("   steady   %-12s %s" % [r.display_name, r.chassis_id])
		else:
			moved += 1
			print("   MOVED    %-12s %s" % [r.display_name, r.chassis_id])
			for d in diffs:
				print("              %s" % d)
	print("")
	print("%d record(s) moved on a second recompute." % moved)


# ── §3 typed @export arrays, the K1 class of bug ─────────────────────────────

func _report_typed_arrays() -> void:
	print("")
	print("══ §3 TYPED @export ARRAYS — does a plain Array survive? ═══════════")
	print("Backlog K1: a typed @export assigned an UNtyped Array is dropped in")
	print("silence. Four typed arrays sit on this record. Assigning a plain")
	print("Array to each, from a script, and reading it back:")
	var r := SoldierRecord.new()
	var probes := {
		"weapon_ids": ["m4"],
		"equipment_ids": ["frag"],
		"module_ids": ["armor_plating"],
		"equipment": [null],
	}
	for field in probes:
		var plain: Array = probes[field]
		r.set(field, plain)
		var got = r.get(field)
		print("   %-14s assigned a plain Array of %d -> held %d  %s" % [
			field, plain.size(), (got as Array).size(),
			"KEPT" if (got as Array).size() == plain.size() else "DROPPED"])
	print("")
	print("Note: a DROPPED row is the K1 bug reachable from code. A KEPT row")
	print("means the engine converted it, and the trap is in .tscn/.tres")
	print("authoring instead — see Traps.")


# ── §4 what the save carries ─────────────────────────────────────────────────

func _report_save_shape(s: CampaignState) -> void:
	print("")
	print("══ §4 WHAT THE SAVE CARRIES — derived, not typed ═══════════════════")
	var r: SoldierRecord = s.roster[0] if not s.roster.is_empty() else s.player_record
	var keys: Array = r.to_dict().keys()
	print("SoldierRecord.to_dict(): %d keys" % keys.size())
	print("   %s" % ", ".join(PackedStringArray(keys)))
	print("")
	print("Every @export on the record, and whether to_dict() carries it:")
	# Key names are not always the field names ("chassis" for chassis_scene,
	# "team" for team_id), so the match is by name OR by a known alias.
	var alias := {
		"chassis_scene": "chassis", "weapon_scene": "weapon", "team_id": "team",
	}
	var carried: Array = []
	var dropped: Array = []
	for p in r.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n := String(p["name"])
		if n.begins_with("_") or n.ends_with("_this_mission"):
			continue
		var key: String = alias.get(n, n)
		if keys.has(key):
			carried.append(n)
		else:
			dropped.append(n)
	print("   CARRIED (%d): %s" % [carried.size(), ", ".join(PackedStringArray(carried))])
	print("   NOT SAVED (%d): %s" % [dropped.size(), ", ".join(PackedStringArray(dropped))])
	print("")
	print("Round-tripping a record through to_dict() -> from_dict(), with NO")
	print("recompute afterwards — this is the state a load hands the game before")
	print("Campaign._adopt_state() calls recompute_roster(). Built with a mark")
	print("and a module on it, or every field would be at its default and the")
	print("loss would be invisible:")
	var loud := _loud_record()
	if loud == null:
		push_warning("probe_squad_facts: could not build a record with non-default derived stats, so §4's round trip proves nothing.")
		return
	var back := SoldierRecord.from_dict(loud.to_dict())
	for f in DERIVED:
		var a = loud.get(f)
		var b = back.get(f)
		print("   %-36s %-14s -> %-14s %s" % [f, str(a), str(b),
			"same" if str(a) == str(b) else "LOST (class default)"])
	print("")
	print("   mark_level survives (%d -> %d), so recompute_roster() rebuilds the" % [
		loud.mark_level, back.mark_level])
	print("   nine lost fields correctly. max_health is the one derived field IN")
	print("   the save, so it is the one that can load stale — a frame retuned in")
	print("   a patch loads at the old number until something recomputes.")


## A record with every derived field off its default: a marked line, a health
## module, and the biggest pile of module bonuses the frame will take.
func _loud_record() -> SoldierRecord:
	var frame: ChassisDefinition = null
	for f in _catalogue.chassis:
		if f != null and f.top_mark() > 0 and f.module_slots > 0:
			frame = f
			break
	if frame == null:
		return null
	var r := SoldierRecord.new()
	r.set_chassis(frame, _catalogue)
	r.mark_level = frame.top_mark()
	var at := 0
	for item in _catalogue.items_of_kind(ItemDefinition.Kind.MODULE):
		if item == null or not frame.takes(item) or at >= r.module_ids.size():
			continue
		r.module_ids[at] = item.id
		at += 1
	r.recompute_stats(_catalogue)
	return r


# ── §5 the mark, the line, and how they come apart ───────────────────────────

func _report_mark_vs_line(base: CampaignState) -> void:
	print("")
	print("══ §5 THE MARK AND THE LINE ═══════════════════════════════════════")
	var s := _copy(base)
	var frame: ChassisDefinition = null
	for r in s.roster:
		var f := _catalogue.chassis_def(r.chassis_id)
		if f != null and f.top_mark() > 0 and f.purchasable:
			frame = f
			break
	if frame == null:
		push_warning("probe_squad_facts: no seeded record sits on a line with a mark above 0, so §5 cannot run.")
		return
	var on_line: Array[SoldierRecord] = []
	for r in s.roster:
		if r.chassis_id == frame.id:
			on_line.append(r)
	print("line %s — %d in service, top_mark %d" % [frame.id, on_line.size(), frame.top_mark()])
	var one: SoldierRecord = on_line[0]
	print("   before    mark_of %d  record.mark_level %d  weapons %s  equipment %s  hp %d" % [
		s.mark_of(frame.id), one.mark_level, str(one.weapon_ids),
		str(one.equipment_ids), one.max_health])

	# A BULK WRITE OVER EVERY RECORD ON THE LINE, bench and wrecks included.
	s.award(100000)   # scratch state: the rail is not what is being measured
	s.grant_unlock(frame.id)
	var ok := s.adopt_mark(frame)
	print("   adopt_mark(%s) -> %s" % [frame.id, ok])
	print("   after     mark_of %d  record.mark_level %d  weapons %s  equipment %s  hp %d" % [
		s.mark_of(frame.id), one.mark_level, str(one.weapon_ids),
		str(one.equipment_ids), one.max_health])
	print("   apply_line_spec(%s) rewrites %d record(s) when called again" % [
		frame.id, s.apply_line_spec(frame.id)])

	# THE LOAD, exactly as Campaign.load_profile() does it: restore_from into a
	# state that is not this one, then the recompute _adopt_state runs. Before
	# Backlog SV1 this was the measurement that it DROPPED line_marks — the line
	# came back at Mk 0 holding records that remembered Mk 2, and the next
	# apply_line_spec revised them down. The two should now agree.
	print("")
	print("Now the load. Campaign.load_profile() -> restore_from(), which carries")
	print("line_marks and line_modules since 2026-10-26 (Backlog SV1). Same save,")
	print("read into a fresh state, then Campaign._adopt_state()'s recompute_roster():")
	var loaded := _fresh_state()
	loaded.restore_from(s.to_dict().duplicate(true))
	loaded.recompute_roster()
	var same: SoldierRecord = null
	for r in loaded.roster:
		if r.id == one.id:
			same = r
			break
	if same == null:
		push_warning("probe_squad_facts: the loaded roster has no record with id '%s'." % one.id)
		return
	print("   loaded    mark_of %d  record.mark_level %d  weapons %s  equipment %s  hp %d" % [
		loaded.mark_of(frame.id), same.mark_level, str(same.weapon_ids),
		str(same.equipment_ids), same.max_health])
	print("   line_marks after the load: %s" % str(loaded.line_marks))
	if loaded.mark_of(frame.id) == same.mark_level:
		print("   -> the line and the record agree at Mk %d, which is the point of" % same.mark_level)
		print("      SV1. The Factory reads mark_of() and shows the same thing.")
	else:
		print("   -> THEY DISAGREE: the line reads Mk %d and the record Mk %d. That is" % [
			loaded.mark_of(frame.id), same.mark_level])
		print("      Backlog SV1 reopened — tools/test_restore_from.gd should be red too.")
	var rewritten := loaded.apply_line_spec(frame.id)
	print("   then one apply_line_spec(%s) — recruiting onto the line, or adopting" % frame.id)
	print("   a mark or module — rewrites %d record(s) to what mark_of() says:" % rewritten)
	print("   revised   mark_of %d  record.mark_level %d  weapons %s  equipment %s  hp %d" % [
		loaded.mark_of(frame.id), same.mark_level, str(same.weapon_ids),
		str(same.equipment_ids), same.max_health])


# ── §6 the order of precedence, as arithmetic ────────────────────────────────

func _report_precedence() -> void:
	print("")
	print("══ §6 PRECEDENCE — chassis base, then mark, then modules ═══════════")
	print("recompute_stats() in four steps, with the module's health_multiplier")
	print("landing on the MARK's bonus as well as the frame's base:")
	var frame: ChassisDefinition = null
	for f in _catalogue.chassis:
		if f != null and f.top_mark() > 0:
			frame = f
			break
	if frame == null:
		push_warning("probe_squad_facts: no frame in the catalogue authors a mark, so §6 cannot run.")
		return
	var module: ItemDefinition = null
	for item in _catalogue.items_of_kind(ItemDefinition.Kind.MODULE):
		if item != null and frame.takes(item) \
				and (item.health_bonus != 0 or not is_equal_approx(item.health_multiplier, 1.0)):
			module = item
			break

	var r := SoldierRecord.new()
	r.set_chassis(frame, _catalogue)
	print("   frame %s  base_health %d  base_accuracy %.2f  base_sensor %.0fm" % [
		frame.id, frame.base_health, frame.base_accuracy, frame.base_sensor_range])
	print("   1 base only          hp %d  acc %.2f  spd %.2f  sensor %.0f" % [
		r.max_health, r.effective_accuracy, r.effective_speed, r.effective_sensor_range])
	for n in range(1, frame.top_mark() + 1):
		r.mark_level = n
		r.recompute_stats(_catalogue)
		var spec = frame.mark_spec(n)
		print("   2 + Mk %d             hp %d  acc %.2f  spd %.2f  sensor %.0f   (mark: %s)" % [
			n, r.max_health, r.effective_accuracy, r.effective_speed,
			r.effective_sensor_range, spec.summary()])
	if module == null:
		print("   3 no health module fits %s, so the module step cannot be shown." % frame.id)
		return
	if r.module_ids.is_empty():
		print("   3 %s has no module slot, so the module step cannot be shown." % frame.id)
		return
	r.module_ids[0] = module.id
	r.recompute_stats(_catalogue)
	print("   3 + %-16s hp %d  acc %.2f  spd %.2f  sensor %.0f   (%+d hp, x%.2f hp)" % [
		module.id, r.max_health, r.effective_accuracy, r.effective_speed,
		r.effective_sensor_range, module.health_bonus, module.health_multiplier])
	print("   4 effective_tuning    %s   (this frame tunes nothing)" % str(r.effective_tuning))
	print("")
	print("Every line whose marks carry `tuning`, and what recompute_stats puts")
	print("on the record. ChassisMark.verify() checks the keys against")
	print("TUNING_KEYS %s — and NOTHING reads them:" % str(ChassisMark.TUNING_KEYS))
	print("a grep for repair_rate / salvage_rate / reload_rate outside")
	print("chassis_mark.gd finds no reader in Character/, Campaign/ or Managers/.")
	var tuned := 0
	for f in _catalogue.chassis:
		if f == null:
			continue
		for n in range(1, f.top_mark() + 1):
			var spec = f.mark_spec(n)
			if spec == null or spec.tuning.is_empty():
				continue
			var t := SoldierRecord.new()
			t.set_chassis(f, _catalogue)
			t.mark_level = n
			t.recompute_stats(_catalogue)
			print("   %-10s Mk %d  effective_tuning %s" % [f.id, n, str(t.effective_tuning)])
			tuned += 1
	print("   %d (frame, mark) pair(s) author tuning. Readers: 0." % tuned)


# ── §7 the orphaned return in can_fit() ──────────────────────────────────────

func _report_can_fit(base: CampaignState) -> void:
	print("")
	print("══ §7 can_fit() — is the orphaned `return false` reachable? ════════")
	print("campaign_state.gd's can_fit() carries an over-indented `return false`")
	print("left behind when the Phase 3.7 rank gate was deleted: the comment")
	print("went, the body did not. GDScript 4.3 parses it. If it ran at function")
	print("level, can_fit would always refuse and _seed_new_campaign could not")
	print("issue a single rifle.")
	var s := _copy(base)
	var r: SoldierRecord = s.roster[0] if not s.roster.is_empty() else null
	if r == null:
		push_warning("probe_squad_facts: the seeded roster is empty, so §7 cannot run.")
		return
	var frame := _catalogue.chassis_def(r.chassis_id)
	var pick: ItemDefinition = null
	for item in _catalogue.items_of_kind(ItemDefinition.Kind.WEAPON):
		if item != null and item.fits_ai() and frame != null and frame.takes(item):
			pick = item
			break
	if pick == null:
		push_warning("probe_squad_facts: nothing in the catalogue fits %s, so §7 cannot run." % r.chassis_id)
		return
	s.armoury.add(pick.id)
	print("   can_fit(%s, %s) -> %s   (expected true)" % [r.display_name, pick.id, s.can_fit(r, pick)])
	print("   the orphan is therefore DEAD CODE inside the slot-count branch")
	print("   above it, not a refusal. Tidy-up only — see Backlog.")


# ── §8 does a mark respect the frame's own gate? ─────────────────────────────

## WHAT A MARK NAMES vs WHAT THE FRAME WILL TAKE.
##
## Two gates, and only one of them is on the mark path. can_fit() asks
## ChassisDefinition.takes(), which refuses a turret anything outside its
## chassis_whitelist and refuses a frame that `drives` anything with
## fits_vehicles false. apply_line_spec() asks NEITHER: _sized() clamps the
## array to the mount count and writes the ids straight in.
##
## Nothing downstream re-checks it either. SquadSpawner._fit_loadout tests only
## item.fits_ai(), so the gun is mounted and the robot fights with it. The one
## thing that does check is Campaign._return_unfittable_squad_kit(), which runs
## ON LOAD and hands the item back to stores — leaving an empty mount that
## nothing refills until the line is applied again.
func _report_mark_vs_takes(cm: Node) -> void:
	print("")
	print("══ §8 A MARK vs THE FRAME'S OWN GATE (takes()) ════════════════════")
	print("apply_line_spec() writes a mark's ids without asking")
	print("ChassisDefinition.takes(), which is the gate can_fit() uses. Every")
	print("purchasable line, every authored mark, every id it names:")
	var bad := 0
	for frame in _catalogue.chassis:
		if frame == null or not frame.purchasable:
			continue
		for n in range(1, frame.top_mark() + 1):
			var spec = frame.mark_spec(n)
			if spec == null:
				continue
			for id in Array(spec.weapon_ids) + Array(spec.equipment_ids):
				if id == &"":
					continue
				var item := _catalogue.item(id)
				if item == null:
					print("   %-10s Mk %d  %-18s NO CATALOGUE ENTRY" % [frame.id, n, id])
					bad += 1
					continue
				if frame.takes(item):
					continue
				var why: Array = []
				if not item.fits_chassis(frame.id):
					why.append("whitelist/requires_chassis")
				if frame.drives and not item.fits_vehicles:
					why.append("fits_vehicles false on a frame that drives")
				if frame.turret and item.kind == ItemDefinition.Kind.WEAPON \
						and not item.chassis_whitelist.has(frame.id):
					why.append("turret, and '%s' is not in its chassis_whitelist %s"
						% [frame.id, str(item.chassis_whitelist)])
				print("   %-10s Mk %d  %-18s takes() REFUSES: %s" % [
					frame.id, n, id, "; ".join(PackedStringArray(why))])
				bad += 1
	print("")
	print("%d (line, mark, id) combination(s) the frame's own gate refuses and" % bad)
	print("the mark writes anyway. fits_ai() still passes, so the body is armed.")
	if bad == 0:
		return

	# AND HERE IS WHAT THE NEXT LOAD DOES TO IT. Run on a scratch state hung on
	# the detached manager, which has autosave off and nowhere to write.
	print("")
	print("What the next load does to one of them, run for real through")
	print("Campaign._return_unfittable_squad_kit():")
	var frame: ChassisDefinition = null
	for f in _catalogue.chassis:
		if f == null or not f.purchasable or f.top_mark() < 1:
			continue
		var spec = f.mark_spec(1)
		if spec == null or spec.weapon_ids.is_empty():
			continue
		var item := _catalogue.item(spec.weapon_ids[0])
		if item != null and not f.takes(item):
			frame = f
			break
	if frame == null:
		print("   every Mk 1 main gun passes takes(), so there is nothing to show.")
		return
	var was = cm.state
	var s := _fresh_state()
	cm.state = s
	var r := SoldierRecord.new()
	r.id = s.mint_id()
	r.display_name = "Scratch"
	r.set_chassis(frame, _catalogue)
	s.roster.append(r)
	s.line_marks[frame.id] = 1
	s.apply_line_spec(frame.id)
	print("   %-10s at Mk 1 after apply_line_spec:  weapons %s" % [frame.id, str(r.weapon_ids)])
	cm._return_unfittable_squad_kit()
	print("   %-10s after one load:                 weapons %s   stores %s" % [
		frame.id, str(r.weapon_ids), str(s.armoury.to_dict().get("stock", {}))])
	print("   nothing refills the mount: recompute_roster() derives stats, not kit.")
	cm.state = was
