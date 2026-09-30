# DESIGN DROP 1 — numbers

Seven items picked off `CONTENT_BACKLOG.md`. Numbers are set against the real
catalogue, not invented: every table below has the existing weapons in it for
comparison. **°** still means new code.

## Where these sit against what exists

| weapon | dmg | cooldown | mag | reload | range | spread | sustained DPS |
|---|---|---|---|---|---|---|---|
| Ancient Rifle (`m4`) | 30 | 0.35 | 30 | 2.6 | 80 | 18 | 86 |
| Mark One (`bolt`) | 55 | 0.80 | 10 | 3.4 | 100 | 15 | 69 |
| Ancient MG (`machine_gun`) | 15 | 0.13 | 100 | 5.0 | 99 | 12 | 115 |
| Heavy MG | 22 | 0.12 | 120 | 6.0 | 105 | 11 | 183 |
| Autocannon | 60 | 0.50 | 20 | 4.5 | 110 | 5 | 120 |
| Grenade Launcher | 45 | 3.20 | 6 | 6.0 | — | 0 | 14 |
| **→ Squad Automatic** | **16** | **0.11** | **100** | **7.0** | **85** | **22** | **145** |
| **→ Cluster Launcher** | **25+5×22** | **1.10** | **6** | **5.5** | **90** | **0** | **~120 area** |
| **→ Repair Lance** | **30** | **1.10** | — | — | **3.4** | — | 27 |
| **→ AI Recoilless** | **110** | **4.50** | **1** | **5.0** | **120** | **8** | 24 |

The Ancient MG is already belt-fed at 100 rounds — but it is
`usable_by_player = false, fits_vehicles = true`. It is a **mount**. The Squad
Automatic is the carried one, and that is the whole distinction.

---

## 1 · SQUAD AUTOMATIC — `squad_auto`

Factory-printed, belt-fed, 100 rounds. Agentic, not ancient: no wood, no
stamped steel, visible belt, printed receiver.

- **Cost** 185 · WEAPON · ammo `7.62` · `usable_by_player = true`
- **`fits_vehicles = false`** — this is the point. It is carried.
- 16 dmg (min 10 past 30m) · 0.11 cd · **100 belt** · **7.0s reload** · 85m
- **22 mrad — the worst accuracy in the game.** Heavy, handheld, walks under its own fire.
- Bursts 10–22 · suppression 4.0/shot · `suppressive_fire = true`

**The trade:** 145 sustained DPS against the Ancient Rifle's 86 — but it cannot
hit anything precisely, dies past 85m, and the 7-second reload is a decision you
make once a fight. It is a weapon for holding a lane, not for winning a duel.

**Unlock:** Hillfort or Basin. It wants to arrive while maps are still close.

---

## 2 · REPAIR LANCE — `repair_lance`

A long two-handed melee weapon. Damages enemies, **repairs allies on contact**.

- **Cost** 90 · WEAPON · MELEE · infantry only (`requires_chassis`)
- **`melee_range = 3.4`** against the 1.5 default — the "long" in long weapon
- `melee_arc_angle = 40` — a thrust, not a swing
- **60 damage** to enemies · 1.1s cycle
- **Repair is half the damage: 30** °
- **And it is the resource.** 3 charges, one spent per ally hit, **+1 every 9s**.
  The damage is always free; the repair runs out. °

**Why charges rather than a flat heal:** a lance that repairs on every swing is
a Mechanic you can also stab people with, and it would retire the Mechanic. On
three charges it is a burst — get to someone, put them back up, then you are a
melee weapon again until it refills. The reservoir on the model is literally
the thing that empties.

At 60 damage it is the hardest-hitting thing in the game per hit outside the
Recoilless, which is the trade for having to close to 3.4m to use it.

**Why it is interesting:** it is the only weapon that makes walking *toward*
your own downed squadmate the aggressive play. Pairs with the Mechanic without
replacing it — the Mechanic repairs from range and cannot fight.

**New code:** one branch in the melee hit resolution — if the thing hit is
friendly, call `heal` instead of `apply_damage`.

---

## 3 · SMOKE CANISTER — `smoke`

- **Cost** 40 · EQUIPMENT · quantity 2
- Thrown. Volume **7m radius, 14 seconds**, fades over the last 3
- **Blocks AI line of sight. Does NOT block bullets.** °

**New code, and it is the honest cost of this item:** the AI's `_tick_los` and
`is_path_clear` are raycasts. Smoke cannot be a physics body or it would stop
rounds too. So smoke volumes register in a group and the LOS test does one
segment-vs-sphere check per active volume. There are rarely more than two.

**Why it is first on my list:** it is the only non-lethal answer to a Watcher,
it fixes every open approach, and it is the single most-missed item in a game
that is entirely about crossing ground under fire.

---

## 4 · MINES — two, deliberately different

### 4a · HEAVY MINE — `mine_heavy`
- **Cost** 55 · EQUIPMENT · quantity 1 · placed, not thrown
- **160 damage, 4.5m radius** — kills a rover, cripples a walker
- Arms 1.5s after placing · **triggers on ENEMY faction only** °

Faction-gated on purpose. A mine that kills your own squad is a mine nobody
places in a game where the squad pathfinds on its own.

### 4b · CLUSTER MINE — `mine_cluster`
- **Cost** 45 · EQUIPMENT · quantity 2 · thrown
- Bursts on landing into **5 submines scattered over 6m**
- Each: 45 damage, 2.0m radius, arms 1.0s, **45s lifetime** then self-clears °

One denies a chokepoint hard. The other denies an area softly and expires. Same
verb, opposite shape.

---

## 5 · CLUSTER LAUNCHER — `cluster_launcher` ✅ BUILT

Six-shot revolver drum, fires on an arc, each round **bursts into
submunitions**. Agentic. Deliberately distinct from the Ancient Grenade
Launcher, which is a single direct blast.

**As built** (the id is `cluster_launcher`, not `cluster_mgl` — that name
stayed on the concept model):

- **Cost** 240 · WEAPON · PROJECTILE, arcing · 42 m/s muzzle, 75m for the AI
- **6-round drum** · 0.55s between shots · 5.5s reload · ammo `40mm`, 18 carried
- **34 direct** on impact, then **6 bomblets at 26 in a 3.4m circle**, fused
  0.55–0.95s so they land over about a second rather than on one beat
- Allies will not fire it inside **14m** (`min_effective_range`) — the bomblets
  scatter five metres and it would kill the squad
- Compare: `grenade_launcher` is 45 direct, 3.2s cycle, one blast

Files: `cluster_shell.gd/.tscn` (extends `AIGrenadeProjectile`, overrides
`_explode()`), `player_cluster_launcher.gd` (extends `HUDWeapon`, overrides
`_fire_shot()`), `cluster_hud_weapon.tscn`, `ai-wep_cluster.tscn`,
`item_cluster_launcher.tres`, `ammo_40mm.tres`. Unlocked by `mutaha_2_city`.

**The difference in play:** the Grenade Launcher is for one hard target behind
cover. The Cluster Launcher empties six rounds in seven seconds and turns a
street into somewhere nobody can stand. It is an area-denial weapon that happens
to fire grenades.

---

## 6 · DRONE CARRIER PACK + THE DIVER

### 6a · DRONE CARRIER PACK — `drone_pack`
- **Cost** 95 · EQUIPMENT · **quantity 2** · fits any frame with an equipment slot
- **Used, not passive.** One use throws the pack open and releases **2 Divers at
  once**; two uses in a mission. °
- Same shape as the Hatchling Canister, which is also `quantity = 2` and also
  puts bodies on the map when you press the button.

**Changed from the first pass**, which trickled one out every 6s while the
carrier was in combat. That made it a passive aura you forgot you had, and it
put the interesting decision — *when* — in the hands of the AI. As a used item
it is a thing you spend: two moments in a mission where four drones arrive
because you chose it.

### 6b · THE DIVER — new frame, supply 0
Not a roster unit — it only exists because something released it, the way
hatchlings do.

- 25 health · very fast · **no weapon slot** · no modules
- **Climbs on release**, acquires the nearest enemy, then **dives into it**
- Impact: **55 damage, 3m radius**, destroys itself °
- Dies to almost anything on the way in — it is a threat you answer by shooting
  it, not by out-ranging it

**Why it is worth the code:** you have no aerial threat the player must look
*up* for, and nothing that makes the squad's small-arms fire matter defensively.

---

## 7 · AI RECOILLESS — `ai-wep_recoilless.tscn`

**This is a gap, not a new idea.** `item_rocket.tres` (id `recoilless`) has a
`player_scene` and **no `ai_scene` at all** — so no enemy and no squadmate can
ever hold one. The item is half-built and has been since it was added.

- PROJECTILE · **110 damage** · 4.5s cycle · **1 round, 5.0s reload** · 120m
- **`min_effective_range = 12`** — it will not fire closer than that. Backblast,
  and it stops a rocket trooper suiciding into your squad.
- 8 mrad · anti-vehicle profile

Gives enemies a credible answer to the Rover and the Walker, which they
currently do not have below the Autocannon, and lets your own squad carry one.

---

## Build order within this drop

1. ✅ **AI Recoilless** — no new code, completes a half-built item.
2. ✅ **Squad Automatic** — no new code, doubles the player's weapon count.
   Unlocked by `pitt_1_rivers`.
3. ✅ **Cluster Launcher** — submunition spawn on detonation; small.
4. **Smoke** — the LOS system. One new check, high payoff.
5. **Mines** — faction-gated trigger + a placement verb. Shares code with smoke's placement.
6. **Repair Lance** — one branch in melee resolution.
7. **Diver + Carrier Pack** — the largest; wants the Nest's hatching refactored to be reusable.
