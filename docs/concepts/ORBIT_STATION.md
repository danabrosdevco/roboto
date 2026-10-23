# ORBIT STATION — massing study

Concept art for `docs/briefs/ORBIT.md`. **Status: massing only.** No navmesh,
no collision worth the name, no interactibles, no art — volumes, sightlines
and scale, to be looked at before TERRAIN spends a fortnight on a station.

**Rendered by** `tools/mock_orbit.gd`, headful, through the game's own screen
filter with `hud.tscn`'s own uniform values, at 1152 × 648, **eye at 1.50 m in
every frame but the plan.**

```bash
godot --audio-driver Dummy --path . --script res://tools/mock_orbit.gd -- docs/concepts
NOFILTER=1 godot --audio-driver Dummy --path . --script res://tools/mock_orbit.gd -- docs/concepts
```

The second writes the same cameras with no filter, suffixed `_raw`. See §2,
which is the reason it exists.

**Settled by the human before this was built:** no squad in orbit.

---

## 1. The brief's four asks, and where each one landed

| asked for | where it is |
|---|---|
| windows, stars out of them | `orbit_window.png` — and §2, which is the problem |
| fake rotation | `orbit_spin_a.png` / `_b.png`, §3 |
| it should feel big | `orbit_gallery.png`, §4 |
| table, pod launcher, machinery underneath | `orbit_table.png`, `orbit_pod.png`, `orbit_well.png` |

---

## 2. THE FINDING: point-stars do not survive the screen filter

**Look at `orbit_window.png` and `orbit_window_raw.png` together.** Same
camera, same scene, one frame apart in the tool.

Raw, it is what was built: four tall apertures with a real starfield behind
them and nothing on the walls. Filtered, **the whole frame is speckled at the
same density and brightness as the stars** — the deck, the mullions, the sill
and the sky all alike. The apertures stop reading as space and become dark
rectangles that happen to be darker.

It is not a bug and it is not the dome. `hud.tscn` runs `dither_strength`
**0.85** against `luma_levels` **10**, plus `grain` 0.05. An ordered dither
that strong over a ten-step luma ramp puts a bright pixel on everything, and a
star is a bright pixel. **The filter is already drawing a starfield over your
entire screen, and it has been all along.**

This is the same wall `docs/concepts/IMPACTS.md` hit from the other side: its
edge pass inverts anything thinner than **4–7 screen pixels** to near-black.
Thin bright things are not available in this game.

### What works instead, and it is in the same picture

**The planet.** A big shape with internal structure quantises cleanly, holds
its edges, and reads instantly — it is the only thing in `orbit_window.png`
that says *orbit* rather than *dark room*. It also points at where you are
going, which a star cannot.

**So the sky's job belongs to large shapes, not points:** the limb, a lit
station spar crossing a window, the glow of something burning on the surface
below. Stars can stay as texture — they cost nothing and they are not doing
the work.

### 2.1 And the planet can have a colour, which took two goes

The first Earth was a **glowing green ball**, and that was two mistakes
stacked on each other.

**One: it was emissive, in a green I had picked.** Fixed by lighting it
instead — it has its own sun on its own visual layer, so it gets a
**terminator** without a second light falling on the deck. A fully lit disc is
a shape; a lit crescent with a dark side is a world.

**Two: it was far too bright, and brightness is what kills hue here.**
`palette()` ramps quantised LUMA through shadow → mid → high, and `high_tint`
is `(0.87, 0.94, 0.72)` — so *anything* that pins to the top band comes out
pale yellow-green whatever colour it started. The second attempt was correctly
textured and still came back a cream blob at `light_energy` 3.4.

**The hue lives in chroma, not in brightness.** The filter adds the source's
own chroma back on top of that ramp — `col += chroma * saturation`, line 230 —
so at `light_energy` **0.95** a textured surface keeps its own colour straight
through a green palette. The rule for anything that has to have a colour in
this game: **give it chroma and keep it out of the top luma band.**

### 2.2 And it is DEAD, which is harder than it sounds

A blue marble is a world worth defending, and that is not the world `lore.txt`
describes: GUBI ended, the cyberspace regions went dark, humanity and its
robots fell into disrepair. So: ash land, leaden water, a dust layer instead
of weather, ice the colour of old snow, **no city lights on the night side**,
and low-frequency burn scars that drop whole regions near black.

**YOU CANNOT GET THERE BY REMOVING COLOUR, AND THAT IS THE TRAP.** A neutral
grey has no chroma to add back at line 230, so it is 60% of a palette whose
mid tint is `(0.30, 0.46, 0.38)` — **and it comes out green.** The deadest
thing you can paint is the one the filter colours in most. The first dead
Earth was a flat grey ball and the filter made it a pale green one.

So every grey on this planet carries a **slight warm bias**, a few hundredths
of red over blue, which the green ramp then cancels. **To read as grey in this
game a thing has to be faintly brown to begin with** — and that applies to
concrete, hulls and dust everywhere else in the project, not just here.

### 2.3 Coastline is the detail budget

`_earth_texture()` runs at a **higher noise frequency than a real map wants**
(0.0075, six octaves). You only ever see a crescent of this through a 4 m
aperture, and large smooth landmasses put no edge in that crop at all. The
quantiser keeps hard boundaries and throws away smooth gradients, so
**coastline per square metre is the detail**, the same way the edge pass is
what makes low-poly geometry legible in the first place. The burn scars are
the other half: low-frequency structure, because at this distance nothing
small survives.

**Three ways out, and this one is the human's:**

1. **Let the planet carry it** (what is rendered). Costs nothing, works today.
2. **Glass that darkens the aperture** so the sky sits in a distinctly lower
   value band than the wall. Cheap, untested.
3. **Drop `dither_strength` for the station only.** It would make the windows
   work and it changes the look of the one room the player spends most of
   their time in — which may be right, and is not mine to decide.

---

## 3. Rotation: nothing in the room moves, the sky turns

`orbit_spin_a.png` and `orbit_spin_b.png` are one camera, two frames, **9° of
sky apart.** Every surface in the station is identical between them.

This is exactly the train's trick, repointed. `tunnel_scroll.gdshader` scrolls
a bar of light along a wall 20 m outside eight window apertures and lets the
apertures turn that into motion; its own header is explicit that **nothing in
the train moves, because moving it would mean moving the player, the squad and
the physics with it.** The same is true of a station and the same answer
works: one node holds the sky, and `rotation.y` is the whole mechanism.

**We would be deleting the train and keeping its best idea.**

A real rate: the limb crossing one 4 m aperture over about forty seconds reads
as motion without being something you can watch. Untested — it needs a video,
not a PNG, and it needs somebody to stand there.

---

## 4. Scale, in metres

Every number is in `mock_orbit.gd` as a named constant.

| | |
|---|---|
| deck | 60 m along the walk, 26 m across |
| ceiling | **18 m** — twelve times the player's own height |
| window apertures | 4 m wide × 9 m tall, 8 m pitch, seven of them |
| sill | **1.2 m, below the eye** |
| well | 11 × 34 m hole in the deck, **46 m** to the machinery floor |
| ops table | 7.0 × 3.0 m, top at 0.95 — `fit_ops_table.gd`'s real slab |

**THE SILL BEING BELOW THE EYE IS WHAT MAKES IT READ AS OUT RATHER THAN UP.**
At 1.2 m the bottom of what you see through a window is sky, not wall. The
train's apertures were 2.0 m wide between 1.25 m and 3.0 m, which is a
porthole by comparison — and the train said so itself.

**THE CEILING IS DOING MORE WORK THAN THE LENGTH.** 60 m of deck reads as a
long room; 18 m of ceiling over it is what reads as *a structure you are
inside rather than a corridor*. If anything has to shrink for performance,
shrink the length.

---

## 5. The pictures

| file | what it is for |
|---|---|
| `orbit_gallery.png` | the walk: window wall, ceiling, pod hatch at the far end |
| `orbit_window.png` + `_raw` | **the A/B in §2.** Read these two together or neither |
| `orbit_well.png` | the refinery below, lit orange from inside itself |
| `orbit_table.png` | the ops table at its real size, against the windows |
| `orbit_pod.png` | the pod in its cradle, hatch lit, beside a window |
| `orbit_spin_a/b.png` | rotation, 9° apart |
| `orbit_plan_not_eye_level.png` | massing from outside. **Named so nobody reads it as a picture of the game** |

**The strongest single image is `orbit_well.png`** and it is the one I would
hand to TERRAIN first: "a platform above a refinery" is legible in it at a
glance, which is what the brief asked for in words.

**THE MACHINERY IS THE ONLY WARM LIGHT IN THE STATION.** Orange from below
against Home Command's blue-white from above, because the machinery predates
Home Command and is running unattended — which is the whole of `lore.txt`, and
it means the one thing lighting your feet is a thing nobody is supervising.

---

## 6. Settled, and what is still open

**GALLERY, decided by the human 2026-10-23.** Not a drum. The honest shape for
a rotating station is a drum you stand inside with "down" pointing outward,
and the horizon curving up in front of you is a famous image and an unreadable
room. The gallery reads immediately, and §8 is now a build spec rather than a
study.

Still open:

1. **Does the deck loop round the well, or run along one side?** It is a loop
   in these renders and that is what was signed off, so it stays unless
   somebody says otherwise. **I would build a single side**: the walk from
   table to pod becomes a straight line along the windows, the well sits
   against the inner wall where you look ACROSS it rather than around it, and
   it is half the deck to build. One constant in `mock_orbit.gd` and a
   re-render if you want to see it before choosing.
2. **Does the pod have a window?** `ORBIT.md` §7: a sealed box is the one
   transition that can exist while the world outside it is being freed, which
   makes the drop the loading screen. A window makes it a descent. Probably
   not both.
3. **How far down is the machinery, really?** 46 m reads. It is also 46 m of
   geometry nobody walks on, and the bottom is dim enough that most of it
   could be a backdrop.
4. **Does the deck run round the well, or along one side?** It is a loop here.
   A single long side is cheaper and makes the walk from table to pod a
   straight line past everything.
5. **Is there anything to do on the deck besides choose and leave?** With no
   squad in orbit, the walk has lost the thing that made the train's rake
   worth its length. §3 of `ORBIT.md` flagged this; it is now live.

---

## 7. What was wrong on the way here, recorded

**The first render was read as "the windows are full of stars" when the
speckle was the filter's own dither over every surface in the frame.** That is
the reason `NOFILTER=1` exists, and the reason §2 is the first section rather
than a footnote.

The sky dome was also built with culling disabled, so the near wall of an
1800 m sphere drew over the deck, the table and everything else — a star field
with a room faintly behind it. And the planet started at 1300 m, which put it
closer to the station than its own radius: the plan shot was taken from
*inside* the planet and came back as a green wall.

**The planet took five passes** and §2.1-2.3 have the reasoning: emissive
green, then correctly textured but exposed three stops too hot and still
cream, then lit at 0.95 where the chroma survives, then flat grey — which the
palette turned green again — and finally warm-biased grey with the dust thinned
and the coastline frequency raised so anything survives the quantiser at all.

**And the well had no shaft.** The deck is 0.4 m of slab with open space under
it, so from down the gallery you looked through the hole, under the floor, and
out at the stars — the floor had a window in it. Eighteen metres of wall round
the opening closes it. Worth carrying into the real build: **any hole in a
deck needs the shaft modelled, not just the hole.**

---

## 8. For TERRAIN: what to build, and what gameplay will look for

The shape is settled, so this section stops being a study and becomes the
contract. §4 has every dimension.

### 8.1 It needs NO NAVMESH and NO WALKER CLEARANCE, and that is most of the job gone

`tools/block_railhead.gd`'s header spends its first forty lines on one piece
of arithmetic: a Walker is 1.7 m wide and 3.0 m tall, Godot has **no
per-agent path clearance**, and the baker will route one down anything that
shows a ribbon — so a corridor had to be ≥ 3.0 m clear, a doorway ≥ 2.2 m,
and nothing walkable could exist between 1.0 m and 2.2 m. `_audit()` measured
all of it from the brushes and refused to write a piece that failed.

**None of that applies with no squad in orbit**, and the train is already
most of the way there. Checked rather than assumed:
`maps/railhead_level.tscn`'s `NavigationRegion3D` **has no `navigation_mesh`
assigned at all.** The node is there as a parent for the art and nothing else.
The squad at base is PLACED at markers and stands in them; it does not path.
(`maps/depot_level.tscn` does carry one — the two bases differ, and the one
that is live does not.)

So the clearance arithmetic was never protecting the base. It protects the
**mission maps**: `railhead_station.tscn` is instanced by Hillfort and the
Salient, and those are baked, with a Walker on them.

Which means: **no NavigationRegion3D, no clearance audit, no 3 m lanes** on
the station, as long as its pieces are not reused on a baked map. Build the
room the shape wants. Say this out loud before anybody starts — it is the
biggest single difference between this and the train, and a large part of
`block_railhead.gd` serves a rule that does not reach orbit.

### 8.2 The marker contract

Named markers are the only thing the art and the gameplay level agree on, and
**nothing may be a typed coordinate** — `maps/railhead_level.gd` says why: the
Polaris objective was typed, the road moved six metres, and the marker ended
up inside a wall. Every position is read out of the art at load.

| marker | what hangs off it |
|---|---|
| `Table_Anchor` | the operations table. 7.0 × 3.0 m slab, top at 0.95 — `fit_ops_table.gd`'s real size, so leave it that footprint of clear deck |
| `Table_ViewA` | where the player wakes, standing at the table facing it. The train learned this: its PlayerArrival was at the far end of the rake and put six carriages between you and the only thing you had to use |
| `Pod_Hatch` | the doorway you walk into. The `LevelExit` goes here |
| `Pod_Inside` | where the player stands once aboard, if the pod is a room you enter rather than a door you touch |
| `Sky_Pivot` | **one node the whole sky is parented to.** §3 is the entire rotation mechanism and it needs the stars, the planet and nothing else under a single transform |

**No `BarracksRack_*`, no `FabricationMount_*`, no `RepairBay_*`.** Those
eleven-plus markers existed to post a squad that is no longer aboard. The
contract is five markers instead of fifteen.

### 8.3 The pieces

1. **Deck** — 60 × 26 m, ceiling 18 m. §6 question 1 may halve it.
2. **Window wall** — seven apertures, 4 × 9 m, 8 m pitch, **sill at 1.2 m**.
   The sill height is the one number I would not move: below the eye is what
   makes the window read as *out* rather than *up*.
3. **The well and its SHAFT** — 11 × 34 m opening, walls carried at least
   18 m down. §7: without the shaft you see space through your own floor.
4. **Machinery** — massing only, 46 m down, lit orange from inside itself. It
   is the only warm light on the station and most of it can be backdrop.
5. **Pod bay** — cradle, collar, hatch, at the far end of the walk.

### 8.4 What this does not cover

The pod's INTERIOR, because `ORBIT.md` §7 has not been answered: a sealed box
can cover a level load and a box with a window cannot. That is a gameplay
test, not an art decision, and it should be run before the bay is modelled.
