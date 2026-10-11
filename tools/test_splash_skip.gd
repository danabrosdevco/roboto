extends SceneTree

# ─────────────────────────────────────────────
# SKIPPING A SPLASH CARD MUST NOT LEAVE THE SCREEN FADED
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_splash_skip.gd -- --no-save
#
# THE BUG THIS EXISTS FOR. Master fades each splash card out with a tween on
# _content.modulate:a, then sets that alpha back to 1.0. _wait() returns the
# instant the player skips, so a skip landing DURING the fade left the tween
# alive: the restore to 1.0 ran, the tween carried on driving the same property
# down, finished at 0.0, and stopped there with nothing left to undo it.
#
# _build_menu clears _content and adds the main menu straight back into that
# same container, so the whole menu arrived with an alpha of zero. Reported as
# "hit W on the splash and all the buttons fade away" — and it was never about
# which key: a click runs the identical branch in _input and is merely harder
# to land inside a 0.45 s window.
#
# DRIVEN END TO END rather than by calling _fade_out_content() directly,
# because the thing that broke was the INTERACTION between the skip flag, the
# wait and the tween. A unit test of the helper would have passed on the
# broken code if it awaited the helper properly, which is exactly what the real
# sequence did not do.
#
# `-- --no-save` because this boots the real game: see tools/smoke.sh.
# ─────────────────────────────────────────────

const MASTER := "res://Managers/master.tscn"

## Give up rather than hang if the sequence never reaches a fade.
const PATIENCE_SECONDS := 25.0

var _fails: int = 0


func _init() -> void:
	await _test_skip_during_a_fade_leaves_the_screen_visible()

	print("")
	if _fails == 0:
		print("ALL SPLASH SKIP CHECKS PASS")
	else:
		print("SPLASH SKIP FAILURES: %d" % _fails)
	quit(0)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("PASS  %s" % label)
	else:
		_fails += 1
		print("FAIL  %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _test_skip_during_a_fade_leaves_the_screen_visible() -> void:
	var master: Node = load(MASTER).instantiate()
	root.add_child(master)
	await process_frame

	var content = master.get("_content")
	if content == null:
		_ok("the splash overlay has a content container", false,
				"_content is null — did the overlay change shape?")
		return

	# WAIT FOR A REAL FADE-OUT.
	#
	# Three conditions, and the first two were learned the hard way. The engine
	# card SETS alpha to 0 on its first frame and then fades up, so both "alpha
	# is low" and "alpha just dropped" are true before any fade-out tween
	# exists. An earlier version of this fired on frame zero, skipped the whole
	# splash before a single tween had been created, and passed against the
	# broken code — proving nothing at all.
	#
	# So: wait until the card has actually come UP, and only then look for it
	# going back down.
	var risen: bool = false
	var prev: float = -1.0
	var waited: float = 0.0
	var caught: bool = false
	while waited < PATIENCE_SECONDS:
		if not is_instance_valid(content):
			break
		var a: float = content.modulate.a
		if a > 0.99:
			risen = true
		elif risen and prev >= 0.0 and a < prev - 0.002 and a < 0.95:
			caught = true
			break
		prev = a
		await process_frame
		waited += 1.0 / 60.0

	_ok("a card does fade out, so there is a window to skip into", caught,
			"never saw alpha fall in %.0fs" % PATIENCE_SECONDS)
	if not caught:
		return

	# The skip, landing mid-fade. Set directly rather than synthesised as an
	# InputEvent: _input's job is to decide WHAT counts as a skip and it is not
	# what broke — the flag is the contract between input and the sequence.
	master.set("_skip_requested", true)

	# Past the fade, and past the rest of the sequence, so the assertion is
	# about the settled state rather than a moment inside it.
	var fade_seconds: float = float(master.get("fade_seconds"))
	var settle: float = maxf(fade_seconds, 0.45) + 1.5
	var t: float = 0.0
	while t < settle:
		await process_frame
		t += 1.0 / 60.0

	if not is_instance_valid(content):
		# A torn-down overlay is a legitimate end state: nothing is left to be
		# invisible. Only say so, rather than passing silently.
		_ok("the overlay was torn down, so nothing can be left faded", true)
		return

	var alpha: float = content.modulate.a
	_ok("the screen is not left faded out after a mid-fade skip",
			alpha > 0.99, "modulate.a settled at %.3f" % alpha)

	# ...and the thing the player actually lost: the menu inside that container.
	var visible_text: int = _count_labels(content)
	_ok("...and whatever is in the container can be seen",
			alpha > 0.99 and visible_text > 0,
			"%d label(s) at alpha %.3f" % [visible_text, alpha])

	master.queue_free()
	await process_frame


func _count_labels(n: Node) -> int:
	var total: int = 0
	for c in n.get_children():
		if c is Label or c is Button:
			total += 1
		total += _count_labels(c)
	return total
