# Map deck — fifty ideas, built and ranked

Fifty map concepts, each one painted as a sketch, generated as terrain, dressed
out of `maps/blocks/` and photographed. Rebuild the whole deck in about ninety
seconds:

```bash
RENDER_OUT=<dir> godot --path . --script res://tools/mapdeck.gd
```

`tools/mapdeck_data.gd` holds the fifty. `tools/contact_sheet.gd` tiles the
pictures into sheets so they can be looked at as a set.

**These are concepts, not levels.** Terrain, a dressing pass and two pictures
each. Nothing here has objectives, a navmesh, a spawn or a mission, and nothing
here has been played — including by me. The ranking is judgement against what
this project has already learned, not a playtest.

---

## What the ranking is built on

Five things, in this order. The first two come straight out of maps that
already failed here.

1. **Flat ground where the squad fights.** Bots climb 0.25 m. Broken ground
   bakes as a wall or as slivers that get culled. Pittsburgh's jagged terrain
   and unwalkable roads are the standing example, and the first version of the
   Hillfort ascent was rejected for the same reason — *"this is way too tall,
   think hills not a mountain."* Height in a good map comes from built
   structure with its own ramps.
2. **Cover everywhere, not only at the objective.** The note on Hillfort after
   playing it was *"overall except for the top of the hill there's nothing."*
   `arena_level` is dead for the same reason: 88 × 54 m of grass with eighty
   near-identical blocks, no landmark and nothing to navigate by.
3. **Decisions, not corridors.** A map earns its keep when it makes the player
   commit — which crossing, which flank, which floor. A river the squad can
   wade is decoration; a river it cannot is a decision.
4. **Readability.** A landmark you can see from anywhere, and lanes whose shape
   you can read from inside them. The proving ground was rebuilt around exactly
   this and it worked.
5. **Not a map we already have.** `mutaha_wip` is approved and is a town with a
   river; `causeway` is the big set-piece; `proving` is the arena ladder.
   Another of any of those earns less than something the ladder is missing.

**Where the deck is thin.** Everything with a real interior, everything with
genuine verticality, and everything that is a fight at fifty metres rather than
three hundred. That shows in the ranking.

---

## The ranking

### Tier 1 — build these

| # | Map | Shape | Why it is up here |
|---|---|---|---|
| 1 | **Ford Town** | linear choke through dense cover | The river IS the main street and both banks are built right up to it. Every one of the five criteria at once: flat, cover the whole way, a crossing decision every 400 m, and a clock tower to steer by. It is the Mutaha formula — the one thing here already approved — but tighter and more legible. |
| 2 | **Boulevard** | a killing ground with parallel safe routes | One forty-metre avenue you must cross and side streets that are the only sane way. The clearest single decision in the deck, and the eye-level shot proves it reads from inside. Cheap to build: it is a street grid and two rows of blocks. |
| 3 | **Old Town** | concentric — outskirts, wall, warren | Outskirts you fight through, a wall you have to breach, a warren behind it. Gated by **built** geometry, which is the rule the ascent map had to learn the hard way. Gives a whole mission an arc. |
| 4 | **Lock Ladder** | sequential chokes on one axis | Three staircase locks and the gates are the only dry crossings. Nothing in the repo plays like it, and the rule is legible the moment you see it. |
| 5 | **Canal District** | grid of small forced crossings | Streets and canals alternate, so every block is an island and every bridge is narrow. The highest density of real decisions per hectare here. |
| 6 | **Foundry** | big interior, heavy exterior approach | One vast shed with a crane down the middle. **The best interior in the deck**, and interiors are the biggest hole in the map roster. |
| 7 | **Market Quarter** | close quarters, no sight lines | Nothing more than thirty metres away and none of it straight. The direct answer to a game where the long-range problem keeps coming up. |
| 8 | **Two Bridges** | binary choice | One river, two crossings, six hundred metres apart. Simple in the way good maps are simple: you cannot cover both and neither can they. |
| 9 | **Rail Station** | interior over an exterior | A shed you fight inside standing on a viaduct you fight under. Two maps, one footprint, and both are dense. |
| 10 | **Grain Terminal** | solid barrier with one gap | A wall of silos between the town and the water. Reads from anywhere, and the single gap does all the work. |

### Tier 2 — worth building, with a caveat each

| # | Map | Caveat |
|---|---|---|
| 11 | **Campus** | Open lawns inside a hard frame. Needs the lawns properly covered or it drifts toward the arena's failure. |
| 12 | **Ruin Square** | One contested interior. Small — a side mission, not a set-piece. |
| 13 | **Clarifier Rings** | Curved cover is genuinely novel here, every route an arc. Underrated; the pipe racks already look right. |
| 14 | **Refinery** | Orbital cover and roofed lanes. Needs roughly twice the tank farm it has to stop feeling sparse. |
| 15 | **Terraced Farms** | A ladder of flat lanes with ramps between. Exactly the right way to do height — but the terraces must come from built steps, not the terrace knob. |
| 16 | **Scrapyard** | An improvised maze that suits the fiction. Cheap. Risks reading as visual noise. |
| 17 | **Tower Blocks** | Strongpoints with open ground between. The open ground is the Hillfort failure mode unless it is properly furnished. |
| 18 | **Oxbow** | A peninsula with one neck. Strong shape; needs a reason to be on the peninsula. |
| 19 | **Container Port** | Maze with a roof, two cranes to navigate by. Close to Scrapyard — build one of the two. |
| 20 | **Dam Crest** | The thinnest choke here and a superb picture. One 8 m crossing may be more frustrating than tense. |
| 21 | **The Weir** | Still water above, cut gorge below. Good image, and the two levels give the fight shape. |
| 22 | **Braided Delta** | Four channels, eight crossings, flanks everywhere. Risks being fiddly rather than tactical. |
| 23 | **Institute Hill** | Terraced car parks up to one block. Solid, unexciting. |
| 24 | **Seafront** | Linear with one flank on open sand. The sand flank is the whole idea and it needs to stay punishing. |
| 25 | **Cement Works** | The 300 m conveyor gallery is a genuinely good feature. The rest of the map is thin around it. |
| 26 | **Interchange** | Real verticality from ramps rather than stairs. Needs the stacked roadway built properly — the terrain cannot make it. |
| 27 | **Server Farm** | Fits the fiction better than anything else here. Identical halls could read as disorienting-in-a-bad-way; needs each row marked. |
| 28 | **Tidal Causeway** | Spectacular, and a gauntlet with no cover is the fight this project already said is not fun. Build it as a finale, not a mission. |
| 29 | **Power Station** | The cooling towers are the best landmarks in the deck. The layout under them is ordinary. |
| 30 | **Border Post** | A pure corridor — good for an early mission that teaches orders, limited after that. |
| 31 | **Fairground** | The wheel is a superb landmark. The map around it is one idea thin. |
| 32 | **Box Canyon** | Clean gating and a flat floor, but a dead end is one-dimensional. |

### Tier 3 — the idea is fine, this project will fight it

| # | Map | What goes wrong |
|---|---|---|
| 33 | **Quarry Benches** | Right instinct, wrong mechanism: stepped benches from the terrace knob come out as ground the squad cannot use. Do it in brushes or not at all. |
| 34 | **Aqueduct** | "Fight on it and under it" needs a real upper deck. Bridge prefabs on the ground do not give one. |
| 35 | **Tunnel Mouths** | The portals are the point and there is nothing behind them. Needs interiors first. |
| 36 | **Marsh Boardwalks** | Maximum channelling and zero cover on the planks. Likely frustrating rather than tense. |
| 37 | **Air Cargo Apron** | A thinner Container Port. |
| 38 | **Rail Yard** | Good idea — see a kilometre along, nothing across — but it needs five times this much rolling stock or it is a field with lines painted on it. |
| 39 | **Mesa Top** | A flat top with two ramps is Hillfort again, and Hillfort exists. |
| 40 | **Sinkhole** | A spiral road cut into terrain is the Pittsburgh problem by another name. |
| 41 | **Dragline Pit** | Same, plus the prize is one prop. |
| 42 | **Fire Breaks** | Scatter has no collision, so the "dense forest" is cosmetic and the map is four lanes in a field. |
| 43 | **Cliff Stair** | Gating by cliff, which is the thing that got rejected on the ascent map. |
| 44 | **Airfield** | A runway is a kilometre of nothing in the middle. That is `arena_level`'s mistake with a better texture. |
| 45 | **Oasis** | One island of cover in a hundred hectares of nothing. Thin. |

### Tier 4 — do not build

| # | Map | Why not |
|---|---|---|
| 46 | **Solar Field** | Waist-high cover for a kilometre is one note held for a whole mission. Better as a *district* of another map. |
| 47 | **Launch Complex** | A processional axis with no cover on it, and nothing either side. |
| 48 | **Dish Array** | Many equal objectives and no centre reads as no objectives and nowhere. |
| 49 | **Pylon Line** | The towers are the only cover for a kilometre. This is the dead `valley_level` with pylons. |
| 50 | **Salt Flat** | Deliberately empty, and empty is precisely what killed two maps here already. |

---

## What the deck says as a whole

**The top of the list is towns and works, and the bottom is open country.** That
is not a taste — it is this project's own record. Both maps that died
(`valley_level`, `arena_level`) died of emptiness, the one that got approved is
a town, and the note on the newest map was that there was nothing between the
objectives. Open ground does not survive contact here.

**Water is the cheapest good decision available.** Six of the top ten use it,
and it costs one painted stroke. A river the squad cannot wade turns a flat map
into a set of committed choices for free — provided the beds stay out of the
navmesh, which has to be checked every time.

**The real gap is interiors.** Foundry and Rail Station rank as high as they do
mostly because almost nothing in the roster is a fight indoors. Whatever gets
built next, an interior would add more than another field.

---

## Notes on the build

- Painted at 8 m a sketch pixel, so a pixel means the same thing in all fifty.
- Blocked out at 3 m cells. Fine for a concept; a real level wants 2 m or 1 m.
- Rows and grids space themselves off each prefab's own bounding box, read at
  build time — sizing pieces from memory is how a placement pass puts three
  buildings through each other, and it has happened here.
- The default recipe is a FLAT map: hills, ridges, erosion and crater depth all
  start near zero and each map turns up only what it needs. That is the
  opposite way round from the presets, and deliberate.
- Some eye-level cameras ended up inside terrain or under water (`aqueduct`,
  `dam_crest`, `braided_delta`). The plan shots carry those maps instead.
