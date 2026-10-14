extends RefCounted
class_name Pricing

# ─────────────────────────────────────────────
# THE WHOLE BALANCE SURFACE, IN ONE FILE.
#
# docs/briefs/CAMPAIGN_REWORK.md §3a and §16.2. Twenty-seven chassis and
# thirty-six items priced individually is sixty-three balance arguments and
# sixty-three chances to get one wrong. Price the BAND, not the thing.
#
# EVERYTHING IS A MULTIPLE OF ONE NUMBER. Change BASE and the entire economy
# moves with it, keeping every ratio. Change a band and a whole class of kit
# moves. Nothing is priced in a .tres any more — `cost` on a definition is
# legacy and is no longer read for anything the player buys.
#
# UNLOCK IS SEPARATE FROM BUY, and deliberately steeper. You pay once to open a
# line, then pay per copy. A line you open for 3× and buy at 1.5× pays for
# itself across a squad and never for a one-off — which is the rule from
# Appendix A, expressed as two multipliers instead of a hardcoded 2×.
#
# WHO DECIDED THESE. The bands and every assignment below came from the human,
# 2026-10-12, overruling an earlier proposal of mine that banded by role. Two
# items were not in that list and are marked ASSUMED where they sit.
# ─────────────────────────────────────────────

## The one number. Everything below is a multiple of it.
const BASE := 50

# ── Bands ────────────────────────────────────────────────────────────────────
# [unlock multiple, buy multiple]. A band with an unlock of 0 is open from the
# start; UNBUYABLE is not for sale at all.

const ISSUED := "issued"        ## Open from the start. The rifle you begin with.
const STANDARD := "standard"    ## The everyday line.
const UPGRADED := "upgraded"    ## Better versions of ordinary things.
const CREW := "crew"            ## Heavy weapons. Cheap to open, dear per copy.
const ADVANCED := "advanced"    ## The top of each line.
const UNBUYABLE := "unbuyable"  ## Exists in the world, never in the shop.

const BANDS := {
	ISSUED: [0.0, 1.0],
	STANDARD: [2.0, 1.0],
	UPGRADED: [3.0, 1.5],
	CREW: [3.0, 2.0],
	ADVANCED: [4.0, 2.0],
}

## Which band each item is in.
##
## CREW AND ADVANCED DIFFER ONLY IN THE UNLOCK. Both cost 2× a copy; a crew
## weapon opens for 3× and an advanced one for 4×. That is the whole
## distinction and it is worth keeping separate, because it is the knob that
## says "this is a reach" without making the thing itself dearer to field.
const ITEM_BAND := {
	# ── Equipment, regular: 2× to open, 1× a copy ──
	&"frag": STANDARD,
	&"smoke": STANDARD,
	&"emp": STANDARD,
	&"repair_kit": STANDARD,
	&"repair_tool": STANDARD,
	&"armor_plating": STANDARD,
	&"hardened_uplink": STANDARD,
	&"utility_harness": STANDARD,

	# ── Equipment, upgraded: 3× to open, 1.5× a copy ──
	&"mine_cluster": UPGRADED,
	&"mine_heavy": UPGRADED,
	# NANITE REBOOT WAS LISTED IN TWO BANDS — upgraded and higher — in the same
	# message. Placed here because it sits at 80 today, among cyclic feed and
	# the hatchling charge rather than the sensor relay and the drone pack.
	# Moving it is one line.
	&"nanite_reboot": UPGRADED,
	&"cyclic_feed": UPGRADED,
	&"hatchling": UPGRADED,
	# ASSUMED. Neither was in the list; both are in the shop and had to land
	# somewhere. Overclock Servos is a module at 60 today and the Repair Lance
	# a weapon at 90, so upgraded (75 a copy) is the nearest band to both.
	&"overclock_servos": UPGRADED,
	&"repair_lance": UPGRADED,

	# ── Equipment, higher tier: 4× to open, 2× a copy ──
	&"optics": ADVANCED,        # Sensor Relay
	&"drone_pack": ADVANCED,
	&"recoilless": ADVANCED,

	# ── Weapons ──
	&"m4": ISSUED,              # Ancient Rifle — always open
	&"light_cannon": STANDARD,
	&"machine_gun": STANDARD,   # Ancient MG
	&"bolt": STANDARD,          # Mark One
	&"grenade_launcher": STANDARD,
	&"heavy_mg": CREW,
	&"squad_auto": CREW,
	&"mortar": CREW,
	&"rocket_pods": CREW,
	&"cluster_launcher": CREW,  # "same as squad auto"
	&"autocannon": ADVANCED,
	&"hatchling_launcher": UNBUYABLE,
}

# ── Chassis ──────────────────────────────────────────────────────────────────

## COST IS A FUNCTION OF SUPPLY, uniform within a tier (§3a). Supply already
## measures how much room a frame takes, so letting it set the price means a
## frame added next year is priced correctly by existing.
##
## SUPER-LINEAR ON PURPOSE. Supply measures room; cost measures capability. A
## Bulwark takes three riflemen's space and is worth a great deal more than
## three riflemen, so it costs more per point of supply — flat pricing would
## make big frames strictly efficient and collapse the roster onto them.
##
## ASSUMED, and the one number here nobody has signed off: the human set BASE
## at 50 and gave multipliers for kit but not for frames. These keep §3a's
## super-linear shape in the same vocabulary as the bands above. One edit.
const CHASSIS_BUY := {1: 1.0, 2: 2.5, 3: 5.0}

## Opening a frame costs twice buying one, the rule from Appendix A.
const CHASSIS_UNLOCK := 2.0


# ── Asking ───────────────────────────────────────────────────────────────────

## What one copy costs. 0 means it is not for sale — check `for_sale` rather
## than reading 0 as free.
func _init() -> void:
	# Static-only. Nothing should ever hold one of these.
	push_warning("Pricing is a static table and should not be instantiated.")


static func band_of(item) -> String:
	if item == null:
		return UNBUYABLE
	return String(ITEM_BAND.get(item.id, STANDARD))


## Is this thing buyable at all? UNBUYABLE kit exists in the world — the enemy
## carries it, a mission hands it over — but never appears in the catalogue.
static func for_sale(item) -> bool:
	if item == null:
		return false
	# in_shop = false means CUT FROM THE GAME and predates all of this; it is
	# still the stronger statement and still wins.
	if "in_shop" in item and not item.in_shop:
		return false
	return band_of(item) != UNBUYABLE


## What one copy of an item costs.
static func item_buy(item) -> int:
	var b := band_of(item)
	if not BANDS.has(b):
		return 0   # UNBUYABLE; for_sale() is the question to ask
	return int(round(float(BANDS[b][1]) * float(BASE)))


## What opening the line costs. 0 for something open from the start.
static func item_unlock(item) -> int:
	var b := band_of(item)
	if not BANDS.has(b):
		return 0
	return int(round(float(BANDS[b][0]) * float(BASE)))


## What one robot built on this frame costs.
static func chassis_buy(frame) -> int:
	if frame == null:
		return 0
	var mult: float = float(CHASSIS_BUY.get(int(frame.supply), 0.0))
	return int(round(mult * float(BASE)))


## What opening the frame costs.
static func chassis_unlock(frame) -> int:
	return int(round(float(chassis_buy(frame)) * CHASSIS_UNLOCK))


## A frame nobody can buy — the enemy-only ones, the structures, and the Diver.
## `purchasable` is authored on the chassis and is the stronger statement, the
## same way in_shop is for items.
static func chassis_for_sale(frame) -> bool:
	if frame == null:
		return false
	if "purchasable" in frame and not frame.purchasable:
		return false
	return CHASSIS_BUY.has(int(frame.supply))
