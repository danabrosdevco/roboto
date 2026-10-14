#!/usr/bin/env bash
# Wires each map's GAMEPLAY LAYER back into its level scene.
#
# WHY THIS EXISTS. Georgetown and Polaris are written from scratch by
# tools/build_georgetown.gd and tools/build_polaris.gd — _write_level() emits
# the whole .tscn as text from a template, so anything hand-added to one of
# them is gone after the next --force rebuild. That is exactly how the
# Hillfort lost its relay console and its extraction point and then shipped a
# mission whose objective HUD was blank, which is what tools/hillfort_objectives.sh
# exists to stop costing again.
#
# The difference here is that the gameplay is NOT pasted in by this script. It
# lives in maps/gameplay/<name>_ops.tscn — a file the terrain tools do not know
# about — and this only has three jobs per level:
#
#   1. put the TrenchBroomLevel script on the root, because World does
#      `next_level_scene.instantiate() as TrenchBroomLevel` and a plain Node3D
#      root casts to null and takes the level load down with it;
#   2. point the root's spawn_point / nav_region / level_exits exports at real
#      nodes, because world.gd reads spawn_point on every load and
#      NavmeshIslands.strip reads nav_region;
#   3. instance the ops scene.
#
# So a rebuild costs one re-run of this and nothing is re-authored. That is the
# whole point of the split.
#
# IDEMPOTENT. Run it as often as you like; a level that already carries its ops
# instance is left alone.
#
#   bash tools/mission_ops.sh
#
# Verify with, per level:
#   LEVEL=res://maps/georgetown_level.tscn godot --headless --audio-driver Dummy \
#       --path . --script res://tools/probe_mission_anchors.gd
# and across the whole campaign:
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/test_mission_objectives.gd
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/test_mission_tags.gd
#
# THE REAL FIX is for the level builders to instance their own map's ops scene
# when they write the level. Until they do, this is the repair — and it is two
# insertions, so it is a cheap one.
set -uo pipefail
cd "$(dirname "$0")/.."

# level file : ops scene : root node name : how the root is declared today
# Causeway is not in this table: it is a hand-built level that already carries
# the script, a PlayerSpawn and a nav region, so it needs the ops instance and
# nothing else. It gets its own branch below.
patch_generated_level() {
	local level="$1" ops="$2" root="$3"
	# $ops is a res:// path because that is what goes INTO the .tscn; the file
	# test needs the project-relative one. Deriving it here rather than passing
	# both is one fewer argument to get out of step.
	local ops_file="${ops#res://}"
	[ -f "$level" ] || { echo "      no $level — skipped"; return 0; }
	[ -f "$ops_file" ] || { echo "      no $ops_file — skipped"; return 0; }

	if grep -q "$ops" "$level"; then
		echo "      $(basename "$level") already carries its ops layer — nothing to do"
		return 0
	fi

	# ── 1. the two resources ──
	local steps
	steps=$(head -1 "$level" | sed 's/.*load_steps=\([0-9]*\).*/\1/')
	if [ -n "$steps" ] && [ "$steps" != "$(head -1 "$level")" ]; then
		sed -i "1s/load_steps=$steps/load_steps=$((steps + 2))/" "$level"
	fi
	# After the LAST ext_resource line, so the block stays contiguous however
	# the builder orders its own resources.
	awk -v ops="$ops" '
		/^\[ext_resource/ { last = NR }
		{ lines[NR] = $0 }
		END {
			for (i = 1; i <= NR; i++) {
				print lines[i]
				if (i == last) {
					print "[ext_resource type=\"Script\" path=\"res://maps/trench_broom_level.gd\" id=\"90_level\"]"
					print "[ext_resource type=\"PackedScene\" path=\"" ops "\" id=\"91_ops\"]"
				}
			}
		}
	' "$level" > "$level.tmp" && mv "$level.tmp" "$level"

	# ── 2. the root's script and its exports ──
	# node_paths has to be declared on the node line or Godot reads the three
	# NodePath properties as plain strings and every export comes back null.
	awk -v root="$root" '
		$0 == "[node name=\"" root "\" type=\"Node3D\"]" {
			print "[node name=\"" root "\" type=\"Node3D\" node_paths=PackedStringArray(\"spawn_point\", \"nav_region\", \"level_exits\")]"
			print "script = ExtResource(\"90_level\")"
			print "spawn_point = NodePath(\"Ops/MissionStart\")"
			print "nav_region = NodePath(\"NavigationRegion3D\")"
			print "level_exits = [NodePath(\"Ops/LevelExit\")]"
			hit = 1
			next
		}
		{ print }
		END { if (!hit) exit 3 }
	' "$level" > "$level.tmp"
	if [ $? -ne 0 ]; then
		rm -f "$level.tmp"
		echo "FAIL: could not find the root node line for $root in $level."
		echo "      The builder may have renamed it; fix this script rather than the level."
		return 1
	fi
	mv "$level.tmp" "$level"

	# ── 3. the ops instance ──
	# Appended, and the [editable] directives are rewritten afterwards: they
	# close a .tscn and a node declared after them is not read back.
	local editables
	editables=$(grep '^\[editable path=' "$level" || true)
	sed -i '/^\[editable path=/d' "$level"
	printf '\n[node name="Ops" parent="." instance=ExtResource("91_ops")]\n' >> "$level"
	if [ -n "$editables" ]; then
		printf '\n%s\n' "$editables" >> "$level"
	fi

	echo "      $(basename "$level"): TrenchBroomLevel script, spawn at Ops/MissionStart, ops layer instanced"
}

# ── COVER ────────────────────────────────────
# COVER POINTS ARE A FUNCTION OF GEOMETRY, so unlike everything else in this
# script they belong in the LEVEL and not in the ops scene. Move a building and
# every baked point near it is a lie — points inside a wall that was not there
# before, and none at all where one was removed — so they SHOULD die with the
# rebuild and be re-baked from the new geometry.
#
# Without one of these a map has no cover points at all and the AI's whole
# cover system has nothing to use on it: every other played map in the project
# carries between a thousand and three and a half thousand. tools/audit_levels.gd
# prints "no cover" for a level that has none, which is how this was found.
#
# This only PLACES the spawner and one seed point. Baking is a separate run and
# cannot be headless, because the spawner raycasts against real collision:
#
#   LEVEL=res://maps/georgetown_level.tscn godot --audio-driver Dummy \
#       --path . --script res://tools/probe_cover_mutaha.gd
#
# The seed CoverPoint_0 is deliberate: that tool splices between the first and
# last existing CoverPoint_ node and bails with "found no CoverPoint_ nodes to
# replace" on a scene that has none. It is a bootstrap, and the first bake
# overwrites it.
add_cover_spawner() {
	local level="$1"
	if grep -q 'name="CoverPointSpawner"' "$level"; then
		return 0
	fi
	local steps
	steps=$(head -1 "$level" | sed 's/.*load_steps=\([0-9]*\).*/\1/')
	if [ -n "$steps" ] && [ "$steps" != "$(head -1 "$level")" ]; then
		sed -i "1s/load_steps=$steps/load_steps=$((steps + 2))/" "$level"
	fi
	awk '
		/^\[ext_resource/ { last = NR }
		{ lines[NR] = $0 }
		END {
			for (i = 1; i <= NR; i++) {
				print lines[i]
				if (i == last) {
					print "[ext_resource type=\"PackedScene\" uid=\"uid://cyslwv078g4sk\" path=\"res://Env/world_objects/cover_point_spawner.tscn\" id=\"92_coverspawn\"]"
					print "[ext_resource type=\"Script\" path=\"res://Env/world_objects/cover_point.gd\" id=\"93_coverpt\"]"
				}
			}
		}
	' "$level" > "$level.tmp" && mv "$level.tmp" "$level"
	local editables
	editables=$(grep '^\[editable path=' "$level" || true)
	sed -i '/^\[editable path=/d' "$level"
	# sample_radius 0 is the whole level: the default of 80 m covers a circle
	# you can walk across in fifteen seconds, and the smallest of these maps is
	# 554 m across. min_spacing 4 matches Qamareen.
	cat >> "$level" <<'COVER'

[node name="CoverPointSpawner" parent="." node_paths=PackedStringArray("navigation_region") instance=ExtResource("92_coverspawn")]
navigation_region = NodePath("../NavigationRegion3D")
min_spacing = 4.0
sample_radius = 0.0
debug_visualize = false

[node name="CoverPoint_0" type="Node3D" parent="CoverPointSpawner"]
script = ExtResource("93_coverpt")
cover_direction = Vector3(0, 0, 1)
metadata/cover_direction = Vector3(0, 0, 1)
COVER
	if [ -n "$editables" ]; then
		printf '\n%s\n' "$editables" >> "$level"
	fi
}

# The hand-built levels: everything on the root is already right, so only the
# ops instance goes in. Their spawn_point is left exactly where it is — on
# causeway that is PlayerSpawn out on the west bank, which is where the
# operation is meant to start.
patch_authored_level() {
	local level="$1" ops="$2" id="$3"
	local ops_file="${ops#res://}"
	[ -f "$level" ] || { echo "      no $level — skipped"; return 0; }
	[ -f "$ops_file" ] || { echo "      no $ops_file — skipped"; return 0; }
	if grep -q "$ops" "$level"; then
		echo "      $(basename "$level") already carries its ops layer — nothing to do"
		return 0
	fi
	local steps
	steps=$(head -1 "$level" | sed 's/.*load_steps=\([0-9]*\).*/\1/')
	if [ -n "$steps" ] && [ "$steps" != "$(head -1 "$level")" ]; then
		sed -i "1s/load_steps=$steps/load_steps=$((steps + 1))/" "$level"
	fi
	awk -v ops="$ops" -v id="$id" '
		/^\[ext_resource/ { last = NR }
		{ lines[NR] = $0 }
		END {
			for (i = 1; i <= NR; i++) {
				print lines[i]
				if (i == last)
					print "[ext_resource type=\"PackedScene\" path=\"" ops "\" id=\"" id "\"]"
			}
		}
	' "$level" > "$level.tmp" && mv "$level.tmp" "$level"
	local editables
	editables=$(grep '^\[editable path=' "$level" || true)
	sed -i '/^\[editable path=/d' "$level"
	printf '\n[node name="Ops" parent="." instance=ExtResource("%s")]\n' "$id" >> "$level"
	if [ -n "$editables" ]; then
		printf '\n%s\n' "$editables" >> "$level"
	fi
	echo "      $(basename "$level"): ops layer instanced"
}

rc=0
patch_generated_level maps/georgetown_level.tscn res://maps/gameplay/georgetown_ops.tscn GeorgetownLevel || rc=1
patch_generated_level maps/polaris_level.tscn res://maps/gameplay/polaris_ops.tscn PolarisLevel || rc=1
patch_authored_level maps/causeway_level.tscn res://maps/gameplay/causeway_ops.tscn 92_ops || rc=1

# SEPARATELY, and not inside the two functions above, because each of those
# returns early on a level that already carries its ops layer — and the cover
# spawner is a different question with a different answer. A level can have its
# gameplay and still have no cover, which is exactly the state all three were
# in when this was written.
# HILLFORT IS IN THIS LIST AND HAS NO OPS SCENE. It is the only other level a
# mission plays that had no cover points at all — tools/audit_levels.gd prints
# "no cover" for it — and the playtest note on that map was "overall except for
# the top of the hill there's nothing", which is the same complaint from the
# other end. It is regenerated like Georgetown and Polaris, so a hand-added
# spawner would not survive either, and this is the script that re-adds things
# after a rebuild. tools/hillfort_objectives.sh puts its relay back; this puts
# its cover back.
for lvl in maps/georgetown_level.tscn maps/polaris_level.tscn maps/causeway_level.tscn \
		maps/hillfort_level.tscn; do
	[ -f "$lvl" ] && add_cover_spawner "$lvl"
done
exit $rc
