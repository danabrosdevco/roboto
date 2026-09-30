#!/usr/bin/env bash
# ─────────────────────────────────────────────
# SPRINKLE HEAVY RIFLEMEN — swaps some Rifle Troopers in a mission for the
# plated ones, from the Coast Road on.
#
# ONE PER SQUAD AT MOST, and only every Nth squad that has a rifle in it: a
# heavy is meant to be the body you notice and concentrate on, which it stops
# being the moment a whole squad is made of them.
#
#   tools/sprinkle_heavies.sh <mission.tres> <every-Nth-squad>
#
# Idempotent-ish: run it twice and it converts the NEXT rifle in the same
# squads, so check the count it prints rather than re-running blind.
# ─────────────────────────────────────────────
set -euo pipefail
F="$1"
EVERY="${2:-3}"
ARMOURED_RES='res://Campaign/chassis/chassis_rifleman_armoured.tres'
NEWID="6h_rifleheavy"

[ -f "$F" ] || { echo "no such file: $F" >&2; exit 1; }

if grep -q "$NEWID" "$F"; then
	echo "$(basename "$F"): already carries the heavy ext_resource; not adding it twice"
else
	# The ext_resource block ends at the first blank line after it; the new
	# entry goes on the line before that, and load_steps counts it.
	STEPS=$(sed -n '1s/.*load_steps=\([0-9]*\).*/\1/p' "$F")
	LAST_EXT=$(grep -n '^\[ext_resource' "$F" | tail -1 | cut -d: -f1)
	sed -i "1s/load_steps=$STEPS/load_steps=$((STEPS + 1))/" "$F"
	sed -i "${LAST_EXT}a [ext_resource type=\"Resource\" uid=\"uid://cchassisrifle02\" path=\"$ARMOURED_RES\" id=\"$NEWID\"]" "$F"
fi

BEFORE=$(grep -oE 'ExtResource\("6_rifle"\)' "$F" | wc -l)
awk -v every="$EVERY" -v newid="$NEWID" '
	/^roster = / {
		if ($0 ~ /ExtResource\("6_rifle"\)/) {
			squad++
			if (squad % every == 0) {
				sub(/ExtResource\("6_rifle"\)/, "ExtResource(\"" newid "\")")
				swapped++
			}
		}
	}
	{ print }
	END { printf("  squads with rifles: %d, converted: %d\n", squad, swapped) > "/dev/stderr" }
' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
AFTER=$(grep -oE 'ExtResource\("6_rifle"\)' "$F" | wc -l)
HEAVY=$(grep -oE "ExtResource\(\"$NEWID\"\)" "$F" | wc -l)
echo "$(basename "$F"): rifles $BEFORE -> $AFTER, heavies now $HEAVY"
