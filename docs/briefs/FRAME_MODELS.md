# Building a frame model — the shared recipe

One frame, one agent. Read this, then your frame's doc in `docs/frames/`.

---

## 1. Scope — the model, and nothing else

You are building **geometry in a scene**. You are not building the unit.

**In scope**
- `tools/build_<frame>.gd` — a one-shot generator
- `Character/characters/ai/<frame>.tscn` — what it writes

**Out of scope, and do not touch**
- `Campaign/chassis/chassis_*.tres` — no catalogue entry
- new weapon items, new `ItemDefinition`s
- new behaviour scripts, `enemy.gd`, `soldier.gd`, `walker.gd`, `rover.gd`
- `Managers/enums.gd`, missions, the armoury, the shop
- any registration of any kind

A frame whose model exists and whose stats do not is a known, deliberate,
half-finished state. A frame that quietly edited `enemy.gd` to make itself work
is a problem for nine other people.

## 2. The generator is a one-shot, not a build step

`tools/build_bulwark.gd` is the worked example. Read it before you write
anything — it is 514 lines and it is this recipe in executable form.

```
godot --headless --audio-driver Dummy --path . --script res://tools/build_<frame>.gd
```

Run it once. **After that the `.tscn` is the source of truth.** Re-running it
over an edited scene throws away the edit, which is how force-rebuilds have
repeatedly cost this project its gameplay layers. Say so in your header.

It exists because a robot scene is thirty sub-resources with hand-numbered ids
and an exact `load_steps` count, and writing that by hand is transcription with
nothing to learn from.

## 3. The node contract

Copied from `bulwark.tscn`, which passes. Yours may differ in the middle —
legs versus wheels versus rotors — but not at the edges.

```
<Frame> (CharacterBody3D, groups=["enemies"])
+- CollisionShape3D          capsule or box, sized to the ART, not guessed
+- Bark (bark.tscn)          two voice clips, pitch range
+- NavigationAgent3D
+- Detection (Area3D) +- CollisionShape3D
+- Rig (Node3D)
|  +- Hull (CSGMesh3D) + its subtraction cuts
|  +- ... the frame
|  +- WeaponMount (Node3D)   yaw +PI/2, under whatever aims
+- SparkBurst (spark_burst.tscn)
+- OilSpray (oil_spray.tscn)
+- FactionLivery (Node + faction_livery.gd)
```

**Everything visible goes through one `_mesh()` helper** that sets
`material_override` to the shared `robot_metal.tres`. A single unpainted piece
is invisible as a bug until someone renders the frame in a faction colour.

**The eye, if the frame has one, is the exception** and keeps its own
`StandardMaterial3D` with `robot_eye_psx.png`. Three of the ten frames
deliberately have no eye — check your doc before you add one.

## 4. Which script goes on the root

**Use an existing one.** No new behaviour scripts in this pass. Pick by
locomotion, then wire every node-path export that script declares:

| locomotion | script | node paths you must wire |
|---|---|---|
| legged | `walker.gd` | `rig`, `hip_left/right`, `knee_left/right`, `foot_left/right`, `turret`, `gun_pivot` |
| wheeled | `rover.gd` | `rig`, `turret`, `gun_pivot`, `wheels`, `reverse_lamps` (both Array[Node3D]) |
| infantry | `soldier.gd` | none of its own |
| flying | `spotter_drone.gd` | `rotor_loop` (AudioStreamPlayer3D) |

All four inherit `enemy.gd`, so **all four also need** `nav_agent`,
`weapon_mount`, `detection`, `visible_pieces`, `particle_effects_die`,
`particle_effects_hit`, and `coax_mount` if the frame has a second mount.

**Do not take this table on trust — `grep '^@export var' <script>` and check.**
It was wrong on first writing: it claimed `spotter_drone.gd` declared no node
paths, and the Kite agent found `rotor_loop`, which the script stops and
restarts on park, crash, downed and revive. A flyer without that node is
silent through all four, and nothing says so.
If your frame has no turret (the Lance), the script still declares one: give it
a body-fixed `Node3D` named `Turret` that never rotates, and say in the header
that it is a stub satisfying the export rather than a traverse. **Do not edit
the script to remove the export.**

## 5. The five silent traps

Every one of these shipped on the Bulwark's first build. None raises an error.

1. **`add_to_group("enemies", true)`** — the second argument defaults to
   `false`, meaning "this run only". Without it the scene saves with no
   `groups` line and the robot is invisible to `AIManager`, to EMP and to every
   hostile sweep in the game, while still walking around looking correct.

2. **Typed arrays, or they save as `[]`.** `visible_pieces`,
   `particle_effects_die`, `particle_effects_hit` and the livery's `pieces` are
   typed exports. Assigning a plain `Array` to one fails **silently** and packs
   as empty. Declare `var v: Array[Node3D] = []` and append.

3. **An empty livery `pieces` is worse than no livery.** `FactionLivery` falls
   back to walking its whole parent, which paints every mesh on the frame
   **including the eye**. That is exactly how the Bulwark's eye ended up
   faction-coloured after being carefully left off a list that was never there.

4. **`WeaponMount` yaw is `+PI/2`, not `-PI/2`.** Both shipping frames agree.
   Built the other way the barrel points backwards and nothing complains.

5. **A `NodePath` assigned into a typed `Node3D` export does nothing.** Set the
   property to the node *object*: `root_body.set("rig", rig)`.


**Trap 2 is in the worked example, and it bit.** `build_bulwark.gd` set
`bark_clips` from a plain array. `bark_clips` is `Array[AudioStream]`, so the
assignment was dropped in silence and `bulwark.tscn` shipped with
`bark.tscn`'s three default voice clips instead of the two the generator
names — verified by reading the ExtResource paths out of both files. The
Bulwark has had the wrong voice since it was built and it still barks, which
is why nobody noticed. The generator is fixed; **the scene is not**, because
changing a shipped robot's voice is a game-feel call for the human.

Read that as the real shape of this trap: it is not about the four arrays
listed above, it is about **every typed export on every node you touch**,
including ones on components you merely instantiate.

### Two load errors you are expected to see

Every generated frame scene prints this twice on load:

```
ERROR: Cannot assign contents of "Array[Object]" to "Array[int]".
```

`Enemy` declares `AllowedMovementOptions` and `AllowedCombatOptions` as arrays
of enums — `Array[int]` — but the `.tscn` writer emits them typed against the
element script of the `equipment_slots` array above them. Both values are
empty defaults, so nothing is lost. `bulwark.tscn` has the identical pair and
has printed them since the day it was generated. **Do not chase this and do
not work around it** — report it and leave it; it is one shared fix for the
whole family and it belongs to the coordinator.


### Three more, all found by build agents

**`FactionLivery._gather()` RECURSES.** Listing a container in `pieces` paints
every mesh under it, so `pieces = [Rig]` is the same bug as an empty list
arriving by a different door — it will paint the eye. List leaves, not
parents. The Broodcarrier's list is 55 leaf meshes for exactly this reason.

**`enemy.gd` also declares `weapon` and `coax` as typed `AIWeapon`**, next to
`weapon_mount` and `coax_mount`. Nothing in this pass fits a weapon, so they
stay null — but the table above reads as exhaustive and is not. Note too that
`spotter_drone.gd` extends `Soldier`, not `Enemy` directly; the inheritance is
`SpotterDrone -> Soldier -> Enemy -> AI`, which matters for which seams you
can override.
### One known fault in `concept_kit.gd`

`head()` places its mount ring at `at` and the turret body at
`at + 0.19 * scale`, with the body taller than the gap — so the ring is
**inside the body at every scale** and has never been visible on any concept
sheet. Harmless in a concept, six wasted faces in a model. Move it or drop it,
and say which.

Its antenna is fine on a turret standing on a hull, which is every frame that
uses it that way. On the Kite, hanging the head *under* a hull put the whip
inside the fuselage. Check where yours ends up rather than assuming either.

6. **A legged frame's rest pose cannot live on the hip.** `walker.gd`'s
   `_pose_leg` **assigns** `hip.rotation.x`, `hip.rotation.z`,
   `knee.rotation.x` and both foot rotations every physics frame, including
   zeroes at a dead stop. Anything baked onto a hip or knee is therefore wiped
   on the first tick — and if only some legs are wired, only those collapse,
   so the frame stands with two limbs splayed and two plumb and nothing warns.
   Pre-apply the rotation to the child node's *position* and put it on the
   meshes, leaving hips and knees at identity. `walker.tscn` already does this
   (HipL is at identity; the tilt is on `ThighL`) without saying it is a
   workaround.

   Found independently by the Bastion and See-Engine agents, which is why it
   is here: two frames hit it in the same hour.

   `bark` belongs in the list above too — it is an `@export var bark: Bark` on
   `enemy.gd:93`, and a frame that misses it is silent with nothing to say so,
   the same shape as `rotor_loop`. `check_frame.gd` now asserts it.
A seventh, for anything that cants a barrel upward: a rotation about **+X** maps
−Z to `(0, sin, −cos)`, so a **negative** angle aims the muzzle at the floor.
Three of Picket's five first-round concepts had this sign wrong.

## 6. Proving it

Three commands. All three, in this order, and paste the output in your report.

```bash
bash tools/check.sh --changed
```

```bash
godot --headless --audio-driver Dummy --path . --script res://tools/check_frame.gd -- res://Character/characters/ai/<frame>.tscn
```

`check_frame.gd` is the Bulwark's bug list turned into a test: groups,
typed arrays, livery, eye exclusion, mount yaw, unpainted meshes, and the
measured bounding box. **It must print `PASS`.** `check.sh` proves the scene
parses; every bug in section 5 passes that and fails this one.

```bash
godot --audio-driver Dummy --path . --script res://tools/shoot_chassis.gd -- <out dir> res://Character/characters/ai/<frame>.tscn res://Character/characters/ai/walker.tscn
```

Renders your frame beside the Walker. **Look at the PNG.** The measured
bounding box is in `check_frame.gd`'s output; compare it to the dimensions in
your design doc's section 1 and report the difference rather than hiding it.
This one needs a window — no `--headless`.

The Godot binary is
`D:/Godot Games/Godot_v4.3-stable_win64.exe/Godot_v4.3-stable_win64_console.exe`.
Use the `_console.exe` build: the plain `.exe` detaches and prints nothing, so
a failed run looks exactly like a successful one.

## 7. You are in a shared checkout

Three lanes, one branch, other agents mid-edit.

- **Do not create or switch branches.** Do not `git stash`, `git checkout` or
  `git reset`.
- **Do not commit.** Report back; the coordinator commits.
- **Only ever create your own two new files.** If you believe a shared file
  needs changing, say so in your report instead of changing it.

## 8. Report back with

- the two file paths you created
- `check_frame.gd` output, verbatim, including the measured box
- the path to the render, and what you think of it in two sentences
- **the difference between your measured size and the design doc's**, stated
  plainly
- anything you had to decide that the doc did not settle
- anything you think is wrong with the doc
