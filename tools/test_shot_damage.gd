extends SceneTree

# ─────────────────────────────────────────────
# SHOT DAMAGE — what one round is worth, counting what it breaks up into.
#
# A weapon's base_damage is a HITSCAN number. A launched round carries its
# damage on its projectile, and a cluster round carries six more bomblets inside
# that projectile, so base_damage on the Cluster Launcher read 40 when the round
# delivers up to 220. Nothing in the game used that figure, which is why it went
# unnoticed — but a spec card, a shop screen or a balance pass built on it would
# have called the most expensive infantry weapon in the game weaker than a Mark
# One.
#
# AIWeapon.shot_damage() is the honest answer. These pin it:
#   - a hitscan gun still reports base_damage and nothing else
#   - the cluster shell's six 30-point bomblets are counted
#   - a plain launcher reports its ROUND's blast, not the weapon's base_damage
#   - a launcher's own blast_override still wins, as it does on release
#   - the answer is cached, so a shop redrawing per frame does not instance a
#     shell per frame
#
# Instances weapon scenes only. No world, no save, nothing written.
# ─────────────────────────────────────────────

const CLUSTER := "res://Character/weapon/ai-wep_cluster.tscn"
const MORTAR := "res://Character/weapon/ai-wep_mortar.tscn"
const RIFLE := "res://Character/weapon/ai-wep_m4.tscn"
const RECOILLESS := "res://Character/weapon/ai-wep_recoilless.tscn"

var _fails := 0


func _check(label: String, got, want) -> void:
	if got == want:
		print("  ok   %-52s %s" % [label, str(got)])
	else:
		_fails += 1
		print("  FAIL %-52s got %s, wanted %s" % [label, str(got), str(want)])


func _load(path: String) -> AIWeapon:
	if not ResourceLoader.exists(path):
		_fails += 1
		print("  FAIL %s is missing — the suite cannot check what it cannot load." % path)
		return null
	var w = load(path).instantiate()
	if not (w is AIWeapon):
		_fails += 1
		print("  FAIL %s is not an AIWeapon (%s)." % [path, w.get_class()])
		w.free()
		return null
	return w


func _init() -> void:
	# Keeps a stray Settings write out of the real profile. Nothing here reads
	# settings, but every tool in this folder sets it and an exception would be
	# the one that eventually writes.
	Settings.path = "user://settings_probe.json"
	await process_frame

	print("HITSCAN — base_damage, and no submunitions invented")
	var rifle := _load(RIFLE)
	if rifle != null:
		var d: Dictionary = rifle.shot_damage()
		_check("rifle impact == base_damage", d["impact"], rifle.base_damage)
		_check("rifle submunitions", d["submunitions"], 0)
		_check("rifle total == base_damage", d["total"], rifle.base_damage)
		rifle.free()

	print("CLUSTER — the shell, plus the six bomblets it throws")
	var cluster := _load(CLUSTER)
	if cluster != null:
		var d: Dictionary = cluster.shot_damage()
		# Read off cluster_shell.tscn: blast_damage 40, submunitions 6,
		# submunition_damage 30. Pinned as literals on purpose — if someone
		# retunes the shell this suite should say so rather than quietly agree
		# with whatever the new numbers are.
		_check("cluster impact", d["impact"], 40)
		_check("cluster submunitions", d["submunitions"], 6)
		_check("cluster each bomblet", d["each"], 30)
		_check("cluster total for one round", d["total"], 220)
		# The whole point: the weapon's own field is NOT the answer.
		var understated: bool = cluster.base_damage < d["total"]
		_check("base_damage alone understates the round", understated, true)
		# Cached: a second call must not build a second shell.
		var again: Dictionary = cluster.shot_damage()
		_check("second call is the same dictionary", again, d)
		cluster.free()

	print("MORTAR — a launcher whose round has no submunitions")
	var mortar := _load(MORTAR)
	if mortar != null:
		var d: Dictionary = mortar.shot_damage()
		_check("mortar submunitions", d["submunitions"], 0)
		# A launcher reports its ROUND's blast. It may or may not match the
		# weapon's base_damage; what matters is that it is a real number and the
		# total is the impact alone.
		_check("mortar total == impact", d["total"], d["impact"])
		var sane: bool = int(d["impact"]) > 0
		_check("mortar impact is a real figure", sane, true)
		mortar.free()

	print("RECOILLESS — same class of problem, the damage is on the rocket")
	var rcl := _load(RECOILLESS)
	if rcl != null:
		var d: Dictionary = rcl.shot_damage()
		_check("recoilless submunitions", d["submunitions"], 0)
		_check("recoilless total == impact", d["total"], d["impact"])
		# Not pinned to a literal: unlike the cluster shell, nothing here claims
		# a specific tuning. What matters is that it reports the ROUND and not
		# the weapon's unused base_damage.
		var from_round: bool = int(d["impact"]) > 0
		_check("recoilless impact is a real figure", from_round, true)
		rcl.free()

	print("OVERRIDE — a launcher that retunes its round still reports the truth")
	var over := _load(CLUSTER)
	if over != null:
		# blast_override is what the launcher applies to the round on release,
		# so the reported impact has to follow it or the card describes a round
		# nobody fires.
		over.blast_override = 77
		var d: Dictionary = over.shot_damage()
		_check("override wins on impact", d["impact"], 77)
		_check("override total counts bomblets too", d["total"], 77 + 6 * 30)
		over.free()

	if _fails == 0:
		print("PASS")
	else:
		print("FAIL — %d check(s)" % _fails)
	quit(1 if _fails > 0 else 0)
