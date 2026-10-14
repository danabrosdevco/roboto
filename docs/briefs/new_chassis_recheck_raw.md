# Laboratory — The three fixes, rechecked

> Three changes measured against the run of 2026-10-13, which is committed at docs/briefs/NEW_CHASSIS_AUDIT.md.
> 
> BROOD: cruise_height raised 12.0 to 22.0, the Spotter's proven value. At 12 m it was hit 73% of the time and five of six died; the Spotter at 22 m in the identical fight was never shot at once. The question is whether the frame survives now, and whether it survives so completely that it is no longer reachable at all - because its whole design argument is that a squad which is not slow should be able to kill it.
> 
> PICKET: its rockets now lead. AIWeaponGrenadeLauncher gained an opt-in lead_target, off for the mortar, both grenade launchers and the cluster, on for the rocket pods alone. The solver aims at the target, asks how long the round is in the air, moves the aim point along the target's horizontal velocity by that much, and re-solves twice. The first run scored 0% accuracy over six bodies and three fights; anything above zero is the feature working, and the Walker control is in this plan unchanged so the comparison is inside one run rather than across two.
> 
> BASTION vs WALKER: asked for directly. The Walker carries a heavy MG in BOTH mounts, which was not expressible before - weapon_swaps only ever reached the primary and the coax came from the chassis, so the only way to ask for it was to edit a shipped frame. LabMatchup gained coax_swaps. The first run had the Bastion out-damaging a Walker per body, 225 to 188, while finishing on less hull, 75% to 88%, in separate fights against riflemen. This puts them in the same fight.

Generated 2026-10-13T23:40:55 on v0.009a+dev. Win rates are from the ALLIES' side; "winner survivors" and "winner HP" say how close the wins were (100% = untouched).

## Results

| Matchup | Setup | Runs | Ally wins | Hostile wins | Draws | Avg time (s) | Winner survivors | Winner HP left | Dmg dealt A / H | Accuracy A / H |
|---|---|---|---|---|---|---|---|---|---|---|
| BROOD at 22 m  2 Broodcarrier vs 4 dug-in rifles, 60 m | 2 Broodcarrier (ADVANCE) vs 4 Soldier (HOLD), 60m, Soldier carrying Ancient Rifle | 3 | 0% | 67% | 1 | 51 | 100% | 98% | 0 / 1276 | - / 69% |
| PICKET leading  2 Picket hold at 85 m, 4 rifles cross to them | 2 Picket (HOLD) vs 4 Soldier (ADVANCE), 85m, Soldier carrying Ancient Rifle | 3 | 0% | 0% | 3 | 120 | - | - | 330 / 356 | 0% / 41% |
| PICKET control  2 Walker hold, same fight, unchanged from the first run | 2 Walker (HOLD) vs 4 Soldier (ADVANCE), 85m, Soldier carrying Ancient Rifle | 3 | 0% | 0% | 3 | 120 | - | - | 302 / 84 | 65% / 43% |
| BASTION vs WALKER  2 Bastion hold vs 2 Walker, both mounts heavy MG, 60 m | 2 Bastion (HOLD) vs 2 Walker (ADVANCE), 60m, Walker carrying Heavy Machine Gun | 3 | 0% | 100% | 0 | 8 | 100% | 54% | 891 / 1804 | 81% / 32% |

## By chassis (all matchups)

| Chassis | Side | Fielded | Kills | Deaths | Survived | Dmg dealt | Dmg taken | Dmg dealt per body | Kills per body |
|---|---|---|---|---|---|---|---|---|---|
| Broodcarrier | ally | 6 | 0 | 5 | 17% | 0 | 1076 | 0 | 0.00 |
| Soldier | hostile | 36 | 8 | 6 | 83% | 1716 | 642 | 48 | 0.22 |
| Soldier | ally | 0 | 0 | 2 | - | 0 | 200 | 0 | 0.00 |
| Picket | ally | 6 | 3 | 2 | 67% | 330 | 432 | 55 | 0.50 |
| Walker | ally | 6 | 3 | 0 | 100% | 302 | 84 | 50 | 0.50 |
| Bastion | ally | 6 | 0 | 6 | 0% | 891 | 1804 | 149 | 0.00 |
| Walker | hostile | 6 | 6 | 0 | 100% | 1804 | 891 | 301 | 1.00 |

## Every run

| Matchup | Run | Winner | Time (s) | Allies left | Hostiles left | Dmg A / H | Friendly fire A / H |
|---|---|---|---|---|---|---|---|
| BROOD at 22 m  2 Broodcarrier vs 4 dug-in rifles, 60 m | 1 | hostile | 17 | 0/2 | 4/4 | 0 / 430 | 0 / 10 |
| BROOD at 22 m  2 Broodcarrier vs 4 dug-in rifles, 60 m | 2 | draw | 120 | 1/2 | 4/4 | 0 / 416 | 0 / 0 |
| BROOD at 22 m  2 Broodcarrier vs 4 dug-in rifles, 60 m | 3 | hostile | 16 | 0/2 | 4/4 | 0 / 430 | 0 / 0 |
| PICKET leading  2 Picket hold at 85 m, 4 rifles cross to them | 1 | draw | 120 | 1/2 | 3/4 | 110 / 236 | 0 / 0 |
| PICKET leading  2 Picket hold at 85 m, 4 rifles cross to them | 2 | draw | 120 | 2/2 | 3/4 | 110 / 0 | 38 / 0 |
| PICKET leading  2 Picket hold at 85 m, 4 rifles cross to them | 3 | draw | 120 | 1/2 | 3/4 | 110 / 120 | 38 / 0 |
| PICKET control  2 Walker hold, same fight, unchanged from the first run | 1 | draw | 120 | 2/2 | 3/4 | 88 / 29 | 0 / 0 |
| PICKET control  2 Walker hold, same fight, unchanged from the first run | 2 | draw | 120 | 2/2 | 3/4 | 112 / 27 | 0 / 0 |
| PICKET control  2 Walker hold, same fight, unchanged from the first run | 3 | draw | 120 | 2/2 | 3/4 | 102 / 28 | 0 / 0 |
| BASTION vs WALKER  2 Bastion hold vs 2 Walker, both mounts heavy MG, 60 m | 1 | hostile | 21 | 0/2 | 2/2 | 511 / 604 | 0 / 0 |
| BASTION vs WALKER  2 Bastion hold vs 2 Walker, both mounts heavy MG, 60 m | 2 | hostile | 1 | 0/2 | 2/2 | 200 / 600 | 0 / 0 |
| BASTION vs WALKER  2 Bastion hold vs 2 Walker, both mounts heavy MG, 60 m | 3 | hostile | 2 | 0/2 | 2/2 | 180 / 600 | 0 / 0 |