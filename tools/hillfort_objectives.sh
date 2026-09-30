#!/usr/bin/env bash
# Puts the GAMEPLAY half of the Hillfort back into maps/hillfort_level.tscn.
#
# WHY THIS IS A SCRIPT AND NOT AN EDIT. The hillfort level is regenerated from
# a terrain recipe and a block pass, and the regenerator does not preserve
# nodes it did not place. Every rebuild therefore deletes:
#
#   - RelayObjective      the console the mission is about (id hillfort_relay)
#   - ReachObjective      the way off the hill        (id hillfort_extract)
#   - the squad spawn position and its max_slots
#
# and the mission then deploys into a level whose objectives it names but which
# does not contain them. active_objectives is a WHITELIST — Campaign._prune_
# inactive_objectives() frees every objective the mission does not name — so a
# mission naming two ids the level does not have ends up with none at all: a
# blank objective HUD and no way to finish. That shipped once and cost a
# playtest, which is what this exists to stop costing again.
#
# IDEMPOTENT. Re-run it after any hillfort rebuild; it does nothing if the
# nodes are already there. Verify with:
#
#   godot --headless --audio-driver Dummy --path . \
#         --script res://tools/test_mission_objectives.gd
#
# THE REAL FIX is for the regenerator to leave non-generated nodes alone. Until
# it does, this is the repair.
set -uo pipefail
cd "$(dirname "$0")/.."

LEVEL="maps/hillfort_level.tscn"
[ -f "$LEVEL" ] || { echo "no $LEVEL"; exit 2; }

if grep -q 'name="RelayObjective"' "$LEVEL"; then
	echo "      hillfort already carries its objectives — nothing to do"
	exit 0
fi

# ── WHERE THINGS GO ──────────────────────────
# The console sits on the Hillfort_Dish squad point, which is the spot TERRAIN
# authored as "The Relay Dish" — so it moves when they move it, rather than
# being a number this script guesses at.
DISH=$(grep -A1 'name="Hillfort_Dish"' "$LEVEL" | grep '^transform' \
	| sed 's/.*, \([-0-9.]*\), \([-0-9.]*\), \([-0-9.]*\))/\1, \2, \3/')
[ -n "$DISH" ] || { echo "FAIL: no Hillfort_Dish to hang the console on"; exit 1; }

# YOU START AT THE FOOT OF THE CLIMB, not 250m short of it. The generated spawn
# is at the trailhead, which is a quarter of a kilometre of empty ground before
# the first shot. This is the last point on the Trailhead->Cistern trail, ~44m
# below the cistern garrison: close enough that the mission opens with a fight,
# far enough that it opens at rifle range instead of on top of them.
PLAYER_AT="-166, 11.15, 302"
SQUAD_AT="-170, 10, 308"

# ── 1. RESOURCES ─────────────────────────────
STEPS=$(head -1 "$LEVEL" | sed 's/.*load_steps=\([0-9]*\).*/\1/')
sed -i "1s/load_steps=$STEPS/load_steps=$((STEPS + 6))/" "$LEVEL"
sed -i 's#^\[ext_resource type="PackedScene" uid="uid://62y43tyd5sx6" path="res://Env/world_objects/squad_objective_point.tscn" id="14_sqpoint"\]#&\
[ext_resource type="Script" path="res://Campaign/interact_objective.gd" id="15_interact"]\
[ext_resource type="Script" path="res://Campaign/reach_objective.gd" id="16_reach"]\
[ext_resource type="PackedScene" uid="uid://bk13ou262jq2t" path="res://Env/world_objects/components/template_interactible.tscn" id="17_interactible"]\
[ext_resource type="PackedScene" uid="uid://cqwr1eg01xfqc" path="res://3d_assets/HackerRoom/FBX/PersonalComputer.fbx" id="18_pc"]#' "$LEVEL"
sed -i '0,/^\[sub_resource/s//[sub_resource type="SphereShape3D" id="SphereShape3D_hf_exit"]\
radius = 10.0\
\
[sub_resource type="BoxShape3D" id="BoxShape3D_hf_console"]\
\
[sub_resource/' "$LEVEL"

# ── 2. WHERE YOU COME IN ─────────────────────
awk -v p="$PLAYER_AT" -v s="$SQUAD_AT" '
	/^\[node name="SpawnPoint" parent="\."\]/ || /^\[node name="SpawnPoint" parent="\." instance=/ { print; hit="p"; next }
	/^\[node name="SquadSpawnPoint" type="Node3D" parent="\."\]/ { print; hit="s"; next }
	hit == "p" && /^transform = / { print "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, " p ")"; hit=""; next }
	hit == "s" && /^transform = / { print "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, " s ")"; hit=""; next }
	{ print }
' "$LEVEL" > "$LEVEL.tmp" && mv "$LEVEL.tmp" "$LEVEL"
# No cap. The script default is 0 (everyone) now, but every hand-built level in
# this project says so out loud and a reader comparing them should not have to
# know which way the default went.
sed -i 's#^script = ExtResource("3_squad")$#&\nmax_slots = 999#' "$LEVEL"

# ── 3. THE WAY OUT ───────────────────────────
# requires_objectives_complete: the roof is not an exit until the relay is
# taken, or the mission is "walk to the far end of the map".
awk '
	/^\[node name="LevelExit" parent="NavigationRegion3D" instance=/ { print; hit=1; next }
	hit && /^transform = / {
		print
		print "requires_objectives_complete = true"
		print ""
		print "[node name=\"ReachObjective\" type=\"Node3D\" parent=\"NavigationRegion3D/LevelExit\" node_paths=PackedStringArray(\"area\", \"prerequisites\")]"
		print "script = ExtResource(\"16_reach\")"
		print "area = NodePath(\"Area3D\")"
		print "squad_radius = 30.0"
		print "id = &\"hillfort_extract\""
		print "display_name = \"Off The Hill\""
		print "description = \"The relay is yours. The way out is the hall roof.\""
		print "prerequisites = [NodePath(\"../../../RelayObjective\")]"
		print "is_extraction = true"
		print ""
		print "[node name=\"Area3D\" type=\"Area3D\" parent=\"NavigationRegion3D/LevelExit/ReachObjective\"]"
		print ""
		print "[node name=\"CollisionShape3D\" type=\"CollisionShape3D\" parent=\"NavigationRegion3D/LevelExit/ReachObjective/Area3D\"]"
		print "shape = SubResource(\"SphereShape3D_hf_exit\")"
		hit=0
		next
	}
	{ print }
' "$LEVEL" > "$LEVEL.tmp" && mv "$LEVEL.tmp" "$LEVEL"

# ── 4. THE CONSOLE ───────────────────────────
# Appended, then the [editable] directives are rewritten at the very end: they
# close a .tscn and a node declared after them is not read back.
sed -i '/^\[editable path=/d' "$LEVEL"
cat >> "$LEVEL" <<EOF

[node name="RelayObjective" type="Node3D" parent="." node_paths=PackedStringArray("interactibles", "linked_squad_point")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, $DISH)
script = ExtResource("15_interact")
interactibles = [NodePath("Interactible")]
id = &"hillfort_relay"
display_name = "The Relay"
description = "Take the console in the fort yard."
reward_resources = 40
linked_squad_point = NodePath("../EnemySquadObjs/Hillfort_Dish")

[node name="Interactible" parent="RelayObjective" instance=ExtResource("17_interactible")]
collision_layer = 3
type = 4
respawns_on_reset = false
destroy_on_use = false

[node name="CollisionShape3D" parent="RelayObjective/Interactible" index="0"]
transform = Transform3D(1.38711, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.108154, 0)
shape = SubResource("BoxShape3D_hf_console")

[node name="PersonalComputer" parent="RelayObjective" instance=ExtResource("18_pc")]

[editable path="WorldEnvironment"]
[editable path="RelayObjective/Interactible"]
EOF

echo "      hillfort: relay console at ($DISH), extraction on the hall roof,"
echo "      squad in at ($PLAYER_AT) below the cistern, no deploy cap"
