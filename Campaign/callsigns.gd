extends RefCounted
class_name Callsigns

# ─────────────────────────────────────────────
# SQUAD CALLSIGNS — who is shooting at you, and what that tells you.
#
# A callsign is the only name a player ever reads for an enemy squad: it is in
# the contact report, the objective line and the debrief. So it is the cheapest
# characterisation in the game, and the three factions should not sound alike.
#
# WHAT WAS ALREADY HERE. The twelve shipped missions carry 390 hand-authored
# callsigns, and they are themed BY MAP rather than by faction — Three Rivers
# is Russian metallurgy and Chinese directional gods, the Causeway is civil
# engineering and siege artillery, Lockside is British canal wildlife. That is
# a good system and this does not replace it: an authored spec keeps the name
# it was given. This is for GENERATED squads (§10, Phase 4), which have no
# author to name them.
#
# TWO AXES, NOT ONE.
#
#   FACTION  decides the LANGUAGE. The Swarm is Russian and Chinese. Home
#            Command is NATO and western. Argus does not use language.
#   SITE     widens HOME COMMAND only. The English site vocabularies suit a
#            western force exactly; the Swarm never touches them, because the
#            Russian/Chinese contrast is the point and must not be diluted.
#
# NO DUPLICATES WITHIN AN OPERATION. take() is given the names already in play
# and will not hand out a second copy — two squads called KINZHAL in the same
# contact list is the kind of thing that reads as a bug rather than a
# coincidence.
# ─────────────────────────────────────────────

# ── THE SWARM ────────────────────────────────────────────────────────────────
# Russian and Chinese, as the shipped missions use them. Act 1's whole
# vocabulary: beasts, weather, metal, blades, and the gods of both traditions.

## Transliterated Russian. Blades (KINZHAL, KLINOK), metallurgy (CHUGUN, SHLAK,
## SPLAV, SVINETS, ZAKAL), raptors (BERKUT, SOKOL, KRECHET, SAPSAN), weather
## (BURAN, PURGA, METEL, GROZA), sea (KASATKA, NERPA, MORZH, PRIBOY).
const SWARM_RU: Array[StringName] = [
	&"BARS", &"BELUGA", &"BERKUT", &"BULAT", &"BURAN", &"CHAIKA", &"CHUGUN",
	&"DOZOR", &"GORN", &"GRANIT", &"GROZA", &"INEY", &"ISKRA", &"KASATKA",
	&"KASKAD", &"KINZHAL", &"KLIN", &"KLINOK", &"KOBCHIK", &"KOLCHUGA",
	&"KORSHUN", &"KORUND", &"KRECHET", &"KREMEN", &"LAVINA", &"METEL",
	&"MOLNIYA", &"MORZH", &"NABEG", &"NEFRIT", &"NERPA", &"OBVAL", &"OMUT",
	&"OPLOT", &"ORLAN", &"PEPEL", &"PLAMYA", &"POTOK", &"PRIBOY", &"PRILIV",
	&"PUCHINA", &"PURGA", &"RUBIN", &"RYS", &"SAPSAN", &"SHCHIT", &"SHKVAL",
	&"SHLAK", &"SHMEL", &"SHTURM", &"SKALA", &"SLITOK", &"SMERCH", &"SOBOL",
	&"SOKOL", &"SOPKA", &"SPLAV", &"STERKH", &"STREKOZA", &"STRELA",
	&"STRIZH", &"SVINETS", &"TARAN", &"TAYFUN", &"TUMAN", &"UDAR", &"UTYOS",
	&"VALUN", &"VIKHR", &"VOLK", &"VOLNA", &"VYMPEL", &"YANTAR", &"YASTREB",
	&"ZAKAL", &"ZARYA", &"ZASEKA", &"ZUBR",
]

## Pinyin. Myth and the divine bestiary (QILIN, TAOTIE, PIXIU, FENGHUANG), the
## four directional guardians (QINGLONG, ZHUQUE, BAIHU, XUANWU), sacred
## mountains (KUNLUN, TAISHAN, HUASHAN, EMEI, WUYI), iron (TIELI, TIEJIA,
## TIESHA), and the gods of fire and thunder (ZHURONG, LEIGONG, HUOYAN).
const SWARM_ZH: Array[StringName] = [
	&"BAIHU", &"BAITA", &"BAIYUN", &"BAIZE", &"BIFANG", &"BINGHE", &"BIXI",
	&"CANGLANG", &"CHIYOU", &"DAPENG", &"EMEI", &"ERLANG", &"FEILIAN",
	&"FEIYAN", &"FENGBO", &"FENGHUANG", &"GONGGONG", &"HANBING", &"HEICHAO",
	&"HEILONG", &"HEISHUI", &"HEIYUN", &"HOUYI", &"HUASHAN", &"HUOYAN",
	&"HUYAN", &"JIAOLONG", &"JIAOREN", &"JINGANG", &"JINGLEI", &"JINSHA",
	&"JINWU", &"JIUTIAN", &"JIUWEI", &"JULANG", &"KUAFU", &"KUNLUN",
	&"LANGYA", &"LANHAI", &"LEIGONG", &"LEIYU", &"LIEHUO", &"LONGJUAN",
	&"LONGYA", &"LUSHAN", &"MULAN", &"NEZHA", &"PIXIU", &"QILIN",
	&"QINGLONG", &"QINGSHI", &"QINGYUN", &"SHILIN", &"SHUANGHUA",
	&"SHUANGYAN", &"TAISHAN", &"TAOTIE", &"TENGLONG", &"TIANGOU", &"TIEBI",
	&"TIEJIA", &"TIELI", &"TIELIU", &"TIESHA", &"TIEYI", &"WUYI",
	&"XINGTIAN", &"XUANWU", &"XUEBENG", &"XUELANG", &"YINGLONG", &"YUSHAN",
	&"YUSHI", &"ZHULONG", &"ZHUQUE", &"ZHURONG", &"ZIYAN",
]

# ── SITE FLAVOUR ─────────────────────────────────────────────────────────────
# English, and nothing to do with faction: these say WHERE you are. Lifted from
# the maps that already use them so a generated squad on the Causeway sounds
# like the Causeway. A site with no pool falls back to its faction's language.

## THE CAUSEWAY — civil engineering, siege artillery, and the three words
## maritime salvage law has for things lost at sea: FLOTSAM, JETSAM, LAGAN.
const SITE_CAUSEWAY: Array[StringName] = [
	&"ABUTMENT", &"BALLISTA", &"BEARING", &"BOMBARD", &"BULWARK", &"CORBEL",
	&"COUNTERMARCH", &"CRIBWORK", &"CROWNGUARD", &"CULVERIN", &"CULVERT",
	&"DESCENT", &"EXPANSION", &"FLOTSAM", &"GABION", &"GANTRY", &"GARRISON",
	&"GRAPNEL", &"HARDSTAND", &"HOWITZER", &"JETSAM", &"KERBSTONE", &"LAGAN",
	&"LANTERN", &"LASTDITCH", &"MAGAZINE", &"MERLON", &"PARAPET", &"PITHEAD",
	&"PORTCULLIS", &"REARGUARD", &"REBAR", &"RELIEF", &"REVETMENT",
	&"SCUPPER", &"SETBACK", &"SIEGEWORK", &"SIGNUM", &"SOFFIT", &"SORTIE",
	&"SPALL", &"STOOP", &"TEETH", &"THRESHOLD", &"TOLLBOOTH", &"TOLLHOUSE",
	&"VERGE", &"WIREMAN",
]

## LOCKSIDE — the canal. Waterbirds, coarse fish, and the mustelids that work
## the bank. Nothing military in it at all, which is the joke.
const SITE_LOCKSIDE: Array[StringName] = [
	&"ALEVIN", &"AVOCET", &"BADGER", &"BARBEL", &"BLEAK", &"BREAM",
	&"CARRION", &"CHOUGH", &"CHUB", &"CORMORANT", &"CROW", &"CURLEW",
	&"DACE", &"ELVER", &"FERRET", &"FRY", &"FULMAR", &"GANNET", &"GLUTTON",
	&"GOSHAWK", &"GRILSE", &"GUDGEON", &"HERON", &"HOBBY", &"HOODED",
	&"JACKDAW", &"JAY", &"KELT", &"KESTREL", &"KINGFISHER", &"LAMPREY",
	&"LOACH", &"MAGPIE", &"MARTEN", &"MERLIN", &"MINK", &"NIGHTJAR",
	&"OSPREY", &"OTTER", &"PARR", &"PERCH", &"PETREL", &"PIKE", &"POLECAT",
	&"RAVEN", &"REDD", &"ROACH", &"ROOK", &"RUDD", &"SABLE", &"SALMON",
	&"SANDPIPER", &"SEATROUT", &"SHRIKE", &"SKUA", &"SMOLT", &"STARLING",
	&"STOAT", &"TENCH", &"TERN", &"WAXWING", &"WEASEL", &"ZANDER",
]

## POLARIS — a mall in winter. Retail fittings against the vocabulary of snow
## and ice: AISLEMAN and SASTRUGI in the same list.
const SITE_POLARIS: Array[StringName] = [
	&"AISLEMAN", &"ANCHORAGE", &"AVALANCHE", &"BINYARD", &"BLIZZARD",
	&"BOOTH", &"BORA", &"BRASH", &"CANVAS", &"COLDSNAP", &"CONCOURSE",
	&"CORNICE", &"COUNTER", &"CREVASSE", &"DECKHAND", &"DRIFT",
	&"FIELDHOUSE", &"FIRN", &"FLURRY", &"FORECOURT", &"FROST", &"GALE",
	&"GLACIER", &"GLAZE", &"GRAUPEL", &"GRIDDLE", &"HAIL", &"ICEHOUSE",
	&"KATABAT", &"KERBSIDE", &"KEYSTONE", &"LOADING", &"MORAINE", &"NEVE",
	&"NIGHTSHIFT", &"NORTHER", &"NURSERY", &"PAVILION", &"PLUGBANK",
	&"PROJECTION", &"PYLON", &"RIME", &"RINGER", &"SASTRUGI", &"SERAC",
	&"SLEET", &"SLUSH", &"SQUALL", &"TOLLGATE", &"TROLLEY", &"VALETMAN",
	&"VAULT", &"WAREHOUSED", &"WHITEOUT", &"WINDOW",
]

## HILLFORT — iron-age earthworks. What the parts of a hillfort are called.
const SITE_HILLFORT: Array[StringName] = [
	&"CISTERN", &"DISH", &"GATEHOUSE", &"HIGH-GROUND", &"PILLARS", &"PORTAL",
	&"POSTERN", &"POWERHOUSE", &"SADDLE", &"SHOULDER", &"SPUR", &"TERRACE",
	&"UPLAND", &"YARD",
]

# ── HOME COMMAND ─────────────────────────────────────────────────────────────
# NATO and western. Act 2 is the same war against professionals, and they
# should SOUND professional: no mythology, no animals you would find in a
# hedgerow. Blunt nouns, edged weapons, the ranks of a cavalry that stopped
# existing, and the flat phonetic alphabet underneath it all.
#
# THE POINT OF THE CONTRAST. The Swarm names things after gods and storms
# because somebody chose to. Home Command names things after procedure.

## The alphabet, used plainly. A squad called DELTA is not trying to impress
## you, which is the most unsettling thing about it.
const HOME_PHONETIC: Array[StringName] = [
	&"ALPHA", &"BRAVO", &"CHARLIE", &"DELTA", &"ECHO", &"FOXTROT", &"GOLF",
	&"HOTEL", &"INDIA", &"JULIET", &"KILO", &"LIMA", &"MIKE", &"NOVEMBER",
	&"OSCAR", &"PAPA", &"QUEBEC", &"ROMEO", &"SIERRA", &"TANGO", &"UNIFORM",
	&"VICTOR", &"WHISKEY", &"XRAY", &"YANKEE", &"ZULU",
]

## Edged and blunt. The things a western army names an armoured formation
## after, and has since there were horses.
const HOME_ARMS: Array[StringName] = [
	&"ANVIL", &"BAYONET", &"BROADSWORD", &"CARBINE", &"CLAYMORE", &"CUTLASS",
	&"FALCHION", &"HALBERD", &"HAMMER", &"HATCHET", &"IRONSIDE", &"LONGBOW",
	&"MATTOCK", &"PIKESTAFF", &"POLEAXE", &"RAMROD", &"SABRE", &"SLEDGE",
	&"SPIKE", &"TOMAHAWK",
]

## Formations that have mostly stopped existing, kept as names. A Home Command
## that calls a drone section HUSSAR is quoting an army nobody remembers.
const HOME_RANKS: Array[StringName] = [
	&"CARABINIER", &"CENTURION", &"CRUSADER", &"CUIRASSIER", &"DRAGOON",
	&"FUSILIER", &"GRENADIER", &"HUSSAR", &"LANCER", &"MARSHAL", &"PALADIN",
	&"PIONEER", &"RANGER", &"SAPPER", &"SENTINEL", &"TEMPLAR", &"VANGUARD",
	&"WARDEN", &"YEOMAN", &"ZOUAVE",
]

## Operation-room vocabulary: what a staff officer calls a thing on a map.
const HOME_PROCEDURE: Array[StringName] = [
	&"BACKSTOP", &"BEARING", &"CHECKPOINT", &"CLEARANCE", &"CORDON",
	&"DATUM", &"ECHELON", &"ENFILADE", &"HARDPOINT", &"INTERDICT",
	&"KEYHOLE", &"LODGEMENT", &"OVERWATCH", &"PHASELINE", &"PICKET",
	&"REDOUBT", &"SCREEN", &"STANDOFF", &"TRIPWIRE", &"WAYPOINT",
]

# ── ARGUS ────────────────────────────────────────────────────────────────────
# Nonsense strings, because Argus has stopped meaning things.
#
# The fiction does the work here. Nearly all of what Argus has left goes to its
# own reward loop; it no longer supervises anything and has not named a thing
# on purpose in a long time. Its squads are not CALLED anything — they carry
# whatever identifier fell out of the process that spawned them.
#
# SO THESE ARE GENERATED, NOT LISTED. A hand-written list of nonsense is still
# a list somebody wrote, and it would start to feel like vocabulary by the
# third time you saw it. Built from fragments instead, seeded, so the same
# squad keeps its name across a reload while no two look related.

## Fragments that read as machine, not language. Deliberately ugly.
const ARGUS_STEMS: Array[String] = [
	"NUL", "VOID", "XX", "QQ", "ZR", "KK", "HLT", "NAN", "INF", "ERR",
	"SEG", "TRP", "FLT", "DIV", "REF", "PTR", "OBJ", "SYM", "IDX", "BUF",
]

## The shapes an identifier takes when nothing is choosing it.
const ARGUS_SHAPES: Array[String] = [
	"%s-%02X",       # NUL-7F
	"%s.%d",         # ERR.9
	"%s%s",          # VOIDZR
	"0x%02X%s",      # 0x3FNUL
	"%s_%03d",       # SEG_014
	"%s%s%s",        # QQZRKK
]


# ── Asking ───────────────────────────────────────────────────────────────────

## Which site pools exist. A site with none falls back to its faction.
const BY_SITE := {
	&"causeway": "SITE_CAUSEWAY",
	&"lockside": "SITE_LOCKSIDE",
	&"polaris": "SITE_POLARIS",
	&"hillfort": "SITE_HILLFORT",
}


## Everything a faction can be called.
##
## THE LANGUAGE IS THE FACTION, AND IT DOES NOT BEND. The Swarm is Russian and
## Chinese everywhere, on every map, with no English in it — that contrast with
## Home Command's NATO vocabulary is the whole point, and it is doing the work
## of a lot of exposition the game never has to write. An earlier cut of this
## mixed the site pools in FIRST, which would have put a Swarm squad called
## ABUTMENT on the Causeway and thrown the contrast away for a bit of local
## colour.
##
## SO SITE FLAVOUR IS FOR HOME COMMAND ONLY. The English site vocabularies
## happen to suit a western force exactly — OVERWATCH, HARDPOINT and ABUTMENT
## belong in the same mouth — so they widen Home Command's pool on the maps
## that have one, and the Swarm never touches them.
static func pool(faction: int, site: StringName = &"") -> Array[StringName]:
	var out: Array[StringName] = []
	match faction:
		Enums.Factions.HOME:
			out.append_array(HOME_PHONETIC)
			out.append_array(HOME_ARMS)
			out.append_array(HOME_RANKS)
			out.append_array(HOME_PROCEDURE)
			if site != &"" and BY_SITE.has(site):
				match String(BY_SITE[site]):
					"SITE_CAUSEWAY": out.append_array(SITE_CAUSEWAY)
					"SITE_LOCKSIDE": out.append_array(SITE_LOCKSIDE)
					"SITE_POLARIS": out.append_array(SITE_POLARIS)
					"SITE_HILLFORT": out.append_array(SITE_HILLFORT)
		Enums.Factions.ARGUS:
			pass   # generated per call, never pooled — see _argus()
		_:
			# SWARM, and the default. ENEMY is the Swarm in every shipped
			# mission, so an unflagged force gets the Act 1 vocabulary rather
			# than nothing. NO SITE POOL HERE, deliberately — see above.
			out.append_array(SWARM_RU)
			out.append_array(SWARM_ZH)
	return out


## One callsign, seeded so it survives a reload, and never one of `taken`.
##
## THE SEED IS THE POINT. A squad named at spawn time from randi() gets a new
## name every time the mission is replayed, and a player who died at KINZHAL
## and came back to fight VOLK has no idea it is the same fight.
static func take(faction: int, seed_key: String, taken: Array = [],
		site: StringName = &"") -> StringName:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key)
	if faction == Enums.Factions.ARGUS:
		return _argus(rng, taken)
	var names := pool(faction, site)
	if names.is_empty():
		push_warning("Callsigns: no pool for faction %d, so this squad is unnamed." % faction)
		return &"UNNAMED"
	# Walk from a seeded start rather than re-rolling: with a large `taken` the
	# retry loop is unbounded, and this cannot fail to terminate.
	var start: int = rng.randi_range(0, names.size() - 1)
	for i in names.size():
		var pick: StringName = names[(start + i) % names.size()]
		if not taken.has(pick):
			return pick
	# Every name in the pool is in use — 153 squads on one map. Number it
	# rather than hand back a duplicate.
	return StringName("%s-%d" % [names[start], taken.size()])


## Argus does not pick a name, it leaks one.
static func _argus(rng: RandomNumberGenerator, taken: Array) -> StringName:
	for _attempt in 32:
		var shape: String = ARGUS_SHAPES[rng.randi_range(0, ARGUS_SHAPES.size() - 1)]
		var a: String = ARGUS_STEMS[rng.randi_range(0, ARGUS_STEMS.size() - 1)]
		var b: String = ARGUS_STEMS[rng.randi_range(0, ARGUS_STEMS.size() - 1)]
		var c: String = ARGUS_STEMS[rng.randi_range(0, ARGUS_STEMS.size() - 1)]
		var n: int = rng.randi_range(0, 255)
		var out := ""
		match shape.count("%"):
			1: out = shape % a
			2: out = shape % [a, b] if not shape.contains("%d") and not shape.contains("%02d") and not shape.contains("%03d") else shape % [a, n]
			3: out = shape % [a, b, c]
		if out != "" and not taken.has(StringName(out)):
			return StringName(out)
	# 32 collisions is not plausible; if it happens, say so rather than loop.
	push_warning("Callsigns: could not find a free Argus identifier in 32 tries.")
	return StringName("NUL-%d" % taken.size())
