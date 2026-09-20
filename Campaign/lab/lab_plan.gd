extends Resource
class_name LabPlan

# ─────────────────────────────────────────────
# LAB PLAN — a list of matchups the laboratory runs in order.
#
# Pick one on Master (Laboratory > lab_plan) and tick lab_mode. Each plan is a
# question: "does the defender have an advantage", "where do melee robots stop
# winning". Duplicate one to ask your own; the matchups inside are edited in
# the inspector like any other resource.
# ─────────────────────────────────────────────

@export var title: String = "Laboratory"
@export_multiline var question: String = ""
## LabMatchup resources. Typed as Resource so this script never depends on
## the class list having caught up with a new class (see analytics.gd).
@export var matchups: Array[Resource] = []
## The map to fight on. Empty uses the arena.
@export var level: PackedScene
## Where to fight on a map without the arena's hostile post: the middle of the
## line the two sides start on. Left at zero, the map's post and insertion
## point set the line, as in the arena.
@export var site: Vector3 = Vector3.ZERO
## Which way that line runs, in degrees round from -Z.
@export var site_heading: float = 0.0
## Overrides every matchup's repeats when above 0 — for a quick look at a big
## plan, or a long soak of a small one.
@export var repeats_override: int = 0
## Game speed while the plan runs. 2-3 gets through a big plan quickly; the
## numbers are in game seconds either way.
@export_range(0.5, 4.0, 0.5) var speed: float = 1.0
