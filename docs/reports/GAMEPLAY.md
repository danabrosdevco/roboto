# GAMEPLAY — session reports

**Only the GAMEPLAY agent writes this file.** The coordinator reads it and folds
it into `docs/BOARD.md`. Nobody else touches it, which is why two lanes can
close a session at the same moment and never conflict.

**Append a new entry at the TOP, under this header.** Newest first. Keep old
entries — the point of this file is that the board has a memory.

Template — copy it, keep the four headings, delete what does not apply:

```
## YYYY-MM-DD — one line on what this session was about

**Landed.** What is different now, in plain terms. Not "worked on the depot" —
say what changed and where. Name the files you touched if it is not obvious.

**Gates.** check.sh: PASS/FAIL. test.sh and smoke.sh if you ran them, and what
they said. If you did not run one, say so rather than leaving it blank.

**Needs the human.** Anything to verify in-editor — scene wiring, inspector
values, a look at the thing in-game. This is the most valuable line in the
report; it is the one that used to die in chat scrollback.

**Blocked / next.** What you would do next, and anything stopping you.
```

Two things worth saying out loud, because they are the reports the coordinator
most wants and least often gets:

- **Say when something is unverified.** "Built it, did not run it" is a useful
  report. "Done" when it was never launched is not.
- **Say when you were wrong.** A reversal recorded here saves the next agent
  from repeating it. The rover collision shape that was built, regressed
  `test_vehicle` and got reverted is exactly that kind of thing.

---

## 2026-09-29 (later) — playtest fixes, and a level that will not stay fixed

**Landed.** The six things off the playtest, plus two bugs the work turned up.

- *The Hillfort had no objectives and deployed four robots.* Two separate bugs.
  The level had been regenerated without the objective nodes the mission names,
  and `active_objectives` is a WHITELIST — `Campaign._prune_inactive_objectives`
  frees every objective the mission does not name, so a mission naming two ids
  the level does not have ends up with none at all. The four robots were
  `SquadSpawnPoint.max_slots`, whose script default was 4; every hand-built
  level writes 999 over it and the Hillfort did not, so a seven-seat squad
  deployed four. The default is now 0 (= everyone), because forgetting it must
  not silently cost you robots.
- *Garrisoned shotgunners stood still and died.* `Soldier.perform_action` blocked
  every MOVE in `defensive_mode` unless the frame was `aggressive`, which is set
  for melee rushers only. A 45m shotgun in cover taking 60m rifle fire aimed at
  something it could not touch. It now also lets anyone move who is shot at from
  beyond their own `_max_range()` — `find_advance_target` still stops them at
  their own standoff, and Squad's defend tick skips anyone in COMBAT, so they
  push, then walk back to the post when it is over.
- *The induction opens on the keys.* A REVIEW_KEYS trigger (appended to the enum)
  completes when the KEYS tab of the options screen is shown. `OptionsMenu` emits
  `tab_shown`, `Master` relays it as `keys_reviewed` — relayed because the options
  screen is built on demand and freed on close, so there is nothing for an
  objective built at level load to connect to. It is first because every other
  objective's text names a key.
- *Debrief.* REVIVES was drawn in the compute blue, which is the colour of a
  currency everywhere else on that screen; it is green now, with KILLS, because
  both are what the squad did. Mission time moved from an unlabelled `12:34`
  beside the mission name into the stat row as a TIME counter that counts up.
- *Minimaps.* `tools/minimap_bake.gd` never listed the Hillfort or
  `mutaha_wip_level`, so the briefing for the final mission was showing the
  retired Mutaha map. Both baked. Mutaha renamed to **Qamareen** in the mission's
  display name and briefing; the internal `obj_mutaha_*` tags and the level
  filename are unchanged and are TERRAIN's to rename if they want.
- *Four Qamareen reserve squads that had never arrived.* `squad_engaged_tag()`
  lowercases the callsign — "EAST-YARD" becomes `east-yard_engaged` — and the
  mission wrote the tags in upper case, so WEST-ALLEY, EAST-AMBUSH, RESPONSE-EAST
  and the BOMBER were waiting on tags nothing could ever fire. Found by the new
  suite below, which is the only reason anyone knows.
- *A DEBUG tab on the pause menu, editor-only.* PAUSED → DEBUG opens the options
  screen on a fifth tab: two switches (UNLOCK ALL MISSIONS, UNLOCK ALL HARDWARE)
  and two handouts (+5000 resources, +50 compute), split under headings that say
  which are reversible and which are not. The switches are read LIVE by
  `available_missions()` and `locked_by()` and write nothing, so unticking puts
  the run back to what it earned; `locked_by()` being the one gate all four shop
  surfaces ask is why one flag opens weapons, frames, modules and equipment
  together. **The first gate I wrote was wrong**: `_playtest_data_shown()` uses
  `OS.is_debug_build()`, which is TRUE in a debug-template export — the build you
  hand a playtester. It is `OS.has_feature("editor")` now, checked in four places
  including `Campaign._debug_switch()`, because settings.json ships beside the
  executable as plain text and hiding the tab alone would leave "unlock
  everything" two lines from anyone with a text editor.
- *Three live runtime errors the suite had been printing and nobody failing on.*
  All in game code, all found by reading SCRIPT ERROR lines in a passing run:
  `SquadHUD._on_order_issued` threw on a null squad (every order, in the
  induction); `CampaignState._team_index`/`team_name` indexed a saved team row
  for a key it might not carry; and `DebriefScreen._card` threw on an entry with
  no record, then handed `add_child()` a null. The third was MASKED by the
  second — fixing one let execution reach the next. `test_endings` went from two
  script errors to none.
- *`test_ledger` had 31 checks that had stopped running.* `cat.chassis_def(&"chaser")`
  returned null once chaser and leaper left the player catalogue, `buyable()`
  called `duplicate()` on it, and the error killed the COROUTINE without failing
  the run — so `test_recruiting` and `test_supply_caps_the_active_squad` had not
  executed at all while the suite reported PASS. That is the second time this
  project has been bitten by exactly that. The enemy frames load by path now,
  which is also the honest door: the point of them is that they are NOT in the
  catalogue. 131 checks → 162. It also revealed a silent early return in
  `SoldierRecord.recompute_stats()`, which left a 45-health frame reading
  SoldierRecord's own 100 and said nothing; it warns now.
- *New suite: `tools/test_mission_objectives.gd`.* Reads every mission and its
  level as packed data and checks they agree. It would have caught the Hillfort
  in a second. It knows all four ways a `reinforcement_tag` can be woken — an
  objective id, `nest_down`, `<callsign>_down`, `<callsign>_engaged` — because
  checking against objective ids alone reports most of the game as broken.

**Gates.** `check.sh --changed`: PASS (27 scripts, 45 scenes/resources).
`smoke.sh`: PASS, booted clean — run because master.gd is the main scene and this
session changed it. `test.sh`: **33 suites** (two new), and the only failures are
pre-existing and named below — pittsburgh bridge spacing (TERRAIN), the mutaha
terrain check (a retired map), two tutorial sign checks (markers deleted on
purpose), and the twelve dead reserve tags. The only SCRIPT ERROR left in the
whole run is FuncGodot's `entity_fgd` parse error during level loads, which
`test_livery` passes in spite of.
`tools/test_debug_switches.gd` runs TWICE, once as the editor and once under
`ROBOTO_DEBUG_TOOLS=0` as an export would see it; both branches pass. All 13
minimaps re-baked.

**Needs the human.**

1. **`maps/hillfort_level.tscn` is being regenerated by the TERRAIN lane every
   few minutes** — 12:17, 12:23, 12:25 today — and the regenerator does not
   preserve nodes it did not place. Every rebuild deletes the relay console, the
   extraction and the spawn move, and the mission goes back to a blank objective
   HUD. The repair is one idempotent command:

       bash tools/hillfort_objectives.sh

   Run it after TERRAIN finishes. The real fix is for the block pass to leave
   non-generated nodes alone, which is a coordination call, not mine.
2. **Twelve reserve squads across four missions never arrive.** Their
   `reinforcement_tag` names a capture objective the level does not author —
   `basin_anchor`, `coast_relay_bridge/craters/town`,
   `pitt_relay_dam/shore/strip/furnace`, `mutaha_relay_clock/compute`. Same root
   cause as the Hillfort: the missions were written against capture objectives
   the levels no longer have. Those missions still play, because they also name
   objectives that DO exist, so the prune leaves something alive — but a chunk
   of each designed force has never once spawned. Deciding whether to build the
   objectives or re-point the reserves is a design call.
3. `maps/minimaps/mutaha_wip_level.png` has no `.import` yet. Give the editor
   focus once and it will import; I did not run `--import` with the editor open.
4. Unverified in game: the Hillfort's new start position, the relay console's
   placement in the yard, and the new first induction objective.

**Blocked / next.** Nothing blocked. Next would be the twelve dead reserves,
once someone says which way to fix them.


## 2026-09-29 — the Hillfort, the distance bands, and the Mark One

**Landed.**

- **The Hillfort — the missing rung between Proving Ground and Valley Basin.**
  TERRAIN built `maps/hillfort_level.tscn` with eighteen tagged points and an
  exit; the mission on it is `Campaign/missions/mission_hillfort_1_relay.tres`.
  Fifteen squads, 30 bodies on the map and 8 held back, all infantry — shotguns,
  rifles, chasers and leapers, nothing armoured and nothing on wheels. It is an
  ascent: spawn at y=0 z=449, fight up through the cistern, the standing stones,
  the old gate and the terrace, and take the relay dish in the fort yard at
  y=132. Taking it wakes POSTERN and SPUR, who come back through the postern
  gate and down off the north spur to retake it; the exit is the roof above.
  **This is what the economy audit asked for.** Proving Ground to Basin was a
  6.6× step in opposition against +1 seat — the single cliff in the campaign.
  It is now 3.2× then 2.1×, and the purse going into Basin rose 860 → 1140.
  **It also gives the Mark One a home:** the Hillfort unlocks it, closing the
  last "buyable from minute one" hole. `basin_1_anchor` now requires
  `hillfort_1_relay` rather than `arena_5_proving`.
- **`maps/hillfort_level.tscn` gained two objective nodes** — the RelayDish
  capture point and the ReachObjective on the exit. That is TERRAIN's file and
  the board says missions are GAMEPLAY's, which is exactly the seam: objectives
  live in level scenes. Done on the human's instruction, backed up first, and
  recorded here.
- **Audio: three distance bands.** `Weapons` (0-40m, as authored), `WeaponsMid`
  (40-150m, low-passed to 4.2kHz) and `WeaponsFar` (150m+, 850Hz), all children
  of Effects. `Managers/weapon_audio.gd` picks the band per shot; past 150m it
  switches Godot's attenuation OFF and computes the level itself, falling 2dB
  per doubling instead of 6, continuous at the boundary.
  Called from `AIWeapon.play_shot_audio`, `HUDWeapon`, `Explosion._ready`,
  `PlayerRocket` and `RocketProjectile` — 18 sounds, every gun and every blast.
  **That also fixed the routing:** the Weapons bus already had an EQ, a
  compressor and a limiter built for exactly this, and only TWO of 51 sounds
  reached it, because `_route()` moves Master→Effects and a scene only lands on
  Weapons if it NAMES it.
- **Every `max_distance` cutoff is gone** — the mortar was silent past 250m, the
  rocket launch past 200m, its detonation past 220m and explosions past 750m.
  Those were the things the player most needs to hear coming.
- **The bolt-action is the Mark One**, "Slow, heavy, made by the thousand." The
  old name collided with the Valley Foundry mission, the Foundry robots in
  enemy.gd and the Foundry weapon tier on the board.

**Gates.** check.sh: **PASS** (535 resources). smoke.sh: **PASS**. test.sh:
running at hand-off; the previous full run was 31 suites with the four known
failures and nothing new.

**Measured, not assumed.** `tools/audit_audio.gd` prints every sound's level at
the listener from 10m to 800m, which bus it lands on and what is cut off. At
400m: Ancient Rifle -28.1 → -22.4, Ancient MG -40.4 → -34.7, explosions
-14.5 → -8.9, and the mortar from silent to -16.8.

**A warning worth not believing.** Booting the Hillfort prints
"navmesh_islands: left only 2158 m2 of 891611 reachable from the spawn". It
reads like an unplayable map. It is not: the sweep REFUSED to run, so it
stripped nothing, and a direct path test walks spawn → cistern → pillars → gate
→ terrace → fortgate → relay → roof, every leg reached, 203 points to the relay
and 218 to the exit. The warning is still worth TERRAIN's eye, because a sweep
that always refuses is a sweep that protects nothing.

**Needs the human.**
- **The Hillfort has never been played.** 30 bodies on an ascent is a guess
  calibrated to supply cost, not to how it feels climbing into rifle fire from
  above. The flanking watchers on the two hills are the part most likely to be
  wrong.
- **Audio wants ears, not numbers.** If distant fire is too loud, raise
  `FAR_SLOPE_DB` (2.0) or lower `FAR_CEILING_DB` (-8). If it is too thin, raise
  the far bus cutoff from 850Hz. Your own gun now goes through the Weapons
  compressor, which it mostly did not before.
- **`unit_size` still ranges 10 to 46 with no rationale** and is the main lever
  left on the near and mid bands. The player shotgun is the outlier: -20dB at
  unit 10, which is -40 at 100m where the AI shotgun is -16.

---

## 2026-09-28 (last) — the depot induction: the first visit to base is a mission

**Landed.** The onboarding blocker on the board is closed, by a different route
than the board proposed. Rather than porting fourteen signs out of
`homebase_level.tscn` into TERRAIN's depot, the first visit to base now SETS
FIVE OBJECTIVES in the ordinary objective HUD:

1. repair yourself (you arrive at 35% frame)
2. get your squadmate up (one robot arrives downed)
3. buy an Ancient Rifle
4. fit it to a robot
5. choose an operation

Finishing the fifth sets `completed_tutorial` — the same flag the old GO FORTH
sign set — so every existing reader of it (the signs, the toast, LessonPrompts)
sees a finished tutorial without knowing the induction replaced them. From then
on the depot is just the depot.

- **`Campaign/induction_objective.gd`** — a MissionObjective that completes on
  an EVENT rather than a place. Every other objective in the game is spatial
  because every other objective happens in a level; these happen at base and
  are verbs, not destinations. It uses the base class's own `_on_activated` /
  `complete()` hooks, so the tracker, the HUD, the ordering and the reward
  plumbing all treat them as ordinary objectives and none of them had to learn
  the induction exists.
- **`Campaign/induction.gd`** — builds the five in code and owns the "all done"
  rule. Built in code, not authored into the level: the depot is TERRAIN's file,
  these exist only at base and only once, and a level should not carry nodes
  that are freed on every visit after the first.
- **`TestCharacter.healed(amount, healer)`** — new. The squad's robots have had
  `revived` for a long time; the player had nothing, so "are you patched up yet"
  could only be answered by polling.
- **The objective HUD follows the OBJECTIVES, not the mission.** It hid whenever
  `in_mission` was false, which at base is always — the induction would have set
  five objectives nobody could see. At base with none, it still hides.

**Gates.** check.sh: PASS. **smoke.sh: PASS** (booted clean, 15s, 3 warnings).
test.sh: running at hand-off. New suite `tools/test_induction.gd`, 27 checks,
all passing — it walks the whole thing: a fresh save, each of the five done the
way a player would do it, the visit after (which must be an empty depot with
nobody on the floor), and an unfinished induction resumed.

**What the test caught, which is why it exists.** The first run reported TEN
objectives, not five. `on_level_loaded` fires on every arrival at base —
`World._ready` calls it at boot and the train calls it coming home — so a set
was built per visit and stacked up. Everything else on that run failed
downstream of it. `Induction.clear()` now runs on every base arrival whether or
not a new one follows, using remove_child before the deferred queue_free so the
dead objectives leave the group before `objectives.refresh()` collects them in
the same frame.

**Also this session:** the induction is rebuilt on every visit until finished
rather than marked off in the lesson ledger — a player who quits half way
through would otherwise return to an objective telling them to revive a
squadmate who was standing up.

**From the first playtest, fixed.**
- **The wallet and the objective list drew on top of each other.** Resources and
  compute own the top-right corner AT BASE and hide in the field; the objective
  list did the exact opposite, and `wallet_hud.gd`'s own header says so — "the
  objective list owns that corner in the field and hides at base, so the corner
  is free there". The induction broke that assumption. The panel now drops below
  the wallet at base, measured off `WalletHUD.ROW_BOTTOM` rather than a copied
  number so moving one moves the other.
- **The Foundry viewmodel was too small and its sights did not line up in ADS.**
  Fixed by arithmetic rather than nudging: the viewmodel hangs off the player's
  Camera3D, so a point on the gun can be expressed in the CAMERA's own frame and
  "the sights are centred" is just x == 0, y == 0. A probe reported the sights at
  camera-space x = +0.024 with the default `ads_position` of (0, 0, -1.077)
  shoving the gun 0.19 further sideways. Holder scale 0.18 → 0.26, and
  `ads_position` solved so both sights land on the axis — measured back at
  x = -0.000, y = +0.004 (rear) and -0.004 (front), symmetric about the
  crosshair. `tools/preview_viewmodel.gd` renders the first-person view from the
  player's camera in both poses with a crosshair drawn at dead centre, which is
  how this was confirmed by eye as well as by number.

**The viewmodel pose bug, and a trap in the class default.**
`PlayerEquipment.update_view` lerps `viewmodel.ROTATION`, which is RADIANS, but
the pose exports are authored as though they were degrees — the class default
is `base_rotation = Vector3(-0.3, 6.0, 2.8)`, and 6.0 radians is 344°. The bolt
rifle inherited that default, so its HIP pose was thrown into a near-full turn
with a 160° roll: the gun sat across the screen with its magazine pointing up,
which is what the human photographed and read as "it's not ADS at all". ADS was
correct the whole time — `ads_rotation` is zero, so it was the only pose the
default could not spoil. `bolt_hud_weapon.tscn` now authors `base_position`,
`base_rotation`, `ads_position` and `ads_rotation` explicitly and depends on no
class default.
**Three other held items still inherit it** — `grenade_hud_weapon`,
`knife_hud_weapon` and `rocket_hud_weapon` — and `shotgun_hud_weapon` sets
`Vector3(5, 0, 2.8)`, which is the same mistake written out. Left alone: the
brief was the bolt rifle, and the shotgun is no longer player-usable. Worth a
decision, because either the default is wrong or four weapons are.
`tools/preview_viewmodel.gd` now poses in radians like the game does; posing it
in degrees rendered a pose the game never shows, which is why the first pass
looked correct and the game did not.

**ADS IS NOT A ZOOM, it is the rear sight arriving at your eye.** The first
version put the sights on the view axis and left them where the gun already
was — 93 cm away, so the aperture was a small square in the middle of the
screen and the whole thing read as "centred, then zoomed". Pulling the
viewmodel back along the barrel until the rear sight sits ~28 cm from the
camera is what makes it sight THROUGH the aperture: `ads_position.x` 0.31 →
-2.188, which moves the gun 0.65 m towards the eye and leaves x and y
untouched, so the alignment solved earlier still holds. The butt ends up behind
the camera and is clipped, which is correct for a stock on your cheek.

**The soldier icon carries its rifle**, now that the frame is issued one.
Compared against the alternatives first (`tools/preview_chassis_icon.gd` renders
a chassis armed and bare, three-quarter and side, each flipped): the
three-quarter keeps the eye that makes a soldier a soldier AND shows the gun,
where the side view reads the rifle better but reduces the body to a plain pill.
Kept the framing bake_icons already uses.

**A design change the tests forced.** The induction first restaged the casualty
and the 35% health on EVERY visit until finished. `test_endings` caught what
that meant: come home from an operation and you are healed by
`_repair_at_base` and then immediately re-broken, so a player who survived a
mission arrived at base wounded. The casualty is now staged once per campaign
while the OBJECTIVES still rebuild until finished — which exposed a second bug,
that arming lived inside the staging function, so a resumed induction had five
objectives that were never activated at all. Arming is its own deferred step now.

**The armoury and the unlock ladder, same session.**
- **The shotgun and the pistol are out of the player's hands** — `in_shop`,
  `usable_by_player` and `usable_by_ai` all false on both. Enemy Shotgun
  Troopers are untouched: their gun is baked into `soldier_shotgun.tscn`, not
  issued from the catalogue.
- **Every soldier is issued an Ancient Rifle instead.**
  `chassis_soldier.starting_weapon_id` and `Campaign.starting_weapon_id` both
  &"m4", and `starting_stock` carries four of them — the gun comes OUT OF
  STORES (`fit_item` calls `armoury.take`), so setting the id without stocking
  it left all four Bravos holding nothing, which the induction test caught.
- **Walker behind Three Rivers, Spotter behind Mutaha.** The only chassis no
  mission names is now the Soldier, which closes the "buyable from minute one"
  hole the economy audit found.
- **Chaser and Leaper are gone from the player catalogue.** Removing them from
  the unlock lists alone would have done the OPPOSITE of what was wanted:
  `locked_by()` gates only what a mission names, so an unnamed frame is on sale
  immediately. They are enemy frames and are now enemy-only. Both keep their
  `kill_kinds` entries and icons, because the debrief still has to draw them.
- **The induction is SEVEN objectives** — repair yourself, revive the
  squadmate, buy an Ancient Rifle, put it in your own hands, order a FOLLOW,
  order an ADVANCE, choose an operation. Squad command is the game's actual
  verb and had no lesson at all; `SquadCommander.order_issued` carries the
  verb, and each objective wants its own, which the test pins so a FOLLOW
  cannot tick ADVANCE off with it.
- **THE PLAYER is the one who musters unarmed, not a squad robot.**
  `_seed_new_campaign` issues a rifle to every ROSTER record and the player's
  own record is not in `roster`, so the squad arrives holding rifles and you do
  not — which is the only reason the buy and fit objectives are not already
  complete when they are built. Stores carry exactly four rifles and all four
  are issued, so there is no spare and the shop trip is real.
  BUY is measured against what you owned when the induction started rather than
  "is there one in stores", because the latter reads false again the moment the
  player fits it; FIT looks at the player's own record. Either order works.

**Needs the human.** The induction has been walked headlessly, not played. The
wording of the five blurbs, and whether repairing yourself to FULL is the right
bar for objective 1, both want a playtest. `Campaign.tutorial_player_health`
(0.35) sets how hurt you arrive.

---

## 2026-09-28 (later) — the Foundry Rifle, and the heavy trooper it exists for

**Landed.**

- **Enemy Rifle Trooper 100 → 60 frame**, matching the player's Soldier.
  `chassis_rifleman.tres` and `soldier_rifle.tscn` both, so the chassis and the
  scene cannot disagree. Body for body a trooper is now worth a trooper; it was
  a 3:1 loss with the identical gun.
- **New `rifleman_armoured` — "Heavy Rifleman", 100 frame, slower (0.87).**
  `soldier_rifle_armoured.tscn` is `soldier_rifle.tscn` with a distinct look:
  `base_tint` steel, `metallic` 0.8, `roughness` 0.42 and a narrower paint band,
  so it reads as plated without re-treading the armour geometry the human
  rejected. Those four are exactly the shader parameters `faction_livery.gd`
  does NOT overwrite at runtime — it only sets faction_color, paint_blend,
  marker_energy and shutdown — so the distinction survives the repaint.
  Sprinkled in by `tools/sprinkle_heavies.sh`, at most one per squad and only
  every Nth squad: Coast 5, Three Rivers 5, Mutaha 13, Mutaha City 12.
- **The Foundry Rifle** (`bolt`, 130): `bolt_rifle_model.tscn` is the pack's
  `SniperRifle_6` — chosen by rendering all six sniper variants and looking —
  with its `DarkWood` surface overridden to a cast alloy and a box magazine
  added under the receiver. The pack guns are one mesh with five NAMED surfaces,
  which is why swapping only the stock is a one-line override. Palette taken
  off the m4's own materials so it comes off the same production line.
  `ai-wep_bolt.tscn`, `bolt_hud_weapon.tscn` (FireModes.MANUAL, the bolt path
  that already existed for the pump), `item_bolt.tres`, a `7.62` AmmoStock, and
  baked icons.
- **`Campaign.stage_tutorial`**, off in lab_mode. The induction casualty from
  earlier today was firing inside LAB RUNS — a downed robot and a 35% player in
  the middle of a controlled measurement, found in a lab log.
- **The rifle lost its telescope and gained its sights.** The scope could not be
  hidden or dropped — it is triangles mixed through three surfaces of one merged
  mesh — so `tools/bake_bolt_mesh.gd` rebuilds the mesh without them, cutting
  every triangle above y=0.38 into
  `Character/weapon/models/bolt_rifle_base.res`. 668 triangles out, the Glass
  surface gone entirely. Onto that: iron sights front and rear, a slotted
  handguard with clamps, a bolt knob, ejection port, stock comb and side panel,
  and sling loops.
  **Every position is measured, not eyeballed** — a probe of the baked mesh put
  the barrel top at 0.387 over the receiver and 0.363 at the muzzle, the barrel
  at 0.132 across and the stock comb at 0.158, all centred on z=0. The first
  pass placed parts by eye and they floated: sights sunk into the barrel, fins
  more than twice the barrel's width, a comb hanging in the air.
- **`icon_art.gd` needs a MODEL_OVERRIDE for it.** `model_for()` finds an icon's
  model by looking for an instanced .blend/.fbx inside the weapon scene. A gun
  built from a baked ArrayMesh has none, so it silently fell back to the generic
  drawing and the armoury showed a table. Same fix the shotgun and machine gun
  already carry.
- **Shotgun Trooper 100 → 60** as well, chassis and scene. The infantry ladder
  is now coherent: Leaper 45; Soldier, Rifleman, Shotgunner, Chaser and Mechanic
  60; Spotter 80; Marksman 90; Heavy Rifleman 100.
- **The depot's six info markers are gone** (DEPOT, TERMINAL, MUSTER, BAYS,
  RANGE, TRANSIT), with their parent node, the orphaned script ext_resource and
  load_steps. **`maps/**` is TERRAIN's lane** — done on the human's direct
  instruction, recorded here so the board sees it. The depot now carries no
  Label3D teaching of any kind.
- **`mutaha_2_city` had empty `requires`**, so the 132-enemy city op was offered
  at the terminal on a BRAND NEW SAVE, next to First Contact. Now gated behind
  `mutaha_1_blocks`. Mine, from the session that authored it, and found only by
  booting a fresh campaign rather than reading the resource.
- **The Foundry Rifle's magazine reseated.** In game it clipped through the
  trigger guard and hung off nothing. Measured the underside: the guard hangs to
  y=-0.232 across x 0.20-0.70 and there is NO geometry at all between x 0.70 and
  1.00, while the magazine sat at x=0.92 raked 12° — which swings its top-rear
  corner back to x≈0.60, inside the guard. Now a MagWell box overlaps up into
  the receiver and the magazine (thinner: 0.32x0.22, was 0.46x0.32) enters it by
  0.08 with five ribs and a floorplate. No rake: a raked magazine in a straight
  well is how the clipping started.
- **`kill_kinds.gd` gained the heavy**, in both tables, plus its baked icon.
  `test_quadcopter` caught this: a new chassis the debrief cannot draw would
  have tallied every heavy killed as a nameless fallback. A new enemy frame
  needs a FRAMES entry, a SCENES entry and an icon bake, not just a .tres.

**Gates.** check.sh: **PASS** (533 resources). test.sh: running at hand-off.
Six lab runs on `Campaign/lab/plans/foundry_rifle.tres`.

**What the lab actually said, including where I was wrong.**
The gun was tuned by measurement, not by eye, and the first two settings were
wrong in opposite directions:

- **70 damage one-shot a 60-frame trooper** and the Foundry won 100% against
  line infantry and 67% against heavies — a straight replacement for the Ancient
  Rifle, which is the shotgun mistake inverted.
- **55 damage with a 1.15 s bolt** was worse against BOTH. Arithmetic says why:
  the m4 kills a heavy in 3 gaps × 0.35 = 1.05 s, so no damage number rescues a
  1.15 s cycle. The cycle was the binding constraint, not the damage.
- **Accuracy, not damage, was doing the work.** At 9 mrad against the m4's 18 the
  Foundry out-damaged it 1.3-1.9× in every single configuration. Cutting it to
  15 mrad is what finally produced a trade.

Final, n=12: LINE 67% vs 67% (parity), HEAVY 17% vs 50%. Matchup 2 is the
interesting one — the Foundry deals 4125 damage to the Ancient's 2588 and still
only draws, because a 55-damage round into a 60-frame body wastes half itself.
That overkill IS the trade.

**A fresh save, booted and read off the running game** (`tools/probe_fresh_start.gd`):
500 resources, 4 seats, four Bravos on shotguns at 60 frame, the player at
35/100 with Bravo-4 down at 1/60 — the induction casualty works. **And zero
tutorial signs**, because the depot never had lesson content and now has no
labels either. There is no tutorial MISSION; the tutorial was always the base
signs, `homebase_level.tscn` still has fourteen of them, and porting that
content into the depot is the open M2 blocker.

**Needs the human.**
- **The Foundry Rifle is gated by nothing.** No mission names it in `unlocks`,
  so it is on sale at 130 from the first visit to base — the same hole the
  Walker sits in. The new op between Proving Ground and Basin is the obvious
  home for it.
- **The first-person viewmodel is unverified.** `bolt_hud_weapon.tscn`'s Holder
  transform is scaled off the m4's by model length and never seen in game. It
  will need moving by eye.
- **Two scenes want an editor reload**: `soldier_rifle.tscn` (60 hp) and
  `test_character.tscn` (the 7.62 stock). New icons import on editor focus.
- **The Shotgun Trooper is still 100 frame**, now tougher than the Rifle Trooper
  it stands beside. Left alone deliberately — the instruction named the rifle
  trooper, and dropping the shotgunner is a balance call, not a typo fix.
- **±15 points is the arena's noise floor** at 4v4 and 12 repeats. The same
  configuration returned 50/58/63/67% across four runs, so nothing smaller than
  about 20 points should be read as a result there.

**Blocked / next.** Resource and compute allocation is waiting on the new
mission between Proving Ground and Basin. The Foundry's real job — an
anti-armour multiplier — cannot exist until the armour rule lands, which is
still parked on the commit question.

---

## 2026-09-28 — a dangling tag, the tutorial's opening state, and why the suite never finished

**Landed.**

- **Proving-ground hostiles advance now.** They were not "chilling" because of a
  posture — all six specs were already `ADVANCE`. `post_tag` named
  `obj_arena_centre`, which `proving_level.tscn` does not contain, so
  `_apply_posture` fell through to `squad.get_center()`: an order to advance onto
  the ground the squad is already standing on, satisfied on the first tick. They
  sat on the muster platform (`HostileMuster`, y=3.2) for the whole mission.
  `EnemyForceSpawner._advance_destination()` now points a post-less advance at
  the player's spawn and warns when a tag WAS authored and did not resolve;
  `post_tag` is cleared on the three arena missions so an empty tag reads as a
  decision. Measured on `arena_5_proving`: twelve hostiles, mean z 36.3 → 11.0,
  nearest 58.8 m → 7.3 m in ten seconds. `obj_arena_centre` was the only dangling
  `post_tag` in the project — every other one resolves, so nothing else moved.
- **Starting resources 300 → 500**, `Env/world.tscn` (SHARED — one line, on the
  user's instruction). Only affects a FRESH campaign; `starting_resources` is
  read by `_seed_new_campaign()` alone.
- **The first tutorial opens on a casualty.** `Campaign._stage_first_tutorial()`
  downs the last-mustered robot and drops the player to `tutorial_player_health`
  (0.35) on the first base load. Gated on `completed_tutorial` AND
  `state.mark_lesson(&"induction_triage")`, so it happens once ever, and
  `_queue_base_save()` persists that. Bodies only, never records — writing the
  damage to the record would bill the player compute to undo a scripted lesson
  and could bench the robot. One full repair-tool reservoir (100) covers both
  jobs: 65 to heal yourself, 29 to bring the robot past `revive_at_fraction`.
- **`Campaign._is_base()`**, because `level == base_level` compared a Node to a
  PackedScene and was never once true. The intended early return therefore never
  fired — which is load-bearing, since the base musters in the code below it — so
  only the spurious warning was fixed, not the control flow.
- **The debrief's KILLS and REVIVES counters read 0 on a won mission** — mine,
  from earlier the same day. The count-up in `_physics_process` iterated two
  named fields (`_resources`, `_compute`) that the builder had to remember to
  assign; KILLS and REVIVES were built, shown, and never animated, so they sat
  on their `from` value. A screenshot showed "KILLS 0 / REVIVES 0" above a squad
  card reading 74 kills : 17 revives — the data was always right, only the
  display was stuck. Fixed at the class: `_counter()` now registers every number
  it makes in a `_counters` list, so a counter added later cannot be forgotten,
  and the two named fields are gone. `test_endings` gained four checks — every
  counter must reach its `to`, and a named check that a squad of 5+3 kills and
  2+1 revives reads 8 and 3 at the top.
- **`tools/audit_economy.gd`** (new): prices the whole campaign in "baselines"
  (1 Soldier + 1 Ancient Rifle = 130) against the bodies each op fields. Reads
  world.tscn, the catalogue, the specs and the level scenes as packed data —
  nothing hardcoded, nothing instantiated, no save written.

**Gates.** check.sh: **PASS** (227 scripts, 524 resources). test.sh: **30 suites,
4 failures** — and this is the first complete run in three sessions. It had been
stalling at 26 and never printing a total, so **`test_vehicle`, `test_walker` and
the water-navmesh suite had not run at all**; all three pass now. Of the four
failures, two are TERRAIN's and pre-existing (`pittsburgh_level` bridge spacing,
`the mutaha squad spawn and exit stand on the ground`) and two are
`test_tutorial` honestly reporting missing content (below). smoke.sh: not run.

**Why the suite stalled — worth the next agent's attention.** `test_tutorial.gd`
was HANGING, not failing. The rebuilt depot has six Label3Ds (DEPOT, TERMINAL,
MUSTER, BAYS, RANGE, TRANSIT) and none of them is a lesson, so
`_sign_saying("{reload}")` returned null — and a runtime error inside a coroutine
aborts the coroutine WITHOUT aborting the process, so `quit()` was never reached.
Eighteen stuck `--script` instances had piled up, one per suite run, throttling
the machine. The test now bails through an epilogue that calls `quit()` and says
what is missing. Any test that dereferences something it looked up needs the same
guard.

**That is also the answer to "the tutorial is gone".** The TutorialLabel and
toast machinery are intact and tested; the CONTENT went with the old depot
layout. Nothing in `maps/depot_level.tscn` carries `toast_text` any more, so
there is no lesson in the base to stand at and nothing sets
`completed_tutorial`. Re-authoring those lessons is a GAMEPLAY job, but the signs
live in a TERRAIN file — worth the coordinator deciding which lane places them.

**Needs the human.**
- **Nothing in this session was playtested.** The advance fix, the tutorial
  opening and the 500 grant are all verified headlessly only.
- **The tutorial opening will fire on the live save.** It reads
  `completed_tutorial: false` despite arena 1/3/5 being cleared, so the casualty
  is staged on the next boot rather than only on a brand-new campaign. Adding
  `and state.completed_missions.is_empty()` to the gate makes it strictly
  new-campaign-only if that is wanted.
- **`mutaha_2_city` has no clear bonus at all** — 0 resources, 0 compute, for the
  second-largest fight in the campaign. That is an omission in last session's
  authoring, not a design choice.

**Blocked / next.** The economy audit says three things and none of them is
fixed: Valley Basin is a 6.6× step in opposition against +1 seat; the Rover is
unlocked BY Basin, so the obvious answer to it cannot be bought until after; and
the Walker (320, no mission gates it) is buyable from the first visit to base,
which makes it the real answer to Basin and probably not the intended one. All
three are balance calls for the human. Armour (Phase 2) is still parked on the
commit question, which has now been asked three times.

---

## 2026-09-28 — Phase 1 finishes, and a lab spawn bug that had been faking results

**Landed.**

*Phase 1, the four assigned items.*
- **Mutaha activation distance.** The board called this "one number in level data". It is not — `activation_distance` is an `@export` on the ROBOT scenes in `Character/characters/ai/`, and five of them carried 250. Dropped the three infantry ones (`soldier_rifle`, `soldier_marksman`, `soldier_shotgun`) to 120. Left `enemy_helicopter` alone (a bomber is meant to be seen coming) and `spotter_drone` alone (player-side, so `_is_player_side()` exempts it from culling and its 250 is inert).
- **Spotters park at base.** New `_parked()` on `spotter_drone.gd`, keyed off `Campaign.in_mission` so it covers the depot and home base with no per-level data, resolved lazily through the group because node ready order means the campaign does not exist at `_ready`. Parked: no lift, no orbit, rotor stopped, gravity restored. The early return sits before `_lifted` is set so it still spawns airborne on a real mission.
- **Soldier weapon scale.** `WeaponMount` baked 0.25. Now 0.40 on `soldier_chassis`, `soldier_rifle`, `soldier_marksman`, `soldier_shotgun`. Measured: 0.97 m → 1.56 m, 49% → 78% of body height. `mechanic_chassis` deliberately left at 0.25 — what hangs on it is a welder, not a gun. Knock-on: those scenes are what their chassis icons bake from, so `rifleman`, `marksman`, `shotgunner`, `soldier`, `mechanic` were re-baked.
- **Lobber Rover icon.** Fixed, and the cause is worth keeping: `vehicle_rover.tscn` carries a `DisplayGun` stand-in on its mount, and the baker's "already armed, leave it alone" check treated that as a real weapon — so both rovers baked wearing a placeholder neither of them fights with. At runtime `equip_weapon_scene` CLEARS the mount first; `bake_icons._armed_body` now does the same. The two icons differ.

*Armour prep (Phase 2 note 2 — the perishable one).*
- `Campaign/lab/plans/armour_baseline.tres` + `tools/lab_armour.gd`, run and captured while no armour rule exists. Nine matchups: the ladder (small arms into light / medium / unarmoured control), damage types against one hull, the anti-armour counter, and combined arms.
- Headline for the multipliers: **anti-armour is currently strictly WORSE than a rifle.** Autocannon troopers did 217 damage per run into a walker against a rifle's 221, and lost every fight where rifles won a third. Once MULT lands that must invert, or the rule did not work.
- **There is no anti-armour any AI robot can carry.** `item_rocket.tres` (Recoilless) is `usable_by_ai = false` with no `ai_scene`; the autocannon's `chassis_whitelist` is walker/rover. Matchups 6-7 only work because `weapon_swaps` ignores whitelists — they are a proxy, not something the campaign can field. The counter needs an AI weapon scene before armour ships or it exists only in the player's hands.

*The lab spawn bug.*
- `Managers/lab.gd._ground()` cast a ray from 1 m above the requested point down 20 m and returned the point UNCHANGED on a miss. At full roster the spawn ring is ~7 m across, so on any map with relief the outer robots started their ray inside a bank, missed, and were placed at the site's own height — under the terrain, dead on the first frame. Now routed through `Campaign/ground_snap.stand()`, the same helper the enemy spawner uses, with a widened ±60 m ray as fallback.
- Effect: total damage in a 30-seat fight roughly DOUBLED, and matchup 3 (artillery vs balanced) flipped from 100% to 0%. Every lab number taken on a map with relief before this fix is suspect.
- New plans: `open_ground.tres` (200 m on Coast Road) and `open_30v30.tres` (four 30-supply force designs). `lab_armour.gd` takes `--plan=`, `--speed=` and `--watch`.

**Gates.** `check.sh`: **PASS** throughout. `test.sh`: 25 suites, **two failures, neither mine** — the known `pittsburgh_level` bridge spacing (6.7 m), and a new `test_terrain` failure, "the mutaha squad spawn and exit stand on the ground". `maps/mutaha_level.tscn` was modified at 07:57 today; it is TERRAIN's file and I did not touch it. `smoke.sh`: **not run.**

**Needs the human.**
- **Reload in the editor before saving over them:** `soldier_chassis`, `soldier_rifle`, `soldier_marksman`, `soldier_shotgun` (weapon mount scale, activation distance).
- **The commit question is unresolved.** The board rules that review happens by playtesting rather than in GitHub Desktop, and the armour brief says to land `enemy.gd` as one commit before starting Phase 2. That contradicts a standing instruction to me never to commit. I have made no commits; `enemy.gd` is still uncommitted and still carries the culling work plus the corpse fix. Phase 2 is blocked on this.
- **Draw-call count on Mutaha** still open from YOUR DESK — unchanged, still the thing that decides whether LOD is worth building.

**Blocked / next.**
- **Unverified:** the 250→120 activation change. At spawn it takes awake hostiles 3 → 0, which is a small delta because the culling fix already did the work. The gain should come mid-advance and I could not measure it — the probe that put the player inside the enemy force collapsed (physics fell to 0.05 ms, identical counts in both conditions; the mission ended and the debrief's PauseHold froze everything). Defensible by reasoning, not by measurement. Wants a real playthrough.
- **I was wrong twice, recorded so nobody repeats it.** (1) I reported Lobbers putting 18.8% of their damage into their own side and framed it as an explosive problem. On open ground at 200 m it is 1.0% — the arena figure was three Lobbers advancing shoulder to shoulder on one target in a small space. Friendly fire here scales with crowding and shared targets, not damage type. (2) When the 30-seat mirror control came out 100%/0%, I first blamed the culling asymmetry between ALLIED and ENEMY. Wrong: `lab.gd` sets `AWAKE_FOR = 1.0e6` and wakes every spawned robot permanently, so culling never applies in the lab. The real cause was the spawn bug above.
- **Next, in order.** (1) Per-weapon target selection, which is the standing request: give `AIWeapon` an `acquire(owner, candidates)` that defaults to the owner's `combat_target` so nothing changes, and let a mortar or GL override it to skip targets squadmates already hold and keep its own for at least the round's flight time. `Enemy.weapon_target` already exists as a separate Vector3, so the split is half-built. Prerequisite: `AIWeapon` has no `projectile_speed` or flight-time field at all. (2) Re-measure the 30-seat fights now the spawns are fixed — the mirror moved to 67/33 at n=3, which is as close to even as three runs can report, but n=3 is not a result.

---
