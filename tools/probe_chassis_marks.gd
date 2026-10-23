extends SceneTree

# ─────────────────────────────────────────────
# WHAT EACH PRODUCTION LINE BUILDS, AT EVERY MARK.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/probe_chassis_marks.gd
#
# The gate on step 1 of docs/briefs/MARK_SYSTEM_SPEC.md. Prints all three
# specs for every purchasable line and fails on anything that would be silent
# in play.
#
# IT CHECKS MK 0 HARDEST, because Mk 0 is the one nobody authored. It is
# synthesised by ChassisDefinition.mark_spec(0) from starting_weapon_id and
# coax_weapon_id — the whole point being that a line's base loadout has one
# source of truth rather than two. If that synthesis is wrong, every line
# starts life holding the wrong gun and the Marks above it all look fine.
#
# WHAT WOULD OTHERWISE BE SILENT:
#   - a weapon or equipment id with no catalogue entry resolves to null at
#     apply time and the robot is built carrying nothing
#   - a Mark with more weapons than the frame has mounts drops the extra
#   - a tuning key nothing reads is simply never applied
#   - a line whose Mk 1 and Mk 2 are identical is a tier the player pays for
#     and cannot tell they bought
# ─────────────────────────────────────────────

const CAT := "res://Campaign/items & catalogue/test_item_catalogue.tres"

var _fails := 0


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var cat = load(CAT)
	if cat == null:
		print("FAIL  no catalogue at %s" % CAT)
		quit(1)
		return

	var lines: Array = []
	for frame in cat.chassis:
		if frame != null and frame.purchasable:
			lines.append(frame)
	lines.sort_custom(func(a, b): return String(a.id) < String(b.id))

	print("")
	print("%d purchasable line(s)" % lines.size())
	print("")

	for frame in lines:
		print("%s  —  %d seat(s), %d mount(s), %d equipment slot(s)%s"
			% [String(frame.id).to_upper(), frame.supply, frame.weapon_slots,
			   frame.equipment_slots, "  [drives]" if frame.drives else ""])
		var seen: Array[String] = []
		for n in range(0, frame.top_mark() + 1):
			var spec = frame.mark_spec(n)
			if spec == null:
				print("    Mk %d  FAIL — no spec" % n)
				_fails += 1
				continue
			print("    Mk %d  %s" % [n, spec.summary()])
			seen.append(spec.summary())

			# Mk 0 is synthesised; the rest are authored and verifiable.
			if n > 0:
				for problem in spec.verify(frame):
					print("          FAIL  %s" % problem)
					_fails += 1
			for id in spec.weapon_ids + spec.equipment_ids:
				if cat.item(id) == null:
					print("          FAIL  no catalogue item '%s'" % String(id))
					_fails += 1

		# MK 0 HAS TO MATCH THE FRAME. Checked against the fields directly
		# rather than against mark_spec, or this only proves the synthesis
		# agrees with itself.
		# THE MAIN GUN, AND DELIBERATELY NOT THE COAX. recruit() ships a second
		# mount empty on purpose; Mk 0 has to match what the campaign actually
		# hands you, or every two-mount frame starts with a gun it was never
		# given. The coax arrives at Mk 1 instead.
		var zero = frame.mark_spec(0)
		var want: Array[StringName] = []
		if frame.starting_weapon_id != &"":
			want.append(frame.starting_weapon_id)
		if Array(zero.weapon_ids) != Array(want):
			print("          FAIL  Mk 0 is %s, the frame says %s"
				% [str(zero.weapon_ids), str(want)])
			_fails += 1

		# A GUN THAT COSTS THE FRAME ITS BUILT-IN. `weapon_replaces_built_in`
		# means a fitted weapon takes the place of what the frame came with —
		# the Drayman's BOOM, the Reclaimer's WELDER. A Mark that arms such a
		# frame is therefore trading away the thing the frame is FOR, and
		# nothing about slots or ids would show it: the Mark verifies, every
		# id resolves, and the logistics truck quietly stops being able to
		# plant and lift.
		if frame.weapon_replaces_built_in and frame.built_in != "":
			for n in range(1, frame.top_mark() + 1):
				var s = frame.mark_spec(n)
				if s != null and not s.weapon_ids.is_empty() \
						and frame.starting_weapon_id == &"":
					print("          FAIL  Mk %d arms this frame, which costs it its %s"
						% [n, frame.built_in])
					_fails += 1

		# A TIER YOU CANNOT TELL YOU BOUGHT. Two identical specs means the
		# player pays and nothing changes, which reads as the upgrade being
		# broken rather than as an authoring slip.
		for i in seen.size():
			for j in range(i + 1, seen.size()):
				if seen[i] == seen[j]:
					print("          FAIL  Mk %d and Mk %d are identical" % [i, j])
					_fails += 1
		print("")

	print("%d problem(s)" % _fails)
	quit(1 if _fails > 0 else 0)
