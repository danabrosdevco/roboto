# Roboto — software tree, and growing past the valley

Written 2026-09-19. Part 1 is the design for the SOFTWARE tab (built, blank:
`Campaign/software_tree.gd`, `Character/hud/squad/software_page.gd`). Part 2 is
ten directions for the late-early and early-mid game.

---

## Part 1 — Software

### The idea

Weapons, gear, modules and frames are **hardware**: bought with resources,
fitted to bodies, lost with them. **Software** is the drone's own code — you are
a rogue agentic drone, and this is you getting smarter.

It runs on **compute**, the same capacity a seat runs on. The briefing already
said it (§6): compute is *capacity, not a currency* — won, never bought, and
held rather than spent. A seat is a control link for one more robot; a program
is the drone thinking better. Every point of compute asks one question:

> **another body in the field, or a better mind commanding them?**

Because a program only *holds* compute, uninstalling gives all of it back, any
time. So this is not a shop — it is a set of switches, and the interesting
decision is what you run *for this mission*.

**Tab name.** SOFTWARE is what the code uses; it is the plainest and it makes
the hardware/software split obvious at a glance. Alternatives with more
flavour: KERNEL, FIRMWARE, PROCESSES. Programs could carry a suffix in their
names for texture (`QUICKORDER.EXE`), sparingly.

### What a point of compute is worth

The exchange rate everything is balanced against:

| Compute | Buys in seats | So a program must be worth… |
|---|---|---|
| 1 | one more robot | one more armed soldier, in the fights it touches |
| 2 | a fire team's extra pair | a new *option*, not a bigger number |
| 3 | a heavy unit (the future 3-seat frames: a walker, a drone swarm, an APC) | a new *verb* — something that changes how a mission is played |

If a program is worse than the seats it costs, nobody installs it; if it is
much better, nobody buys seats. Both have to stay live.

**Rules of thumb**

- **Tier 1 (1 compute) — efficiency and information.** Tempo, recovery,
  knowing things sooner. Numbers are fine here, but on things that compound
  (a faster order is faster every order).
- **Tier 2 (2) — options.** Change what an order or an item *can do*.
- **Tier 3 (3) — signatures.** Each should be the thing a player describes to
  someone else. Only one per branch, and a player with ~10 compute can afford a
  capstone *or* three seats, not both plus everything else.
- **Squad-scaling programs compete with seats on purpose.** A program that is
  better per robot you field (fire teams, hive mind) makes seats *more*
  valuable, not less — that is the good kind of tension. Cap them.
- **Refunds make builds situational.** Expect players to reflash between
  missions: a SIGNAL build for a jammer map, COMMAND for a big squad. Design
  programs that shine somewhere rather than everywhere.
- **Decide: base only?** Installing mid-mission (the tab opens with TAB in the
  field) invites swapping per firefight. Recommendation: programs change at
  base only; in the field the page is read-only.

**The budget.** The tree costs 40 compute to fill (four branches × 3·1 + 2·2 +
1·3). The current campaign pays 6 (first clears of arena 4–5 and valley 3–5)
plus hidden objectives. By the early-mid game a player should have ~10–14:
enough for a build, never the whole tree.

### The programs — 36 candidates

Four branches, matching the placeholders in the tree. More candidates than
slots on purpose (the screen has 3 / 2 / 1 per branch): pick the best, cut or
move the rest. Hooks in brackets are systems that already exist in the repo.

#### COMMAND — how the squad takes orders

| Tier | Program | Does | Worth it because |
|---|---|---|---|
| 1 | **Quick Orders** | Orders take effect instantly; the squad moves 15% faster while carrying one out. | Every order, every mission — tempo compounds. |
| 1 | **Waypoint Chain** | Queue up to three move orders; the squad walks the route. | Flanking without babysitting. [order positions] |
| 1 | **Focus Fire** | Tag an enemy with the command key; the squad takes it first, +15% damage to it. | Deletes the dangerous one (a hopper, a gunner) before it acts. |
| 1 | **Rally Beacon** | Robots within 15 m of you self-revive 50% faster; stragglers regroup on you out of contact. | Fewer robots lost to being left behind. [self-revive] |
| 2 | **Fire Teams** | Split the squad into two teams and order them separately. | Doubles what one command key can express — and makes every seat worth more. |
| 2 | **Stances** | Squad-wide AGGRESSIVE (push, +damage, more risk) / CAUTIOUS (cover, hold fire until engaged, +resistance). | The designed-not-built stance from the briefing; gives back the lost verb. |
| 2 | **Overwatch** | A DEFEND order holds fire until something enters the cone, then the first volley hits at +25% accuracy. | Ambushes — turns a hold into a trap. |
| 3 | **Hijack** | Possess an EMP'd or signal-critical *enemy* robot. It fights for you until destroyed, then ejects you. | A free extra robot, taken from theirs — a 3-seat swing. [possession, EMP, SignalState] |
| 3 | **Hive Mind** | Anything one robot sees, all of them see — and you see it through walls for a moment. +accuracy against spotted targets. | Information at the scale of a drone swarm. [detection, stimulus manager] |

#### SIGNAL — the link between you and them

| Tier | Program | Does | Worth it because |
|---|---|---|---|
| 1 | **Error Correction** | Signal recovers 50% faster. | Aim depends on signal; this is aim, recovered. [signal_integrity] |
| 1 | **Long-Range Link** | Command range +50%; out-of-range robots lose signal slower. | Big maps stop punishing spread-out squads. |
| 1 | **Hardened Handshake** | Your robots can't be e-killed; the worst jamming leaves them CRITICAL. | Removes the instant loss. [SignalState.EKILL] |
| 1 | **Ping** | A key reveals enemies within 40 m for 3 s (20 s cooldown). | The Scanner's job, as software — it left the shop. |
| 2 | **Mesh Network** | Robots relay signal to each other; a squadmate near another counts as in range. | Makes spreading out safe; pairs with Fire Teams. |
| 2 | **Counter-Jam** | An EMP or jam that hits your squad also fuzzes enemy robots within 10 m of the victim. | Punishes the enemy for using the tool you fear most. |
| 2 | **Intercept** | Enemy calls for reserves are overheard: you get their direction, and a quarter of calls fail. | Turns the reinforcement director into information. [RESERVE posture] |
| 3 | **Overload** | Emit an EMP pulse from yourself: enemies within 12 m frozen 3 s (60 s cooldown). | Stops a chaser/hopper rush dead — the job of a heavy bodyguard. [EMP] |
| 3 | **Ghost Signal** | While you aren't firing, enemy sensors can't lock onto you. | A whole stealth playstyle: command from the shadows. |

#### COMBAT — you, in the fight

| Tier | Program | Does | Worth it because |
|---|---|---|---|
| 1 | **Steady Hands** | Your spread −25% while standing still. | Rewards stop-and-shoot; made for the bolt-action era (Part 2 §2). |
| 1 | **Fast Hands** | Reload and weapon switch 30% faster. | Every reload, every mission. |
| 1 | **Field Welder** | The repair tool heals 40% faster and reaches 1.5× as far. | Keeping a robot up is keeping a seat's worth in the fight. [repair tool] |
| 1 | **Deep Pockets** | +1 frag and +25% reserve ammo. | Matters more the day ammo costs something. [ammo pools] |
| 2 | **Armour-Piercing** | Your rifles ignore 30% of armour. | The answer to scaling enemy toughness (Part 2 §2). |
| 2 | **Marked for Death** | Your hits mark a target for 4 s: the squad deals +20% to it. | You become the squad's spotter. |
| 2 | **Second Wind** | Once a mission, a killing blow leaves you at 1 HP with 3 s of invulnerability. | One saved mission is worth more than any stat. [YOU DIED] |
| 3 | **Overclock** | Slow time to 40% for 3 s (60 s cooldown). | A machine mind's signature — a 3-seat moment on demand. |
| 3 | **Split Process** | While you possess a squadmate, your own body fights on as an AI with your loadout. | Possession stops costing you a body. [possession] |

#### FABRICATION — what the base can make

| Tier | Program | Does | Worth it because |
|---|---|---|---|
| 1 | **Salvage Protocols** | +20% resources from missions. | Resources buy robots and gear — slow, but it compounds. |
| 1 | **Efficient Rebuild** | Rebuilding a destroyed robot costs 40% less. | Makes risk cheaper; pairs with aggressive play. |
| 1 | **Bulk Orders** | Armorer prices −15%. | Straight economy. |
| 1 | **Recycling** | Selling refunds 75%, not half. | Makes experimenting with gear cheap. |
| 2 | **Field Printer** | +1 use of every throwable per mission, for everyone. | A whole squad's extra grenades. [equipment quantity] |
| 2 | **Frame Tuning** | Robots built at the Factory get +15% health, and Soldiers come with a rifle instead of a pistol. | Better robots out of the same seats. |
| 2 | **Scavenger Drones** | Destroyed enemies drop resources and ammo to collect. | A reason to push into what you killed. |
| 3 | **Forward Fabricator** | Once a mission, rebuild one destroyed squadmate at a deployable fabricator. | Undoes a loss mid-fight — a unit's worth, recovered. |
| 3 | **Swarm Foundry** | Every mission starts with three hatchling drones that follow you and go for your target. | Literally the drone swarm, for its price. [hatchling] |

---

## Part 2 — Growing past the valley

Where the game is now: the **arena** teaches the verbs with one or two allies
(early-early); the **valley** is the full squad against garrisons, with
compute starting to flow (early). Ten directions for the late-early game — the
next map — and the early-mid game after it.

The vibe for the next stage, from the human: **the main weapon shifts from
low-power, fast rifles to harder-hitting, pseudo-bolt-action rifles as enemy
health scales up.** That runs through most of these.

1. **The Data Center — the next map.** The title's promise. Server halls
   (racks as broken sight lines, rewards positioning), cooling plants, cable
   trenches, catwalks for height. Missions: breach the perimeter, hold the
   cooling plant, pull the core. Hidden objectives are *data caches* that pay
   compute. The kenney industrial kit in `3d_assets/` is a start on the look.

2. **Armour, and the bolt-action era.** Enemies stop just getting more HP and
   start carrying *armour*: a flat amount taken off every hit. A 20-damage
   rifle round against 15 armour does 5, so the Ancient Rifle stops being the
   answer and slow, heavy, hard-hitting rifles become it — the gun pack's
   `SniperRifle_1–6` models, and the DMR finally with its own art. Weak points
   (a sensor eye) reward the aimed shot. Fast rifles stay the answer to swarms
   (chasers, hatchlings), so loadouts become choices per mission. Squad
   marksmen on DEFEND become snipers. Pairs with Armour-Piercing and Steady
   Hands in Part 1.

3. **A second enemy faction, with a doctrine.** The valley's scavenger bands
   rush and swarm. The data center's security AI — call it the Custodian —
   fights with the signal: jammers, turrets, lockdown doors, armoured sentry
   frames, gunships. Each faction is a different puzzle and a reason to
   reflash your software (SIGNAL against the Custodian, COMMAND against a
   rush).

4. **Heavy units: the 3-seat frames.** The gunship (`chassis_helicopter.tres`
   exists), a walker (the "space marine"), a drone-swarm carrier, an APC that
   is moving cover and a respawn point. Each costs two or three seats — the
   direct rival to a tier-3 program, which is exactly the tension supply was
   built for.

5. **Research — chassis swaps and new tech.** The late-game research the human
   specified: move a veteran into a better frame. Plus the bolt-action line,
   tier-two modules, and building *captured* enemy frames. Fed by salvage from
   enemy wrecks — the "neural bits" half of the economy split in the briefing
   (§6), finally with a job.

6. **A campaign map.** The mission board grows into a region: sectors taken
   by clearing missions produce resources (and occasionally compute) each
   deployment; the enemy counter-attacks sectors, which become *defend*
   missions. Territory is progress you can see, and the missions get a why.
   The map board and minimap painter are already built.

7. **Operations — missions in chains.** Two or three phases on one map with
   only a short field resupply between them: no return to base, damage
   carries between phases, bigger rewards at the end. The bench stops being a
   parking lot and becomes rotation depth. (Works with the new end-of-mission
   repair: an operation is one mission with more than one fight in it.)

8. **Escalation you cause.** The reinforcement director (`Posture.RESERVE`)
   driven by a mission *heat* meter: explosions, alarms, long firefights and
   dropped bodies raise it; reserves wake, gunships arrive, jammers deploy.
   Fast or quiet play keeps it low. Difficulty that answers how you play, not
   a clock — and a reason for Ghost Signal and Intercept to exist.

9. **The war around you.** GAMEPLAN §9's abstract engagement layer: allied
   squads fighting elsewhere on the map, heard on the radio and in distant
   fire, whose wins and losses change your mission (a collapsed flank wakes a
   reserve behind you). The early-mid game shifts from "your squad against a
   garrison" to "your squad as the spearhead of an offensive" — scale without
   paying for the bodies.

10. **The base grows.** Home base as rooms you build with resources: the
    Factory and Armorer you have, then a Research lab (§5), a Comms room
    (see engagements and incoming reserves on the map), a Repair bay (cheaper
    rebuilds). The base becomes the visible record of the campaign — and, once
    the enemy knows where it is, something to defend.

Two in reserve: **veteran traits** (a rank-up offers a choice of trait —
Marksman, Brawler, Medic — so a named robot becomes a *kind* of robot), and
**mission conditions** (night, rain, an EMP storm, data fog that blanks the
minimap).
