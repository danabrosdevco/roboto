# SEE-ENGINE — design document

ARGUS · supply 3 · ground · command node · enemy only
**status: concept selected, not built**

**Prerequisite: `docs/frames/ENEMY_FACTIONS.md`. Do not build this before
`are_hostile` is a table.**

---

## 1. Concept

**Selected: A — THE OCULUS.** 3.10 W x 4.57 H x 2.84 L.

One 2.3 m lens in a two-hoop gimbal on a too-slender column, four thin overlong
legs, and the pupil set off-centre and low.

**It reads as a single watching intelligence**, which is precisely what Argus
is, and it does so as one shape — which matters at icon size, where the busier
options turn to mush. The gimbal hoops and the spindly legs make it look
assembled for seeing rather than for fighting, and the off-centre pupil is the
detail that makes it uncomfortable to look at.

No `K.head` anywhere in any of the four, and none of them has a face. The
Walker's single offset eye is StratCom's grammar and the player's own factory;
Argus should be recognisable at a glance as **not from the same production
line**.

The other three: **B CHANDELIER** — no hull at all, a spine with three tiers of
7/5/3 outward-staring eyes — is the most alien of the four and was the close
second, but it is also the busiest and would not survive being drawn at 40
pixels. **C SLAB** is a blank monolith whose only optic is nine lenses in a
letterbox slot, with four unmatched booms reaching out around it: the body does
not look at you, its limbs do, which is a genuinely unsettling idea, but at
6.82 m wide it is enormous. **D CANOPY** is an inverted cone heaviest at the
top with eleven eyes staring down off the rim; it looks like it could not take
a step, which is evocative but reads as a lamp.
Art brief: Argus is an orbital command intelligence that has corrupted and now
spends nearly everything on its own reward loop. Tyrian purple. It should look
like it was designed by something that **does not think in terms of soldiers**
— unsettling proportions, too many sensors, no obvious face. Many eyes, or one
enormous one. Explicitly *not* the Walker's single offset eye, which is
StratCom's grammar.

## 2. What it is for

Argus is a command intelligence. Its frame should command, not brawl.

**While it lives, nearby Argus units aim better and share contacts.** That runs
straight through the contact ledger built into `AIManager` — `note_seen`,
`designate`, `contact_for`, and the `w_fresh` / `contact_accuracy` terms that
already make a spotted target easier to hit. The See-Engine is the enemy's
version of the player's Spotter, turned into a force multiplier for a whole
formation.

**It barely fights, and that is the threat.** It is the first enemy whose
danger is legible without a gun pointed at you: the formation around it is
visibly better than it should be, and the counter is obvious without being
easy — get past the escort and kill the thing that is not shooting.

Thematically it is also the only frame in the game that *is* Argus rather than
merely belonging to it. The chain of command in CLAUDE.md says Argus no longer
supervises anything; a See-Engine on the ground is one of the few places that
neglect becomes visible as a machine.

## 3. Stats

| field | value | why |
|---|---|---|
| `id` | `&"see_engine"` | **permanent once a kill is saved** |
| faction | ARGUS | |
| `supply` | 3 | |
| `cost` | 0 | `purchasable = false` |
| `base_health` | 240 | it must be killable once reached |
| `base_speed` | 0.75 | |
| `base_sensor_range` | **110** | the highest in the game; the Spotter is 90 |
| `weapon_slots` | 0 | **it does not shoot** |
| `turret` | false | |
| `vehicle` | true | |
| `drives` | false | |
| `equipment_slots` | 0 | |
| `module_slots` | 0 | |
| `musters_at_base` | false | |
| `signal_resistance` (scene) | 1.4 | hardened, not immune |

**`weapon_slots = 0` and the highest sensor in the game are the same
statement.** It sees everything and shoots nothing, and everything near it
shoots better for that reason.

## 4. New weapons

**None.** Its effect is behaviour on the chassis, not an item. There is nothing
to mount.

## 5. Model

New scene from `tools/build_see_engine.gd`; script `see_engine.gd`, `extends
Soldier` or `Walker` depending on the concept.

```
See-Engine (CharacterBody3D, groups=["enemies"])   <- add_to_group(.., TRUE)
+- CollisionShape3D
+- Bark / NavigationAgent3D / Detection
+- Rig
|  +- Hull: NOT the player's chamfered vocabulary. Argus should read wrong
|  +- Sensor cluster: many lenses, or one large one. No turret ring
|  +- Masts / antennae
|  +- Legs or a column
+- SparkBurst / OilSpray
+- FactionLivery  (TYPED Array[Node3D])
```

**No single offset eye.** That silhouette is the player's own factory and
belongs to StratCom. Argus should be recognisable at icon size as *not from the
same production line*, and the eye is the cheapest place to say so.

Plus the five silent traps: typed node-path exports, `add_to_group(.., true)`,
typed `Array[Node3D]`, mount yaw **+90 degrees** if any mount exists, and the
`turret`-node rule (not relevant — nothing fires).

## 6. Code requirements

**Nothing in `Enemy` or `Soldier`.** Two pieces, both reusing systems that
shipped recently:

1. **Contact sharing.** `AIManager.note_seen(faction, body)` already writes
   into the per-faction contact table, and `hostiles_for` / `contact_for` /
   `is_fresh` already read it. A See-Engine that calls `note_seen` for
   everything inside its 110 m sensor **is** the contact-sharing effect — the
   plumbing exists and this frame is a caller.

2. **Tightened aim.** `_contact_assisted()` and `SPOTTED_SPREAD` already make a
   robot shoot straighter at a target a squadmate can see. If the See-Engine's
   `note_seen` calls make its formation's targets "assisted", that term does
   the work with no new code. **Verify this before writing anything else** —
   if it already falls out, this frame is almost free.

   If it does not fall out, the fallback is an explicit accuracy bonus applied
   to same-faction units in radius, computed fresh each tick rather than
   mutated, for the same reason the Bastion's resistance bonus must be.

3. **The death must be legible.** Killing it has to visibly degrade the
   formation, or the player never learns the rule. The existing suppression
   VFX and the HUD's contact brackets are the obvious hooks: contacts the
   See-Engine was feeding should go stale and the brackets should drop.
   **If the player cannot see the difference, the unit does not exist.**

**Known gap:** nothing in `EquipmentContext` or the combat scoring knows "my
command node died", so the formation will not *react* — it will just get
worse. That is acceptable and arguably correct, but it means the legibility in
(3) is doing all the communication.

## 7. Tests

`tools/test_see_engine.gd`:

- registered, supply 3, `purchasable = false`, faction ARGUS,
  `weapon_slots = 0`, `base_sensor_range = 110`
- **`are_hostile(PLAYER, ARGUS)` true both ways** — proves task zero
- it writes contacts for its faction: a target it can see appears in
  `AIManager.contact_for(ARGUS, target)` and is fresh
- an ARGUS unit that cannot personally see that target still benefits —
  measured through `_contact_assisted()` or the explicit bonus, whichever
  section 6.2 settles on
- **a SWARM or STRATCOM unit does NOT benefit** — same trap as the Bastion,
  and it follows from the three enemy factions not being hostile to each other
- killing it stops the contact feed, asserted by checking freshness decays
- in `"enemies"` and `AI.SIGNAL_GROUP`; typed arrays populated
- it never enters a firing state

## 8. Open

- Whether `_contact_assisted()` already delivers the aim bonus (section 6.2).
  This is the single question that decides whether this frame is cheap or
  medium. **Check it first.**
- Radius for the command effect. The 110 m sensor is what it *sees*; what it
  *helps* should probably be smaller, or one See-Engine covers a whole map.
- Whether Argus units should be visibly worse when it dies, or merely
  measurably worse. Visibly is better and costs art.
