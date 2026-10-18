extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# THE LEVER AND THE TABLE MUST NOT SHARE A VOLUME.
#
# The departure lever sits on the end of the operations table, and both are
# reached with F. The player's InteractRaycast is a RayCast3D, which returns the
# CLOSEST collider — so if the lever's interact volume touches the table's, F
# gets the table and the lever is decoration. It still LOOKS right. It still
# animates when you call its handler directly. The only symptom is that
# pressing F at it opens the campaign board instead.
#
# tools/probe_home_base.gd catches this on a real boot, which is the honest
# test, but it costs a full game boot and only runs when somebody runs it. The
# clearance is really just arithmetic between four constants in three files:
#
#   tools/fit_ops_table.gd          where both volumes are and how big
#   Env/world_objects/departure_lever.gd   how far the handle swings
#   tools/block_railhead.gd         the slab the table's volume is sized to
#
# and any of them can be edited innocently. Lengthening the handle to make it
# easier to see, or widening the slab by 0.4 m, breaks it silently. So the
# clearance is checked here as an invariant instead of living in a comment.
#
#   godot --headless --path . --script res://tools/test_departure_lever.gd
# ─────────────────────────────────────────────

const FIT := "res://tools/fit_ops_table.gd"
const LEVER := "res://Env/world_objects/departure_lever.gd"

## How much air the two volumes must keep between them. Not zero: touching
## boxes are a coin flip, and floating point makes the coin worse.
const MIN_CLEARANCE := 0.05

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	var fit: Dictionary = (load(FIT) as GDScript).get_script_constant_map()
	var lever = (load(LEVER) as GDScript).new()

	for k in ["SLAB_HX", "TABLE_TOP", "LEVER_OUT", "LEVER_PIVOT_Y", "LEVER_BOX", "LEVER_BOX_OFFSET"]:
		if not fit.has(k):
			_check("fit_ops_table.gd still declares %s" % k, false,
				"renamed or removed, so this test cannot check anything")
			print("")
			print("%d failure(s)" % _fails)
			quit(1)
			return

	# ── the two volumes ─────────────────────────
	# Along the car is GODOT Z: FuncGodot maps Quake (x, y, z) onto Godot
	# (y, z, x), so the slab's +/-SLAB_HX becomes a Z extent.
	var table_near: float = -float(fit["SLAB_HX"])
	var box: Vector3 = fit["LEVER_BOX"]
	var off: Vector3 = fit["LEVER_BOX_OFFSET"]
	var lever_centre_z: float = -float(fit["LEVER_OUT"]) + off.z
	var lever_far: float = lever_centre_z + box.z * 0.5     # the end nearest the table

	var gap: float = table_near - lever_far
	_check("the lever's interact volume clears the table's",
		gap >= MIN_CLEARANCE,
		"%.3f m of air (table ends %.2f, lever starts %.2f)" % [gap, table_near, lever_far])

	# ── the handle's arc ────────────────────────
	# The volume can be clear and the HANDLE still swing back over the slab,
	# which puts the thing you are looking at inside the table's volume even
	# though its trigger is not.
	var pivot_z: float = -float(fit["LEVER_OUT"])
	var pivot_y: float = float(fit["LEVER_PIVOT_Y"])
	var arm: float = float(lever.arm_length) + float(lever.knob_radius)
	var lever_near: float = lever_centre_z - box.z * 0.5
	var box_lo_y: float = pivot_y + off.y - box.y * 0.5
	var box_hi_y: float = pivot_y + off.y + box.y * 0.5

	for pose: Array in [["stowed", lever.stowed_degrees], ["thrown", lever.thrown_degrees]]:
		var a: float = deg_to_rad(float(pose[1]))
		# The handle swings about local X, so the knob is (0, L cos a, L sin a).
		var kz: float = pivot_z + arm * sin(a)
		var ky: float = pivot_y + arm * cos(a)
		_check("the %s handle stays clear of the table" % pose[0],
			kz <= table_near - MIN_CLEARANCE,
			"knob at z %.3f, table ends %.3f" % [kz, table_near])
		_check("...and inside its own interact volume",
			kz >= lever_near and kz <= lever_far and ky >= box_lo_y and ky <= box_hi_y,
			"knob (%.3f, %.3f) in z [%.2f, %.2f] y [%.2f, %.2f]" % [
				kz, ky, lever_near, lever_far, box_lo_y, box_hi_y])

	# ── and it is below the slab, not on it ─────
	# Nothing stands on the table's top surface. The runtime projection's lit
	# plate is 6.6 x 2.7 m on a 7.0 x 3.0 slab, which leaves 0.16 m of bare
	# surface at the ends, and the projection draws additively with no depth
	# test — so anything over it does not occlude it, it just reads as broken.
	_check("the pivot is below the working surface",
		pivot_y < float(fit["TABLE_TOP"]),
		"pivot %.2f, surface %.2f" % [pivot_y, float(fit["TABLE_TOP"])])

	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
