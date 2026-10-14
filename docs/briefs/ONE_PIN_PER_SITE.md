# ONE PIN PER SITE

**The operations table draws one marker per MISSION. It should draw one per
PLACE.** Written 2026-10-13.

## The problem, stated once

A site is now a place with **two operations on it** — take it, or hold it. The
board does not know that. `OpsTable._layout()` walks `Campaign.missions` and
puts a marker at each one's coordinates, so Valley Basin draws **two pins
stacked on the same spot**, one for `basin_1_anchor` and one for
`basin_2_defend`.

Today that is a cosmetic collision on one map. After
`docs/briefs/SITE_CONVERSION.md` it is **eight more**, and the board becomes
unreadable exactly as the campaign layer becomes interesting.

It is also wrong in a way that matters beyond overlap: **a pin is a PLACE**. It
should carry who holds it, what it pays, whether it is under attack and what
you can do there. "What can I do here" is a property of the site, not a reason
to draw a second site.

## What it should be

> **One marker per Location. The operations are what the marker OFFERS.**

| the marker says | from |
| --- | --- |
| who holds it | `state.site_owner()` — HELD blue, adversary amber, grey if unreachable |
| **under attack** | `state.under_attack` — CRIT red, and it outranks everything |
| what it pays | `Location.resources_per_turn`, `.compute` |
| how hard it is | `Location.resistance` |
| what you can do | the missions that resolve to this Location and are deployable |

Selecting a site lists its operations rather than being one:

```
VALLEY BASIN            HELD · 13/TURN · 1 CPU
  > HOLD THE BASIN      UNDER ATTACK — answer it
    RETAKE              (not available: you hold this)
```

## Why this is small

The data is already there and already keyed correctly.

- `LocationCatalogue.for_mission()` maps either operation to its Location, and
  the defence was deliberately wired through `defend_mission_id` so both
  resolve to one site.
- `_facts_for()` already computes `held`, `under_attack`, `per_resources`,
  `per_compute` and `resistance` — all of them per MISSION, all of them
  actually properties of the Location.
- `_tint_for()` is already one rule and already ownership-first.

**The change is in `_layout()` and `_facts_for()`, not in the board drawing.**
Group the mission list by Location, lay out one node per group, and let the
facts come off the Location with the operations as a list hanging on it.

## The awkward parts, named

**1. THE SIM ARENAS HAVE NO LOCATION, DELIBERATELY** (§15 — they are a practice
track and not on the adjacency graph). Grouping by Location leaves three
missions with nowhere to go. They should not be on this board at all — see
`docs/briefs/SIM_ARENA_MODE.md`, which removes them. **Do that one first and
this problem disappears**; until then they need a fallback group keyed by
mission id.

**2. `LAYOUT` IS KEYED BY MISSION ID.** `ops_table.gd` carries a hand-authored
coordinate per mission, and `basin_2_defend` was given the attack's coordinates
as a stopgap when it started warning. Re-key it by **location id**, which is
also fewer entries.

**3. ICONS ARE KEYED BY MISSION ID TOO** (`SITE_ICONS`). Same re-key. A site has
one icon; what you do there does not change what the place looks like.

**4. `_edges()` DRAWS THE DOTTED ROUTES FROM `requires`.** The real adjacency
graph now lives on `Location.connects_to`, measured and reciprocal, with a
suite asserting it. The board should draw THAT — it is the frontier rule the
player is actually playing against, and `requires` is a progression ladder that
happens to look like a map.

## Done when

- Valley Basin draws **one** marker, with both operations listed on it
- A site under attack reads as such without selecting it
- Nothing is keyed by mission id except the operation list itself
- The dotted routes are `connects_to`, not `requires`
- Eight more conversions add eight markers, not sixteen

---

## DONE IN PART, 2026-10-13 — one pin per place

Reported off a screenshot: *"valley basin has a duplicate location on top of
it."* Two pins, exactly as predicted above.

**`_board_missions()` now skips `m.defence`.** The defence is not dropped — it
is folded onto the attack's pin as `defend_id` in `_facts_for()`, and the card
offers **DEFEND IT** when a raid is actually in doubt there. Asked of
`available_missions()` rather than read off the Location, so the one rule about
when a defence exists stays in one place.

That closes the "done when" lines about the duplicate and about answering a
raid from the site. **Still outstanding:** `LAYOUT`, `ICONS` and `HEIGHTS` are
still keyed by mission id (the defence's entries are now simply unused), and
`_edges()` still draws `requires` rather than `connects_to`. Those are the
re-keying half, and nothing is wrong on screen until a site has two *attacks*.

## Three other things fixed from the same screenshot

**The arena's card ran off the bottom of the panel.** It was drawing the full
site block for a place with no Location: COMPUTE 0, RESOURCE 0/turn,
RESISTANCE 0, under a heading that said **ADVERSARY HELD** — the training
facility, held by the enemy. The sim branch now runs *first* in
`_refresh_panel()` and draws a name, one line and the button. The same fix went
into the table's own 3D readout, which had the identical fallthrough.

**Clicking the arena did nothing.** `_queue()` opens with a guard on
`deployable`, and the arena is deliberately not deployable — it is a door, not
an operation. So the click was swallowed and nothing happened, and the only way
in was to hover it and find the button. A click on a sim site now opens it, and
the guard prints why it refused instead of returning silently.

**The war was selectable before the training was done.** `requires` already
gated the first site behind the arenas, but invisibly, and the DEBUG switch
opens it. `_training_done()` reads the clears directly: until both exercises
are run every site is `deployable = false` with `needs_training` set, the card
says **FINISH TRAINING FIRST**, and the arena is drawn at 1.6× — the board's
existing "somewhere you could go" cue, and on a fresh campaign it is the only
enlarged pin on the table.

## And one real bug behind them

`Campaign.reset_campaign()` built a bare `CampaignState` and never re-wired
`catalogue` or `locations`, which the other two state-building paths both do.
Nothing complained: every `if state.locations != null` guard quietly took the
other branch, so the whole territory layer vanished — no ownership, no income,
no defences, every figure 0. Only tools call it, but four of them do, and they
had been asserting against that dead layer.

Covered by `tools/test_ops_board.gd` (21 checks).
