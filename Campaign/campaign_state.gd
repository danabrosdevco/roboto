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

## THE PRE-PROFILE SAVE, and NO CODE READS THIS ANY MORE — as of 2026-10-26 it
## is named here, printed by tools/probe_save_facts.gd, and nothing else. Saves
## live in user://saves/ one file per profile; the live path to the old single
## save is SaveSlots.LEGACY, which has its own copy of the string because it
## swaps in a sandbox for tool runs. Kept so the path a player's campaign may
## still be sitting at has a name. Deleting it is the tail of Backlog SV6.
const SAVE_PATH := "user://campaign.json"
# Bump when the shape changes. is_outdated() is all that reads it: a save from
# an older shape is REFUSED, not transformed — there is no migrate() and the
# note where it used to be says why.
#
# 2 — THE MARK SYSTEM, 2026-10-22. A robot's loadout stopped being something
# the player fitted one at a time and became what its production line builds,
# so a v1 save describes a game that no longer exists: robots carrying modules
# bought from a shop that is gone, on lines that have no mark. The human's
# call was that the change is big enough to drop them rather than invent a
# migration nobody can verify.
const SAVE_VERSION := 2

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
## CARRIED BY restore_from() like every other field, since 2026-10-26 — and it
## is still true that dying does not un-read something you were told on the way
## in the door. Nothing marks a lesson during a run: both markers fire at base
## (Campaign._is_base for the induction, LessonPrompts._on_home for the rest),
## which is after extract() has already rewound. So the rewind has nothing to
## roll back here, and what the list being carried actually fixes is a LOAD —
## it used to be left behind, so one profile's lessons read as seen in the
## next. See the note on restore_from().
@export var lessons_seen: Array[StringName] = []
## Set when the last operation is cleared. Opens every mission at the terminal
## for good, and the win is only announced the once.
@export var campaign_won: bool = false
## RETIRED (Phase 3.1). The unlock set IS the allocation key set now — see
## is_unlocked(). Kept only so a save written before the change can be read
## and migrated in from_dict; nothing else should ever touch it.
@export var unlocked: Array[StringName] = []

# ── PRODUCTION LINES ──────────────────────────
# What each chassis line BUILDS, rather than what any one robot carries. See
# docs/briefs/archive/MARK_SYSTEM_SPEC.md.
#
# DELIBERATELY NOT A SECOND HOME FOR "IS THE LINE OPEN". That is
# is_unlocked(), which reads allocations[unlock_key(id)] and is what
# unlock_chassis() writes. Two places storing the same fact is how they start
# disagreeing.
#
## chassis id -> mark level. Absent means Mk 0, which every open line is.
@export var line_marks: Dictionary = {}
## chassis id -> the one module adopted for that line. Absent means none.
@export var line_modules: Dictionary = {}
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
## The gun you are issued and cannot lose. It is the cost-0 entry in
## Campaign/software_tree.gd's CARRY list, named again here because this file
## must not preload the tree (the tree types its parameters as CampaignState).
## test_memory_screen.gd asserts the two agree.
const ISSUED_WEAPON_ID := &"m4"

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
##
## EMPTY BY DEFAULT, AND THAT IS THE SAFE ANSWER. It defaulted to SAVE_PATH —
## user://campaign.json, the save a player may still be playing — so every bare
## CampaignState.new() in the project came into the world pointed at it, and
## saving one wrote over a real campaign. It did exactly that once. Only
## Campaign._ready blanked it, which covers the game and not the forty tools
## and suites that build a state directly. A campaign with nowhere to live is
## never written (see save_to_disk), so the only cost of this default is that
## something meaning to write must say where. Backlog SV2.
var save_path: String = ""

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
## Preloaded, not referenced as `Pricing`: a new `class_name` is not visible
## to another script until the editor rescans and this project cannot run
## --import. Same trap as Location and CoreSignal.
const _Pricing := preload("res://Campaign/pricing.gd")

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
# TERRITORY — what turn it is and what you hold.
#
# docs/briefs/CAMPAIGN_REWORK.md Phases 1 and 2. The whole rework rests on
# this: today the only way to get paid is to run an operation, so clearing the
# board is worth more than owning it and "holding territory" means nothing.
# A site pays EVERY TURN you hold it, whether or not you went near it.
#
# OWNERSHIP CANNOT BE DERIVED FROM completed_missions, and this file already
# said so before any of this existed — "completed_missions only answers 'ever',
# which is not enough". A site you took in Act 1 and lost in Act 2 is still in
# that array forever. Do not try.
# ─────────────────────────────────────────────

## WHICH TURN IT IS. A turn IS an operation (§5), so this moves when one ends,
## not on a clock.
@export var turn: int = 0

## WHO HOLDS WHAT: location id -> { "owner": int, "since_turn": int }.
##
## A DICTIONARY, NOT A SET OF HELD IDS. A set can only answer "mine or not",
## and §3 needs four answers — yours, Home Command's, the Swarm's, nobody's —
## because the thing you take a site from changes across the three acts.
## `since_turn` is what closes §5's farming hole: it is how the campaign can
## tell a site you have held for ten turns from one you retook this turn.
##
## `owner` is an Enums.Factions value. NOT an enum of its own: PLAYER, SWARM,
## HOME and ARGUS already exist there and already mean exactly this.
@export var sites: Dictionary = {}

## WHICH SITE IS UNDER ATTACK RIGHT NOW, and waiting on an answer.
##
## Phase 6. When the other side's raid is too close to call, the site does NOT
## change hands — the player is offered the defence instead. This is what the
## operations table reads to mark it and put a DEFEND option on it.
##
## Empty means nothing is pending. It clears when the defence is played or
## when it is settled on paper.
@export var under_attack: StringName = &""

## The turn the raid landed. A pending defence that is never answered settles
## itself the next time the player does anything — see Campaign.extract — and
## this is how that is noticed.
@export var under_attack_turn: int = -1

## Resolved at runtime by CampaignManager, like `catalogue`; not saved.
## Typed Resource, not LocationCatalogue: a new `class_name` is not visible to
## another script until the editor rescans and this project cannot run
## --import, so naming the type fails the parse check. Same trap as Location.
var locations: Resource

## The turn moved. The board, the readouts and anything paying attention to
## time hang off this.
signal turn_advanced(turn: int)
## Somebody took or lost ground.
signal sites_changed


# ─────────────────────────────────────────────
# TERRITORY — reading it
# ─────────────────────────────────────────────

## Who holds a place. Falls back to the location's authored `start_owner`, so a
## campaign that has never touched a site still knows whose it is — and a save
## written before this existed reads correctly without a migration.
func site_owner(id: StringName) -> int:
	var row = sites.get(String(id))
	if row != null:
		return int(row.get("owner", Enums.Factions.SWARM))
	var l = locations.of(id) if locations != null else null
	return int(l.start_owner) if l != null else int(Enums.Factions.SWARM)


func holds(id: StringName) -> bool:
	return site_owner(id) == int(Enums.Factions.PLAYER)


## Which turn the current owner took it. -1 for a place nobody has touched.
func site_since(id: StringName) -> int:
	var row = sites.get(String(id))
	return int(row.get("since_turn", -1)) if row != null else -1


## Every location id you hold. Walks the CATALOGUE, not `sites` — a place you
## hold because it was authored yours has no row until something changes it.
func held_sites() -> Array[StringName]:
	var out: Array[StringName] = []
	if locations == null:
		push_warning("CampaignState: no LocationCatalogue, so the campaign cannot tell what you hold and income will be zero.")
		return out
	for l in locations.all():
		if site_owner(l.id) == int(Enums.Factions.PLAYER):
			out.append(l.id)
	return out


## What holding pays per turn. This is the economy (§2) — the board already
## prints a figure and today it is `one_off × 0.1`, which is advertising income
## the game does not pay.
func income_per_turn() -> int:
	var total := 0
	if locations == null:
		return total   # already warned by held_sites; a silent 0 here would be the bug
	for id in held_sites():
		var l = locations.of(id)
		if l != null:
			total += int(l.resources_per_turn)
	return total


## COMPUTE FROM GROUND, all or nothing.
##
## Not added to `compute_earned` on capture and subtracted on loss — derived,
## so losing a site CANNOT leave a stale credit behind. That matters because
## compute is the supply cap: a site lost while its compute is spent should put
## you OVER your cap, and §2 says so deliberately. Add-and-subtract gets that
## right only until one path forgets to subtract.
func site_compute() -> int:
	var total := 0
	if locations == null:
		return total   # already warned by held_sites
	for id in held_sites():
		var l = locations.of(id)
		if l != null:
			total += int(l.compute)
	return total


# ─────────────────────────────────────────────
# TERRITORY — changing it
# ─────────────────────────────────────────────

## THE ONLY PLACE OWNERSHIP MOVES. Every capture, every loss, every act
## handover goes through here so `since_turn` cannot drift out of step with
## `owner` and so one signal covers all of it.
func set_site_owner(id: StringName, owner: int) -> void:
	if id == &"":
		push_warning("CampaignState: asked to set the owner of a blank site id; ignored.")
		return
	if site_owner(id) == owner and sites.has(String(id)):
		return   # already theirs and already recorded; nothing moved
	sites[String(id)] = {"owner": int(owner), "since_turn": turn}
	sites_changed.emit()
	# Compute is derived from what you hold, so taking or losing ground changes
	# the ledger even though nothing was spent.
	ledger_changed.emit()


## THE SINGLE MUTATION POINT FOR TIME (Phase 1.3).
##
## IT DOES NOT PAY. Income used to be collected right here, and because this
## is called early in extract() that put the pay BEFORE the site changed
## hands — so a place you had just taken started paying on the *next*
## operation. The comment that used to sit here argued for it ("holding a site
## for three turns pays three times", which it does either way).
##
## Decided 2026-10-23: income is what you hold AFTER the mission. extract()
## therefore calls pay_income() itself, once the ground has moved. If you add
## another caller that advances time, call pay_income() too or that turn pays
## nobody. Backlog K17.
func advance_turn() -> void:
	turn += 1
	turn_advanced.emit(turn)


## PAYS EVERY HELD SITE FOR ONE TURN, and returns what it paid.
##
## Returns the figure rather than leaving the caller to ask income_per_turn()
## again, because between the two reads a site can change hands and the
## debrief would report a number nobody was paid.
func pay_income() -> int:
	var paid := income_per_turn()
	if paid > 0:
		award(paid)
	return paid


# ─────────────────────────────────────────────
# NO SHOPPING IN THE FIELD
#
# TAB opens the squad manager mid-mission, and the Factory never asked whether
# we were out there — so you could build a robot, open a production line, adopt
# a mark or a module, install a program or buy a seat from inside a firefight.
#
# A GATE THAT EXISTS ONLY IN THE UI IS NOT A GATE (recruit()'s own words).
# Greying the buttons leaves every one of these callable, and the Factory is
# not the only caller. So the refusal lives here, at the bottom, where
# everything has to come through it. Backlog K12.
#
# NOT SAVED AND NOT RESTORED, deliberately. It is a fact about this session,
# not about the campaign: it is absent from to_dict()/from_dict(), so a save
# can never come back from disk stuck in the field, and absent from
# restore_from(), so the rewind cannot reach in and change where we are.
# Campaign owns it — set in begin_deploy(), cleared in extract().
# ─────────────────────────────────────────────

## True between begin_deploy() and extract(). See the block above.
var in_field: bool = false


## Refuses a purchase that is being attempted mid-mission, and says so.
##
## Warns rather than failing quietly, because a spending function that returns
## false for no stated reason is indistinguishable from one that cannot afford
## it — and the UI plays the same "denied" sound for both.
func _refuse_in_field(what: String) -> bool:
	if not in_field:
		return false
	push_warning("CampaignState: refused %s — no purchases in the field (Backlog K12)." % what)
	return true


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




# ─────────────────────────────────────────────
# UNLOCKS — pay once to open a line, then pay per copy.
#
# Appendix A in full. The mechanism is one line, because the ledger was built
# for exactly this: allocations are keyed by an ARBITRARY STRING, so
#
#   allocate("unlock:cluster_launcher", 200)
#
# IS the unlock, and "is it open?" is `allocations.has("unlock:...")`.
#
# NO NEW PERSISTED FIELD. No second balance to drift, no migration for the cost
# side, and a price changed in a patch recomputes correctly on every existing
# save — which is the property the ledger was built for.
#
# IT ALSO RETIRES `unlocked`. The flat array of granted ids is redundant: the
# allocation key set IS the unlock set. Anything still asking the old question
# should ask is_unlocked().
#
# AN UNLOCK IS CAPITAL, NOT SPENDING (A.2). It sits in `allocations` forever
# and is never refunded, so it permanently lowers `available()` — which is the
# honest reading: you converted resources into a capability you still have.
# ─────────────────────────────────────────────

## The ledger key for a line. One place, because a typo here is an unlock that
## silently never registers.
static func unlock_key(id: StringName) -> String:
	return "unlock:%s" % id


## Is this line open? Takes an id so it works for frames and kit alike.
##
## AN ISSUED LINE IS OPEN WITHOUT AN ALLOCATION. The Ancient Rifle costs 0 to
## unlock, and a zero-cost allocation written at campaign start would be a
## thing to remember to write — on every new campaign, every migration, every
## test fixture. Deriving it from the band means it cannot be forgotten.
func is_unlocked(id: StringName) -> bool:
	if allocations.has(unlock_key(id)):
		return true
	if catalogue == null:
		return false   # nothing to ask about the band; caller gets the strict answer
	var item := catalogue.item(id)
	if item != null:
		return _Pricing.band_of(item) == _Pricing.ISSUED
	return false


## Open a line for free: the starting kit, a debug grant, and the migration of
## a save written when `unlocked` was an array.
##
## A ZERO-COST ALLOCATION, not a special case. It is in the same dictionary as
## a paid one and answers the same question, so nothing downstream needs to
## know the difference — which is the point of keying the ledger by string.
func grant_unlock(id: StringName) -> void:
	if id == &"":
		push_warning("CampaignState: asked to grant a blank unlock id; ignored.")
		return
	if allocations.has(unlock_key(id)):
		return
	allocations[unlock_key(id)] = 0
	ledger_changed.emit()


## Buy the line. Returns false if it is already open, unaffordable, or the
## thing is not for sale at all.
func unlock_item(item: ItemDefinition) -> bool:
	if item == null:
		return false
	if _refuse_in_field("opening the line for %s" % item.id):
		return false
	if not _Pricing.for_sale(item):
		return false   # UNBUYABLE or cut; the catalogue should not have offered it
	if is_unlocked(item.id):
		return false   # already open; not an error, just nothing to do
	if not unlock_requirements_met(item):
		return false
	return allocate(unlock_key(item.id), _Pricing.item_unlock(item))


func unlock_chassis(frame: ChassisDefinition) -> bool:
	if frame == null:
		return false
	if _refuse_in_field("opening the line for %s" % frame.id):
		return false
	if not _Pricing.chassis_for_sale(frame):
		return false
	if is_unlocked(frame.id):
		return false
	if not unlock_requirements_met(frame):
		return false
	return allocate(unlock_key(frame.id), _Pricing.chassis_unlock(frame))


## THE MARK ONE → MARK TWO CHAINS. A line can name lines that must be open
## before it can be. Everything with no prerequisites answers true, which is
## almost everything.
func unlock_requirements_met(def) -> bool:
	if def == null or not ("unlock_requires" in def):
		return true
	for req in def.unlock_requires:
		if not is_unlocked(req):
			return false
	return true


## Which prerequisites are still missing, for the catalogue line that has to
## say WHY it cannot be bought.
func missing_unlock_requirements(def) -> Array[StringName]:
	var out: Array[StringName] = []
	if def == null or not ("unlock_requires" in def):
		return out
	for req in def.unlock_requires:
		if not is_unlocked(req):
			out.append(req)
	return out


## THE FOUR LINE STATES the fabrication car draws (Phase 3.5). One function so
## the catalogue and anything else asking agree, rather than each re-deriving
## it from three separate questions.
enum Line {
	OPEN,        ## already yours; buy copies at the normal price
	AFFORDABLE,  ## can be opened right now
	SHORT,       ## wants more resources than you have
	BLOCKED,     ## a prerequisite line is not open yet
}


func line_state(def) -> Line:
	if def == null:
		return Line.BLOCKED
	if is_unlocked(def.id):
		return Line.OPEN
	if not unlock_requirements_met(def):
		return Line.BLOCKED
	var price: int = _unlock_price(def)
	return Line.AFFORDABLE if can_afford(price) else Line.SHORT


## What opening this costs, frame or kit. The catalogue holds both in one list
## and should not have to know which it is holding.
func _unlock_price(def) -> int:
	if def is ChassisDefinition:
		return _Pricing.chassis_unlock(def)
	return _Pricing.item_unlock(def)

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


## ALL THE COMPUTE YOU HAVE: what was awarded, plus the compute of every
## Location you hold.
##
## THE SECOND TERM IS THE WHOLE CAMPAIGN NOW. As of 2026-10-26 nothing else
## adds to `compute_earned` after the seed — first clears stopped paying
## (K11b), so `compute_earned` is `starting_compute` and debug handouts, and
## everything else you have is ground you are holding this minute.
##
## Anything measuring "how far along is this campaign" must read THIS, not
## `compute_earned`, or it reads 2 forever. force_generator.garrison_supply()
## is the one that matters: it is the entire difficulty curve of every
## defence, and it used to ride on first-clear compute.
func compute_total() -> int:
	return compute_earned + site_compute()


## WHAT IS LEFT TO SPEND: everything you have, minus what seats and software
## are holding.
##
## site_compute() had no caller at all until 2026-10-26 — this was
## `compute_earned − held`, so `Location.compute`, 12 across the whole board,
## was credited to nobody (Backlog K11).
##
## DERIVED, not banked — see site_compute(). **Losing a site takes its compute
## back**, which is the rule the human set on 2026-10-26: lose the location,
## lose the compute. That can leave the ledger over-allocated, which is
## intended; over_allocated_by() is the debt they have to clear before they can
## deploy again, and it is reachable in ordinary play now rather than only
## after a requisition nothing performs.
func compute_free() -> int:
	var held := 0
	for amount in compute_held.values():
		held += int(amount)
	return compute_total() - held


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


## ─────────────────────────────────────────────
## NOTHING CLAIMS COMPUTE ANY MORE, and that is the point of the gate going
## quiet rather than away.
##
## This was the once-per-campaign ratchet for the two one-off compute sources:
## an op's first clear ("clear:<op>") and a hidden objective
## ("<op>:<objective>"). Objectives stopped paying on 2026-10-23 (K9) and
## first clears on 2026-10-26 (K11b), so **it has no caller in the game**.
##
## KEPT, with its save field, for two reasons. `compute_claimed` is in
## `to_dict()`, so dropping it is a save-format change for a list that costs
## nothing to carry; and existing saves have entries in it. If a capture bonus
## is ever reinstated, this is the thing that stops a replay farming it.
##
## `clear_compute_paid()` below has had no caller for longer still.
## ─────────────────────────────────────────────

## Marks `key` as paid and returns `amount`, or 0 if it was paid before. The
## caller adds the total with award_compute(), which announces it once.
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
	if _refuse_in_field("buying a seat"):
		return false
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
	# Giving a seat back is not a purchase, but it is still the squad's shape
	# changing while the squad is standing in it — and it frees compute, which
	# is the currency the rest of this gate protects.
	if _refuse_in_field("giving a seat back"):
		return false
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
	if _refuse_in_field("installing %s" % id):
		return false
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
	# Uninstalling is not spending, it is the refund — and refund_supply() is
	# gated for exactly the same reason: it frees compute, which is the currency
	# the rest of this gate protects, and it changes what the player is carrying
	# while they are out there carrying it. K12 gated the seat refund and missed
	# this one; found closing K32, 2026-10-26.
	#
	# NO DEADLOCK WITH THE OVER-ALLOCATION GATE. Losing a site can leave the
	# ledger under and mission_exit refuses to deploy until it is cleared — but
	# that check runs BEFORE begin_deploy(), so `in_field` is still false and
	# freeing compute at base is exactly as available as it ever was.
	if _refuse_in_field("uninstalling %s" % id):
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


# ── MEMORY: WHAT YOU CARRY ────────────────────
# NONE OF THIS IS AN ARMOURY TRANSACTION. What is loaded in memory is a
# program, not a copy sitting in stores, so carrying your own weapon takes
# nothing out of the pool and putting it down returns nothing to it. That is
# the whole difference between these and fit_item() above, and mixing them up
# would print free copies of every gun you ever carried.
#
# THE GATE IS THE TREE'S, NOT THESE. Whether an item may be carried at all,
# and whether it is loaded, is Campaign/software_tree.gd's business; these
# refuse what physically cannot go in the slot and nothing else. Call
# SoftwareTree.load_item()/unload_item() rather than reaching past them.

## Put `item` in the player's one weapon slot. Refuses anything that has no
## player implementation, because a gun with no HUDWeapon leaves you holding
## nothing at all.
func carry_weapon(item: ItemDefinition) -> bool:
	if player_record == null or item == null:
		return false
	if item.kind != ItemDefinition.Kind.WEAPON or not item.fits_player():
		push_warning("CampaignState.carry_weapon: %s is not a weapon the player can hold." % item.id)
		return false
	if player_record.weapon_ids.is_empty():
		push_warning("CampaignState.carry_weapon: the player's frame has no weapon slot.")
		return false
	player_record.weapon_ids[0] = item.id
	player_record.recompute_stats(catalogue)
	roster_changed.emit()
	return true


## Put `item` in one of the player's equipment slots. `slot_index` of -1 takes
## the first empty one, which is what a CARRY button on a card means; a full
## row refuses rather than picking something to throw away for you.
func carry_equipment(item: ItemDefinition, slot_index: int = -1) -> bool:
	if player_record == null or item == null:
		return false
	if item.kind != ItemDefinition.Kind.EQUIPMENT or not item.fits_player():
		push_warning("CampaignState.carry_equipment: %s is not equipment the player can carry." % item.id)
		return false
	var slots: Array = player_record.equipment_ids
	if slot_index < 0:
		slot_index = slots.find(&"")
		if slot_index < 0:
			return false   # every slot full: the page says so, this does not guess
	if slot_index >= slots.size():
		return false
	if slots.has(item.id):
		return false   # two of the same charge is one slot wasted, not two
	slots[slot_index] = item.id
	player_record.recompute_stats(catalogue)
	roster_changed.emit()
	return true


func drop_equipment(slot_index: int) -> bool:
	if player_record == null or slot_index < 0 or slot_index >= player_record.equipment_ids.size():
		return false
	if player_record.equipment_ids[slot_index] == &"":
		return false
	player_record.equipment_ids[slot_index] = &""
	player_record.recompute_stats(catalogue)
	roster_changed.emit()
	return true


## Take `item_id` out of the player's hands wherever it is — what unloading it
## from memory has to do. A weapon slot left empty falls back to the issued
## rifle: you are never unarmed by a click on this screen.
func drop_player_item(item_id: StringName) -> int:
	if player_record == null or item_id == &"":
		return 0
	var dropped := 0
	for i in player_record.weapon_ids.size():
		if player_record.weapon_ids[i] == item_id:
			player_record.weapon_ids[i] = ISSUED_WEAPON_ID if i == 0 else &""
			dropped += 1
	for i in player_record.equipment_ids.size():
		if player_record.equipment_ids[i] == item_id:
			player_record.equipment_ids[i] = &""
			dropped += 1
	if dropped > 0:
		player_record.recompute_stats(catalogue)
		roster_changed.emit()
	return dropped


# ── RECRUITMENT ───────────────────────────────
## A new robot, born in `chassis`, for the frame's cost. It joins the active
## squad if there is supply for it and the bench if not — buying is never
## blocked by supply, only fielding is. A Soldier comes with its frame's
## starting weapon (a pistol) and otherwise empty slots; a Chaser or Hopper
## fights with what it was built with. Returns the new record, or null if it
## could not be paid for.
# ─────────────────────────────────────────────
# PRODUCTION LINES
# ─────────────────────────────────────────────

## What mark this line currently builds. Clamped to what the frame authors, so
## a save naming a mark a retuned chassis no longer has cannot ask for it.
func mark_of(chassis_id: StringName) -> int:
	var n := int(line_marks.get(chassis_id, 0))
	if catalogue == null:
		return maxi(0, n)
	var frame := catalogue.chassis_def(chassis_id)
	return clampi(n, 0, frame.top_mark() if frame != null else 0)


## The module adopted for this line, or &"" for none.
func module_of(chassis_id: StringName) -> StringName:
	return StringName(line_modules.get(chassis_id, &""))


## Allocation keys. Separate per mark so advancing twice is two purchases and
## the ledger can tell them apart; one for the module because there is one.
static func mark_key(id: StringName, n: int) -> String:
	return "mark:%s:%d" % [id, n]
static func module_key(id: StringName) -> String:
	return "module:%s" % id


## ADVANCE A LINE BY ONE MARK.
##
## ONE AT A TIME, deliberately. Jumping straight to Mk 2 would skip Mk 1's
## allocation and leave the ledger describing a line that was never advanced —
## and "pay for each tier" is also what makes the rail a progression rather
## than a menu.
func adopt_mark(frame: ChassisDefinition) -> bool:
	if frame == null or not frame.purchasable:
		return false
	if _refuse_in_field("adopting a mark on the %s line" % frame.id):
		return false
	# THE LINE HAS TO BE OPEN. Same gate recruit() answers to: a line nobody
	# has paid to open cannot be advanced past the spec it does not build.
	if not is_unlocked(frame.id):
		return false
	var next := mark_of(frame.id) + 1
	if next > frame.top_mark():
		return false   # nothing authored above this
	var cost := _Pricing.mark_buy(frame, next)
	if not _allocate_quiet(mark_key(frame.id, next), cost):
		return false
	line_marks[frame.id] = next
	apply_line_spec(frame.id)
	ledger_changed.emit()
	return true


## ADOPT THIS LINE'S ONE MODULE.
##
## IRREVERSIBLE, AND THE ONLY IRREVERSIBLE THING HERE. A line has one keystone
## and choosing it is the single build decision the system asks for; letting it
## be swapped would make it a loadout slot again, which is the whole thing this
## replaced.
func adopt_module(frame: ChassisDefinition, item: ItemDefinition) -> bool:
	if frame == null or item == null or not frame.purchasable:
		return false
	if _refuse_in_field("fitting %s to the %s line" % [item.id, frame.id]):
		return false
	if not is_unlocked(frame.id):
		return false
	if module_of(frame.id) != &"":
		return false   # already chosen, and it does not change
	if item.kind != ItemDefinition.Kind.MODULE:
		return false
	# ELIGIBILITY IS THE FRAME'S ANSWER, NOT A COPY OF IT. takes() already
	# refuses a module whose fits_vehicles is false on anything that drives,
	# which is what makes Overclock Servos and Nanite Reboot legs-only. A
	# second rule here would be a second rule to keep in step.
	if not frame.takes(item):
		return false
	# A MODULE IS STILL A THING THAT HAD TO BE RESEARCHED. The line being open
	# buys the frame, not every module that could go on it.
	if not is_unlocked(item.id):
		return false
	var cost := _Pricing.module_buy(frame)
	if not _allocate_quiet(module_key(frame.id), cost):
		return false
	line_modules[frame.id] = item.id
	apply_line_spec(frame.id)
	ledger_changed.emit()
	return true


## Which modules this line could adopt.
##
## WHAT THE FRAME CAN TAKE, AND NOTHING ELSE. An earlier cut returned
## everything and let the Factory grey out the rest with a reason, on the
## theory that a Rover driver should learn Overclock Servos exist. In practice
## that is five dead cards in a row of seven, and a module a frame can NEVER
## take is not a thing the player is deciding about — it is noise wearing the
## costume of a choice.
##
## STILL INCLUDES THE UNRESEARCHED ONES, which are a different thing: those a
## frame CAN take and the player has not bought yet, so they are the goal
## rather than the noise. The Factory shows them with their price.
func modules_for(frame: ChassisDefinition) -> Array[ItemDefinition]:
	var out: Array[ItemDefinition] = []
	if frame == null or catalogue == null:
		return out
	for item in catalogue.items_of_kind(ItemDefinition.Kind.MODULE):
		if item != null and _Pricing.for_sale(item) and frame.takes(item):
			out.append(item)
	return out


## EVERY ROBOT ON THIS LINE BECOMES WHAT THE LINE NOW BUILDS.
##
## The one function all three line operations share — adopting a mark,
## adopting a module, and building a new unit all end here. Returns how many
## records it rewrote.
##
## A BULK WRITE, NOT A DERIVED READ. The spec's §1 explains why at length: 11
## production files read weapon_ids / equipment_ids / module_ids and 12 suites
## assert on them, seven of those being chassis suites that build their
## fixtures by writing loadout ids directly. Keeping the arrays as storage and
## overwriting them here leaves every one of those untouched.
##
## BENCHED AND DESTROYED RECORDS TOO. A line revision is the factory changing
## what it turns out, not a quartermaster walking round the ones on parade —
## skipping the bench would mean a robot's spec depended on where it happened
## to be standing when you paid.
##
## WHAT WAS FITTED IS NOT RETURNED TO STORES. Checked rather than assumed: the
## ledger invariant is available() == earned - sum(allocations), which is about
## money and not inventory, so overwriting these cannot unbalance it.
func apply_line_spec(chassis_id: StringName) -> int:
	if catalogue == null:
		push_warning("CampaignState: no catalogue, so line '%s' cannot be applied and its robots keep whatever they had." % String(chassis_id))
		return 0
	var frame := catalogue.chassis_def(chassis_id)
	if frame == null:
		push_warning("CampaignState: no chassis '%s' in the catalogue, so its line cannot be applied." % String(chassis_id))
		return 0
	var spec = frame.mark_spec(mark_of(chassis_id))
	if spec == null:
		push_warning("CampaignState: chassis '%s' has no spec at mark %d, so its robots keep whatever they had." % [String(chassis_id), mark_of(chassis_id)])
		return 0

	var module := module_of(chassis_id)
	var n := 0
	for r in roster:
		if r == null or r.chassis_id != chassis_id:
			continue
		# SIZED TO THE FRAME, not to the spec. A mark that overruns its mounts
		# is an authoring error probe_chassis_marks already fails on; this
		# clamps rather than growing a robot a mount it does not have.
		# BEFORE the arrays, because recompute_stats below reads it.
		r.mark_level = mark_of(chassis_id)
		r.weapon_ids = _sized(spec.weapon_ids, frame.weapon_slots)
		r.equipment_ids = _sized(spec.equipment_ids, frame.equipment_slots)
		r.module_ids = _sized([module] if module != &"" else [], maxi(1, frame.module_slots))
		r.fit_equipment_capacity(catalogue)
		r.recompute_stats(catalogue)
		n += 1
	if n > 0:
		roster_changed.emit()
	return n


## `ids` padded or truncated to exactly `slots`, so a record's arrays always
## match its frame no matter what a mark asked for.
func _sized(ids: Array, slots: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in maxi(0, slots):
		out.append(StringName(ids[i]) if i < ids.size() else &"")
	return out


func recruit(chassis: ChassisDefinition) -> SoldierRecord:
	if chassis == null or not chassis.purchasable:
		return null
	if _refuse_in_field("building a %s" % chassis.id):
		return null
	# THE LINE HAS TO BE OPEN FIRST (Phase 3). The factory draws its BUILD
	# button from line_state(), and a gate that exists only in the UI is not a
	# gate — anything else calling recruit() would walk straight past it.
	if not is_unlocked(chassis.id):
		return null
	var record := SoldierRecord.new()
	record.id = mint_id()
	if not _allocate_quiet("unit:%s" % record.id, _Pricing.chassis_buy(chassis)):
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
	# IT ARRIVES AT WHAT THE LINE BUILDS. Appended first so apply_line_spec
	# sees it; at Mk 0 this writes back the same main gun the block above just
	# issued, which is why that block stays rather than being replaced — it is
	# what Mk 0 is synthesised FROM.
	if mark_of(chassis.id) > 0 or module_of(chassis.id) != &"":
		apply_line_spec(chassis.id)
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
	# PAID REPAIR IS A BASE ACTION. This writes a `repair:` allocation, so it is
	# spending by the same definition as everything else K12 refuses, and it was
	# missed there; found closing K32, 2026-10-26. The field has its own repair
	# and it is a different thing entirely — the Mechanic's tool goes through
	# apply_healing(), which costs nothing and is not touched here. Survivors are
	# mended free at extraction by heal_survivors().
	if _refuse_in_field("rebuilding %s" % record.display_name):
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


# THERE IS NO repair_all(). It was "kept for debug and for a future between-
# campaigns reset", had no caller anywhere in the game, in tools/ or as a
# [connection], and did strictly less than heal_survivors() above — which runs
# the same loop and covers player_record as well. Deleted rather than kept for
# a hypothetical caller, because a second function doing nearly the job of a
# live one is how the two stop matching. Backlog SQ3.


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
# THE KIT HALF PAYS NOTHING IN THE SHIPPED GAME, and has not since the shops
# went on 2026-10-22. It needs an `item:<id>:<n>` allocation; only buy_item()
# writes one; nothing in the UI calls buy_item(). So in practice a wreck is
# worth a third of its frame and that is all — the rule below is intact, there
# is simply nothing for it to find. Left standing rather than cut, because it
# is the shop's transaction shape and the shop's removal is its own open
# question (Backlog S7). The SCRAP button no longer advertises it: see
# scrap_kit_value(). Backlog S8.
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
	total += scrap_kit_value(record)
	return total


## The KIT half of scrap_value, on its own, so a button can say which part of
## the payout it is offering.
##
## IT IS 0 IN THE SHIPPED GAME and the SCRAP tooltip used to promise it anyway:
## "a third of the frame and half of everything fitted to it". Paying for kit
## needs an `item:<id>:<n>` allocation, only buy_item() writes one, and nothing
## in the UI has called buy_item() since the shops went (2026-10-22 — see the
## header of squad_manager_ui.gd). So every fitted item on every wreck takes
## _kit_payout's "issued with the frame" branch and the player was told about
## a payout that could not arrive. Backlog S8.
##
## DERIVED, NOT ASSUMED ZERO. _kit_payout is a live mechanism and the shop may
## come back; the tooltip now reads this number rather than restating a rule,
## so it goes on being true either way.
func scrap_kit_value(record: SoldierRecord) -> int:
	var total := 0
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
	# PRICED NOW, not when it was built. A frame with no allocation was issued
	# rather than bought (the starting roster), and what it is worth is what one
	# costs today — which is the whole point of pricing from a table.
	return _Pricing.chassis_buy(frame) if frame != null else 0


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
	if _refuse_in_field("scrapping %s" % record.display_name):
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


# THERE IS NO remove_destroyed(). It swept every DESTROYED record off the
# roster in one go and returned them, and nothing has ever called it. A wreck
# leaves the roster one way: the player scraps it, through scrap_soldier()
# above, which is a decision with a payout attached. A silent bulk sweep is the
# opposite of that, and having it sitting here invited one. Backlog SQ3.


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
	# RANK NO LONGER GATES KIT (Phase 3.7). Rank gating and purchase gating
	# were two answers to the same question — "can this robot have this yet" —
	# and the catalogue is the one that stays. Rank still exists and still
	# means something for stats; it just does not lock anything.
	#
	# A SECOND `return false` SAT HERE, over-indented, left behind when that
	# gate's `if` was deleted and its comment was not. GDScript read it as a
	# second statement inside the `armoury.spare(...)` block above, so it
	# parsed, never ran, and looked for all the world like a condition. It did
	# nothing and is gone. Backlog SQ3.
	#
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


# THERE IS NO CampaignState.set_chassis() — SO THERE IS NO REFIT. It put an
# existing robot on a different frame, returning anything the smaller frame
# could not hold to stores, and nothing has ever called it: a frame is chosen
# when the robot is built and never again. That is worth knowing rather than
# discovering, because it is why `mark_level` travelling WITH a robot instead
# of with its production line is unreachable today.
#
# SoldierRecord.set_chassis() is a different function and is very much alive —
# recruit() and buy_chassis() both go through it. Backlog SQ3.


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
	if item == null:
		return false
	if _refuse_in_field("buying %s" % item.id):
		return false
	# THE LINE HAS TO BE OPEN FIRST. Pay once to make a thing available, then
	# pay per copy — Appendix A. A catalogue that offered a locked item would
	# be offering something this refuses, so the two must agree.
	if not is_unlocked(item.id):
		return false
	var price: int = _Pricing.item_buy(item)
	if not can_afford(price):
		return false
	var key := "item:%s:%d" % [item.id, _next_purchase()]
	# Quiet, then stock, then announce — see _allocate_quiet.
	if not _allocate_quiet(key, price):
		return false
	armoury.add(item.id)
	ledger_changed.emit()
	return true


func buy_chassis(chassis: ChassisDefinition) -> bool:
	if chassis == null:
		return false
	if _refuse_in_field("buying a %s frame" % chassis.id):
		return false
	if not is_unlocked(chassis.id):
		return false
	var price: int = _Pricing.chassis_buy(chassis)
	if not can_afford(price):
		return false
	var key := "chassis:%s:%d" % [chassis.id, _next_purchase()]
	# Same ordering as buy_item: the chassis is in stores before anyone is told.
	if not _allocate_quiet(key, price):
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
	if item != null and _refuse_in_field("selling %s" % item.id):
		return false
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
		award(sale_value(_Pricing.item_buy(item)))
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
		return sale_value(_Pricing.item_buy(item))
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
		# PRODUCTION LINES. Read back through data.get with an empty default,
		# so a save written before marks existed loads every line at Mk 0 with
		# no module — which is exactly what an un-advanced line is.
		"line_marks": line_marks.duplicate(),
		"line_modules": line_modules.duplicate(),
		"roster": records,
		"completed_missions": missions,
		"mission_clears": mission_clears.duplicate(),
		# TERRITORY. No SAVE_VERSION bump and no migration: from_dict reads
		# every field through data.get(key, default), so a save written before
		# these existed loads with an empty board — and site_owner() falls back
		# to each location's authored start_owner, which is the right answer.
		# (Wipe-and-restart was taken anyway, 2026-10-12 — §16.1.)
		"turn": turn,
		"sites": sites.duplicate(true),
		"under_attack": String(under_attack),
		"under_attack_turn": under_attack_turn,
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
	# duplicate(), for the same reason `sites` below is duplicated: a Dictionary
	# read out of JSON is shared with whatever else holds that parse, and both
	# of these are mutated in place by adopt_mark / adopt_module. Restoring
	# the same snapshot twice used to hand two states one dictionary.
	s.line_marks = (data.get("line_marks", {}) as Dictionary).duplicate()
	s.line_modules = (data.get("line_modules", {}) as Dictionary).duplicate()
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
	s.turn = int(data.get("turn", 0))
	# duplicate(true), because a Dictionary read out of JSON is shared with
	# whatever else holds that parse — and `sites` is mutated in place by
	# set_site_owner.
	s.sites = (data.get("sites", {}) as Dictionary).duplicate(true)
	s.under_attack = StringName(str(data.get("under_attack", "")))
	s.under_attack_turn = int(data.get("under_attack_turn", -1))
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
	# MIGRATION (Phase 3.2): every id a save already had unlocked becomes a
	# ZERO-COST allocation. They were earned under the old rules and must not
	# suddenly cost resources — and once they are allocation keys, is_unlocked()
	# answers for them exactly as it does for anything bought.
	#
	# Written even though saves are being wiped (§16.1), because a wipe is a
	# decision about THIS machine and this is the only code that would ever
	# know how to read the old shape.
	for u in data.get("unlocked", []):
		var id := _renamed(StringName(str(u)))
		unlocks.append(id)
		if not s.allocations.has(unlock_key(id)):
			s.allocations[unlock_key(id)] = 0
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
# freshly parsed state has none. `save_path` stays too, and must: it is which
# FILE this is, not what is in it, and a load that adopted the dictionary's
# idea of where it lives would write the loaded campaign back over the one it
# was read into. Campaign.load_profile sets it immediately after this returns.
#
# THREE CALLERS, AND IT IS A LOAD FOR TWO OF THEM:
#   - Campaign.load_profile  — opening a save
#   - Campaign.new_profile   — blanking the state by restoring a blank dict
#   - Campaign.extract       — the rewind after a failed run
#
# THIS LIST IS EVERY FIELD IN to_dict(), AND IT HAS TO BE. It held 22 of the
# 29 until 2026-10-26, and the seven it forgot — line_marks, line_modules,
# turn, sites, under_attack, under_attack_turn, lessons_seen — were not a
# rewind nicety but a lost campaign: every boot came up at turn 0 on the
# authored board with every production line at Mk 0, and the next autosave
# wrote that over the file. new_profile inherited the same seven from whatever
# was open. Measured by tools/probe_save_facts.gd §2 and §3 (Backlog SV1).
#
# WHAT ASSERTS IT, because the old comment named a guard that could not work:
# it said test_endings covered a missed field, and test_endings restored a
# state into ITSELF — where a field this function forgets already holds the
# right value, so the check cannot fail. tools/test_restore_from.gd is the
# replacement: it compares this list against to_dict()'s keys in the source,
# and restores a played campaign into a DIFFERENT state (Backlog SV3).
func restore_from(data: Dictionary) -> void:
	var was := CampaignState.from_dict(data)
	earned = was.earned
	allocations = was.allocations
	# THE PRODUCTION LINES. A robot's loadout belongs to its line, not to the
	# robot, so a load that moved the roster and not these put every record
	# back carrying Mk 2 kit on a line the game believed was at Mk 0.
	line_marks = was.line_marks
	line_modules = was.line_modules
	roster = was.roster
	completed_missions = was.completed_missions
	mission_clears = was.mission_clears
	# THE BOARD. Without these a load started on the authored map at turn 0
	# however far the campaign had got, and a raid in progress was forgotten.
	turn = was.turn
	sites = was.sites
	under_attack = was.under_attack
	under_attack_turn = was.under_attack_turn
	completed_tutorial = was.completed_tutorial
	# LESSONS. Carried like everything else as of 2026-10-26. It changes
	# nothing for the rewind — both markers fire at base (Campaign._is_base
	# and LessonPrompts._on_home), after extract() has already rewound, so
	# there is never a lesson marked during a run for a rewind to un-see — and
	# it stops one profile's lessons being counted as read in the next.
	lessons_seen = was.lessons_seen
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
	# WHEN THIS CAMPAIGN WAS LAST PLAYED, stamped here because here is the only
	# moment it is true. The field was written to the save and read back by the
	# profile menu to order the list, and set by nothing — so the ordering was
	# really file mtime, and any tool that touched a save moved it to the top.
	# Stamped after the file opened, so a write that could not happen does not
	# claim a session. Backlog SV4.
	last_played_utc = Time.get_datetime_string_from_system(true)
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return true


var _no_save_said: bool = false
var _no_path_said: bool = false


## The save at `path` as a dictionary, or empty when there is nothing readable
## there — no file, unreadable, not JSON, or from a build whose shape this one
## refuses. The caller decides whether empty means "new campaign" or "something
## is wrong"; it is deliberately not told which, because nothing acts on the
## difference and three callers guessing at it is worse than one not knowing.
##
## Split out of load_from_disk so a caller can restore_from() it INTO the state
## the game is already holding. See the note on restore_from: handing out a new
## object leaves every HUD and screen wired to one nobody updates.
##
## PATH IS REQUIRED. It defaulted to SAVE_PATH — the legacy user://campaign.json
## — so a bare load_dict() read a file that is no longer any profile's. Every
## caller already passes one. Backlog SV2.
static func load_dict(path: String) -> Dictionary:
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
	if is_outdated(got):
		push_warning("CampaignState: %s is from an older build (save version %d, this build reads %d) and is not loadable. The file is left alone." % [path, int(got.get("version", 0)), SAVE_VERSION])
		return {}
	# FROM A NEWER BUILD, which is not refused and probably should be: the save
	# loads, from_dict ignores whatever it does not recognise, and the next
	# autosave writes the older shape back over it. Warning is all this does.
	# What should happen instead is Backlog SV5, and it is the human's call.
	var version := int(got.get("version", 0))
	if version > SAVE_VERSION:
		push_warning("CampaignState: %s is version %d and this build reads %d. It will load, and saving will write the older shape back over it." % [
			path, version, SAVE_VERSION])
	return got


## The save at `path` as a state of its own, or null when there is none to read.
##
## Through load_dict, so there is ONE reader. This used to be a second,
## line-for-line copy of the same open-parse-gate sequence, which meant every
## change to how a save is read had to be made twice and neither copy said so.
## Both answers are unchanged: every way this can fail returned null before and
## returns null now, because load_dict answers all of them with an empty
## dictionary.
static func load_from_disk(path: String) -> CampaignState:
	var data := load_dict(path)
	if data.is_empty():
		return null
	return from_dict(data)


# Every field read above already has a default, so a save written before a field
# existed loads cleanly. This is here for the changes defaults can't cover.
## IS THIS SAVE FROM A BUILD WHOSE SHAPE WE NO LONGER READ?
##
## Separate from "broken", and the distinction is the whole point: a corrupt
## file and a file from last month are different things to tell a player, and
## calling an old campaign corrupt is both untrue and alarming.
##
## NOTHING DELETES IT. The file stays exactly where it is — refusing to load
## it is the entire requirement, and removing somebody's campaign is hard to
## forgive and trivial to avoid. It stays listed so it can be seen and
## deliberately removed by the person whose campaign it is.
static func is_outdated(data: Dictionary) -> bool:
	return int(data.get("version", 0)) < SAVE_VERSION

# THERE IS NO migrate(). There was, and it migrated nothing — one warning about
# a newer save and `return data`, called by both load paths as though a save
# were being transformed on the way in. It is not: every field is read through
# data.get with a default, so a save written before a field existed loads
# cleanly without anyone's help, and the one shape change that defaults could
# not cover (v1 → v2, the mark system) was answered by refusing v1 rather than
# by inventing a migration nobody could verify. is_outdated() is the whole
# gate. The warning moved into load_dict, where the path can be named.
# Backlog SV6. tools/migrate_save.gd is a separate thing and stays: it rewrites
# an old file on disk, by hand, for somebody who asks it to.
