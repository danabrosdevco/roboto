# Brief — bearskin fur, for the Walker's officer form

Written 2026-10-06 by GAMEPLAY, off eight rounds of vehicle hat mock-ups
(`tools/mockup_shots.gd -- <dir> trials`). The geometry is settled and approved;
the surface is not. `mockup_parts.fur_material()` looks for `bearskin_fur.tres`,
fails, and falls back to flat `StandardMaterial3D` at albedo 0.11 — in the
renders it reads as a charcoal chimney.

Owner: **whoever takes it**. Status: **not started**.

**Deliverable:** two entries in `tools/make_textures.gd` — `bearskin_fur` and
`bearskin_fur_worn` — each with a `_mask.png`, built the same way `camo_fabric`
and the `pauldron_plate` set were. No pixel of the bought pack gets read,
sampled or filtered; the licence is kept by drawing from nothing and copying only
the style, which is what that file already does.

The moment `bearskin_fur.tres` exists the kit picks it up with no code change —
`fur_material()` already resolves it by name and warns when it is missing.

---

## Why this is not `beret_wool`

Those are two different surfaces and the difference is the whole point.

**Wool is flat and dense; fur is deep and broken.** Dress wool reads as a
restless flat colour. Fur reads as a surface with *depth* — darker in the
valleys between strands, brighter where the nap catches light, and irregular at
every scale. A bearskin rendered in wool is a felt tube, which is exactly what
the current placeholder looks like.

**And this is the largest single piece of cloth in the game.** A 0.96 m column
plus a 0.63 m crown cap, on a frame three metres tall. The beret is a 1.00
disc seen at a glance; this is a wall. Everything that is forgivable at beret
scale is obvious here.

## What it goes on

Two pieces, both large and both curved — which makes this the opposite problem
to the pauldron brief, where everything was small, and to the wool brief, where
everything was flat.

| piece | shape | size on screen at 20 m |
|---|---|---|
| column | 16-sided cylinder, r 0.56, 0.96 tall | ~26 × 45 px |
| crown cap | squashed sphere r 0.63, wider than the column | ~30 px across |

Three consequences:

**1. The seam runs vertically, sixteen times around.** A 16-sided cylinder tiles
the texture around its circumference, so a pattern with any horizontal structure
will show sixteen repeats marching round it. **Make it vertical-dominant** —
which is also what fur does, since it hangs.

**2. It is big enough to need two scales.** Unlike everything else in the pack,
this piece is large enough that a single grain size will read as noise. It wants
a fine strand texture AND a coarse clumping on top of it.

**3. It is the darkest thing in the pack and must still read.** A guardsman's
bearskin is black. Against this game's pale concrete and washed-out ground, a
genuinely black column becomes a silhouette with no interior at all.

## The one real decision: it stays OUT of the faction colour

This is the opposite call to `beret_wool`, which the brief in `BERET_WOOL.md`
puts at 70–85% in band so a player's beret is cyan and an enemy's amber.

`Character/faction_metal.gdshader` repaints by luminance band — centre 0.45,
width 0.425. **A bearskin should sit below it, like `camo_fabric` does**
(measured at 0.2% repainted), for one reason: a cyan bearskin is a novelty hat.
The bearskin's job is to be an enormous black mass that cannot be mistaken for
anything else on the battlefield, and that silhouette does the rank-reading on
its own without needing colour.

So: **under 10% in band**, with the mask holding out everything except —

- the **plume** is separate geometry on `as_plate`, so it is already handled;
- a **narrow brighter band at the very top of the crown**, which may be left in
  band so there is one small faction-coloured highlight catching the light. This
  is optional and worth trying both ways.

Use the `_mask.png` red channel with `derive_mask_from_albedo = false`. Green is
0: no emissive.

## Numbers to hit

Checked with `godot --headless --path . --script res://tools/probe_texture_stats.gd -- textures/PSX_Textures bearskin`

- 256×256, RGB8
- mean luminance **0.10–0.15**. Deliberately the darkest entry in the pack —
  below `camo_fabric`'s 0.130 is acceptable here, where it was not on the beret.
- peak **≤ 0.34**. Lower than the pack's usual 0.46 ceiling, because the
  brightest a fur highlight gets is still dark grey. **Hold this.**
  `pauldron_plate` shipped at 0.701 against a 0.46 ceiling and photographs as
  polished chrome; that is the standing defect in this kit and the reason this
  number is called out twice.
- **minimum luminance ≥ 0.045.** This is the unusual one and it matters more
  than the ceiling: pure black kills the interior of the shape and leaves a
  cut-out. There must be enough floor that the column reads as a volume.
- saturation **0.02–0.07**. Almost neutral, very slightly warm.
- in band **under 10%**.
- quantised to 32 levels a channel through the same 4×4 ordered dither
  everything else in that file uses.

## What should be in it

In rough order of how much work each does at distance:

1. **Vertical strand structure.** Hard-edged streaks running top to bottom,
   8–14 texels wide, varying in length and never reaching the full height. This
   is the base layer and most of the read.
2. **Coarse clumping over the top.** Irregular darker masses 40–70 texels
   across, soft-edged, grouping the strands. Real fur clumps; without this the
   strands read as corduroy.
3. **A broad vertical light gradient**, brighter toward the top third. GL
   compatibility lights this flat and the piece is a cylinder, so the falloff
   that makes a furred column read has to be painted in. Keep it gentle — this
   is the detail most likely to tip into looking like a gradient fill.
4. **Tip highlights**: a sparse scatter of short brighter strokes at the top end
   of some strands, where light catches the ends. Perhaps 1 strand in 8.
5. **`_worn`**: the same bearskin after a campaign — matted in patches, the
   clumping heavier and less even, a few strands laid flat and shinier. The
   relationship between `bearskin_fur` and `bearskin_fur_worn` should match the
   one between `camo_fabric` and `camo_fabric_worn`, so the pair can be swapped
   by rank or by missions survived without a second conversation.

## What should not

- **Horizontal structure of any kind.** Sixteen repeats round the cylinder will
  turn any horizontal band into a visible ring.
- **A tileable regular pattern.** At 26 px wide the column shows roughly one
  repeat per facet; a recognisable motif will march.
- **Pure black.** See the minimum-luminance note.
- **Anything above 0.34.** A bright highlight on fur reads as wet plastic.
- **Anything finer than ~6 texels.** Finer than that is grey mush at 20 m.

## How to check it is right

Three steps, in this order. The third is the one that matters.

1. `probe_texture_stats.gd` for the numbers above, including the MINIMUM, which
   that probe does not currently report — add it, or check it by eye in an image
   editor's histogram.
2. Nothing to wire — `fur_material()` already loads it by name.
3. **Re-run the hat trials and look.** `godot --audio-driver Dummy --path .
   --script res://tools/mockup_shots.gd -- <dir> trials` renders all seven hats
   on their frames. Eight rounds of this is how these got from rounded lumps to
   recognisable helmets, and every one of those rounds was a thing that looked
   fine reasoned about and wrong photographed. A fur that passes the stats and
   still reads as a charcoal tube in the close-up has failed.

## Open question for the human

The Tarleton's roach was going to share this texture, and at the last review it
was moved to `pauldron_plate` instead — a polished metal comb rather than fur,
which suits a robot in a cavalry helmet. **If that stands, this texture has
exactly one customer**, and it is worth asking whether one bearskin justifies a
bespoke pair of textures or whether it should borrow `beret_wool` darkened. My
view is that it justifies them, because the piece is enormous and a felt tube is
very obviously a felt tube — but it is a real cost and the call is yours.
