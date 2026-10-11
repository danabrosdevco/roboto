# Brief — the Vessel's roof panels and bay deck

Written 2026-10-10, off the lit in-game render of the finished Vessel chassis
(`Character/characters/ai/vessel.tscn`, photographed through
`tools/mockup_shots.gd -- <dir> vessel`). The geometry is settled; the surface
is not. Every painted piece wears `robot_metal.tres` through `FactionLivery`,
and on this frame that fails twice for two different reasons — the doors are
too big for a tiling texture, and the bay is not a hull at all.

Owner: **TERRAIN**. Status: **not started**.

**Deliverable:** three entries in `tools/make_textures.gd` — `vessel_panel`
with its `_mask.png`, `vessel_panel_inner` with its `_mask.png`, and
`cargo_deck` — built the way `pauldron_plate` and the `camo_fabric` pair were.
No pixel of any bought pack gets read, sampled or filtered; the licence is kept
by drawing from nothing and copying only the style, which is what that file
already does.

---

## What it goes on

Twenty-six painted pieces, measured off `tools/build_vessel.gd`. The frame
measures **3.53 W × 3.37 H × 4.03 L** (`check_frame.gd`) and is the biggest
object in the game.

| node | shape | size, metres |
|---|---|---|
| `Rig/Bay/DoorL/Leaf`, `Rig/Bay/DoorR/Leaf` | chamfered plate, bevel 0.12, hinged on the outer rail, built at 130° open | **2.45 × 1.075 × 0.10 each** |
| `Rig/Bay/Coaming` | block with a `Well` cut through the top | 2.15 × 0.6 × 2.5; **well 1.78 × 2.15 × 0.50 deep** |
| `Rig/Hull` | chamfered block, glacis / tail / two 30° flank bevels | **2.7 × 1.3 × 4.0** uncut |
| `Rig/Bay/CradleA`, `CradleB` | chamfered deck plates in the bay floor | 1.7 × 0.6 × 0.19 |
| `Rig/Bay/Chock{A,B}{L,R}` | tapered wedges | 0.3 × 0.26 × 0.5 |
| `Rig/Bay/Cargo{A,B}` | the two carried Hatchlings, listed whole | body 0.42 × 0.5 × 0.2, rotors 0.86 across |
| `Rig/Bay/HingeBar{L,R}` | cylinders on the coaming's outer top rail | r 0.05 × 2.45 |
| `Rig/Bay/Door{L,R}/Stud0..3` | bolt heads standing proud of each leaf | r 0.035 × 0.049 |
| `Rig/TurretRing`, `Turret/TurretBody`, `Antenna`, `GunPivot/Mantlet` | the Walker head at 0.58 | body 0.684 × 0.348 × 0.754 |

`Turret/Eye` is off the livery list with its own material, and so are the six
wheels and the lamps. Nothing in this brief touches any of them.

### The number that matters

One door leaf's face is **2.45 × 1.075 = 2.63 m²**. The Bulwark's tower shield
— "the largest flat surface on any robot in the game", per `SHIELD_PLATE.md` —
is 1.55 × 2.20 = **3.41 m²**.

So each leaf is 77% of a shield, **the pair is 5.27 m², one and a half
shields**, and the bay floor under them is a further 3.83 m² of plane. This
frame carries roughly **two and two thirds of the surface that brief was
written about**, in three pieces, all of which the player looks at from above.

## Why it cannot stay on the shared hull material

`SHIELD_PLATE.md` §"Why it cannot stay on the shared hull material" makes the
tiling argument and this brief does not restate it. What is new here is that
the Vessel breaks it in a way the shield does not, and that one of these
surfaces is not armour at all.

**1. The doors are bigger than the shield and flatter than the shield.** The
shield at least has a vision slot and a hemispherical boss in it; the leaves
are unbroken 2.45 × 1.075 planes with four 7 cm studs on them. In the render
the hull mottle lands on them as visible diagonal banding — the same blob
crossing the panel three times — which is the exact failure the shield brief
predicted and the first thing the eye finds on the frame.

**2. They are the proposition.** `VESSEL.md` §1 picked this concept over three
others because "doors open is a universally legible statement about what a
vehicle is for", and because open and closed are two silhouettes "so the state
the player cares about is the state they can see". A door indistinguishable
from the hull it is hinged to is not a door. The shield brief's point 1 —
"a frame whose defining feature is indistinguishable from its leg has no
defining feature" — applies here with two features instead of one.

**3. And the bay is not armour.** This is the part nothing else in the game has
and the part most likely to be skipped. The well is 1.78 × 2.15 × 0.50 deep,
it holds two cradles and four chocks, and the player sees into it from above
because the player commands from a height. **A cargo deck is scuffed where
things are dragged in and out of it.** A bay floor wearing hull armour reads as
solid — as a dish pressed into the roof rather than as a space with a volume —
which costs the frame the one read it was chosen for.

## The three surfaces

### 1. `vessel_panel` — the roof, outer face

What the leaf shows when the doors are **closed**: the top of the vehicle, seen
from above, weathered. Also what it shows when open, since at 130° the outer
face rolls up to face the sky.

- **Long seams running fore-and-aft**, along the 2.45 m axis, dividing the leaf
  into three or four skin panels. That direction is the leaf's long axis and it
  also runs with the hinge, which is how a real roof panel is made up.
- **Structure at 30–50 cm.** The leaf is 2.45 m long; at the shield brief's
  20 m yardstick that is about 180 px, so the eye has room for real detail and
  will punish anything that repeats. Give it a border band inboard of the free
  edge, a cross-rib or two, and a stencilled load marking — one strong idea the
  way `_epaulette` carries one.
- **Weather, not damage.** Rain streaking running outboard from the centreline
  seam, dirt gathered against the ribs, sun bleaching on the crowns. The
  `_grime` helper darkens rather than lightens and is the right tool.
- **Scuffing along the centreline**, where the two leaves meet and where
  anything loading the bay would be walked or dragged over them.
- **Nothing finer than ~8 texels at 256.** Same rule as everything in this
  family.

### 2. `vessel_panel_inner` — the same leaf, the other face

The face that is the **ceiling of the bay when closed and the inside of an open
door when open**. It is never weathered, because it is never outside, and it is
only ever seen in the one situation the frame exists for.

- **Ribs and stiffeners**, not panels. The inside of a door is structure.
- **Hinge and strut mounting pads** near what is the outboard edge in texture
  space, since that is where the leaf is carried.
- **Cable or conduit runs.** This is where a vehicle's wiring goes and it is
  the cheapest thing that says "inside".
- **No rain streaking, no sun bleach, no dirt gradient.** All three say
  "outdoors", and this face never is.
- **Darker overall than `vessel_panel`** — mean 0.18–0.22 against the roof's
  0.22–0.26. An interior face is in shadow in the render and should read that
  way even where the engine does not light it.

**A geometry note, flagged rather than worked around.** `Leaf` is one
`CSGPolygon3D` with one material, and its two faces share UVs. **There is no
way to give those faces different textures without a geometry change** — either
a second thin plate laid on the inner face, or the leaf split into two meshes.
That is not this lane's call and is not this brief's ask. If the frame lane
declines it, ship `vessel_panel` alone and drop the inner entry; the roof is
the bigger surface and the one the tiling argument is about. The second entry
is written here because the human has already said the doors "should open and
close", and the moment they do, a face that was never meant to be seen becomes
the face the player looks at.

### 3. `cargo_deck` — the bay

**A deck plate, worn in lanes.** Not armour, not a floor tile.

- **A tread or chequer pattern**, directional along the bay's 2.15 m length —
  the direction a drone comes out.
- **Wear polished through the tread in two lanes**, under where the cradles
  sit. Brighter, smoother, lower-contrast than the surrounding deck. This is
  the single detail that sells "things are dragged in and out of here" and it
  is the reason for the entry.
- **Tie-down points and a painted stowage outline.** A hazard-edge band round
  the well's lip would do more work than anything else at a glance from above.
- **Scratches, long and shallow**, running the same way as the lanes. Four or
  five, not forty — the rule `PLATE_TEXTURE.md` set.
- **No rust and no rain.** The bay is covered when the doors are shut.

**A second geometry note, and the bigger one.** *There is no bay-floor node.*
`Coaming`'s `Well` cutter runs from below the coaming's own underside up
through its top, so the visible floor of the bay is **the top face of
`Rig/Hull`** — the generator's own header says so. `cargo_deck` therefore has
nothing to land on today: assigning it to `Hull` would put deck plate on the
entire vehicle. Either a deck mesh gets added inside the well, or the texture
goes on `CradleA`/`CradleB` only and the floor between them stays hull. The
cradles are 1.7 × 0.6 each, which is 2.04 m² of the well's 3.83 — most of what
the player looks down into, so that is a real fallback and not a fudge. **Say
which before drawing, because it changes the tile's scale.**

## How much the faction repaints

The doors: **a lot, and brightly**. They are the frame's identity and they are
flat to the sky, which is the single best place on any model in this game to
read a faction at distance. Use the `_mask.png` red channel with
`derive_mask_from_albedo = false`, as the epaulettes and pauldrons do; green is
0.

- **Painted:** the panel field, 60–70% of the tile on `vessel_panel`.
- **Held out:** seam shadows, rib shadows, stud heads, the stencilled marking,
  and the scuffed centreline where paint would be worn back to metal. That last
  one does the same job the shield's unpainted scars do — it reads instantly as
  "this gets used", in any faction colour.
- **`vessel_panel_inner`: much less**, 30–40%. The inside of a door is rarely
  painted in the livery colour on a real vehicle, and a bay lined in flat
  faction colour loses all its depth.
- **`cargo_deck`: almost none, 10–20%**, and only on the hazard band if one is
  drawn. A deck is bare metal and the worn lanes must stay bare, or the two
  things the texture exists to show both turn the same colour.

### Watch the ceiling, again

`CEIL` in `make_textures.gd` is 0.46 and `pauldron_plate` overshoots it to a
measured peak of 0.701 and photographs as chrome. Do not inherit that here. The
shader paints `albedo * faction_color * 2.0`: under PLAYER cyan
`Color(0.55, 0.90, 0.95)` the blue multiplier is 1.90, so **anything above
albedo 0.53 clips flat**, and a 2.6 m² plane that clips is 2.6 m² of
featureless white. Bright worn metal on the centreline must come from the mask,
not from pushing albedo up.

Numbers, checked with
`godot --headless --path . --script res://tools/probe_texture_stats.gd -- textures/PSX_Textures vessel cargo`:

| | mean lum | peak | sat | in band |
|---|---|---|---|---|
| `vessel_panel` | 0.22–0.26 | ≤ 0.46 | 0.08–0.16 | 60–70% |
| `vessel_panel_inner` | 0.18–0.22 | ≤ 0.46 | 0.06–0.12 | 30–40% |
| `cargo_deck` | 0.20–0.25 | ≤ 0.46 | 0.05–0.10 | 10–20% |

All three 256×256, RGB8, quantised to 32 levels through the same 4×4 ordered
dither. The banding is most of what makes the pack read as PSX.

## What should not be in any of them

- **Rust.** Covered in `PLATE_TEXTURE.md` and still true: this is maintained
  kit, not a shelled bridge. A rusted variant is a fourth entry, not a change
  to these.
- **A regular grid of rivets on the doors.** The geometry already places four
  real `Stud` meshes per leaf and a drawn grid will not line up with them.
- **Anything diagonal.** Both leaves and the bay are long rectangles; a
  diagonal pattern on a 2.45 m plane is the most visible possible tile.

## How to see it

```bash
godot --audio-driver Dummy --path . --script res://tools/mockup_shots.gd -- <out dir> vessel
```

Needs a window — run **without** `--headless`, against
`Godot_v4.3-stable_win64_console.exe`.

Two cautions from the round that produced this brief. The rig's standard
three-quarter framing is **eye level**, and at eye level the open leaves
occlude the bay completely — you cannot judge `cargo_deck` from it at all. And
a door leaf at 130° presents its outer face to the camera, so that shot never
shows `vessel_panel_inner` either. **Judge all three from a high
three-quarter**, which is also the angle the player actually commands from, and
judge the doors at 20 m in two faction colours. A swatch has told us the wrong
thing about every surface in this project so far.

## Hooking it up when it is done

All twenty-six pieces are in the Vessel's `FactionLivery.pieces` and take the
shared hull material. Giving these three their own surfaces means registering
base materials; `faction_livery.gd` already supports it (`add_pieces_with`, and
the `_bases` dictionary), which is the same mechanism the hats use to keep wool
looking like wool, and `Campaign/cosmetics.gd`'s `SURFACES` table is the
precedent for how a surface is declared.

**Out of scope, noted so nobody folds it in:** the human asked that the doors
open and close. They can — `tools/build_vessel.gd` built the hinges for it, and
closing is `rotation.z → 0` on `Bay/DoorL` and `Bay/DoorR`, 130° of travel each
and nothing else moving. That is a script job for `vessel.gd` and belongs with
the release behaviour, not with a texture.
