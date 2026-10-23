extends SceneTree

# ─────────────────────────────────────────────
# THE COMPANY CARD, CAUGHT AT FULL.
#
#   godot --audio-driver Dummy --path . \
#       --script res://tools/shot_splash_company.gd -- <out dir>
#
# Master's boot sequence is engine card -> company card -> title card, and the
# company card types itself in over a couple of seconds before "presents" fades
# up under it. A shot taken on a timer catches it half typed, so this watches
# for the state instead: the headline Label's visible_ratio reaching 1 and the
# suffix Label's alpha coming up with it.
#
# NOT HEADLESS, and not optional. The splash runs the CRT/signal filter, which
# READS THE SCREEN — under the dummy renderer there is nothing to read, so a
# headless grab comes back flat and looks like a clean capture of the wrong
# thing. Windowed at the 1152x648 the game actually uses.
#
# IT WRITES NO SAVE. autosave off and Settings on a probe file, the same rule
# every other tool in here follows.
# ─────────────────────────────────────────────

## Frames to wait after the card reads "done", so the suffix has settled and
## the filter has a full frame to work from.
const SETTLE := 8
## Give up rather than hang if the sequence never gets there.
const PATIENCE := 1800


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	var args := OS.get_cmdline_user_args()
	var out: String = String(args[0]) if args.size() > 0 else "res://docs/marketing/wip"
	DirAccess.make_dir_recursive_absolute(out)

	await process_frame
	var win := root.get_window()
	win.size = Vector2i(1152, 648)
	win.title = "splash grab"

	var master: Master = load("res://Managers/master.tscn").instantiate()
	master.skip_splash = false
	# Stop at the menu rather than running on into a mission.
	master.show_main_menu = true
	var cm = master.find_child("CampaignManager", true, false)
	if cm != null:
		cm.autosave = false
	root.add_child(master)

	var head: Label = null
	var waited := 0
	while waited < PATIENCE:
		await process_frame
		waited += 1
		head = _company_label(root)
		if head != null and head.visible_ratio >= 0.999:
			break
	if head == null:
		print("FAIL  never found the company card — has company_text changed?")
		quit(1)
		return

	for _i in SETTLE:
		await process_frame

	var img := win.get_texture().get_image()
	var path: String = out.path_join("splash_company_card.png")
	var err := img.save_png(path)
	if err != OK:
		print("FAIL  could not write %s (%d)" % [path, err])
		quit(1)
		return
	print("OK    %s  (%dx%d, caught after %d frames)"
		% [path, img.get_width(), img.get_height(), waited])
	quit(0)


## The headline Label of the company card, by its TEXT rather than its name —
## _play_card builds anonymous labels, so the words are the only handle.
func _company_label(n: Node) -> Label:
	if n is Label and String((n as Label).text).begins_with("DANA"):
		return n as Label
	for c in n.get_children():
		var f := _company_label(c)
		if f != null:
			return f
	return null
