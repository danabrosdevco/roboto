# MOVE THE PLATFORM DOOR TO THE OPERATIONS CAR

**A brief for TERRAIN. Written 2026-10-15.** Small job, one real trap in it —
the trap is in §3 and it has already bitten once.

## What is wanted, in one line

**You wake in Operations and you should leave from Operations.** Today the only
way off the train is a side door at the far end of the rake, five cars away.

## Why — measured, not felt

`tools/probe_railhead.gd` walks the depot and prints every leg. Before any of
this was touched:

| | |
| --- | --- |
| arrive → operations table | 3.1 m |
| table → departure lever | 3.7 m |
| table → your squad | **60.0 m** |
| arrive → out the door | **64.8 m** |

Everything you *do* between operations is in one car. Everything you need to
*leave* is at the other end of the train. The rake runs Motive +96,
Fabrication +64, Armoury +32, Repair 0, **Operations −32**, Barracks −64,
**Platform −96**.

As a stopgap GAMEPLAY pointed the muster and the exit at
`Station_PlatformCentre`, which halved both legs to ~34 m. That is better and
still wrong: it puts the way out beside the Repair car for no reason anybody
could name. The door belongs on the car you are standing in.

## 1. There IS platform to step onto — this was the first thing checked

`block_railhead.gd`:

```
const ST_X0 := -141.0   ## platform's rear end
const ST_X1 :=  125.0   ## platform's front end
const ST_Y0 := OW       ## 4.75, the platform's edge against the car
const ST_Y1 :=  20.0    ## the back wall — a 15.25 m platform
```

The platform spans **−141 to +125** along the rake's axis. Operations sits at
**z −32**, comfortably inside it, with the full 15.25 m depth outside the door.
So this needs no change to the station at all.

## 2. The five anchors — `tools/build_railhead.gd:271–276`

```gdscript
_anchors["PlatformDoor"]            = _at("Platform", 0.0, R.HW, 0.0)
_anchors["PlatformDoor_Outside"]    = _at("Platform", 0.0, R.OW + 2.5, 0.0)
_anchors["PlatformDoor_LeafClosed"] = _at("Platform", 0.0, R.HW - 0.05, 1.7)
_anchors["PlatformDoor_LeafOpen"]   = _at("Platform", 2.0 * R.DOOR, R.HW - 0.05, 1.7)
_anchors["PlatformDoor_Zone"]       = _at("Platform", 0.0, 2.0, 0.0)
```

All five take `"Platform"` as their car. They become `"Operations"`. That part
is a find-and-replace.

## 3. THE TRAP — do not re-centre the rake

This is the whole reason the brief exists. `build_railhead.gd:100`, verbatim:

> **THE RAKE'S POSITION IS PINNED BY THE PLATFORM CAR, NOT BY THE SPAWN.** The
> station's PlatformDoor, RampTop and HeadHouse markers sit at fixed places on
> a station laid at the origin, and the Platform car's side door has to line up
> with them. Re-centring the rake so Operations landed on the spawn at z = 0
> moved the Platform car 32 m and **put eleven markers inside colliders** — the
> build said so and the reach test could not even start. So the formula stays,
> and the spawn moves to meet Operations instead.

Somebody has already tried to solve this by sliding the train and it failed
loudly. **Do not move the rake.** The platform is long enough that the door
does not need to be at the station's centre — it only needs platform outside
it, and at z −32 there is 15 m of it.

## 4. The part that is actual work

The anchors are markers. **The opening is brushwork**, and it is in two places:

- **Cut** a side opening in `maps/blocks/railhead/railhead_car_ops.map` at the
  car's middle, matching the one the platform car has.
- **Close** the opening in `railhead_car_platform.map`, or the train has a hole
  in it at the far end and the squad can walk out of the back of the depot.

Both are `.map` files rebuilt by their own tools; nothing is hand-edited into a
`.tscn`.

## 5. The ops car is not empty

`railhead_car_ops.tscn` already carries the operations table and the departure
lever, seated by `tools/fit_ops_table.gd` at `OpsTableAnchor` and
`OpsLeverAnchor`. The table is **7.0 × 3.0 m**, the widest the car allows, and
it lies along the car.

So the door wants a side the table does not block. Worth placing the opening
and then running `tools/probe_railhead.gd`, which measures the walk and the
footing for every fitting and will say if the door lands somewhere the player
cannot reach.

## 6. What GAMEPLAY does when it lands — nothing, almost

`maps/railhead_level.gd` places the exit off a marker name:

```gdscript
const M_EXIT := "Station_PlatformCentre"   ## the stopgap
```

It becomes `"PlatformDoor_Outside"`. **One word**, and from then on the exit
follows the door automatically, because it is resolved by name at load rather
than typed as a coordinate. The squad muster goes the same way.

`RailheadLevel._audit_walk()` already warns on boot if any fitting ends up more
than 40 m from the operations table, so a future rake re-order cannot quietly
put the walk back.

## Done when

- The opening is in the Operations car and gone from the Platform car
- The five `PlatformDoor_*` anchors read `"Operations"`
- The rake is **unmoved** — `Car7_Platform` still at z −96
- `tools/probe_railhead.gd` reports every leg under 40 m and everything on floor
- Tell GAMEPLAY it has landed and the exit becomes one word
