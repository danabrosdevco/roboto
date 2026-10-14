# Laboratory — The new chassis, audited

> Every frame added on 2026-10-10, put in the fight it was designed for, each paired with a control that isolates the question. Three repeats is a look, not a measurement.
> 
> LANCE: does it shoot at all? It has no turret and aims by slewing its hull at 50 deg/s, and rover.gd only turns the body when turret is null - which it is not. The control is a Rover, the frame it is built on, in the identical fight.
> 
> PICKET: does it do anything? 95 m of indirect rocket against four riflemen who have to cross 85 m of open ground. If the answer is no, damage dealt is zero. The control is a Walker holding the same line with a direct-fire autocannon.
> 
> KITE: is it picked off? 90 hull at 22 m cruise against four dug-in rifles. The control is a Rover - same supply band, same fight, on the ground - so the question is whether altitude helps or kills.
> 
> BROOD: does 12 m fly too low? Two Broodcarriers against four dug-in rifles, and the control is two SPOTTERS: also unarmed, also a flyer, also no threat, but cruising at 22 m instead of 12. If the Brood dies and the Spotter lives, the altitude is the whole answer.
> 
> VESSEL, BASTION, SEE-ENGINE, DRAYMAN: each attached to a squad, because none of them is a line frame and fielding them alone would measure nothing. Bastion against a Walker on the same hold; See-Engine against the same four rifles with nobody feeding them contacts, which is the only way its spread bonus shows up as a number.

Generated 2026-10-13T23:22:07 on v0.009a+dev. Win rates are from the ALLIES' side; "winner survivors" and "winner HP" say how close the wins were (100% = untouched).

## Results

| Matchup | Setup | Runs | Ally wins | Hostile wins | Draws | Avg time (s) | Winner survivors | Winner HP left | Dmg dealt A / H | Accuracy A / H |
|---|---|---|---|---|---|---|---|---|---|---|
| LANCE  2 Lance advance onto 3 dug-in rifles, 55 m | 2 Lance (ADVANCE) vs 3 Soldier (HOLD), 55m, Soldier carrying Ancient Rifle | 3 | 67% | 33% | 0 | 6 | 78% | 29% | 790 / 515 | 89% / 44% |
| LANCE control  2 Rover, same fight | 2 Rover Chassis (ADVANCE) vs 3 Soldier (HOLD), 55m, Soldier carrying Ancient Rifle | 3 | 100% | 0% | 0 | 4 | 100% | 58% | 587 / 453 | 45% / 59% |
| PICKET  2 Picket hold at 85 m, 4 rifles cross to them | 2 Picket (HOLD) vs 4 Soldier (ADVANCE), 85m, Soldier carrying Ancient Rifle | 3 | 0% | 33% | 2 | 86 | 100% | 100% | 220 / 805 | 0% / 56% |
| PICKET control  2 Walker hold, same fight | 2 Walker (HOLD) vs 4 Soldier (ADVANCE), 85m, Soldier carrying Ancient Rifle | 3 | 0% | 0% | 3 | 120 | - | - | 323 / 81 | 67% / 25% |
| KITE  2 Kite advance onto 4 dug-in rifles, 60 m | 2 Kite (ADVANCE) vs 4 Soldier (HOLD), 60m, Soldier carrying Ancient Rifle | 3 | 100% | 0% | 0 | 17 | 100% | 71% | 760 / 159 | 66% / 19% |
| KITE control  2 Rover, same fight on the ground | 2 Rover Chassis (ADVANCE) vs 4 Soldier (HOLD), 60m, Soldier carrying Ancient Rifle | 3 | 100% | 0% | 0 | 5 | 100% | 65% | 781 / 375 | 50% / 42% |
| BROOD  2 Broodcarrier at 12 m cruise vs 4 dug-in rifles, 60 m | 2 Broodcarrier (ADVANCE) vs 4 Soldier (HOLD), 60m, Soldier carrying Ancient Rifle | 3 | 0% | 67% | 1 | 50 | 100% | 98% | 0 / 1259 | - / 73% |
| BROOD control  2 Spotter, same fight at 22 m cruise | 2 Spotter Drone (ADVANCE) vs 4 Soldier (HOLD), 60m, Soldier carrying Ancient Rifle | 3 | 0% | 0% | 3 | 120 | - | - | 0 / 0 | - / - |
| VESSEL  1 Vessel + 2 rifles vs 4 rifles, 50 m | 1 Vessel + 2 Soldier (ADVANCE) vs 4 Soldier (HOLD), 50m, Soldier carrying Ancient Rifle | 3 | 0% | 100% | 0 | 39 | 75% | 48% | 403 / 1585 | 10% / 36% |
| BASTION  1 Bastion + 3 rifles hold vs 6 rifles, 60 m | 1 Bastion + 3 Soldier (HOLD) vs 6 Soldier (ADVANCE), 60m, Soldier carrying Ancient Rifle | 3 | 100% | 0% | 0 | 19 | 92% | 75% | 1315 / 391 | 43% / 30% |
| BASTION control  1 Walker + 3 rifles hold, same fight | 1 Walker + 3 Soldier (HOLD) vs 6 Soldier (ADVANCE), 60m, Soldier carrying Ancient Rifle | 3 | 100% | 0% | 0 | 14 | 100% | 88% | 1540 / 170 | 63% / 30% |
| SEE-ENGINE  1 See-Engine + 4 rifles vs 4 rifles, 55 m | 1 See-Engine + 4 Soldier (ADVANCE) vs 4 Soldier (HOLD), 55m, Soldier carrying Ancient Rifle | 3 | 67% | 33% | 0 | 20 | 73% | 48% | 787 / 1131 | 41% / 38% |
| SEE-ENGINE control  4 rifles alone vs 4 rifles | 4 Soldier (ADVANCE) vs 4 Soldier (HOLD), 55m, Soldier carrying Ancient Rifle | 3 | 0% | 100% | 0 | 14 | 75% | 55% | 347 / 942 | 31% / 36% |
| DRAYMAN  1 Drayman + 3 rifles vs 4 rifles, 50 m | 1 Drayman + 3 Soldier (ADVANCE) vs 4 Soldier (HOLD), 50m, Soldier carrying Ancient Rifle | 3 | 33% | 67% | 0 | 8 | 75% | 63% | 293 / 1243 | 29% / 49% |

## By chassis (all matchups)

| Chassis | Side | Fielded | Kills | Deaths | Survived | Dmg dealt | Dmg taken | Dmg dealt per body | Kills per body |
|---|---|---|---|---|---|---|---|---|---|
| Lance | ally | 6 | 8 | 2 | 67% | 790 | 515 | 132 | 1.33 |
| Soldier | hostile | 174 | 59 | 100 | 43% | 9109 | 8220 | 52 | 0.34 |
| Rover Chassis | ally | 12 | 21 | 0 | 100% | 1368 | 828 | 114 | 1.75 |
| Picket | ally | 6 | 2 | 4 | 33% | 220 | 805 | 37 | 0.33 |
| Walker | ally | 9 | 18 | 0 | 100% | 1694 | 195 | 188 | 2.00 |
| Kite | ally | 6 | 12 | 0 | 100% | 760 | 159 | 127 | 2.00 |
| Broodcarrier | ally | 6 | 0 | 5 | 17% | 0 | 1059 | 0 | 0.00 |
| Soldier | ally | 57 | 26 | 37 | 35% | 2496 | 3256 | 44 | 0.46 |
| Spotter Drone | ally | 6 | 0 | 0 | 100% | 0 | 0 | 0 | 0.00 |
| Vessel | ally | 3 | 0 | 3 | 0% | 0 | 812 | 0 | 0.00 |
| hatchling | ally | 0 | 2 | 4 | - | 144 | 280 | 144 | 2.00 |
| Bastion | ally | 3 | 11 | 0 | 100% | 674 | 273 | 225 | 3.67 |
| See-Engine | ally | 3 | 0 | 1 | 67% | 0 | 361 | 0 | 0.00 |
| Drayman | ally | 3 | 0 | 3 | 0% | 0 | 571 | 0 | 0.00 |

## Every run

| Matchup | Run | Winner | Time (s) | Allies left | Hostiles left | Dmg A / H | Friendly fire A / H |
|---|---|---|---|---|---|---|---|
| LANCE  2 Lance advance onto 3 dug-in rifles, 55 m | 1 | ally | 6 | 2/2 | 0/3 | 278 / 133 | 0 / 0 |
| LANCE  2 Lance advance onto 3 dug-in rifles, 55 m | 2 | hostile | 9 | 0/2 | 1/3 | 234 / 249 | 0 / 0 |
| LANCE  2 Lance advance onto 3 dug-in rifles, 55 m | 3 | ally | 4 | 2/2 | 0/3 | 278 / 133 | 0 / 0 |
| LANCE control  2 Rover, same fight | 1 | ally | 4 | 2/2 | 0/3 | 198 / 107 | 0 / 0 |
| LANCE control  2 Rover, same fight | 2 | ally | 5 | 2/2 | 0/3 | 195 / 241 | 0 / 0 |
| LANCE control  2 Rover, same fight | 3 | ally | 3 | 2/2 | 0/3 | 194 / 105 | 0 / 0 |
| PICKET  2 Picket hold at 85 m, 4 rifles cross to them | 1 | draw | 120 | 1/2 | 3/4 | 110 / 236 | 0 / 0 |
| PICKET  2 Picket hold at 85 m, 4 rifles cross to them | 2 | hostile | 18 | 0/2 | 4/4 | 0 / 300 | 0 / 0 |
| PICKET  2 Picket hold at 85 m, 4 rifles cross to them | 3 | draw | 120 | 1/2 | 3/4 | 110 / 269 | 0 / 0 |
| PICKET control  2 Walker hold, same fight | 1 | draw | 120 | 2/2 | 3/4 | 112 / 27 | 0 / 0 |
| PICKET control  2 Walker hold, same fight | 2 | draw | 120 | 2/2 | 3/4 | 112 / 27 | 0 / 0 |
| PICKET control  2 Walker hold, same fight | 3 | draw | 120 | 2/2 | 3/4 | 99 / 27 | 0 / 0 |
| KITE  2 Kite advance onto 4 dug-in rifles, 60 m | 1 | ally | 5 | 2/2 | 0/4 | 255 / 52 | 0 / 0 |
| KITE  2 Kite advance onto 4 dug-in rifles, 60 m | 2 | ally | 6 | 2/2 | 0/4 | 255 / 80 | 0 / 0 |
| KITE  2 Kite advance onto 4 dug-in rifles, 60 m | 3 | ally | 39 | 2/2 | 0/4 | 250 / 27 | 0 / 0 |
| KITE control  2 Rover, same fight on the ground | 1 | ally | 6 | 2/2 | 0/4 | 268 / 115 | 0 / 0 |
| KITE control  2 Rover, same fight on the ground | 2 | ally | 5 | 2/2 | 0/4 | 258 / 102 | 0 / 0 |
| KITE control  2 Rover, same fight on the ground | 3 | ally | 5 | 2/2 | 0/4 | 255 / 158 | 0 / 0 |
| BROOD  2 Broodcarrier at 12 m cruise vs 4 dug-in rifles, 60 m | 1 | hostile | 15 | 0/2 | 4/4 | 0 / 416 | 0 / 10 |
| BROOD  2 Broodcarrier at 12 m cruise vs 4 dug-in rifles, 60 m | 2 | draw | 120 | 1/2 | 4/4 | 0 / 412 | 0 / 34 |
| BROOD  2 Broodcarrier at 12 m cruise vs 4 dug-in rifles, 60 m | 3 | hostile | 15 | 0/2 | 4/4 | 0 / 431 | 0 / 0 |
| BROOD control  2 Spotter, same fight at 22 m cruise | 1 | draw | 120 | 2/2 | 4/4 | 0 / 0 | 0 / 0 |
| BROOD control  2 Spotter, same fight at 22 m cruise | 2 | draw | 120 | 2/2 | 4/4 | 0 / 0 | 0 / 0 |
| BROOD control  2 Spotter, same fight at 22 m cruise | 3 | draw | 120 | 2/2 | 4/4 | 0 / 0 | 0 / 0 |
| VESSEL  1 Vessel + 2 rifles vs 4 rifles, 50 m | 1 | hostile | 25 | 0/3 | 4/4 | 86 / 409 | 0 / 10 |
| VESSEL  1 Vessel + 2 rifles vs 4 rifles, 50 m | 2 | hostile | 63 | 0/3 | 2/4 | 217 / 616 | 0 / 10 |
| VESSEL  1 Vessel + 2 rifles vs 4 rifles, 50 m | 3 | hostile | 30 | 0/3 | 3/4 | 100 / 560 | 0 / 0 |
| BASTION  1 Bastion + 3 rifles hold vs 6 rifles, 60 m | 1 | ally | 23 | 3/4 | 0/6 | 425 / 334 | 0 / 0 |
| BASTION  1 Bastion + 3 rifles hold vs 6 rifles, 60 m | 2 | ally | 12 | 4/4 | 0/6 | 398 / 27 | 0 / 0 |
| BASTION  1 Bastion + 3 rifles hold vs 6 rifles, 60 m | 3 | ally | 23 | 4/4 | 0/6 | 492 / 30 | 0 / 0 |
| BASTION control  1 Walker + 3 rifles hold, same fight | 1 | ally | 37 | 4/4 | 0/6 | 434 / 114 | 5 / 0 |
| BASTION control  1 Walker + 3 rifles hold, same fight | 2 | ally | 3 | 4/4 | 0/6 | 555 / 28 | 0 / 0 |
| BASTION control  1 Walker + 3 rifles hold, same fight | 3 | ally | 3 | 4/4 | 0/6 | 551 / 28 | 0 / 0 |
| SEE-ENGINE  1 See-Engine + 4 rifles vs 4 rifles, 55 m | 1 | ally | 33 | 2/5 | 0/4 | 294 / 400 | 0 / 0 |
| SEE-ENGINE  1 See-Engine + 4 rifles vs 4 rifles, 55 m | 2 | hostile | 17 | 0/5 | 4/4 | 140 / 561 | 0 / 0 |
| SEE-ENGINE  1 See-Engine + 4 rifles vs 4 rifles, 55 m | 3 | ally | 11 | 4/5 | 0/4 | 353 / 170 | 0 / 0 |
| SEE-ENGINE control  4 rifles alone vs 4 rifles | 1 | hostile | 13 | 0/4 | 3/4 | 197 / 291 | 0 / 0 |
| SEE-ENGINE control  4 rifles alone vs 4 rifles | 2 | hostile | 10 | 0/4 | 3/4 | 60 / 346 | 0 / 0 |
| SEE-ENGINE control  4 rifles alone vs 4 rifles | 3 | hostile | 18 | 0/4 | 3/4 | 90 / 305 | 0 / 0 |
| DRAYMAN  1 Drayman + 3 rifles vs 4 rifles, 50 m | 1 | hostile | 5 | 0/4 | 4/4 | 30 / 430 | 0 / 0 |
| DRAYMAN  1 Drayman + 3 rifles vs 4 rifles, 50 m | 2 | ally | 12 | 1/4 | 0/4 | 263 / 397 | 0 / 10 |
| DRAYMAN  1 Drayman + 3 rifles vs 4 rifles, 50 m | 3 | hostile | 6 | 0/4 | 4/4 | 0 / 416 | 0 / 0 |