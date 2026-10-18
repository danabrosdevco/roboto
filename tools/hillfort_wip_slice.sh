#!/usr/bin/env bash
# Puts the site slice back into maps/hillfort_wip_level.tscn.
#
# WHY THIS IS A SCRIPT AND NOT AN EDIT. hillfort_wip is regenerated from a
# terrain recipe, and the regenerator does not preserve nodes it did not place.
# This map has been rebuilt twice since the slice was first added (2026-10-17
# 07:38 and 09:09) and lost it both times. The 09:09 rebuild DID keep the six
# cores, the two Patrols and the LevelExit, so the only thing that still goes
# missing is this one node.
#
# WHAT IT COSTS WHEN IT IS GONE. The slice is the whole gameplay layer:
#
#   - no bunker. SiteSlice raises the entrance kit on HFW_Bunker at runtime;
#     with no slice, the marker sits in the rampart with nothing on it.
#   - no operation, so the six HoldableCores are never seated and none of the
#     cores can be captured at all.
#   - the mission becomes unfinishable. test_mission_objectives'
#     _wins_at_bunker() decides whether a mission is allowed to name captures
#     and no extraction by asking the LEVEL whether it carries a slice. Without
#     one, hfw_1_fort names six cores, no way off the map, and the player takes
#     the fort and then stands in it.
#
# IDEMPOTENT. Re-run after any hillfort_wip rebuild; it does nothing if the
# node is already there. Verify with:
#
#   bash tools/bucket.sh terrain
#   godot --headless --audio-driver Dummy --path . \
#         --script res://tools/test_hillfort_live.gd
#
# THE REAL FIX is for the regenerator to leave non-generated nodes alone. Until
# it does, this is the repair.
set -uo pipefail
cd "$(dirname "$0")/.."

LEVEL="maps/hillfort_wip_level.tscn"
SLICE="Env/world_objects/hillfort_wip_slice.gd"
[ -f "$LEVEL" ] || { echo "no $LEVEL"; exit 2; }
[ -f "$SLICE" ] || { echo "no $SLICE — the slice script itself is gone"; exit 2; }

# THE NAME IS LOAD-BEARING. site_slice._find() and test_hillfort_live both look
# for the literal string "HillfortWipSlice"; a node of the right type under any
# other name resolves to nothing and fails silently.
if grep -q 'name="HillfortWipSlice"' "$LEVEL"; then
	echo "      hillfort_wip already carries its slice — nothing to do"
	exit 0
fi

# The marker the slice hangs the bunker on. Checked rather than assumed,
# because bunker_fallback would otherwise put a tunnel mouth at a hardcoded
# (6, 34, -99) in whatever the rebuild left there.
if ! grep -q 'name="HFW_Bunker"' "$LEVEL"; then
	echo "FAIL: no HFW_Bunker marker — the slice would fall back to a guessed"
	echo "      position. Ask TERRAIN to put the marker back first."
	exit 1
fi

STEPS=$(head -1 "$LEVEL" | sed 's/.*load_steps=\([0-9]*\).*/\1/')
case "$STEPS" in
	''|*[!0-9]*) echo "FAIL: could not read load_steps from line 1"; exit 1 ;;
esac
sed -i "1s/load_steps=$STEPS/load_steps=$((STEPS + 1))/" "$LEVEL"

# Appended after the ext_resource block. id 900_slice is deliberately far from
# the generated numbering so a rebuild that renumbers its own resources cannot
# collide with it.
sed -i 's#^\[ext_resource type="Script" path="res://Managers/AI/patrol_path.gd" id="11_patrol"\]#&\
[ext_resource type="Script" path="res://Env/world_objects/hillfort_wip_slice.gd" id="900_slice"]#' "$LEVEL"
grep -q 'id="900_slice"' "$LEVEL" || {
	echo "FAIL: could not anchor the ext_resource — the patrol_path line moved."
	exit 1
}

# APPENDED, AND THE [editable] DIRECTIVES GO LAST. They close a .tscn and a
# node declared after them is not read back — that cost a silent no-op on the
# shipped hillfort before hillfort_objectives.sh was written this way.
EDITABLE=$(grep '^\[editable path=' "$LEVEL")
sed -i '/^\[editable path=/d' "$LEVEL"
cat >> "$LEVEL" <<EOF

[node name="HillfortWipSlice" type="Node3D" parent="."]
script = ExtResource("900_slice")

$EDITABLE
EOF

echo "      hillfort_wip: HillfortWipSlice added, load_steps $STEPS -> $((STEPS + 1))"
echo "      six cores seatable, bunker on HFW_Bunker, operation won at the bunker"
