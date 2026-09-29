extends SceneTree

# ─────────────────────────────────────────────
# ECONOMY AUDIT — what the campaign pays you against what it puts in front of
# you, mission by mission, in the order the terminal offers them.
#
# Everything is priced in BASELINES: one Soldier chassis plus one Ancient Rifle,
# the cheapest thing that can hold a position and the unit the player actually
# shops in. "This op pays 1.8 troopers" is legible in a way "240" is not.
#
# READS THE REAL DATA, nothing hardcoded. The mission order comes off
# world.tscn's CampaignManager, costs off the catalogue, enemy counts off each
# mission's own specs, and objective payouts out of each level scene. Change a
# number anywhere and re-run this; it cannot drift.
#
# SceneState, not instantiation: reading world.tscn and the level scenes as
# packed data means no level is ever loaded, nothing physics-simulated, and no
# campaign.json written. The whole audit runs in a couple of seconds.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/audit_economy.gd
# ─────────────────────────────────────────────

## Priced in these. Both read from the catalogue, never assumed.
const BASE_CHASSIS := &"soldier"
const BASE_WEAPON := &"m4"


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var world: PackedScene = load("res://Env/world.tscn")
	var cm := _campaign_props(world.get_state())
	if cm.is_empty():
		printerr("audit_economy: no CampaignManager in world.tscn")
		quit(1)
		return

	var catalogue: ItemCatalogue = cm.get("catalogue")
	var missions: Array = cm.get("missions", [])
	var purse: int = int(cm.get("starting_resources", 0))
	var stock: Array = cm.get("starting_stock", [])
	var squad_seats: int = int(cm.get("starting_squad_size", 0))

	var frame: ChassisDefinition = catalogue.chassis_def(BASE_CHASSIS)
	var gun: ItemDefinition = catalogue.item(BASE_WEAPON)
	var baseline: int = frame.cost + gun.cost

	print("")
	print("══ ECONOMY AUDIT ══════════════════════════════════════════════════")
	print("BASELINE = 1 %s (%d) + 1 %s (%d) = %d resources." % [
		frame.display_name, frame.cost, gun.display_name, gun.cost, baseline])
	print("You start with %d resources, %d squad seat(s), and these in stores:" % [
		purse, squad_seats])
	print("   %s" % _stock_line(catalogue, stock))
	print("")

	# ── What the shop charges ──
	print("── WHAT A FIGHTING BODY COSTS ─────────────────────────────────────")
	print("%-36s %6s %8s %5s  %s" % ["fielded unit", "cost", "baselines", "sply", "chassis + gun"])
	for pair in [[&"soldier", &"shotgun"], [&"soldier", &"m4"], [&"soldier", &"machine_gun"],
			[&"mechanic", &"m4"], [&"rover", &"machine_gun"], [&"rover", &"grenade_launcher"],
			[&"reclaimer", &"m4"], [&"spotter", &""], [&"walker", &"heavy_mg"],
			[&"walker", &"autocannon"]]:
		var c: ChassisDefinition = catalogue.chassis_def(pair[0])
		if c == null:
			print("%-36s   (not in the catalogue — cannot be bought)" % String(pair[0]))
			continue
		var w: ItemDefinition = null
		if pair[1] != &"":
			w = catalogue.item(pair[1])
			if w == null:
				print("%-36s   (%s is not in the catalogue)" % [c.display_name, String(pair[1])])
				continue
		var total: int = c.cost + (w.cost if w != null else 0)
		print("%-36s %6d %8.1f %5d  %s" % [
			"%s + %s" % [c.display_name, w.display_name if w != null else "(no gun)"],
			total, float(total) / float(baseline), c.supply,
			"%d + %d" % [c.cost, w.cost if w != null else 0]])
	print("")

	# ── The campaign, in order ──
	print("── THE CAMPAIGN IN ORDER ──────────────────────────────────────────")
	print("'purse' is everything earned BEFORE this op, spent on nothing.")
	print("%-26s %4s %5s %5s %6s %6s %7s %6s %6s" % [
		"operation", "seat", "onmap", "resv", "supply", "pays", "compute", "purse", "base"])
	var rows: Array = []
	for m in missions:
		if m == null:
			continue
		var force := _force(m)
		var obj := _objective_pay(m)
		var pays: int = int(m.reward_resources) + int(obj["resources"])
		var compute: int = int(m.compute_reward) + int(obj["compute"])
		rows.append({
			"m": m, "force": force, "obj": obj, "pays": pays, "compute": compute,
			"purse": purse,
		})
		print("%-26s %4s %5d %5d %6d %6d %7d %6d %6.1f" % [
			m.display_name.substr(0, 26),
			"all" if int(m.squad_size) < 0 else str(int(m.squad_size)),
			int(force["on_map"]), int(force["reserve"]), int(force["supply"]),
			pays, compute, purse, float(purse) / float(baseline)])
		purse += pays
	print("%-26s %4s %5s %5s %6s %6s %7s %6d %6.1f" % [
		"(after the last op)", "", "", "", "", "", "", purse, float(purse) / float(baseline)])
	print("")

	# ── The ratio that matters ──
	print("── YOU AGAINST THEM ───────────────────────────────────────────────")
	print("SEATS ARE THE REAL WALL, NOT MONEY. A seat is 1 supply and costs 1")
	print("compute; you start with %d and the whole campaign pays %d more, so the" % [
		squad_seats, _total_compute(rows)])
	print("ceiling is %d supply — %d troopers, or %d rovers, or %d walkers." % [
		squad_seats + _total_compute(rows), squad_seats + _total_compute(rows),
		(squad_seats + _total_compute(rows)) / 2, (squad_seats + _total_compute(rows)) / 3])
	print("'afford' is troopers the purse buys. 'seats' assumes every compute was")
	print("spent on supply the moment it was earned — the most squad possible.")
	print("%-26s %6s %5s %6s %6s %7s  %s" % [
		"operation", "afford", "seat", "fields", "onmap", "odds", "note"])
	# Compute is paid on FIRST CLEAR, so an op's compute buys a seat for the NEXT
	# one, never for itself.
	var seats := squad_seats
	for r in rows:
		var m = r["m"]
		var afford: int = int(floor(float(r["purse"]) / float(baseline)))
		var cap: int = seats if int(m.squad_size) < 0 else mini(seats, int(m.squad_size))
		var fields: int = mini(afford, cap)
		var on_map: int = int(r["force"]["on_map"])
		var total: int = on_map + int(r["force"]["reserve"])
		# +1 for the player, who is worth at least a body.
		var odds: float = float(total) / maxf(1.0, float(fields + 1))
		print("%-26s %6d %5d %6d %6d %6.1f:1  %s" % [
			m.display_name.substr(0, 26), afford, cap, fields, on_map, odds,
			_note(r, baseline)])
		seats += int(r["compute"])
	print("")
	print("── THE MONEY YOU CANNOT SPEND ─────────────────────────────────────")
	print("Purse against the most a full squad of baselines could ever cost.")
	print("%-26s %8s %9s %9s" % ["operation", "purse", "squad max", "idle"])
	seats = squad_seats
	for r in rows:
		var m = r["m"]
		var cap: int = seats if int(m.squad_size) < 0 else mini(seats, int(m.squad_size))
		var squad_max: int = cap * baseline
		print("%-26s %8d %9d %9d" % [
			m.display_name.substr(0, 26), int(r["purse"]), squad_max,
			maxi(0, int(r["purse"]) - squad_max)])
		seats += int(r["compute"])
	print("")
	print("── SUPPLY, SIDE BY SIDE ───────────────────────────────────────────")
	print("The enemy force priced at YOUR supply rates, against your own cap.")
	print("%-26s %8s %7s %8s" % ["operation", "theirs", "yours", "ratio"])
	seats = squad_seats
	for r in rows:
		var m = r["m"]
		var cap: int = seats if int(m.squad_size) < 0 else mini(seats, int(m.squad_size))
		print("%-26s %8d %7d %7.0f:1" % [
			m.display_name.substr(0, 26), int(r["force"]["supply"]), cap,
			float(r["force"]["supply"]) / maxf(1.0, float(cap))])
		seats += int(r["compute"])
	print("")

	# ── What the shop will even sell you ──
	print("── WHAT YOU CAN BUY GOING IN ──────────────────────────────────────")
	print("locked_by() gates only what some mission NAMES in its unlocks, so a")
	print("chassis no mission names is on sale from the first visit to base.")
	var gated := {}
	for m in missions:
		if m == null:
			continue
		for u in m.unlocks:
			if not gated.has(u):
				gated[u] = m.id
	var never: Array = []
	for c_def in catalogue.chassis:
		if c_def != null and not gated.has(c_def.id):
			never.append("%s (%d, %d supply)" % [
				c_def.display_name, c_def.cost, c_def.supply])
	print("NEVER GATED, buyable from the start: %s" % ", ".join(never))
	print("")
	print("%-26s %6s %5s  %s" % ["operation", "purse", "seat", "best body on sale, and what fills the rest"])
	var open := {}
	seats = squad_seats
	for r in rows:
		var m = r["m"]
		var cap: int = seats if int(m.squad_size) < 0 else mini(seats, int(m.squad_size))
		print("%-26s %6d %5d  %s" % [
			m.display_name.substr(0, 26), int(r["purse"]), cap,
			_best_force(catalogue, gated, open, int(r["purse"]), cap, baseline)])
		for u in m.unlocks:
			open[u] = true
		seats += int(r["compute"])
	print("")

	# ── Per-mission detail ──
	print("── WHERE EACH PAYOUT COMES FROM ───────────────────────────────────")
	for r in rows:
		var m = r["m"]
		print("%s  (%s)" % [m.display_name, m.id])
		print("    clear bonus      %d res, %d compute" % [int(m.reward_resources), int(m.compute_reward)])
		for row in r["obj"]["rows"]:
			print("    %-16s %d res, %d compute%s" % [
				str(row["id"]).substr(0, 16), int(row["res"]), int(row["compute"]),
				"   (optional)" if bool(row["optional"]) else ""])
		print("    opposition       %s" % _force_line(r["force"]))
		print("    squad            %s" % (
			"solo — no allies deploy" if int(m.squad_size) == 0
			else ("everyone active" if int(m.squad_size) < 0 else "at most %d" % int(m.squad_size))))
		print("    needs cleared    %s" % ("nothing — open from the start" if m.requires.is_empty() else str(m.requires)))
		print("    UNLOCKS          %s" % ("nothing" if m.unlocks.is_empty() else _unlock_line(catalogue, m.unlocks)))
		if bool(m.repeatable):
			print("    REPEATABLE       the clear bonus pays again every time; compute does not.")
	quit(0)


## Unlock ids as the player meets them — a name and a price, not a StringName,
## and flagged when an id matches nothing in the catalogue at all.
func _unlock_line(catalogue: ItemCatalogue, ids: Array) -> String:
	var parts: Array = []
	for id in ids:
		var c: ChassisDefinition = catalogue.chassis_def(id)
		if c != null:
			parts.append("%s [frame %d, %d supply]" % [c.display_name, c.cost, c.supply])
			continue
		var it: ItemDefinition = catalogue.item(id)
		if it != null:
			parts.append("%s [%d]" % [it.display_name, it.cost])
			continue
		parts.append("%s [NOT IN THE CATALOGUE]" % String(id))
	return ", ".join(parts)


## CampaignManager's settings as the game will see them: what world.tscn
## authors, over the script's own defaults.
##
## BOTH HALVES MATTER. SceneState hands back only the properties the scene
## actually overrides, so anything left at its default — starting_squad_size is
## the one that bites — comes back missing and reads as 0. That made every
## "fields" column zero and every odds figure nonsense on the first run.
func _campaign_props(st: SceneState) -> Dictionary:
	var out := {}
	var defaults: Node = load("res://Campaign/campaign.gd").new()
	for p in defaults.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out[String(p["name"])] = defaults.get(p["name"])
	defaults.free()
	for i in st.get_node_count():
		if st.get_node_name(i) != "CampaignManager":
			continue
		for j in st.get_node_property_count(i):
			out[String(st.get_node_property_name(i, j))] = st.get_node_property_value(i, j)
		return out
	return {}


## Bodies on the map at the first shot, bodies held in reserve, and what the
## whole force would cost the player at their own supply prices.
func _force(m: MissionDefinition) -> Dictionary:
	var on_map := 0
	var reserve := 0
	var supply := 0
	var kinds := {}
	for spec in m.enemy_force:
		if spec == null:
			continue
		var bodies: int = spec.body_count()
		if spec.posture == EnemySquadSpec.Posture.RESERVE:
			reserve += bodies
		else:
			on_map += bodies
		for c in spec.roster:
			if c != null:
				supply += c.supply
				kinds[c.display_name] = int(kinds.get(c.display_name, 0)) + 1
		# Count-form specs name no chassis, so they are bodies without a price.
		if spec.roster.is_empty() and bodies > 0:
			kinds["(unnamed x%d)" % bodies] = bodies
	return {"on_map": on_map, "reserve": reserve, "supply": supply, "kinds": kinds,
		"squads": m.enemy_force.size()}


## Every active objective's payout, read out of the level scene as packed data.
func _objective_pay(m: MissionDefinition) -> Dictionary:
	var out := {"resources": 0, "compute": 0, "rows": []}
	if m.level_scene == null:
		return out
	var st: SceneState = m.level_scene.get_state()
	for i in st.get_node_count():
		var id: StringName = &""
		var res := 0
		var compute := 0
		var optional := false
		var has_id := false
		for j in st.get_node_property_count(i):
			var name := String(st.get_node_property_name(i, j))
			var v: Variant = st.get_node_property_value(i, j)
			match name:
				"id":
					id = StringName(str(v))
					has_id = true
				"reward_resources": res = int(v)
				"compute_reward": compute = int(v)
				"optional": optional = bool(v)
		if not has_id or id == &"":
			continue
		# An empty active_objectives means the level's own set, all of it.
		if not m.active_objectives.is_empty() and not m.active_objectives.has(id):
			continue
		if res == 0 and compute == 0:
			continue
		out["resources"] = int(out["resources"]) + res
		out["compute"] = int(out["compute"]) + compute
		out["rows"].append({"id": id, "res": res, "compute": compute, "optional": optional})
	return out


func _force_line(force: Dictionary) -> String:
	var parts: Array = []
	var kinds: Dictionary = force["kinds"]
	for k in kinds:
		parts.append("%d %s" % [int(kinds[k]), k])
	return "%d squad(s), %d on the map, %d in reserve — %s" % [
		int(force["squads"]), int(force["on_map"]), int(force["reserve"]),
		", ".join(parts) if not parts.is_empty() else "no named chassis"]


func _stock_line(catalogue: ItemCatalogue, stock: Array) -> String:
	var counts := {}
	for id in stock:
		counts[id] = int(counts.get(id, 0)) + 1
	var parts: Array = []
	var worth := 0
	for id in counts:
		var item: ItemDefinition = catalogue.item(id)
		var name: String = item.display_name if item != null else String(id)
		worth += (item.cost if item != null else 0) * int(counts[id])
		parts.append("%dx %s" % [int(counts[id]), name])
	return "%s   (worth %d if you had to buy it)" % [", ".join(parts), worth]


## The heaviest single body on sale right now, then baseline troopers in the
## seats and money it leaves. Greedy on purpose: it answers "what is the most
## the shop lets me bring", which is the question the difficulty curve has to be
## read against.
func _best_force(catalogue: ItemCatalogue, gated: Dictionary, open: Dictionary,
		purse: int, seats: int, baseline: int) -> String:
	if seats <= 0:
		return "solo op — no allies deploy"
	var best: ChassisDefinition = null
	var best_gun: ItemDefinition = null
	var best_cost := 0
	for c in catalogue.chassis:
		if c == null or c.supply > seats:
			continue
		if gated.has(c.id) and not open.has(c.id):
			continue
		# Priced with the dearest gun it is allowed AND the player may buy, which
		# is the ceiling the difficulty has to be read against.
		var gun: ItemDefinition = null
		for it in catalogue.items:
			if it == null or it.kind != ItemDefinition.Kind.WEAPON or not it.in_shop:
				continue
			if gated.has(it.id) and not open.has(it.id):
				continue
			if not it.fits_chassis(c.id):
				continue
			# requires_chassis is satisfied by owning the frame it is fitted to.
			if not it.requires_chassis.is_empty() and not it.requires_chassis.has(c.id):
				continue
			if gun == null or it.cost > gun.cost:
				gun = it
		var cost: int = c.cost + (gun.cost if gun != null else 0)
		if cost > purse:
			continue
		if best == null or cost > best_cost:
			best = c
			best_gun = gun
			best_cost = cost
	if best == null:
		return "nothing affordable"
	var left_seats: int = seats - best.supply
	var left_purse: int = purse - best_cost
	var extra: int = mini(left_seats, int(floor(float(left_purse) / float(baseline))))
	return "%s + %s (%d, %d sply) + %d baseline%s = %d of %d" % [
		best.display_name, best_gun.display_name if best_gun != null else "no gun",
		best_cost, best.supply, extra, "" if extra == 1 else "s",
		best_cost + extra * baseline, purse]


## Every compute the campaign pays, first clears and objectives together.
func _total_compute(rows: Array) -> int:
	var n := 0
	for r in rows:
		n += int(r["compute"])
	return n


func _note(r: Dictionary, baseline: int) -> String:
	var force: Dictionary = r["force"]
	var total: int = int(force["on_map"]) + int(force["reserve"])
	# How much of the force this op's own payout would replace, if the player
	# spent every resource of it on baseline troopers. It is the cleanest read
	# on whether an op funds the next one.
	return "pays back %.1f troopers, %.0f%% of what it fielded" % [
		float(r["pays"]) / float(baseline),
		float(r["pays"]) / float(baseline) / maxf(1.0, float(total)) * 100.0]
