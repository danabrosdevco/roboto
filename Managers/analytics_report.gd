extends RefCounted

# ─────────────────────────────────────────────
# ANALYTICS REPORT — turns an events.jsonl into answers.
#
# A pure function of the events: build(events, title) -> Markdown. The game
# runs it after every mission for the session's own report.md, and
# tools/analytics.sh runs it over every session in a folder at once. Events
# from the tool carry "s" (their session), so attempts from different sessions
# never merge.
#
# Every table answers one question from the playtest brief, and says which.
# Numbers are per attempt or per minute of PLAY time (menus and the briefing
# are paused and excluded), so a long mission and a short one compare fairly.
# ─────────────────────────────────────────────

const EXPLOSIVES := ["Frag", "EMP", "Hatchling"]
# Squad orders in the words the player uses. A TAP of the command key is DEFEND
# (go there and hold); a HOLD is FOLLOW.
const ORDER_NAMES := {
	"DEFEND": "Move & hold (tap)",
	"FOLLOW": "Follow (hold)",
	"ADVANCE": "Advance",
	"ATTACK": "Attack target",
	"WITHDRAW": "Withdraw",
	"PATROL": "Patrol",
	"NONE": "No order",
}


static func build(events: Array, title: String) -> String:
	var d := _digest(events)
	var o: PackedStringArray = []
	o.append("# Playtest report — %s" % title)
	o.append("")
	o.append("Generated %s from %d events. Times are play time: pauses, menus and the briefing are excluded." % [
		Time.get_datetime_string_from_system(), events.size()])
	o.append("")
	# Which export(s) the sessions came from. A merged report can span builds,
	# and a number that moved between two builds is worth knowing about.
	var builds := PackedStringArray()
	for e in events:
		var v := str(e.get("version", "")) if str(e.get("ev", "")) == "session_start" else ""
		if v != "" and not builds.has(v):
			builds.append(v)
	if not builds.is_empty():
		o.append("%s %s." % ["Build" if builds.size() == 1 else "Builds", ", ".join(builds)])
		o.append("")
	_glance(o, d)
	_missions(o, d)
	_deaths(o, d)
	_threats(o, d)
	_player_weapons(o, d)
	_ammo(o, d)
	_health(o, d)
	_allies(o, d)
	_orders(o, d)
	_equipment(o, d)
	_signal(o, d)
	o.append("---")
	o.append("Raw data: `events.jsonl` in the same folder, one JSON object per line. Every line has `ev` (event type) and `t` (seconds into the session); lines during a mission add `m` (mission id), `a` (attempt number) and `mt` (seconds into the mission).")
	return "\n".join(o)


# ─────────────────────────────────────────────
# DIGEST — one pass over the events
# ─────────────────────────────────────────────
static func _digest(events: Array) -> Dictionary:
	var d := {
		"sessions": {}, "attempts": {}, "order_keys": [],
		"hurt": {}, "pweap": {}, "aweap": {}, "enemies": {},
		"deaths": [], "ran_out": {}, "dry": {}, "no_reserve": {},
		"healed_by": {}, "revives": {}, "throws": {}, "blast_kills": {},
		"order_time": {}, "order_ally": {}, "player_orders": {},
		"signal": {}, "ekill_by": {}, "ekilled": {},
	}
	for e in events:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var s := str(e.get("s", "1"))
		d["sessions"][s] = maxf(float(d["sessions"].get(s, 0.0)), float(e.get("t", 0.0)))
		var ev := str(e.get("ev", ""))
		var key := "%s#%s" % [s, str(e.get("a", 0))]
		var att: Dictionary = d["attempts"].get(key, {})
		match ev:
			"mission_start":
				att = {"m": str(e.get("m", "")), "name": str(e.get("name", e.get("m", ""))),
					"result": "unfinished", "dur": 0.0, "p_taken": 0, "p_healed": 0,
					"kills": 0, "ally_downs": 0, "hp": -1, "max_hp": -1, "allies": {},
					"enemy_bodies": int(e.get("enemy_bodies", 0)), "shots": {}, "hits": {},
					"orders": {}, "ammo": {}, "last_mt": 0.0}
				d["attempts"][key] = att
				d["order_keys"].append(key)
			"squad":
				if not att.is_empty():
					for kit in e.get("allies", []):
						att["allies"][str(kit.get("name", "?"))] = {"kit": kit, "dealt": 0, "kills": 0,
							"taken": 0, "downs": 0, "revived": 0}
			"mission_end":
				if not att.is_empty():
					att["result"] = str(e.get("result", "?"))
					att["dur"] = float(e.get("duration", 0.0))
					att["hp"] = int(e.get("hp", -1))
					att["max_hp"] = int(e.get("max_hp", -1))
					att["shots"] = e.get("shots", {})
					att["hits"] = e.get("hits", {})
					att["signal"] = e.get("signal", {})
					att["orders"] = e.get("orders", {})
					att["ammo"] = e.get("ammo", {})
					att["won"] = bool(e.get("won", false))
			"damage":
				_on_damage(d, att, e)
			"heal":
				_on_heal(d, att, e)
			"revive":
				var by: Dictionary = e.get("by", {})
				_bump(d["revives"], str(by.get("kind", "?")))
			"player_death":
				var killer: Dictionary = e.get("killer", {})
				d["deaths"].append({"m": str(e.get("m", "")), "name": str(att.get("name", e.get("m", ""))),
					"mt": float(e.get("mt", 0.0)), "kind": str(killer.get("kind", "?")),
					"side": str(killer.get("side", "?")), "w": str(e.get("w", "?")),
					"recent": e.get("recent", [])})
			"ammo":
				var kind := str(e.get("kind", ""))
				if kind == "ran_out":
					var r: Dictionary = d["ran_out"].get(str(e.get("type", "?")), {"n": 0, "mts": [], "atts": {}})
					r["n"] += 1
					r["mts"].append(float(e.get("mt", 0.0)))
					r["atts"][key] = true
					d["ran_out"][str(e.get("type", "?"))] = r
				elif kind == "dry_fire":
					_bump(d["dry"], str(e.get("w", "?")))
				elif kind == "no_reserve":
					_bump(d["no_reserve"], str(e.get("w", "?")))
			"throw":
				var by: Dictionary = e.get("by", {})
				_bump(d["throws"], "%s|%s" % [str(by.get("side", "?")), str(e.get("item", "?"))])
			"order":
				if bool(e.get("by_player", false)):
					_bump(d["player_orders"], str(e.get("to", "?")))
			"ekill":
				var by: Dictionary = e.get("atk", {})
				var vic: Dictionary = e.get("vic", {})
				# An enemy's row is its frame, as its signal is keyed (see _shot_key).
				var by_side := str(by.get("side", "world"))
				_bump(d["ekill_by"], _signal_source(by_side, str(by.get("kind", "?")),
					"" if by_side == "enemy" else str(e.get("w", "?"))))
				_bump(d["ekilled"], "%s|%s" % [str(vic.get("side", "?")), str(vic.get("kind", "?"))])
		if not att.is_empty() and e.has("mt"):
			att["last_mt"] = maxf(float(att["last_mt"]), float(e["mt"]))

	# Orders and shots only arrive in mission_end; fold them in afterwards.
	for key in d["attempts"]:
		var att: Dictionary = d["attempts"][key]
		if att["dur"] <= 0.0:
			att["dur"] = att["last_mt"]
		for sq in att["orders"]:
			for order in att["orders"][sq]:
				d["order_time"][order] = float(d["order_time"].get(order, 0.0)) + float(att["orders"][sq][order])
		for k in att["shots"]:
			var parts := str(k).split("|")
			match parts[0]:
				"player":
					var w := _slot(d["pweap"], parts[1])
					w["shots"] += int(att["shots"][k])
					w["hits"] += int(att["hits"].get(k, 0))
				"ally":
					var w2 := _slot(d["aweap"], parts[2] if parts.size() > 2 else "?")
					w2["shots"] += int(att["shots"][k])
					w2["hits"] += int(att["hits"].get(k, 0))
					var who: String = parts[1]
					if att["allies"].has(who):
						att["allies"][who]["shots"] = int(att["allies"][who].get("shots", 0)) + int(att["shots"][k])
				"enemy":
					var en := _enemy(d, parts[1])
					en["shots"] += int(att["shots"][k])
					en["hits"] += int(att["hits"].get(k, 0))
		# Signal arrives keyed like shots; allies fold together by weapon, so
		# "Squad: Machine Gun" is one row however many rovers carried one.
		for k in att.get("signal", {}):
			var parts := str(k).split("|")
			var src := ""
			match parts[0]:
				"player":
					src = _signal_source("player", "player", parts[1])
				"ally":
					src = _signal_source("ally", "", parts[2] if parts.size() > 2 else "?")
				"enemy":
					src = _signal_source("enemy", parts[1], "")
				_:
					src = _signal_source("world", "", parts[1] if parts.size() > 1 else "?")
			d["signal"][src] = float(d["signal"].get(src, 0.0)) + float(att["signal"][k])
	return d


static func _on_damage(d: Dictionary, att: Dictionary, e: Dictionary) -> void:
	var atk: Dictionary = e.get("atk", {})
	var vic: Dictionary = e.get("vic", {})
	var dmg := int(e.get("dmg", 0))
	var lethal := bool(e.get("lethal", false))
	var w := str(e.get("w", "?"))
	var a_side := str(atk.get("side", "?"))
	var v_side := str(vic.get("side", "?"))

	if v_side == "player":
		var hk := "%s|%s|%s" % [a_side, str(atk.get("kind", "?")), w]
		var h: Dictionary = d["hurt"].get(hk, {"side": a_side, "kind": str(atk.get("kind", "?")), "w": w,
			"dmg": 0, "hits": 0, "kills": 0})
		h["dmg"] += dmg
		h["hits"] += 1
		h["kills"] += 1 if lethal else 0
		d["hurt"][hk] = h
		if not att.is_empty():
			att["p_taken"] += dmg
	if a_side == "player":
		var pw := _slot(d["pweap"], w)
		if v_side == "enemy":
			pw["dmg"] += dmg
			pw["kills"] += 1 if lethal else 0
		elif v_side == "ally":
			pw["ff"] += dmg
	if a_side == "ally":
		var aw := _slot(d["aweap"], w)
		if v_side == "enemy":
			aw["dmg"] += dmg
			aw["kills"] += 1 if lethal else 0
			if not att.is_empty() and att["allies"].has(str(atk.get("name", ""))):
				var al: Dictionary = att["allies"][str(atk.get("name", ""))]
				al["dealt"] += dmg
				al["kills"] += 1 if lethal else 0
			var ob := _order_bucket(d, str(e.get("ao", "")))
			ob["dealt"] += dmg
	if a_side == "enemy":
		var en := _enemy(d, str(atk.get("kind", "?")))
		if v_side == "player":
			en["to_player"] += dmg
			en["kill_player"] += 1 if lethal else 0
		elif v_side == "ally":
			en["to_allies"] += dmg
			en["down_ally"] += 1 if lethal else 0
	if v_side == "enemy" and lethal:
		_enemy(d, str(vic.get("kind", "?")))["deaths"] += 1
		if not att.is_empty():
			att["kills"] += 1
		if EXPLOSIVES.has(w):
			_bump(d["blast_kills"], "%s|%s" % [a_side, w])
	if v_side == "ally":
		if not att.is_empty():
			if lethal:
				att["ally_downs"] += 1
			if att["allies"].has(str(vic.get("name", ""))):
				var al2: Dictionary = att["allies"][str(vic.get("name", ""))]
				al2["taken"] += dmg
				al2["downs"] += 1 if lethal else 0
		var ob2 := _order_bucket(d, str(e.get("vo", "")))
		ob2["taken"] += dmg
		ob2["downs"] += 1 if lethal else 0


static func _on_heal(d: Dictionary, att: Dictionary, e: Dictionary) -> void:
	var vic: Dictionary = e.get("vic", {})
	var by: Dictionary = e.get("by", {})
	var amt := int(e.get("amt", 0))
	var healer := "%s|%s" % [str(by.get("side", "?")), str(by.get("kind", "?"))]
	var target := str(vic.get("side", "?"))
	var slot: Dictionary = d["healed_by"].get("%s>%s" % [healer, target],
		{"healer": healer, "target": target, "amt": 0, "n": 0})
	slot["amt"] += amt
	slot["n"] += 1
	d["healed_by"]["%s>%s" % [healer, target]] = slot
	if bool(e.get("revive", false)):
		_bump(d["revives"], healer)
	if not att.is_empty():
		if target == "player":
			att["p_healed"] += amt
		elif target == "ally" and att["allies"].has(str(vic.get("name", ""))):
			if bool(e.get("revive", false)):
				att["allies"][str(vic.get("name", ""))]["revived"] += 1


static func _slot(table: Dictionary, w: String) -> Dictionary:
	if not table.has(w):
		table[w] = {"shots": 0, "hits": 0, "dmg": 0, "kills": 0, "ff": 0}
	return table[w]


static func _enemy(d: Dictionary, kind: String) -> Dictionary:
	if not d["enemies"].has(kind):
		d["enemies"][kind] = {"shots": 0, "hits": 0, "to_player": 0, "to_allies": 0,
			"kill_player": 0, "down_ally": 0, "deaths": 0}
	return d["enemies"][kind]


static func _order_bucket(d: Dictionary, order: String) -> Dictionary:
	var k := order if order != "" else "(no order)"
	if not d["order_ally"].has(k):
		d["order_ally"][k] = {"dealt": 0, "taken": 0, "downs": 0}
	return d["order_ally"][k]


static func _bump(table: Dictionary, k: String, by: int = 1) -> void:
	table[k] = int(table.get(k, 0)) + by


# ─────────────────────────────────────────────
# SECTIONS
# ─────────────────────────────────────────────
static func _glance(o: PackedStringArray, d: Dictionary) -> void:
	var play := 0.0
	var clears := 0
	var deaths := 0
	for k in d["attempts"]:
		var a: Dictionary = d["attempts"][k]
		play += float(a["dur"])
		if a["result"] == "success":
			clears += 1
		elif a["result"] == "death":
			deaths += 1
	var n: int = d["attempts"].size()
	var session_time := 0.0
	for s in d["sessions"]:
		session_time += float(d["sessions"][s])
	o.append("## At a glance")
	o.append("")
	o.append("- Sessions: **%d**, total session time **%s min**, of which on missions **%s min**" % [
		d["sessions"].size(), _f(session_time / 60.0), _f(play / 60.0)])
	o.append("- Mission attempts: **%d** — cleared **%d** (%s), died **%d**, other **%d**" % [
		n, clears, _pct(clears, n), deaths, n - clears - deaths])
	if play > 0.0:
		o.append("- Deaths per hour on missions: **%s**" % _f(deaths / (play / 3600.0)))
	var top_threat := _top(d["hurt"], "dmg")
	if top_threat != "":
		var t: Dictionary = d["hurt"][top_threat]
		o.append("- Biggest threat to the player: **%s** — %d damage" % [_src(t["kind"], t["w"], t["side"]), t["dmg"]])
	var top_gun := _top(d["pweap"], "kills")
	if top_gun != "":
		o.append("- Player's deadliest weapon: **%s** — %d kills" % [top_gun, d["pweap"][top_gun]["kills"]])
	var top_order := _top_value(d["order_time"])
	if top_order != "":
		o.append("- Squad spent most time on: **%s**" % ORDER_NAMES.get(top_order, top_order))
	o.append("")


static func _missions(o: PackedStringArray, d: Dictionary) -> void:
	o.append("## How hard is it? (per mission)")
	o.append("")
	var by_m := {}
	var order: Array = []
	for k in d["order_keys"]:
		var a: Dictionary = d["attempts"][k]
		var m: String = a["m"]
		if not by_m.has(m):
			by_m[m] = {"name": a["name"], "n": 0, "clear": 0, "death": 0, "other": 0, "clear_time": 0.0,
				"death_time": 0.0, "taken": 0, "healed": 0, "play": 0.0, "downs": 0, "kills": 0,
				"bodies": 0, "hp_left": 0.0, "hp_n": 0}
			order.append(m)
		var r: Dictionary = by_m[m]
		r["n"] += 1
		r["play"] += float(a["dur"])
		r["taken"] += int(a["p_taken"])
		r["healed"] += int(a["p_healed"])
		r["downs"] += int(a["ally_downs"])
		r["kills"] += int(a["kills"])
		r["bodies"] += int(a["enemy_bodies"])
		match a["result"]:
			"success":
				r["clear"] += 1
				r["clear_time"] += float(a["dur"])
				if int(a["max_hp"]) > 0:
					r["hp_left"] += float(a["hp"]) / float(a["max_hp"])
					r["hp_n"] += 1
			"death":
				r["death"] += 1
				r["death_time"] += float(a["dur"])
			_:
				r["other"] += 1
	var rows: Array = []
	for m in order:
		var r: Dictionary = by_m[m]
		rows.append([r["name"], r["n"], "%d (%s)" % [r["clear"], _pct(r["clear"], r["n"])], r["death"], r["other"],
			_f(r["clear_time"] / 60.0 / maxf(1, r["clear"])) if r["clear"] > 0 else "-",
			_f(r["death_time"] / 60.0 / maxf(1, r["death"])) if r["death"] > 0 else "-",
			_f(float(r["taken"]) / maxf(1, r["n"])),
			_f(float(r["taken"]) / maxf(0.01, r["play"] / 60.0)),
			_f(float(r["healed"]) / maxf(1, r["n"])),
			_pct(r["hp_left"], r["hp_n"]) if r["hp_n"] > 0 else "-",
			_f(float(r["downs"]) / maxf(1, r["n"])),
			"%d / %d" % [r["kills"], r["bodies"]]])
	o.append(_table(["Mission", "Attempts", "Cleared", "Died", "Other", "Avg clear (min)", "Avg time to death (min)",
		"Player dmg taken / attempt", "Player dmg taken / min", "Player healed / attempt", "HP left on clear",
		"Ally downs / attempt", "Enemies killed / fielded"], rows))
	o.append("")


static func _deaths(o: PackedStringArray, d: Dictionary) -> void:
	o.append("## When and how do players die?")
	o.append("")
	if d["deaths"].is_empty():
		o.append("No player deaths recorded.")
		o.append("")
		return
	var rows: Array = []
	for x in d["deaths"]:
		# Grouped: "Rifle Trooper ×10 (100 dmg)" reads; ten separate entries don't.
		var by_src := {}
		var order: Array = []
		for h in x["recent"]:
			var src := _src(str(h.get("kind", "?")), str(h.get("w", "?")), str(h.get("side", "enemy")))
			if not by_src.has(src):
				by_src[src] = [0, 0]
				order.append(src)
			by_src[src][0] += 1
			by_src[src][1] += int(h.get("dmg", 0))
		var recent: PackedStringArray = []
		for src in order:
			recent.append("%s ×%d (%d dmg)" % [src, by_src[src][0], by_src[src][1]])
		rows.append([x["name"], _f(float(x["mt"]) / 60.0), _src(x["kind"], x["w"], x["side"]), ", ".join(recent)])
	o.append(_table(["Mission", "Minute", "Killing blow", "Damage in the 6s before"], rows))
	o.append("")


static func _threats(o: PackedStringArray, d: Dictionary) -> void:
	o.append("## What hurts the player most?")
	o.append("")
	var total := 0
	for k in d["hurt"]:
		total += int(d["hurt"][k]["dmg"])
	var keys: Array = d["hurt"].keys()
	keys.sort_custom(func(a, b): return int(d["hurt"][a]["dmg"]) > int(d["hurt"][b]["dmg"]))
	var rows: Array = []
	for k in keys:
		var h: Dictionary = d["hurt"][k]
		rows.append([_src(h["kind"], h["w"], h["side"]), h["dmg"], _pct(h["dmg"], total), h["hits"],
			_f(float(h["dmg"]) / maxf(1, h["hits"])), h["kills"]])
	o.append(_table(["Source", "Damage to player", "Share", "Hits", "Dmg / hit", "Killing blows"], rows))
	o.append("")
	o.append("### Enemy types")
	o.append("")
	var erows: Array = []
	for kind in d["enemies"]:
		var en: Dictionary = d["enemies"][kind]
		erows.append([kind, en["deaths"], en["shots"], _pct(en["hits"], en["shots"]), en["to_player"],
			en["to_allies"], en["kill_player"], en["down_ally"]])
	o.append(_table(["Enemy", "Killed", "Attacks", "Hit rate", "Dmg to player", "Dmg to allies",
		"Player kills", "Ally downs"], erows))
	o.append("")


static func _player_weapons(o: PackedStringArray, d: Dictionary) -> void:
	o.append("## Which player weapons work?")
	o.append("")
	var rows: Array = []
	for w in d["pweap"]:
		var s: Dictionary = d["pweap"][w]
		rows.append([w, s["shots"], s["hits"], _pct(s["hits"], s["shots"]), s["dmg"], s["kills"],
			_f(float(s["dmg"]) / maxf(1, s["shots"])) if s["shots"] > 0 else "-",
			_f(float(s["shots"]) / s["kills"]) if s["kills"] > 0 and s["shots"] > 0 else "-", s["ff"]])
	o.append(_table(["Weapon", "Shots", "Shots that hit", "Accuracy", "Damage", "Kills", "Dmg / shot",
		"Shots / kill", "Friendly fire dmg"], rows))
	o.append("")
	o.append("Accuracy counts a shot once however many pellets land. Thrown items have no shots; see Equipment.")
	o.append("")


static func _ammo(o: PackedStringArray, d: Dictionary) -> void:
	o.append("## Are players running out of ammo?")
	o.append("")
	var n: int = d["attempts"].size()
	var rows: Array = []
	for t in d["ran_out"]:
		var r: Dictionary = d["ran_out"][t]
		var mts: Array = r["mts"]
		mts.sort()
		rows.append([t, r["n"], "%d of %d" % [r["atts"].size(), n], _f(float(mts[int(mts.size() / 2.0)]) / 60.0)])
	if rows.is_empty():
		o.append("No reserve ran dry.")
	else:
		o.append(_table(["Ammo", "Times a reserve hit zero", "Attempts where it happened", "Median minute"], rows))
	o.append("")
	var left := {}
	for k in d["attempts"]:
		var a: Dictionary = d["attempts"][k]
		for t in a["ammo"]:
			var pair: Array = a["ammo"][t]
			if not left.has(t):
				left[t] = {"count": 0.0, "cap": 0.0, "n": 0}
			left[t]["count"] += float(pair[0])
			left[t]["cap"] += float(pair[1])
			left[t]["n"] += 1
	var lrows: Array = []
	for t in left:
		var l: Dictionary = left[t]
		lrows.append([t, _f(l["count"] / maxf(1, l["n"])), _f(l["cap"] / maxf(1, l["n"])) if l["cap"] > 0 else "no cap",
			_pct(l["count"], l["cap"]) if l["cap"] > 0 else "-"])
	if not lrows.is_empty():
		o.append("### Reserve left at the end of a mission")
		o.append("")
		o.append(_table(["Ammo", "Avg left", "Avg capacity", "Left"], lrows))
		o.append("")
	var shot_rows: Array = []
	for w in d["pweap"]:
		shot_rows.append([w, _f(float(d["pweap"][w]["shots"]) / maxf(1, n)), int(d["dry"].get(w, 0)),
			int(d["no_reserve"].get(w, 0))])
	if not shot_rows.is_empty():
		o.append("### Shots per attempt")
		o.append("")
		o.append(_table(["Weapon", "Shots / attempt", "Trigger on empty mag", "Reload with no reserve"], shot_rows))
		o.append("")


static func _health(o: PackedStringArray, d: Dictionary) -> void:
	o.append("## Damage taken vs. healing")
	o.append("")
	var taken := 0
	var healed := 0
	var ally_taken := 0
	for k in d["attempts"]:
		var a: Dictionary = d["attempts"][k]
		taken += int(a["p_taken"])
		healed += int(a["p_healed"])
		for name in a["allies"]:
			ally_taken += int(a["allies"][name]["taken"])
	o.append("- Player: took **%d**, healed **%d**" % [taken, healed])
	var to_allies := 0
	for k in d["healed_by"]:
		if d["healed_by"][k]["target"] == "ally":
			to_allies += int(d["healed_by"][k]["amt"])
	o.append("- Allies: took **%d**, repaired **%d**" % [ally_taken, to_allies])
	o.append("")
	var rows: Array = []
	for k in d["healed_by"]:
		var h: Dictionary = d["healed_by"][k]
		rows.append([h["healer"], h["target"], h["amt"], h["n"], int(d["revives"].get(h["healer"], 0))])
	if int(d["revives"].get("nanite", 0)) > 0:
		rows.append(["self|nanite", "ally", "-", "-", int(d["revives"]["nanite"])])
	if not rows.is_empty():
		o.append(_table(["Healer (side|what)", "Healed", "Amount", "Times", "Revives"], rows))
		o.append("")


static func _allies(o: PackedStringArray, d: Dictionary) -> void:
	o.append("## Does kit change how allies perform?")
	o.append("")
	o.append("One row per piece of kit. An ally-mission is one robot on one attempt, so a robot carrying two modules counts toward both.")
	o.append("")
	var groups := {}
	for k in d["attempts"]:
		var a: Dictionary = d["attempts"][k]
		var minutes := maxf(0.01, float(a["dur"]) / 60.0)
		for name in a["allies"]:
			var al: Dictionary = a["allies"][name]
			var kit: Dictionary = al["kit"]
			var tags: Array = []
			# The frame first: a chaser has no weapon or equipment rows, so
			# without this it would only show up as "Module: (none)".
			if str(kit.get("chassis", "")) != "":
				tags.append("Frame: %s" % str(kit["chassis"]).capitalize())
			for w in kit.get("weapons", []):
				tags.append("Weapon: %s" % w)
			for e in kit.get("equipment", []):
				tags.append("Equipment: %s" % e)
			var mods: Array = kit.get("modules", [])
			if mods.is_empty():
				tags.append("Module: (none)")
			for m in mods:
				tags.append("Module: %s" % m)
			tags.append("Rank %d" % int(kit.get("rank", 0)))
			for tag in tags:
				if not groups.has(tag):
					groups[tag] = {"n": 0, "dealt_min": 0.0, "kills": 0, "taken_min": 0.0, "downs": 0, "shots": 0}
				var g: Dictionary = groups[tag]
				g["n"] += 1
				g["dealt_min"] += float(al["dealt"]) / minutes
				g["taken_min"] += float(al["taken"]) / minutes
				g["kills"] += int(al["kills"])
				g["downs"] += int(al["downs"])
				g["shots"] += int(al.get("shots", 0))
	var tags_sorted: Array = groups.keys()
	tags_sorted.sort()
	var rows: Array = []
	for tag in tags_sorted:
		var g: Dictionary = groups[tag]
		var n: float = maxf(1, g["n"])
		rows.append([tag, g["n"], _f(g["dealt_min"] / n), _f(g["kills"] / n), _f(g["taken_min"] / n),
			_f(g["downs"] / n), _f(g["shots"] / n)])
	if rows.is_empty():
		o.append("No allies deployed yet.")
	else:
		o.append(_table(["Kit", "Ally-missions", "Dmg dealt / min", "Kills / mission", "Dmg taken / min",
			"Downs / mission", "Shots / mission"], rows))
	o.append("")
	var wrows: Array = []
	for w in d["aweap"]:
		var s: Dictionary = d["aweap"][w]
		wrows.append([w, s["shots"], _pct(s["hits"], s["shots"]), s["dmg"], s["kills"],
			_f(float(s["dmg"]) / maxf(1, s["shots"])) if s["shots"] > 0 else "-"])
	if not wrows.is_empty():
		o.append("### Ally weapons")
		o.append("")
		o.append(_table(["Weapon", "Shots", "Accuracy", "Damage", "Kills", "Dmg / shot"], wrows))
		o.append("")


static func _orders(o: PackedStringArray, d: Dictionary) -> void:
	o.append("## Follow vs. advance: what do squads do, and what works?")
	o.append("")
	var total := 0.0
	for order in d["order_time"]:
		total += float(d["order_time"][order])
	var rows: Array = []
	for order in d["order_time"]:
		var secs := float(d["order_time"][order])
		var mins := maxf(0.01, secs / 60.0)
		var b: Dictionary = d["order_ally"].get(order, {"dealt": 0, "taken": 0, "downs": 0})
		rows.append([ORDER_NAMES.get(order, order), _f(secs / 60.0), _pct(secs, total), _f(float(b["dealt"]) / mins),
			_f(float(b["taken"]) / mins), _f(float(b["downs"]) / mins * 10.0), int(d["player_orders"].get(order, 0))])
	if rows.is_empty():
		o.append("No squad orders recorded.")
	else:
		o.append(_table(["Squad order", "Minutes", "Share", "Squad dmg dealt / min", "Squad dmg taken / min",
			"Downs / 10 min", "Times you switched to it"], rows))
		o.append("")
		o.append("Minutes add up across squads. Damage is bucketed by the order the ally's squad was under at the moment of the hit.")
	o.append("")


static func _equipment(o: PackedStringArray, d: Dictionary) -> void:
	o.append("## Equipment use")
	o.append("")
	var n: int = maxi(1, d["attempts"].size())
	var rows: Array = []
	for k in d["throws"]:
		var parts := str(k).split("|")
		rows.append([parts[1], parts[0], d["throws"][k], _f(float(d["throws"][k]) / n),
			int(d["blast_kills"].get("%s|%s" % [parts[0], parts[1]], 0))])
	if rows.is_empty():
		o.append("Nothing thrown.")
	else:
		o.append(_table(["Item", "Thrown by", "Times", "Per attempt", "Kills"], rows))
	o.append("")


static func _signal(o: PackedStringArray, d: Dictionary) -> void:
	o.append("## Signal and e-kills")
	o.append("")
	var sources := {}
	for s in d["signal"]:
		sources[s] = true
	for s in d["ekill_by"]:
		sources[s] = true
	if sources.is_empty():
		o.append("No signal damage recorded.")
		o.append("")
		return
	var rows: Array = []
	for s in sources:
		rows.append([s, _f(float(d["signal"].get(s, 0.0))), int(d["ekill_by"].get(s, 0))])
	rows.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	o.append(_table(["Source", "Signal taken off", "E-kills"], rows))
	o.append("")
	var fell := PackedStringArray()
	for k in d["ekilled"]:
		var parts := str(k).split("|")
		fell.append("%d %s%s" % [d["ekilled"][k], parts[1], " (yours)" if parts[0] == "ally" or parts[0] == "player" else ""])
	if not fell.is_empty():
		o.append("E-killed: %s." % ", ".join(fell))
		o.append("")
	o.append("Signal is a robot's link to its commander. Suppression and EMPs wear it down; at zero the robot is e-killed — frozen, no orders, no fire — until it recovers to half. 1.0 is one robot's whole signal. Suppression is credited to the gun that fired, an EMP to the EMP.")
	o.append("")


# "You: EMP", "Squad: Machine Gun", "Enemy: Rover".
static func _signal_source(side: String, kind: String, w: String) -> String:
	match side:
		"player":
			return "You: %s" % w
		"ally":
			return "Squad: %s" % w
		"enemy":
			return "Enemy: %s" % (kind if w == "" or w == "?" or w == "unknown" else w)
	return "Other: %s" % w


# ─────────────────────────────────────────────
# FORMATTING
# ─────────────────────────────────────────────
static func _table(headers: Array, rows: Array) -> String:
	if rows.is_empty():
		return "_(no data)_"
	var lines: PackedStringArray = []
	lines.append("| " + " | ".join(PackedStringArray(headers.map(func(h): return str(h)))) + " |")
	lines.append("|" + "---|".repeat(headers.size()))
	for r in rows:
		lines.append("| " + " | ".join(PackedStringArray(r.map(func(c): return str(c)))) + " |")
	return "\n".join(lines)


# "Shotgun Trooper", "Hopper Chassis (Frag)", "Bravo-2 (Ancient Rifle) — friendly".
# An enemy's weapon is usually its chassis, so the weapon only shows when it is
# something else — a thrown frag, say.
static func _src(kind: String, w: String, side: String) -> String:
	var label := kind
	if w != "" and w != "unknown" and w != "?" and w != kind:
		label = "%s (%s)" % [kind, w]
	if side == "ally" or side == "player":
		label += " — friendly"
	elif side == "world":
		label += " — world"
	return label


static func _f(x: float) -> String:
	return "%.1f" % x


static func _pct(a: float, b: float) -> String:
	if b <= 0.0:
		return "-"
	return "%d%%" % int(round(100.0 * a / b))


static func _top(table: Dictionary, field: String) -> String:
	var best := ""
	var best_v := 0
	for k in table:
		var v := int(table[k].get(field, 0))
		if v > best_v:
			best_v = v
			best = k
	return best


static func _top_value(table: Dictionary) -> String:
	var best := ""
	var best_v := 0.0
	for k in table:
		if float(table[k]) > best_v:
			best_v = float(table[k])
			best = k
	return best
