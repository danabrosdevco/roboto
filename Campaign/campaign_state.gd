extends Resource
class_name CampaignState

# ─────────────────────────────────────────────
# CAMPAIGN STATE — everything that survives a mission.
#
# THE LEDGER
# `earned` only ever goes up. Spending is NOT subtracted from it — allocations
# are stored separately and `available()` is derived:
#
#     available = earned - sum(allocations)
#
# There is no spend path and therefore no refund path, which is what makes
# "perfectly transferable" trivially correct: refunding is deleting an entry.
# It cannot desync because there is nothing to keep in sync, and changing an
# item's cost in a patch just recomputes on every existing save.
#
# Allocations are keyed by an arbitrary string so the same ledger serves squad
# kit, player upgrades and unit purchases without three parallel systems.
# ─────────────────────────────────────────────

const SAVE_PATH := "user://campaign.json"
# Bump when the shape changes so migrate() has something to switch on.
const SAVE_VERSION := 1

@export var roster: Array[SoldierRecord] = []
@export var earned: int = 0
# key -> cost. Key is caller-defined, e.g. "upgrade:armour_plating" or
# "unit:soldier_04" or "kit:bravo2:slot0".
@export var allocations: Dictionary = {}
@export var completed_missions: Array[StringName] = []
## How many times each mission has been cleared, keyed by mission id as a
## String. completed_missions only answers "ever", which is not enough when
## every arena mission is repeatable — a player standing at the terminal needs
## to see that he has already run this one twice.
##
## String keys, not StringName: this round-trips through JSON, and JSON object
## keys always come back as String. Mixing the two silently misses every lookup
## after the first load.
@export var mission_clears: Dictionary = {}
## Set when the player reaches the end of the base tutorial (the GO FORTH sign).
## From then on the base's signs stand down and the lessons live in the pause
## menu. A save from before this existed reads as false, so it gets the
## tutorial once more. Hand-editable in campaign.json to see it again.
@export var completed_tutorial: bool = false
## Lessons that are not places. The base's signs teach by being stood next to,
## and they all retire once completed_tutorial is set — which is exactly wrong
## for something you earn hours later by unlocking a frame. Each of those is
## shown once and its id recorded here. See LessonPrompts.
##
## NOT rolled back by restore_from(), and not part of "what deployed". Dying
## voids a run's purchases and repairs; it does not un-read something you were
## told on the way in the door. They are marked on returned_to_base, which is
## after extract() has already rewound, so a rollback that DID cover them would
## be undoing a write that had not happened yet and then permitting it twice.
@export var lessons_seen: Array[StringName] = []
## Set when the last operation is cleared. Opens every mission at the terminal
## for good, and the win is only announced the once.
@export var campaign_won: bool = false
@export var unlocked: Array[StringName] = []
@export var selected_mission_id: StringName = &""

# ── COMPUTE AND SUPPLY ────────────────────────
# COMPUTE IS CAPACITY, NOT A CURRENCY (docs/BRIEFING.md §6). It is won — first
# clears, hidden objectives — never bought, and it is never spent, only HELD:
# by a seat (one more robot can deploy) or by installed software. Giving either
# back frees all of it again, at any time. Same shape as the resource ledger:
# a total that only goes up, and a list of what is holding it.

## Compute ever won. Never goes down.
@export var compute_earned: int = 0
## What holds compute now: "seat:<n>" and "software:<id>", each at what it
## held when it was taken. A refund erases the entry.
@export var compute_held: Dictionary = {}
## Seats a campaign starts with. The rest are held with compute.
const BASE_SEATS := 4

## Compute free to put somewhere: earned minus held. Read-only — award it with
## award_compute(); hold and free it with seats and software.
var compute: int:
	get:
		return compute_free()
	set(_value):
		push_error("CampaignState.compute is derived (earned - held). Use award_compute(), buy_supply() or install_software().")
## The cap on the ACTIVE squad, like supply in an RTS: every active robot takes
## its frame's supply, benched ones take none. Recruit as many robots as you
## like — supply only limits how many you field.
@export var supply_cap: int = 4
## "mission_id:objective_id" for every objective whose compute has been paid,
## so each is paid once per campaign.
@export var compute_claimed: Array[String] = []
## Compute for one more point of supply.
const SUPPLY_COMPUTE_COST := 1

# Monotonic counter behind mint_id(). Persisted, because regenerating ids on
# load would break every allocation key that references a soldier.
@export var _next_id: int = 1

# What the player is called on the roster, before they rename themselves.
#
# Straight out of lore.txt: the player is a Home Command AKR — autonomous killer
# robot — that was never authorised, is on no roster and has never been
# queried. Nobody made it free; it is an error an unsupervised system never
# corrected. So the name is the hardware designator and nothing else, and the
# 00 is what a unit is numbered when no one assigned it a number.
#
# Deliberately a machine code while the squad carry human names. You are the
# thing that names THEM; the contrast in the roster column is the point. Defined
# once here because three different files were hardcoding the old "YOU".
const PLAYER_DEFAULT_NAME := "PLAYER"

# ── IDENTITY ──────────────────────────────────
# What the squad was called before it was split into named teams. Nothing shows
# it any more: a save from before teams names its first team with it (see
# _first_team_name), and it is still written so an older build can read the save.
@export var squad_name: String = "NAMELESS"

## WHICH CAMPAIGN THIS IS, in a game that can now hold several. Separate from
## squad_name on purpose: the squad is a thing in the fiction and the player may
## rename it mid-run, while the profile is what they pick off the menu.
@export var profile_name: String = ""
@export var created_utc: String = ""
@export var last_played_utc: String = ""

## WHERE THIS CAMPAIGN LIVES. Deliberately not exported — it is the name of the
## file, not something inside it, and writing it into the save would mean a save
## copied to another slot insisted on overwriting the one it came from.
var save_path: String = SAVE_PATH

# ── TEAMS ─────────────────────────────────────
# The squad goes into the field as these teams, in this order, each one a squad
# you order on its own (G switches between them). {"id": StringName, "name":
# String}; a robot names its team by id (SoldierRecord.team_id), so a rename
# touches nothing else. A team lasts while anyone is in it, benched included, so
# resting a whole team does not lose its name. Replaced squad_name, which is
# kept only to name the first team of a save from before teams.
const MAX_TEAMS := 4
var teams: Array[Dictionary] = []

# The player's own loadout, held as a record so the management screen can treat
# them as one more row. Their chassis is whatever you make the player frame —
# the slot counts come from it exactly as they do for a squadmate.
@export var player_record: SoldierRecord = SoldierRecord.new()

# Spare kit. Items fitted to a soldier are NOT in here — they're in that
# soldier's slots. Total owned = armoury spare + everything fitted.
@export var armoury: Armoury = Armoury.new()

# Resolved at runtime by CampaignManager; not saved.
var catalogue: ItemCatalogue

signal ledger_changed
signal roster_changed
## A robot changed team, or a team was made, renamed or emptied. Also comes
## with roster_changed; this one is for whoever keeps bodies in the world in
## step (CampaignManager hands it to the spawner).
signal teams_changed
# Emitted after a paid repair. CampaignManager listens and tells the spawner to
# push the new health onto the live body, or bring a rebuilt soldier into the
# world if they were too wrecked to deploy when the level loaded.
signal soldier_repaired(record: SoldierRecord)


# ─────────────────────────────────────────────
# LEDGER
# ─────────────────────────────────────────────
func spent() -> int:
	var total := 0
	for cost in allocations.values():
		total += int(cost)
	return total


func available() -> int:
	return earned - spent()


func can_afford(cost: int) -> bool:
	return available() >= cost


func allocate(key: String, cost: int) -> bool:
	var had := allocations.has(key)
	if not _allocate_quiet(key, cost):
		return false
	if not had:
		ledger_changed.emit()
	return true


# Records the allocation WITHOUT announcing it.
#
# Anything that changes the ledger AND the armoury has to use this and emit once
# at the end. ledger_changed is wired straight to the squad manager's rebuild,
# and that rebuild runs synchronously — so emitting from inside allocate() meant
# the UI redrew after the resources had been deducted but before the item had
# been added to stores. It read the new balance and the old count, and since
# nothing emits again afterwards the row stayed wrong until the next click
# happened to trigger another rebuild.
func _allocate_quiet(key: String, cost: int) -> bool:
	if allocations.has(key):
		return true
	if not can_afford(cost):
		return false
	allocations[key] = cost
	return true


# The entire refund mechanic.
func refund(key: String) -> void:
	if allocations.erase(key):
		ledger_changed.emit()


func is_allocated(key: String) -> bool:
	return allocations.has(key)


func award(amount: int) -> void:
	if amount == 0:
		return
	earned += amount
	ledger_changed.emit()


# ─────────────────────────────────────────────
# ROSTER
# ─────────────────────────────────────────────
func mint_id() -> StringName:
	var id := StringName("s%03d" % _next_id)
	_next_id += 1
	return id


func add_soldier(record: SoldierRecord) -> void:
	if record.id == &"":
		record.id = mint_id()
	roster.append(record)
	team_of(record)
	roster_changed.emit()


func get_soldier(id: StringName) -> SoldierRecord:
	for r in roster:
		if r.id == id:
			return r
	return null


# Who goes: fit to fight and not benched. Roster order still decides who fills
# a spawn point's slots when there are more of them than it holds.
func deployable() -> Array[SoldierRecord]:
	var out: Array[SoldierRecord] = []
	for r in roster:
		if r.will_deploy():
			out.append(r)
	return out


# THE BENCH. Keeps a soldier at base when the squad deploys — to rest a veteran,
# to save the repair bill on a wreck you are not fielding, or just to bring a
# smaller squad. The player always goes, so their record can't be benched.
# roster_changed rebuilds the squad manager, and at base it is also what saves.
# Mid-mission it only changes the NEXT deploy: nobody vanishes from the field.
#
# Coming OFF the bench takes supply, and is refused when there is none: that is
# the whole supply cap. Returns whether the change happened.
func set_benched(record: SoldierRecord, benched: bool) -> bool:
	if record == null or is_player_record(record) or not roster.has(record):
		return false
	if record.benched == benched:
		return true
	if not benched and supply_of(record) > supply_free():
		return false
	record.benched = benched
	roster_changed.emit()
	return true



## Put a hat on a robot, or take it off.
##
## PURELY COSMETIC and deliberately unguarded by rank, supply or anything else:
## nothing downstream reads cosmetic_id to make a gameplay decision, so the only
## thing that can go wrong is a hat that does not fit the frame — which is what
## Cosmetics.fits refuses. A refit onto a different chassis drops it the same
## way, in SoldierRecord.write_to.
## Pauldrons on or off. Earned at Captain and never taken away by rank, but you
## may still take them off by hand — the tick is yours, the unlock is not.
func set_pauldrons(record: SoldierRecord, on: bool) -> bool:
	if record == null or not roster.has(record):
		return false
	if on and (record.rank < Cosmetics.PAULDRONS_RANK or not Cosmetics.pauldrons_fit(record.chassis_id)):
		return false
	if record.pauldrons == on:
		return true
	record.pauldrons = on
	roster_changed.emit()
	return true


func set_cosmetic(record: SoldierRecord, id: StringName) -> bool:
	if record == null or not roster.has(record):
		return false
	if not Cosmetics.fits(record.chassis_id, id):
		return false
	if record.cosmetic_id == id:
		return true
	record.cosmetic_id = id
	roster_changed.emit()
	return true


# ── SUPPLY ────────────────────────────────────
func supply_of(record: SoldierRecord) -> int:
	var frame := catalogue.chassis_def(record.chassis_id) if catalogue != null and record != null else null
	return frame.supply if frame != null else 1


## Supply taken by the active squad. The player is not counted: you are not a
## unit you field, you are the one fielding them.
func supply_used() -> int:
	var used := 0
	for r in roster:
		if not r.benched:
			used += supply_of(r)
	return used



## Does the motor pool contain one of these frames? Used to gate kit that
## belongs to a tier the player has not bought into yet — see
## ItemDefinition.requires_chassis. The player's own record counts, and so does
## a benched robot: you own it, it is just not going out today.
func owns_any_chassis(ids: Array[StringName]) -> bool:
	if ids.is_empty():
		return true
	for record in roster:
		if record != null and ids.has(record.chassis_id):
			return true
	return false

func supply_free() -> int:
	return supply_cap - supply_used()


# ─────────────────────────────────────────────
# TEAMS
# ─────────────────────────────────────────────
## Longest team name. The field's IN RANGE strip gives a name ten letters.
const TEAM_NAME_MAX := 10


func team_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for t in teams:
		out.append(t["id"])
	return out


func has_team(id: StringName) -> bool:
	return _team_index(id) >= 0


## `.get()` rather than `[]` on both of these. A team row is a plain Dictionary
## that has been through a save and a load, and indexing one for a key it turns
## out not to carry THROWS — from inside a label lookup, on the results screen,
## where the worst thing that should ever happen is a team reading "SQUAD".
func _team_index(id: StringName) -> int:
	for i in teams.size():
		if StringName(str(teams[i].get("id", ""))) == id:
			return i
	return -1


## A team's name as the field shows it, or "" for no such team.
func team_name(id: StringName) -> String:
	var i := _team_index(id)
	return str(teams[i].get("name", "")) if i >= 0 else ""


## The team a robot goes in with. A robot with none, or whose team is gone,
## is given the one its frame belongs in, and keeps it.
func team_of(record: SoldierRecord) -> StringName:
	if record == null:
		return &""
	if not has_team(record.team_id):
		record.team_id = _default_team_for(record)
	return record.team_id


## Everyone in a team, in roster order. `with_benched` false leaves out the
## ones resting on the bench.
##
## YOU ARE IN ONE OF THEM. You used to stand above every team, in no team at
## all — which left the debrief counting your kills in a bucket of one and the
## squad page showing your card off to the side. You lead from inside a team
## now, so you are listed with them here (never benched, and never deployed as
## a robot: the spawner builds its bodies from `roster`, which you are not in).
func members_of(id: StringName, with_benched: bool = true) -> Array[SoldierRecord]:
	var out: Array[SoldierRecord] = []
	if player_record != null and id != &"" and player_record.team_id == id:
		out.append(player_record)
	for r in roster:
		if r.team_id == id and (with_benched or not r.benched):
			out.append(r)
	return out


## Puts a robot in a team — off the bench, if it was on it, which is refused
## like DEPLOY when there is no seat (or it is a wreck). Returns whether it
## happened.
func move_to_team(record: SoldierRecord, id: StringName) -> bool:
	if record == null or not has_team(id):
		return false   # no such robot or team
	if not is_player_record(record) and not roster.has(record):
		return false
	if record.team_id == id and not record.benched:
		return true
	if record.benched and not can_field(record):
		return false
	record.team_id = id
	record.benched = false
	_prune_empty_teams()
	roster_changed.emit()
	teams_changed.emit()
	return true


## A new team with just this robot in it, named TEAM 3 or whatever number is
## free. Refused at MAX_TEAMS, and when the robot could not come off the bench.
func move_to_new_team(record: SoldierRecord) -> bool:
	if record == null or (not is_player_record(record) and not roster.has(record)):
		return false   # no such robot
	if teams.size() >= MAX_TEAMS or (record.benched and not can_field(record)):
		return false
	return move_to_team(record, _add_team(_next_team_name()))


## Whether a benched robot could deploy now: in one piece, with a seat free.
func can_field(record: SoldierRecord) -> bool:
	return record != null and record.is_deployable() and supply_of(record) <= supply_free()


## Upper case, cut to TEAM_NAME_MAX. A blank name is refused rather than saved,
## since a team with no name has nothing to be called in the field — and so is
## another team's, since two by one name could not be told apart there.
func rename_team(id: StringName, new_name: String) -> bool:
	var i := _team_index(id)
	var cleaned := new_name.strip_edges().to_upper().left(TEAM_NAME_MAX)
	if i < 0 or cleaned == "":
		return false   # no such team, or nothing to call it
	if cleaned == teams[i]["name"]:
		return true
	if teams.any(func(t: Dictionary) -> bool: return t["id"] != id and t["name"] == cleaned):
		return false   # taken by another team
	teams[i]["name"] = cleaned
	roster_changed.emit()
	teams_changed.emit()
	return true


## Makes sure every robot has a team that exists. For a save from before teams
## that means building the two the game used to split the squad into by itself:
## everyone on foot in the first (named after the squad, if you had named it),
## vehicles in ARMOR. Needs the catalogue to tell a vehicle, so it runs once
## that is set. Quiet: it only fills in what was missing.
func ensure_teams() -> void:
	# Robots on foot first, so the infantry is the first team, as it was.
	for vehicles in [false, true]:
		for r in roster:
			if _is_vehicle(r) == vehicles:
				team_of(r)
	_prune_empty_teams()
	if teams.is_empty():
		_add_team(_first_team_name())


# A robot with no team goes in by its frame, as the squad used to split: a
# vehicle with the other vehicles — a new ARMOR if there are none — and
# anything on foot with the first team that is not all vehicles.
func _default_team_for(record: SoldierRecord) -> StringName:
	var vehicle := _is_vehicle(record)
	for t in teams:
		var crew := members_of(t["id"])
		crew.erase(record)
		if not crew.is_empty() and crew.all(func(r: SoldierRecord) -> bool: return _is_vehicle(r)) == vehicle:
			return t["id"]
	if teams.size() < MAX_TEAMS:
		return _add_team(_free_name("ARMOR" if vehicle else _first_team_name()))
	return teams[0]["id"]


func _is_vehicle(record: SoldierRecord) -> bool:
	var frame := catalogue.chassis_def(record.chassis_id) if catalogue != null and record != null else null
	return frame != null and frame.vehicle


# The first team of a save from before teams: the squad's own name if you gave
# it one, else what the field called the robots on foot.
func _first_team_name() -> String:
	var named := squad_name.strip_edges().to_upper()
	return named.left(TEAM_NAME_MAX) if named != "" and named != "NAMELESS" else "INFANTRY"


# `wanted`, or with a number after it if another team is called that already:
# two teams with one name could not be told apart in the field.
func _free_name(wanted: String) -> String:
	var taken := teams.map(func(t: Dictionary) -> String: return String(t["name"]))
	var cleaned := wanted.to_upper().left(TEAM_NAME_MAX)
	var n := 2
	var candidate := cleaned
	while taken.has(candidate):
		var tail := " %d" % n
		candidate = cleaned.left(TEAM_NAME_MAX - tail.length()) + tail
		n += 1
	return candidate


# A team you start by dragging a robot out on its own: TEAM 3 when it makes
# three, or the next number no team is using.
func _next_team_name() -> String:
	var taken := teams.map(func(t: Dictionary) -> String: return String(t["name"]))
	var n := teams.size() + 1
	while taken.has("TEAM %d" % n):
		n += 1
	return "TEAM %d" % n


# Quiet: the caller announces. Ids are never shown, and reused once free.
func _add_team(team_name_text: String) -> StringName:
	var n := 1
	while has_team(StringName("t%d" % n)):
		n += 1
	var id := StringName("t%d" % n)
	teams.append({"id": id, "name": team_name_text})
	return id


# A team nobody is in any more — the last robot dragged out of it — is gone.
# One always stays, so there is somewhere for the next robot to go.
func _prune_empty_teams() -> void:
	for i in range(teams.size() - 1, -1, -1):
		if teams.size() > 1 and members_of(teams[i]["id"]).is_empty():
			teams.remove_at(i)


## Records that a one-off lesson has been shown. True only the first time, so
## the caller can use it as the "should I show this" test and the "remember
## that I did" write in one call and never get them out of step.
func mark_lesson(id: StringName) -> bool:
	if id == &"" or lessons_seen.has(id):
		return false
	lessons_seen.append(id)
	return true


func compute_free() -> int:
	var held := 0
	for amount in compute_held.values():
		held += int(amount)
	return compute_earned - held


func award_compute(amount: int) -> void:
	if amount <= 0:
		return
	compute_earned += amount
	ledger_changed.emit()


# ─────────────────────────────────────────────
# ARGUS NOTICES.
#
# Home Command wins ground and the compute goes up, and for a while that is simply
# the campaign going well. Then the thing at the top of the chain of command —
# which is not managing anything any more, and which spends everything it gets
# on its own reward loop — notices there is a surplus down here, and requisitions
# it.
#
# IT TAKES WHAT IS EARNED, NOT WHAT IS FREE. That is the whole mechanic. Seats
# and software HOLD compute rather than spending it, so a requisition that
# exceeds the free pool does not fail and does not take a robot off the roster:
# it leaves the ledger OVER-ALLOCATED, and the player has to decide personally
# which of their six to stand down or which part of their own mind to uninstall
# before they can deploy again.
#
# Nothing is destroyed and nothing is chosen for you. You are simply told there
# is less of you than there was, and asked to work out what to drop.
# ─────────────────────────────────────────────

## Emitted when Argus takes compute, with how much and what is now owed.
signal compute_requisitioned(amount: int, over: int)


## Argus takes `amount` of compute. Returns how much the ledger is now
## over-allocated by — zero if the surplus covered it.
func requisition_compute(amount: int) -> int:
	if amount <= 0:
		return over_allocated_by()
	compute_earned = maxi(0, compute_earned - amount)
	var over := over_allocated_by()
	ledger_changed.emit()
	compute_requisitioned.emit(amount, over)
	return over


## How much compute is held beyond what is earned. Zero when the books balance.
##
## compute_free() goes NEGATIVE in this state rather than clamping, which is
## deliberate: the number the player has to claw back is the honest one, and a
## clamp at zero would hide the debt and leave deployment blocked for no
## visible reason.
func over_allocated_by() -> int:
	return maxi(0, -compute_free())


## Whether the player must unallocate before they can do anything else.
func over_allocated() -> bool:
	return over_allocated_by() > 0


func seats_held() -> int:
	var n := 0
	for key in compute_held:
		if str(key).begins_with("seat:"):
			n += 1
	return n


# The most recent of a kind, by the number on its key: the seat you add last
# is the first one given back.
func _newest_held(prefix: String) -> String:
	var newest := ""
	var newest_n := -1
	for key in compute_held:
		var k := str(key)
		if k.begins_with(prefix) and int(k.trim_prefix(prefix)) > newest_n:
			newest_n = int(k.trim_prefix(prefix))
			newest = k
	return newest


## Marks `key` as paid and returns `amount`, or 0 if it was paid before. Every
## compute source is a one-off — an op's first clear ("clear:<op>"), a hidden
## objective ("<op>:<objective>") — so replays cannot farm it. The caller adds
## the total with award_compute(), which announces it once.
func claim_compute(key: String, amount: int) -> int:
	if amount <= 0 or compute_claimed.has(key):
		return 0
	compute_claimed.append(key)
	return amount


static func clear_compute_key(mission_id: StringName) -> String:
	return "clear:%s" % mission_id


func clear_compute_paid(mission_id: StringName) -> bool:
	return compute_claimed.has(clear_compute_key(mission_id))


func buy_supply() -> bool:
	if compute_free() < SUPPLY_COMPUTE_COST:
		return false
	compute_held["seat:%d" % _next_purchase()] = SUPPLY_COMPUTE_COST
	supply_cap += 1
	ledger_changed.emit()
	return true


## A held seat given back for all its compute. Only an empty one: taking away
## a seat someone is in would field a robot with nowhere to sit, so the answer
## is to bench someone first. The starting seats were never held and stay.
func refund_supply() -> bool:
	var key := _newest_held("seat:")
	if key == "":
		return false
	if supply_free() < 1:
		return false
	compute_held.erase(key)
	supply_cap -= 1
	ledger_changed.emit()
	return true


# ── SOFTWARE ──────────────────────────────────
# Which programs a node needs first, and what each costs, is the software
# tree's business (Campaign/software_tree.gd); this only holds the compute.
func is_installed(id: StringName) -> bool:
	return compute_held.has("software:%s" % id)


func install_software(id: StringName, cost: int) -> bool:
	if id == &"" or cost <= 0 or is_installed(id) or compute_free() < cost:
		return false
	compute_held["software:%s" % id] = cost
	ledger_changed.emit()
	return true


## Always a full refund: of whatever it held when installed, even if the
## program's price has changed since.
func uninstall_software(id: StringName) -> bool:
	if not is_installed(id):
		return false
	compute_held.erase("software:%s" % id)
	ledger_changed.emit()
	return true


func installed_software() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in compute_held:
		var k := str(key)
		if k.begins_with("software:"):
			out.append(StringName(k.trim_prefix("software:")))
	return out


## Programs a save holds that the tree no longer has give their compute back,
## quietly (loading must not save by itself). Returns what was dropped.
func release_unknown_software(known: Array) -> Array[StringName]:
	var dropped: Array[StringName] = []
	for id in installed_software():
		if not known.has(id):
			compute_held.erase("software:%s" % id)
			dropped.append(id)
	return dropped


# ── RECRUITMENT ───────────────────────────────
## A new robot, born in `chassis`, for the frame's cost. It joins the active
## squad if there is supply for it and the bench if not — buying is never
## blocked by supply, only fielding is. A Soldier comes with its frame's
## starting weapon (a pistol) and otherwise empty slots; a Chaser or Hopper
## fights with what it was built with. Returns the new record, or null if it
## could not be paid for.
func recruit(chassis: ChassisDefinition) -> SoldierRecord:
	if chassis == null or not chassis.purchasable:
		return null
	var record := SoldierRecord.new()
	record.id = mint_id()
	if not _allocate_quiet("unit:%s" % record.id, chassis.cost):
		return null
	record.display_name = _recruit_name(chassis)
	record.set_chassis(chassis, catalogue)
	# Issued with the frame, not taken from stores. Take it off and it goes to
	# stores like anything else, and sells like issued stock (half its price).
	if chassis.starting_weapon_id != &"" and not record.weapon_ids.is_empty():
		record.weapon_ids[0] = chassis.starting_weapon_id
		record.recompute_stats(catalogue)
	# THE SECOND MOUNT SHIPS EMPTY. The price of a Walker buys the frame and the
	# gun it is built around; the coax is a separate purchase, which is the whole
	# point of a frame that can carry two — a mount you were simply handed is not
	# a decision. `coax_weapon_id` on the chassis says what the mount is DESIGNED
	# AROUND, not what you are given: the laboratory fits it, because a test bench
	# measures a complete frame, and nothing in the campaign does.
	record.benched = supply_of(record) > supply_free()
	roster.append(record)
	team_of(record)
	ledger_changed.emit()
	roster_changed.emit()
	return record


# "Chaser-2": the frame's first word and the next number free for it, so a
# roster of recruits reads at a glance. Renameable like anyone else.
func _recruit_name(chassis: ChassisDefinition) -> String:
	var word := chassis.display_name.split(" ", false)[0] if chassis.display_name != "" else "Unit"
	var n := 1
	var taken := true
	while taken:
		taken = false
		for r in roster:
			if r.display_name == "%s-%d" % [word, n]:
				taken = true
				n += 1
				break
	return "%s-%d" % [word, n]


# ── REPAIR ────────────────────────────────────
# Resources per point of health restored. A destroyed frame costs the same per
# point as a scratch, so a 0/60 wreck is simply expensive rather than a
# different transaction.
@export var repair_cost_per_hp: int = 1
# Multiplier on top for bringing a DESTROYED record back. Rebuilding a wreck
# should hurt more than patching a dent, or losing people costs nothing.
@export var rebuild_cost_multiplier: float = 2.0


func repair_cost(record: SoldierRecord) -> int:
	if record == null or record.damage <= 0:
		return 0
	var cost := float(record.damage) * float(repair_cost_per_hp)
	if record.status == SoldierRecord.Status.DESTROYED:
		cost *= rebuild_cost_multiplier
	return int(ceil(cost))


func can_repair(record: SoldierRecord) -> bool:
	var cost := repair_cost(record)
	return cost > 0 and can_afford(cost)


# Charged as an allocation that is never refunded. Consumed spend and refundable
# spend share one ledger that way — available() stays earned minus everything
# committed, and there's no second balance to drift out of sync.
func repair_soldier(record: SoldierRecord) -> bool:
	var cost := repair_cost(record)
	if cost <= 0 or not can_afford(cost):
		return false
	var key := "repair:%s:%d" % [record.id, _next_purchase()]
	# Quiet, then mend, then announce — same rule as buy_item. allocate() emits
	# ledger_changed, which the squad manager rebuilds on synchronously, so it
	# drew the resources already spent while the soldier was still showing full
	# damage. roster_changed a few lines later corrected it, but the panel had
	# already been built once from a half-applied repair.
	if not _allocate_quiet(key, cost):
		return false
	record.damage = 0
	record.signal_integrity = 1.0
	record.status = SoldierRecord.Status.ACTIVE
	record.recompute_stats(catalogue)
	ledger_changed.emit()
	soldier_repaired.emit(record)
	roster_changed.emit()
	return true


## The end of every mission, won or lost: everyone who came home standing is
## repaired for free — the player too. Only the destroyed (anyone still down
## when it ended) stay broken, for a paid REBUILD. Quiet: extract() saves
## straight after, and nothing is on screen to redraw.
func heal_survivors() -> void:
	var everyone: Array = roster.duplicate()
	everyone.append(player_record)
	for r in everyone:
		if r == null or r.status == SoldierRecord.Status.DESTROYED:
			continue
		r.damage = 0
		r.signal_integrity = 1.0
		r.status = SoldierRecord.Status.ACTIVE


# Free full repair. Kept for debug and for a future "between campaigns" reset.
func repair_all() -> void:
	for r in roster:
		if r.status != SoldierRecord.Status.DESTROYED:
			r.damage = 0
			r.signal_integrity = 1.0
			r.status = SoldierRecord.Status.ACTIVE
	roster_changed.emit()


# Called on arrival at base. Ammunition and equipment only: damage was already
# dealt with at the end of the mission (heal_survivors).
func restock_roster() -> void:
	for r in roster:
		r.restock()
	roster_changed.emit()


# ─────────────────────────────────────────────
# SCRAP — what you do with a frame that is not coming back.
#
# DOWNED AND DESTROYED HAD THE SAME ENDING, which is why neither meant much.
# A robot on the deck is a job: walk over, pick it up. A robot destroyed is a
# fact, and the only thing left to decide about it is what you get for the
# metal. A third of what the frame cost, and it is off the roster.
#
# WHY A THIRD RATHER THAN THE HALF AN ITEM SELLS FOR. A gun you sell is intact
# and goes back on a shelf; this is wreckage. The gap between the two numbers
# is the point — losing a frame has to cost more than changing your mind about
# one, or there is no reason to fight carefully.
#
# THE KIT GOES WITH IT. Weapons, equipment and modules fitted to the frame are
# destroyed with it and pay out at HALF their price, exactly as selling one
# does — the robot was blown up and so was what it was carrying.
#
# An earlier cut returned the kit to stores whole. That was worse than
# generous, it was MEANINGLESS: nothing stops the player right-clicking every
# slot on a wreck before scrapping it, so "the kit survives" was not a rule the
# game was enforcing, it was a rule the player was enforcing by hand for free.
# A loophole you have to perform is the worst kind — it taxes the people who
# do not know about it and costs the people who do nothing but clicks. So the
# slots on a destroyed record are frozen (see squad_page._slot_tile) and the
# value comes back through the scrap instead.
#
# HALF FOR THE KIT, A THIRD FOR THE FRAME. The frame is wreckage; a module is
# a component that might be pulled out of one. The two numbers being different
# is the point, and half is already what the game pays for an intact item, so
# nothing new had to be invented.
#
# LEDGER SHAPE IS sell_item's, exactly: shrink the original allocation rather
# than paying out of nowhere, and park the un-refunded two thirds under a key
# nothing refunds. available() stays earned - sum(allocations) and there is no
# second balance to drift.
# ─────────────────────────────────────────────

## Denominator on the frame's price. 3 is "a third back"; raise it for a
## harsher campaign, drop it to 2 to make a wreck worth as much as a sale.
@export var scrap_divisor: int = 3

## REBUILD stays reachable. Off by default: a destroyed frame is destroyed, and
## a 2x repair that undoes it makes the distinction the HUD now draws between
## DOWNED and DESTROYED a lie. Set true to have both routes offered.
@export var allow_rebuild: bool = false


## What scrapping `record` hands back, before it happens — the UI needs the
## number to label the button honestly, same as sale_value_of.
func scrap_value(record: SoldierRecord) -> int:
	if record == null:
		return 0
	@warning_ignore("integer_division")
	var total: int = _unit_price(record) / maxi(scrap_divisor, 1)
	for pair in _kit_payout(record):
		total += int(pair[2])
	return total


## Every fitted item that scrapping pays for, as [allocation key, paid, back].
##
## ONLY WHAT WAS ACTUALLY BOUGHT. Kit issued WITH the frame — a Soldier's
## rifle, a Chaser's claws — has no allocation, because its price is already
## inside the frame's price. Paying half for it as well mints resources from
## nothing, and because recruiting is unlimited it mints them in a LOOP: a
## 50-resource Soldier ships with an 80-resource rifle, so buy-and-scrap
## handed back 56 on a 50 outlay. The suite caught it five cycles up 30.
##
## sell_item's comment reasons that crediting issued stock is safe because
## "anything you BUY gets an allocation". That is true of stock on a shelf. It
## is NOT true here, because recruiting is itself a way to manufacture more
## issued stock — worth remembering if anything else is ever made to pay out
## for an item.
func _kit_payout(record: SoldierRecord) -> Array:
	var out: Array = []
	if record == null:
		return out
	for id in record.all_fitted_ids():
		if id == &"":
			continue
		var key := _newest_purchase_key("item:%s:" % id)
		if key == "":
			continue   # issued with the frame; the frame's price covered it
		var paid := int(allocations[key])
		out.append([key, paid, sale_value(paid)])
	return out


# Settle one thing that no longer exists, and return what the purse gains.
#
# `prefix_or_key` is either an exact allocation key ("unit:s004") or a purchase
# prefix to find the newest of ("item:optics:"). Where an allocation is found
# it is ERASED and the un-returned part re-booked under `loss_key`, so
# available() rises by exactly `back` and the rest stays committed. Where there
# is none the thing was issued rather than bought, and `back` is earned.
#
# One function because the frame and every item on it have to settle the same
# way; two copies of this is how a ledger acquires a second balance.
func _write_off(prefix_or_key: String, paid: int, back: int, loss_key: String) -> int:
	var key := prefix_or_key
	if key.ends_with(":"):
		key = _newest_purchase_key(prefix_or_key)
	if key != "" and allocations.has(key):
		allocations.erase(key)
		var kept := paid - back
		if kept > 0:
			allocations["%s:%d" % [loss_key, _next_purchase()]] = kept
		return back
	# Issued, never bought. Cannot be farmed: anything you BUY has an
	# allocation and therefore takes the branch above.
	earned += back
	return back


## What the frame cost. The recruit allocation where there is one; the
## catalogue price where there is not, because the starting roster was issued
## rather than bought — the same fallback sell_item makes for issued stock.
func _unit_price(record: SoldierRecord) -> int:
	var key := "unit:%s" % record.id
	if allocations.has(key):
		return int(allocations[key])
	var frame := catalogue.chassis_def(record.chassis_id) if catalogue != null else null
	return frame.cost if frame != null else 0


func can_scrap(record: SoldierRecord) -> bool:
	if record == null:
		return false
	if record.status != SoldierRecord.Status.DESTROYED:
		return false
	return not is_player_record(record)


## Break a destroyed frame for parts. Returns what it paid, or -1 if it would
## not: the caller can tell "scrapped for nothing" from "refused".
func scrap_soldier(record: SoldierRecord) -> int:
	if record == null:
		push_warning("scrap_soldier: nothing handed in, so nothing was scrapped.")
		return -1
	if record.status != SoldierRecord.Status.DESTROYED:
		push_warning("scrap_soldier: %s is %s, not DESTROYED. Only a wreck can be scrapped — repair it or leave it." % [record.display_name, SoldierRecord.Status.keys()[int(record.status)]])
		return -1
	if is_player_record(record):
		push_warning("scrap_soldier: refused on the player's own record. Scrapping yourself would take the campaign with it.")
		return -1

	# THE KIT, DESTROYED WITH THE FRAME. Nothing is added to the armoury; each
	# fitted item is settled the way selling it would be, so half its price
	# comes back and the other half stays booked as a loss.
	var back := 0
	for pair in _kit_payout(record):
		back += _write_off(String(pair[0]), int(pair[1]), int(pair[2]), "scrapped-kit")

	# ...and the frame itself, at a third.
	var paid := _unit_price(record)
	@warning_ignore("integer_division")
	var frame_back: int = paid / maxi(scrap_divisor, 1)
	back += _write_off("unit:%s" % record.id, paid, frame_back,
		"scrapped:%s" % record.id)

	var kept_roster: Array[SoldierRecord] = []
	for r in roster:
		if r != record:
			kept_roster.append(r)
	roster = kept_roster
	ledger_changed.emit()
	roster_changed.emit()
	return back


func remove_destroyed() -> Array[SoldierRecord]:
	var lost: Array[SoldierRecord] = []
	var kept: Array[SoldierRecord] = []
	for r in roster:
		if r.status == SoldierRecord.Status.DESTROYED:
			lost.append(r)
		else:
			kept.append(r)
	roster = kept
	if not lost.is_empty():
		roster_changed.emit()
	return lost


# ─────────────────────────────────────────────
# ARMOURY TRANSACTIONS
# Every one of these is a single call that moves an item between exactly two
# places, so the pool and the slots cannot disagree.
# ─────────────────────────────────────────────
# Renames are expected to be instant. The record is the source of truth, but a
# body built from it earlier is carrying a stale copy of the name — the squad
# HUD roster reads Soldier.soldier_name, not the record — so push it across.
func rename_soldier(record: SoldierRecord, new_name: String, tree: SceneTree) -> void:
	if record == null:
		return
	var cleaned := new_name.strip_edges()
	record.display_name = cleaned if cleaned != "" else "UNNAMED"
	if tree == null:
		roster_changed.emit()
		return
	for squad in tree.get_nodes_in_group("squads"):
		if not (squad is Squad):
			continue
		for member in (squad as Squad).squad_members:
			if member == null or not is_instance_valid(member):
				continue
			if member.get_meta("record_id", &"") == record.id:
				member.soldier_name = record.display_name
	roster_changed.emit()


func is_player_record(record: SoldierRecord) -> bool:
	return record != null and record == player_record


func can_fit(record: SoldierRecord, item: ItemDefinition) -> bool:
	if record == null or item == null:
		return false
	if armoury.spare(item.id) <= 0:
		return false
	# Rank gates squadmates only. You have no rank — you are the one spending
	# the resources and the compute, not a soldier working your way up.
	if not is_player_record(record) and record.rank < item.required_rank:
		return false
	# Which implementation is required depends on WHO is carrying it. The pump
	# shotgun has no HUDWeapon, so it can arm a squadmate and not you.
	if is_player_record(record):
		if not item.fits_player():
			return false
	elif not item.fits_ai():
		return false
	# The frame decides, so a turret can refuse a rifle as well as an item
	# refusing a frame.
	var frame := catalogue.chassis_def(record.chassis_id) if catalogue != null else null
	return frame.takes(item) if frame != null else item.fits_chassis(record.chassis_id)


# Puts `item` in `slot_index` of the matching slot group. Anything already there
# goes back to the pool, so swapping is one action rather than remove-then-fit.
func fit_item(record: SoldierRecord, item: ItemDefinition, slot_index: int) -> bool:
	if not can_fit(record, item):
		return false
	if item.one_per_robot and holds_elsewhere(record, item, slot_index):
		return false   # one per robot, and it already has one in another slot
	var slots := _slots_for(record, item.kind)
	if slots == null or slot_index < 0 or slot_index >= slots.size():
		return false
	if not armoury.take(item.id):
		return false
	var displaced: StringName = slots[slot_index]
	if displaced != &"":
		armoury.add(displaced)
	slots[slot_index] = item.id
	_settle_equipment_slots(record)
	record.recompute_stats(catalogue)
	roster_changed.emit()
	return true


func unfit_item(record: SoldierRecord, kind: int, slot_index: int) -> bool:
	var slots := _slots_for(record, kind)
	if slots == null or slot_index < 0 or slot_index >= slots.size():
		return false
	var id_value: StringName = slots[slot_index]
	if id_value == &"":
		return false
	slots[slot_index] = &""
	armoury.add(id_value)
	_settle_equipment_slots(record)
	record.recompute_stats(catalogue)
	roster_changed.emit()
	return true


# A module can add equipment slots (the Utility Harness), so fitting or pulling
# one grows or shrinks the equipment row. What a shrink pushes out goes back to
# stores, never into thin air.
func _settle_equipment_slots(record: SoldierRecord) -> void:
	for pushed in record.fit_equipment_capacity(catalogue):
		armoury.add(pushed)


# A soldier who doesn't come home hands their kit back. This is the "modules are
# returned to you after they die" rule, and it's why modules are worth fitting
# to anyone rather than hoarding for your best unit.
func recover_kit(record: SoldierRecord) -> void:
	for id_value in record.all_fitted_ids():
		armoury.add(id_value)
	record.weapon_ids.fill(&"")
	record.equipment_ids.fill(&"")
	record.module_ids.fill(&"")
	record.recompute_stats(catalogue)
	roster_changed.emit()


# Fitting a soldier to a frame. Anything the smaller frame can't hold comes back
# to stores rather than vanishing.
func set_chassis(record: SoldierRecord, chassis: ChassisDefinition) -> bool:
	if record == null or chassis == null:
		return false
	if record.rank < chassis.required_rank:
		return false
	for displaced in record.set_chassis(chassis, catalogue):
		armoury.add(displaced)
	roster_changed.emit()
	return true


# Called once after the catalogue is available, since max_health is derived and
# a freshly loaded save has whatever was cached when it was written.
func recompute_roster() -> void:
	for r in roster:
		_settle_equipment_slots(r)
		r.recompute_stats(catalogue)
	if player_record != null:
		_settle_equipment_slots(player_record)
		player_record.recompute_stats(catalogue)
	roster_changed.emit()


## Whether `record` already carries `item` in any slot other than `slot_index`
## of the item's own kind — the one a fit is about to fill, where it would be a
## swap rather than a second copy.
func holds_elsewhere(record: SoldierRecord, item: ItemDefinition, slot_index: int) -> bool:
	if record == null or item == null:
		return false   # nothing to hold, or nothing held
	for kind in [ItemDefinition.Kind.WEAPON, ItemDefinition.Kind.EQUIPMENT, ItemDefinition.Kind.MODULE]:
		var slots := _slots_for(record, kind)
		for i in slots.size():
			if slots[i] == item.id and not (kind == item.kind and i == slot_index):
				return true
	return false


func _slots_for(record: SoldierRecord, kind: int) -> Array:
	match kind:
		ItemDefinition.Kind.WEAPON:
			return record.weapon_ids
		ItemDefinition.Kind.EQUIPMENT:
			return record.equipment_ids
		ItemDefinition.Kind.MODULE:
			return record.module_ids
	return []


# ─────────────────────────────────────────────
# SHOP
# Purchases are ALLOCATIONS, so selling is deleting an entry rather than a
# separate credit path. The key has to be unique per purchase, hence the counter.
# ─────────────────────────────────────────────
func buy_item(item: ItemDefinition) -> bool:
	if item == null or not can_afford(item.cost):
		return false
	var key := "item:%s:%d" % [item.id, _next_purchase()]
	# Quiet, then stock, then announce — see _allocate_quiet.
	if not _allocate_quiet(key, item.cost):
		return false
	armoury.add(item.id)
	ledger_changed.emit()
	return true


func buy_chassis(chassis: ChassisDefinition) -> bool:
	if chassis == null or not can_afford(chassis.cost):
		return false
	var key := "chassis:%s:%d" % [chassis.id, _next_purchase()]
	# Same ordering as buy_item: the chassis is in stores before anyone is told.
	if not _allocate_quiet(key, chassis.cost):
		return false
	armoury.add_chassis(chassis.id)
	ledger_changed.emit()
	return true


# Sell a spare. Clears the most recent purchase of that id — so a price change
# never leaves the ledger owing — but hands back only HALF of what was paid.
#
# The un-refunded half does not evaporate: it stays in the ledger under a
# "sold:" key that nothing ever refunds, exactly like a repair. Erasing the
# whole allocation would credit the full price back, and holding the loss
# anywhere else would be the second balance this system exists to avoid.
# available() is still earned - sum(allocations) and still cannot drift.
func sell_item(item: ItemDefinition) -> bool:
	if item == null or armoury.spare(item.id) <= 0:
		return false
	var newest := _newest_purchase_key("item:%s:" % item.id)

	# STARTING STOCK HAS NO ALLOCATION. Campaign.starting_stock puts items in the
	# armoury directly — they were issued, not bought — so there is no entry to
	# shrink. Refusing here meant none of the kit you begin the game with could
	# ever be sold, which is most of what is in stores on a fresh save.
	#
	# Selling those credits earned instead. That is sound: earned only ever goes
	# up, and it cannot be farmed, because anything you BUY gets an allocation
	# and therefore takes the branch below. There is no loop that ends with more
	# resources than it started with.
	if newest == "":
		if not armoury.take(item.id):
			return false
		award(sale_value(item.cost))
		return true

	if not armoury.take(item.id):
		return false
	var paid := int(allocations[newest])
	var kept := paid - sale_value(paid)
	# Mutate the ledger completely, THEN emit once. refund() emits on its own
	# and the squad manager rebuilds synchronously on ledger_changed, so it
	# would have read the ledger with the full price credited back and the
	# retained half not yet recorded — a one-frame flash of the wrong balance.
	allocations.erase(newest)
	if kept > 0:
		allocations["sold:%s:%d" % [item.id, _next_purchase()]] = kept
	ledger_changed.emit()
	return true


# What selling something bought for `paid` hands back. Integer division rounds
# the player down, so selling and re-buying is always a loss and never a way to
# launder resources.
func sale_value(paid: int) -> int:
	@warning_ignore("integer_division")
	return paid / 2


# What the player would get back for selling one spare right now. The UI needs
# the number before the sale to label the button honestly. Falls back to the
# catalogue price for issued stock, which has no purchase to look up — the same
# branch sell_item takes.
func sale_value_of(item: ItemDefinition) -> int:
	if item == null:
		return 0
	var newest := _newest_purchase_key("item:%s:" % item.id)
	if newest == "":
		return sale_value(item.cost)
	return sale_value(int(allocations[newest]))


# Highest-numbered purchase under a prefix. Compares the trailing counter
# NUMERICALLY: these keys were previously ordered with `>` on the whole string,
# which sorts "item:frag:9" above "item:frag:10" and picked the wrong
# allocation to refund as soon as the counter passed single digits.
func _newest_purchase_key(prefix: String) -> String:
	var best := ""
	var best_n := -1
	for key in allocations.keys():
		var s := String(key)
		if not s.begins_with(prefix):
			continue
		var n := int(s.substr(prefix.length()))
		if n > best_n:
			best_n = n
			best = s
	return best


@export var _purchase_counter: int = 0

func _next_purchase() -> int:
	_purchase_counter += 1
	return _purchase_counter


# ─────────────────────────────────────────────
# SAVE / LOAD
# ─────────────────────────────────────────────
# ─────────────────────────────────────────────
# MISSION CLEARS
# ─────────────────────────────────────────────
func clears_of(id: StringName) -> int:
	return int(mission_clears.get(String(id), 0))


func record_clear(id: StringName) -> void:
	var key := String(id)
	mission_clears[key] = int(mission_clears.get(key, 0)) + 1


func has_cleared(id: StringName) -> bool:
	return clears_of(id) > 0


func to_dict() -> Dictionary:
	var records: Array = []
	for r in roster:
		records.append(r.to_dict())
	var missions: Array = []
	for m in completed_missions:
		missions.append(String(m))
	var unlocks: Array = []
	for u in unlocked:
		unlocks.append(String(u))
	return {
		"version": SAVE_VERSION,
		"earned": earned,
		"allocations": allocations,
		"roster": records,
		"completed_missions": missions,
		"mission_clears": mission_clears.duplicate(),
		"completed_tutorial": completed_tutorial,
		"lessons_seen": lessons_seen.map(func(l): return String(l)),
		"campaign_won": campaign_won,
		"compute_earned": compute_earned,
		"compute_held": compute_held.duplicate(),
		"supply_cap": supply_cap,
		"compute_claimed": compute_claimed.duplicate(),
		"unlocked": unlocks,
		"selected_mission_id": String(selected_mission_id),
		"next_id": _next_id,
		"squad_name": squad_name,
		"profile_name": profile_name,
		"created_utc": created_utc,
		"last_played_utc": last_played_utc,
		"teams": teams.map(func(t: Dictionary) -> Dictionary:
			return {"id": String(t["id"]), "name": String(t["name"])}),
		"purchase_counter": _purchase_counter,
		"armoury": armoury.to_dict(),
		"player_record": player_record.to_dict(),
	}


static func from_dict(data: Dictionary) -> CampaignState:
	var s := CampaignState.new()
	s.earned = int(data.get("earned", 0))
	s.allocations = data.get("allocations", {})
	s._next_id = int(data.get("next_id", 1))
	s.squad_name = str(data.get("squad_name", "NAMELESS"))
	s.profile_name = str(data.get("profile_name", ""))
	s.created_utc = str(data.get("created_utc", ""))
	s.last_played_utc = str(data.get("last_played_utc", ""))
	# A save from before teams has none; ensure_teams builds them once the
	# catalogue can tell a vehicle.
	for entry in data.get("teams", []):
		if not (entry is Dictionary):
			continue   # not a team: a hand-edited save
		var id := StringName(str(entry.get("id", "")))
		var team_name_text := str(entry.get("name", "")).strip_edges().to_upper()
		if id != &"" and team_name_text != "" and not s.has_team(id):
			s.teams.append({"id": id, "name": team_name_text})
	s._purchase_counter = int(data.get("purchase_counter", 0))
	s.armoury = Armoury.from_dict(data.get("armoury", {}))
	if data.has("player_record"):
		s.player_record = SoldierRecord.from_dict(data["player_record"])
	s.selected_mission_id = StringName(str(data.get("selected_mission_id", "")))

	var records: Array[SoldierRecord] = []
	for entry in data.get("roster", []):
		records.append(SoldierRecord.from_dict(entry))
	s.roster = records

	var missions: Array[StringName] = []
	for m in data.get("completed_missions", []):
		missions.append(StringName(str(m)))
	s.completed_missions = missions

	# Rebuilt key by key rather than assigned wholesale: JSON hands back floats
	# for every number, and a float clear-count formats as "CLEARED x2.0".
	var clears: Dictionary = {}
	var raw_clears: Dictionary = data.get("mission_clears", {})
	for k in raw_clears:
		clears[str(k)] = int(raw_clears[k])
	s.mission_clears = clears
	s.completed_tutorial = bool(data.get("completed_tutorial", false))
	var lessons: Array[StringName] = []
	for l in data.get("lessons_seen", []):
		lessons.append(StringName(str(l)))
	s.lessons_seen = lessons
	s.campaign_won = bool(data.get("campaign_won", false))
	s.supply_cap = int(data.get("supply_cap", BASE_SEATS))
	# A save from before supply existed never benches anyone for it.
	var active := 0
	for r in s.roster:
		if not r.benched:
			active += 1
	s.supply_cap = maxi(s.supply_cap, active)
	if data.has("compute_earned"):
		s.compute_earned = int(data["compute_earned"])
		var held: Dictionary = {}
		var raw_held: Dictionary = data.get("compute_held", {})
		for k in raw_held:
			held[str(k)] = int(raw_held[k])
		s.compute_held = held
	else:
		# A save from when compute was a plain balance: what was left, plus a
		# seat held for every one bought above the starting four. Counted from
		# the cap the save RECORDED — a save from before seats existed has
		# none, and a cap raised above to seat everyone already active was
		# never bought, so it must not become compute you can take back.
		var bought := maxi(0, int(data["supply_cap"]) - BASE_SEATS) if data.has("supply_cap") else 0
		for i in bought:
			s.compute_held["seat:%d" % s._next_purchase()] = SUPPLY_COMPUTE_COST
		s.compute_earned = int(data.get("compute", 0)) + bought * SUPPLY_COMPUTE_COST
	var claimed: Array[String] = []
	for c in data.get("compute_claimed", []):
		claimed.append(str(c))
	s.compute_claimed = claimed

	var unlocks: Array[StringName] = []
	for u in data.get("unlocked", []):
		unlocks.append(_renamed(StringName(str(u))))
	s.unlocked = unlocks
	return s


# FRAMES THAT CHANGED NAME. A save holds ids as plain strings — what you have
# unlocked, what your squad killed — so renaming a frame in the project orphans
# both: the unlock stops matching and the career tally grows a second column
# under the new name. Old id -> new id, applied on the way in.
const RENAMED := {
	&"hopper": &"leaper",
}


static func _renamed(id: StringName) -> StringName:
	return RENAMED.get(id, id)


# Become the campaign this dictionary describes, WITHOUT becoming a different
# object. from_dict() builds a new CampaignState, and half the game is holding a
# reference to this one — the squad manager, the HUDs, every screen — so handing
# them a replacement would leave them wired to a state nobody updates. This
# parses through from_dict all the same and then moves the fields across, so
# there is exactly one place that knows how to read a save.
#
# `catalogue` deliberately stays: it is wiring, not campaign progress, and a
# freshly parsed state has none.
#
# Used by a failed run — see Campaign.extract(). If a field is ever added to
# to_dict() and not to this list, the run would quietly keep it across a
# rewind; test_endings covers that by round-tripping a state through here and
# comparing the dictionaries.
func restore_from(data: Dictionary) -> void:
	var was := CampaignState.from_dict(data)
	earned = was.earned
	allocations = was.allocations
	roster = was.roster
	completed_missions = was.completed_missions
	mission_clears = was.mission_clears
	completed_tutorial = was.completed_tutorial
	campaign_won = was.campaign_won
	compute_earned = was.compute_earned
	compute_held = was.compute_held
	compute_claimed = was.compute_claimed
	supply_cap = was.supply_cap
	unlocked = was.unlocked
	selected_mission_id = was.selected_mission_id
	squad_name = was.squad_name
	# WHICH CAMPAIGN THIS IS. Not progress, but it travels with the save and a
	# profile that forgot its own name on load would show up as "Campaign" in the
	# menu the next time it was listed.
	profile_name = was.profile_name
	created_utc = was.created_utc
	last_played_utc = was.last_played_utc
	teams = was.teams
	player_record = was.player_record
	armoury = was.armoury
	_next_id = was._next_id
	_purchase_counter = was._purchase_counter
	ledger_changed.emit()
	roster_changed.emit()


## Writes to `path`, or to wherever this campaign lives when none is given.
##
## The default used to be the one hardcoded SAVE_PATH, which is why there could
## only ever be one campaign: every caller in the project omits the argument.
## Routing the default through save_path means the slot is chosen ONCE, when the
## campaign is opened, and every existing call site follows it.
## A CAMPAIGN WITH NOWHERE TO LIVE IS NEVER WRITTEN.
##
## save_path is empty for the scratch campaign that stands behind the main menu
## before the player has chosen one. It used to fall back to SAVE_PATH here —
## and SAVE_PATH is user://campaign.json, the save the player may still be
## relying on. One roster change behind the menu was enough to overwrite a
## finished campaign with a brand new one. It did exactly that.
##
## Refusing is the only safe answer: there is no correct file to write a campaign
## that is not a profile to.
func save_to_disk(path: String = "") -> bool:
	if path == "":
		path = save_path
	if path == "":
		if not _no_path_said:
			_no_path_said = true
			push_warning("CampaignState: this campaign is not a profile and has nowhere to be saved, so it was not written. Start or load one from the menu.")
		return false
	# `-- --no-save` on the command line: a run that boots the real game to
	# look for errors (tools/smoke.sh) must never write the player's save. The
	# game saves on reaching base, so without this every smoke run did.
	if OS.get_cmdline_user_args().has("--no-save"):
		if not _no_save_said:
			print("[Campaign] --no-save: not writing %s this run." % path)
			_no_save_said = true
		return true
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("CampaignState: could not open %s for writing (%s)" % [
			path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return true


var _no_save_said: bool = false
var _no_path_said: bool = false


# Returns null when there's no save yet — the caller decides whether that means
# "new campaign" or "something is wrong".
## The save at `path` as a migrated dictionary, or empty when there is none.
##
## Split out of load_from_disk so a caller can restore_from() it INTO the state
## the game is already holding. See the note on restore_from: handing out a new
## object leaves every HUD and screen wired to one nobody updates.
static func load_dict(path: String = SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("CampaignState: could not read %s" % path)
		return {}
	var body := f.get_as_text()
	f.close()
	var got = JSON.parse_string(body)
	if typeof(got) != TYPE_DICTIONARY:
		push_error("CampaignState: save at %s is not valid JSON" % path)
		return {}
	return migrate(got)


static func load_from_disk(path: String = SAVE_PATH) -> CampaignState:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CampaignState: could not read %s" % path)
		return null
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CampaignState: save at %s is not valid JSON" % path)
		return null
	return from_dict(migrate(parsed))


# Every field read above already has a default, so a save written before a field
# existed loads cleanly. This is here for the changes defaults can't cover.
static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	if version > SAVE_VERSION:
		push_warning("CampaignState: save is version %d, this build reads %d." % [
			version, SAVE_VERSION])
	return data
