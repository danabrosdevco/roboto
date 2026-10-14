extends SceneTree

# ─────────────────────────────────────────────
# DRESSING THE COMPUTE CORE — Paint, Lit, and the pulse.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/core_skeleton_dress.gd [-- <scene> ...]
#
# Runs over maps/blocks/compute/compute_core{_small,,_large}.tscn, which
# tools/block_prefabs.gd builds from the .map files tools/build_core_skeleton.gd
# writes. With no arguments it does all three.
#
# ─────────────────────────────────────────────
# WHY THIS EXISTS AT ALL, AND WHY IT IS NOT A BUILD STEP
#
# FuncGodot assigns materials BY TEXTURE NAME. A freshly built core prefab is
# therefore navy metal all over with four grey screens on it: no faction
# colour, no emission, no pulse, and — the part that matters — no way for
# anything to recolour one band without recolouring every surface that shares
# its texture.
#
# THE SHIPPED CORE WAS ONE MERGED WORLDSPAWN MESH, so nothing on it could be
# recoloured at all, which is why Env/world_objects/core_signal.gd fakes owner
# colour to this day with a procedural collar and band and why its own header
# asks for art that replaces it. build_core_skeleton.gd fixes the geometry half
# of that — every painted band and every lit slot is its own
# func_detail_illusionary entity, so FuncGodot gives each one its own
# MeshInstance3D — and this fixes the material half.
#
# IT IS RE-APPLIABLE, ON PURPOSE. A block_prefabs rebuild throws the dressing
# away, exactly as a map regeneration throws hand-added objectives away, and
# the answer in this project is the same: a patch script that can be run again
# rather than editor work that cannot. So this pass is idempotent — it deletes
# the Signal node it made last time before making a new one, and it reads the
# .map rather than the scene to decide what anything is.
#
# ─────────────────────────────────────────────
# WHAT IT BUILDS
#
#   <root: FuncGodotMap>
#     entity_0_worldspawn            the solids and all the collision
#     entity_1_func_detail_illusionary   the trim — mesh only, left alone
#     Signal                         Node3D, script = core_pulse.gd
#       Paint                        one MeshInstance3D per painted band
#       Lit                          one MeshInstance3D per lit slot
#
# THE SIGNAL NODE IS A DEVIATION FROM THE STUDY AND IT IS FORCED. The study's
# cores were plain Node3D roots and carried core_pulse.gd on the root itself. A
# FuncGodot prefab's root carries func_godot_map.gd, which is what lets a human
# select it and press Build, and a node holds one script. So the pulse goes on
# a child, and Paint and Lit go under that child because core_pulse.gd resolves
# ^"Lit" relative to itself. Nothing else consumes Paint or Lit yet —
# core_signal.gd does not mention them — so an owner-colour pass written later
# should find them with find_child() rather than a fixed path.
#
# THE EMPTY ENTITY WRAPPERS ARE FREED. FuncGodot gives each illusionary entity
# a Node3D holding one MeshInstance3D; the mesh is moved out and the wrapper
# would then be an empty node with a transform on it, which is a trap for the
# next person reading the scene.
#
# ─────────────────────────────────────────────
# THE FOUR MATERIAL RULES, all of which are scar tissue. See section 7 of
# docs/briefs/COMPUTE_CORE_ART.md for the full account.
#
#   1. BOTH LISTS SET emission AS WELL AS albedo_color. Anything that sets
#      albedo alone repaints the surface and leaves it glowing in the previous
#      owner's colour.
#   2. EVERY MATERIAL IS resource_local_to_scene. A sub-resource in a .tscn is
#      ONE object shared by every instantiation of that scene, so two cores in
#      a level would share materials and the second capture would repaint the
#      first. The brief calls this latent "because no level holds two" —
#      MEASURED, TEN OF THE TEN LEVELS THAT HOLD A CORE HOLD AT LEAST THREE,
#      and causeway_ops holds eight. It is not latent; it would have fired on
#      the first capture.
#   3. THE SCREEN TEXTURE GOES ON emission AS WELL AS albedo, WITH
#      EMISSION_OP_ADD, so the faction colour is a floor the data grain sits on
#      — hue owned by the faction, grain by the texture. MULTIPLY recolours the
#      glow and an Argus core comes out unreadable.
#   4. EMISSION ENERGY MULTIPLIES INTO CLIPPING, NOT BRIGHTNESS. FAC_ADVERSARY
#      is Color(0.91, 0.63, 0.23) and red is already at 0.91, so 1.3
#      photographed pale with the amber going toward white. 0.45 on the paint,
#      and the lit slots carry the glow.
#
# AND NOTHING WRITES emission_energy_multiplier ON A Lit MATERIAL except this
# pass, once: core_pulse.gd animates exactly that float and reads the value
# baked here as the rest level.
# ─────────────────────────────────────────────

const DIR := "res://maps/blocks/compute"
const SCENES := ["compute_core_small", "compute_core", "compute_core_large"]

const _Palette := preload("res://Character/hud/hud_palette.gd")
const PULSE_SCRIPT := "res://maps/blocks/compute/core_pulse.gd"

const MAST_TEX := "res://textures/PSX_Textures/metal_wall_3.png"
## THE LIT TEXTURE, AND IT IS AN OVERRIDE OF SECTION 5 OF GAMEPLAY'S BRIEF.
##
## Their brief says glitch_tx_1. Measured, glitch_tx_1 is SATURATION 0.771 — a
## strongly hued texture — and the core has to carry FOUR faction colours:
## amber FAC_ADVERSARY for the Swarm, blue SIGNAL for the player, green
## FAC_HOME for Home Command, tyrian FAC_ARGUS for Argus. A 0.77-saturation
## grain cannot carry purple and amber both: adding a heavily hued grain onto a
## faction colour muddies it even under EMISSION_OP_ADD, which is the same
## failure rule 3 above warns about for MULTIPLY, arriving by a different route.
##
## glitch_tx_neutral is the same image with the hue stripped and the exposure
## kept: saturation 0.771 -> 0.109, mean 0.183 -> 0.176, peak 0.561 unchanged.
## Value-only grain, so the faction colour genuinely owns the HUE and the
## texture owns the SPARKLE — which is what rule 3 asks for in words. Because
## the mean is within half a percent of glitch_tx_1's, the study's measured
## energies below carry over unchanged. Everything else in sections 5 and 7
## stands.
const SCREEN_TEX := "res://textures/PSX_Textures/glitch_tx_neutral.png"

## PAINT IS PAINTED METAL; LIT IS THE GLOW. The second build ran the paint at
## 0.95 and the bands photographed as flat plastic tape — emission at that
## energy with no emission texture is a constant amber across the face, so
## metal_wall_3's ribs, the whole reason this look is on a ribbed sheet, were
## swamped and the bands stopped looking like metal. 0.45 is where the ribs
## survive and the band is still unmistakably lit against the navy. It is a
## split of two earlier notes rather than a reversal of either: "glowing, not
## flat" is carried by the Lit slots, which have a texture in their emission
## and stay interesting at any energy, and "it should look metal" by the paint.
const PAINT_GLOW := 0.45
## REST level for the slots. core_pulse.gd multiplies it by PEAK_GAIN (2.4) at
## the crest, and 0.40 x 2.4 = 0.96 puts FAC_ADVERSARY's red just at the
## ceiling — which is the arithmetic that matters, because emission here is
## ADDED to the texture.
const LIT_GLOW := 0.40
## The console plate alone sits brighter: it is the one lit face big enough to
## be read texel by texel, and at the rest level the texture's own value beat
## the faction colour under it.
const CONSOLE_GLOW := 0.85

var _mast_tex: Texture2D
var _screen_tex: Texture2D
var _pulse: Script


func _initialize() -> void:
	_mast_tex = load(MAST_TEX) as Texture2D
	_screen_tex = load(SCREEN_TEX) as Texture2D
	_pulse = load(PULSE_SCRIPT) as Script
	if _mast_tex == null or _screen_tex == null or _pulse == null:
		printerr("core_skeleton_dress: a texture or core_pulse.gd failed to load, so every band would ship bare")
		quit(1)
		return
	var wanted: Array = []
	for a in OS.get_cmdline_user_args():
		wanted.append(a.get_file().get_basename())
	if wanted.is_empty():
		wanted = SCENES
	var done := 0
	for nm: String in wanted:
		if not _dress(nm):
			quit(1)
			return
		done += 1
	print("CORE DRESS DONE: %d scene(s)" % done)
	quit()


func _dress(nm: String) -> bool:
	var scene_path: String = "%s/%s.tscn" % [DIR, nm]
	var map_path: String = "%s/%s.map" % [DIR, nm]
	var packed := load(scene_path) as PackedScene
	if packed == null:
		printerr("core_skeleton_dress: no scene at %s — run block_prefabs.gd first" % scene_path)
		return false
	var tags := _read_tags(map_path)
	if tags.is_empty():
		printerr("core_skeleton_dress: %s carries no core: tags — was it written by build_core_skeleton.gd?" % map_path)
		return false
	var root := packed.instantiate()

	# Idempotent: last run's Signal goes before this run's is built. queue_free
	# is deferred and this tool never runs a frame, so it has to be
	# remove_child then free — the rule CLAUDE.md states for rebuilding UI, and
	# it is the same rule here.
	var old := root.get_node_or_null(^"Signal")
	if old != null:
		root.remove_child(old)
		old.free()

	var signal_node := Node3D.new()
	signal_node.name = "Signal"
	signal_node.set_script(_pulse)
	root.add_child(signal_node)
	var paint_node := _group(signal_node, "Paint", root)
	var lit_node := _group(signal_node, "Lit", root)
	signal_node.owner = root

	var painted := 0
	var lit := 0
	var missing: Array = []
	for idx: int in tags:
		var tag: String = tags[idx]
		var holder := root.get_node_or_null(NodePath("entity_%d_func_detail_illusionary" % idx))
		if holder == null:
			# Every early return warns. A tag with no entity means the .map and
			# the .tscn have drifted apart, which is silent and fatal: the band
			# would simply never be coloured and nobody would know which one.
			missing.append(idx)
			continue
		var mi: MeshInstance3D = null
		for c in holder.get_children():
			if c is MeshInstance3D:
				mi = c
				break
		if mi == null:
			missing.append(idx)
			continue
		# The entity node carries the brush group's origin offset and the mesh
		# sits at identity under it, so the offset has to come across or every
		# band lands at the core's foot.
		var xform: Transform3D = (holder as Node3D).transform * mi.transform
		# OWNER CLEARED BEFORE THE REPARENT, not after. Godot warns that adding
		# a node that still carries an owner "will make owner inconsistent",
		# and it is not only a warning: the first run of this pass left the
		# owners set and the packed scene came back with an eleventh lit mesh
		# in a Lit node that had been handed ten.
		mi.owner = null
		holder.remove_child(mi)
		if tag.begins_with("core:paint"):
			painted += 1
			mi.name = "Band%d" % painted
			mi.material_override = _paint_material()
			paint_node.add_child(mi)
		elif tag.begins_with("core:lit"):
			lit += 1
			var y := _tag_height(tag)
			# Parenthesised, because `"Slot%d" % lit if cond else "x"` binds the
			# ternary INSIDE the format and the console plate came out named
			# @MeshInstance3D@4.
			mi.name = ("Slot%d" % lit) if not is_nan(y) else "ConsolePlate"
			mi.material_override = _lit_material(is_nan(y))
			lit_node.add_child(mi)
			if not is_nan(y):
				# core_pulse.gd buckets by this and nothing else. A lit piece
				# WITHOUT it is deliberately constant, which is the console
				# plate: an interface that goes dark for part of every cycle is
				# a worse interface however good it looks.
				mi.set_meta(&"pulse_y", y)
		mi.transform = xform
		mi.owner = root
		# The wrapper is now an empty Node3D with a transform on it, which is a
		# trap for whoever reads this scene next.
		root.remove_child(holder)
		holder.free()

	if not missing.is_empty():
		printerr("core_skeleton_dress: %s — %d tagged entity(s) had no mesh in the scene (%s). The .map and the .tscn have drifted; rebuild with block_prefabs.gd."
				% [nm, missing.size(), str(missing)])
		root.free()
		return false
	if painted == 0 or lit == 0:
		printerr("core_skeleton_dress: %s dressed %d painted and %d lit piece(s) — one of them is zero, so the core has no faction colour or no pulse" % [nm, painted, lit])
		root.free()
		return false

	var out := PackedScene.new()
	var err := out.pack(root)
	if err == OK:
		err = ResourceSaver.save(out, scene_path)
	root.free()
	if err != OK:
		printerr("core_skeleton_dress: could not save %s (%s)" % [scene_path, error_string(err)])
		return false
	print("      %-20s Paint %d · Lit %d (%d pulsing, %d constant)"
			% [nm, painted, lit, lit - _constant(tags), _constant(tags)])
	return true


func _constant(tags: Dictionary) -> int:
	var n := 0
	for idx: int in tags:
		var t: String = tags[idx]
		if t.begins_with("core:lit") and is_nan(_tag_height(t)):
			n += 1
	return n


func _group(parent: Node, nm: String, owner_of: Node) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	parent.add_child(n)
	n.owner = owner_of
	return n


## entity index -> tag, read out of the `// entity N  core:...` comments
## build_core_skeleton.gd writes. The .map is the source of truth about what
## each entity IS; the scene only knows it is a mesh.
func _read_tags(map_path: String) -> Dictionary:
	var out := {}
	var text := FileAccess.get_file_as_string(map_path)
	if text.is_empty():
		printerr("core_skeleton_dress: could not read %s" % map_path)
		return out
	for line: String in text.split("\n"):
		if not line.begins_with("// entity "):
			continue
		var rest := line.substr(10).strip_edges()
		var sp := rest.find(" ")
		if sp < 0:
			continue
		var idx := rest.substr(0, sp)
		var tag := rest.substr(sp).strip_edges()
		# PAINT AND LIT ONLY. `core:trim` is tagged too — so the .map says what
		# it is rather than leaving it as the one untagged entity — and an
		# earlier version of this filter took everything beginning "core:" and
		# then branched on "is it paint?", which quietly moved the whole trim
		# mesh into Lit and lit it. Match both names explicitly.
		if not idx.is_valid_int():
			continue
		if not (tag.begins_with("core:paint") or tag.begins_with("core:lit")):
			continue
		out[idx.to_int()] = tag
	return out


## `core:lit y=3.1563` -> 3.1563. No y= means "never pulses" and comes back NAN.
func _tag_height(tag: String) -> float:
	var at := tag.find("y=")
	if at < 0:
		return NAN
	var v := tag.substr(at + 2).strip_edges()
	return v.to_float() if v.is_valid_float() else NAN


## FRESH PER BAND, not shared. Resources are shared in this engine: one
## material handed to eight bands is one object, and an owner-colour pass would
## then be unable to light them one at a time.
func _paint_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _mast_tex
	m.albedo_color = _Palette.FAC_ADVERSARY
	# Rule 1: emission as well as albedo. core_signal.gd's own _emissive() is
	# the project's pattern, minus its SHADING_MODE_UNSHADED — that file applies
	# unshaded to thin open tubes which are pure signal, and unshaded flattens a
	# band into a sticker.
	m.emission_enabled = true
	m.emission = _Palette.FAC_ADVERSARY
	m.emission_energy_multiplier = PAINT_GLOW
	m.metallic_specular = 0.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	# NO TRIPLANAR, and that is a difference from the study rather than an
	# oversight. The study's pieces were BoxMeshes, which map 0..1 across every
	# face whatever its size, so a 256 px sheet came out stretched over a 2.6 m
	# cap and tiled into a 0.2 m band — several materials at several scales on
	# one model, and the fault that cost it a render. Brush faces carry real
	# Valve-220 texture axes with a units-per-texel scale on them, so the
	# density is already constant in metres and triplanar would throw that
	# away.
	m.resource_local_to_scene = true
	return m


## Faction-coloured screen. The grain goes on BOTH albedo and emission and the
## operator is ADD, so the faction colour is a floor the noise sits on rather
## than a tint the noise recolours.
func _lit_material(constant: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _screen_tex
	m.albedo_color = _Palette.FAC_ADVERSARY
	m.emission_enabled = true
	m.emission = _Palette.FAC_ADVERSARY
	m.emission_texture = _screen_tex
	m.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
	m.emission_energy_multiplier = CONSOLE_GLOW if constant else LIT_GLOW
	m.metallic_specular = 0.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	# Doubly required here: core_pulse.gd writes this material's energy, so two
	# cores sharing one would stutter against each other.
	m.resource_local_to_scene = true
	return m
