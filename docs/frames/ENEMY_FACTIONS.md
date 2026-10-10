# The enemy three — shared prerequisite

Broodcarrier (Swarm) · Bastion (StratCom) · See-Engine (Argus)

**Read this before any of the three. It is the same blocker for all of them
and it is the single most dangerous thing in this whole batch.**

---

## The append is free. The function next to it is not.

A read-only sweep of every faction reference in the project found the cost of
adding SWARM, STRATCOM and ARGUS to `Enums.Factions` to be **MEDIUM**, and
almost all of that is one function.

### What is genuinely free

**No faction value reaches `campaign.json`.** `CampaignState.to_dict` and
`SoldierRecord.to_dict` were read field by field; neither carries one. The
player squad's ALLIED is re-derived at spawn (`soldier_record.gd:375`).

**The faction int IS on disk in 805 places** — `EnemySquadSpec` sub-resources
across 30 mission files — and **every single one of them is `1`**. So
appending is a literal no-op for all of them. Reordering would silently
repoint every hostile in 27 missions with no parse error and no warning, which
is the project's append-only rule earning its keep again.

**Missions can already name a faction.** `EnemySquadSpec.faction` is an
existing export and `enemy_force_spawner.gd:270` already does
`soldier.faction = spec.faction`. Writing `faction = 4` in a mission spawns a
Swarm squad the day the enum value exists. No schema change, no new spawner.

### The blocker: `are_hostile()` has no default arm

`Managers/enums.gd:29-38` matches on four values and falls out to
`return false`. Append a fifth and **a robot carrying it is simultaneously
invisible and near-invulnerable, in both directions, with nothing in the log**:

| site | what happens |
|---|---|
| `ai_manager.gd:365` | nobody targets it, and it targets nobody |
| `ai_weapon.gd:320` | `_is_friendly` says everything is friendly, so `friendly_in_line` blocks its own shot — **it never fires** |
| `hud_weapon_template.gd:333` | the player's rounds hit it for `friendly_fire_multiplier` |
| `explosion.gd:141` | so do blasts |
| `emp_blast.gd:107` | EMP skips it as friendly |
| `mine.gd:179` | mines never arm on it |
| `tracer.gd:66` | its tracers render in the **friendly** colour |
| `possession.gd:105` | **the player can possess it** |
| `player_repair_tool.gd:451` | **the player can repair it** |
| `enemy_force_spawner.gd:963` | the pre-deploy purge leaves it standing |
| `eliminate_objective.gd:59` | an eliminate objective will not count it |
| `analytics.gd:584` | killing one logs as friendly fire |

Thirty-five call sites, **not one of which errors when the answer is wrong**.
GDScript does not warn on a non-exhaustive enum match, so the append compiles
clean and presents at runtime as "the new enemies just stand there".

### Task zero

**Rewrite `are_hostile` as a table before any enemy frame exists**, with a test
that asserts every pair in both directions — including pairs that do not exist
yet, so the next append cannot repeat this.

Two constraints found in the same sweep:

- **Inter-faction hostility cannot live in `are_hostile`.** It is pure and
  stateless, so "Swarm and StratCom fight each other in mission A but not B"
  has nowhere to go without making the table mission-aware.
- **If the three ARE mutually hostile**, `hostiles_for()` and
  `activation_sources()` start listing enemies as each other's activation
  sources, so hostile forces keep each other awake and the distance cull stops
  culling. That is a performance cliff, not a nicety.

**Recommendation: all three are hostile to the player and to ALLIED, and NOT
to each other.** It costs nothing, avoids the cull problem, and nothing in the
game yet asks to see two enemy factions fight.

### Everything else is mechanical

- three entries in `faction_livery.gd`'s `COLORS` (a Dictionary with a `.get`
  fallback, not a fixed array — missing keys render grey, they do not crash)
- three match arms in `hud_palette.gd:73` (it already has a default, so the
  failure mode is "all three render Swarm amber")
- two hardcoded `== ENEMY` comparisons: `ai_manager.gd:497`,
  `squad_commander.gd:756` — the second means **new factions never hear the
  player's transmit**
- one hardcoded `[ALLIED, ENEMY]` list in the debug contact overlay
- three `FRAMES` entries in `kill_kinds.gd`

The colours are already written and waiting: `FAC_SWARM` amber, `FAC_STRATCOM`
institutional green, `FAC_ARGUS` tyrian, at `hud_palette.gd:62-65`, with a
comment saying adding the factions would be an append.

### One thing to get right first time

`kills_by_kind` keys are persisted and read back through a rename table.
`kill_kinds.gd:21` records that the quadcopter bomber is **still called
`gunship`** because renaming it would orphan every tally already written.

**The three new frame ids are permanent the day the first kill is saved.**
Choose them deliberately: `brood`, `bastion`, `see_engine`.

### A correction worth carrying

The quadcopter bomber and the "helicopter" are **one unit** —
`chassis_helicopter.tres` has `id = &"gunship"` and
`display_name = "Quadcopter Bomber"`. The original gap analysis listed them as
two. There is also a third flyer nobody mentioned: the Diver, a one-shot
kamikaze drone with `supply = 0`, spawned by equipment rather than fielded.
