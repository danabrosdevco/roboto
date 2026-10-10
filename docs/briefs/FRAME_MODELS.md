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
| wheeled | `rover.gd` | `rig`, `turret`, `gun_pivot`, `wheels` (Array[Node3D]) |
| infantry | `soldier.gd` | none of its own |
| flying | `spotter_drone.gd` | none of its own |

All four inherit `enemy.gd`, so **all four also need** `nav_agent`,
`weapon_mount`, `detection` and `visible_pieces`.

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

A sixth, for anything that cants a barrel upward: a rotation about **+X** maps
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
