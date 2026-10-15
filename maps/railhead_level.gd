extends TrenchBroomLevel

# ─────────────────────────────────────────────
# RAILHEAD — the armoured train, as a playable level.
#
# TERRAIN generates the ART (maps/railhead_art.tscn) and regenerates it
# whenever the cars change. This is the other half: the gameplay level that
# instances that art and hangs everything the base needs off it.
#
# THE SPLIT IS LOAD-BEARING AND WRITTEN DOWN IN THEIR BUILDER.
# tools/build_railhead.gd refuses to write a level scene at all, and says why
# in its header: a generator that writes one deletes the spawns, the terminal
# and the exits the next time it runs, which has already happened twice on
# other levels in this project. So the art is generated and this is authored,
# and the two meet at NAMED MARKERS.
#
# NOTHING HERE IS A TYPED COORDINATE, for the same reason their builder says
# it: the Polaris objective was typed, the road moved six metres, and the
# marker ended up inside a wall. Every position below is read out of the art
# scene at load, so when a car changes length the base follows it.
#
# WHY _ready AND NOT LATER. World._change_level adds this level and then
# immediately reads `spawn_point` to place the player — add_child runs _ready
# synchronously, so this is the last moment the spawn can be moved onto its
# marker before anybody asks where it is.
# ─────────────────────────────────────────────

const _OpsTable := preload("res://Env/world_objects/ops_table.gd")
const _DepartureLever := preload("res://Env/world_objects/departure_lever.gd")
const _DepartureRide := preload("res://Env/world_objects/departure_ride.gd")

## The art scene's marker names. These are the contract with
## tools/build_railhead.gd — it writes them into Markers/ and they are the
## only thing the two halves agree on.
## AT THE TABLE, not down on the platform.
##
## TERRAIN's PlayerArrival marker is at the far end of the rake, which is
## right for arriving off a mission but wrong for waking up: it put six
## carriages between the player and the only thing at the base they have to
## use. HoloTable_ViewA is one of the two standing positions TERRAIN left
## beside the operations table, which is exactly where you want to come
## online.
const M_SPAWN := "HoloTable_ViewA"
## And turned to face the table. A spawn marker's ROTATION sets which way the
## player is looking when they arrive, and these markers carry none — left
## alone you wake up facing whatever direction the marker was authored at,
## which beside a table is a coin flip on whether you can see it.
const M_SPAWN_FACE := "HoloTable"
const M_TABLE := "OpsTableAnchor"
## The departure lever's pivot, outboard of the table's platform end. Also put
## there by tools/fit_ops_table.gd, and placed where it is so that throwing it
## leaves you facing the way out — docs/briefs/OPS_TABLE_LEVER.md.
const M_LEVER := "OpsLeverAnchor"
## The squad forms up where you leave from — see M_EXIT below. SquadSpawnPoint
## arcs them out BEHIND this point, so they stand on the platform rather than
## on the departure pad itself.
const M_MUSTER := "PlatformDoor_Outside"
## Which way the board faces on the table. 90 puts its long axis down the
## car; -90 reverses which end of the campaign is toward the locomotive.
@export var table_yaw_degrees: float = 90.0

## WHERE YOU LEAVE THE TRAIN, and where the squad forms up to go with you.
##
## BOTH ON THE STATION PLATFORM, which is beside Car4_Repair at z 0 — one car
## from the operations car at z -32.
##
## They used to be the platform door and muster point on Car7_Platform at
## z -92..-96. That was the shortest walk when the operations car was at the
## far end; it is not any more. The rake now runs Motive +96, Fabrication +64,
## Armoury +32, Repair 0, Operations -32, Barracks -64, Platform -96 — so
## choosing an operation at the table and then leaving on it meant walking the
## length of five cars, 65 m, past everything you had already done.
##
## THE ART WAS NOT TOUCHED TO FIX THIS. Both of these are marker names, and the
## station the train pulls into already has the marker: the fix is which point
## this level reads, not where any geometry sits. _audit_walk below is what
## catches it the next time the rake is re-ordered.
const M_EXIT := "PlatformDoor_Outside"

## Set in the scene to the instanced art.
@export var art: Node3D
## Set in the scene to the SpawnPoint node this moves onto the marker.
@export var spawn_marker_target: Node3D
## The SquadSpawnPoint. Without one the squad silently never musters, and the
## induction's revive step self-completes complaining there is nobody down.
@export var muster: Node3D
## The pad you walk onto to deploy. A plain LevelExit with is_departure set —
## NOT a MissionExit, which no map in this project places.
@export var departure: Node3D


func _ready() -> void:
	if art == null:
		art = get_node_or_null(^"NavigationRegion3D/RailheadArt") as Node3D
	if art == null:
		push_error("RailheadLevel: no art scene. The base will load empty and the player will fall.")
		return
	_place_spawn()
	_place(muster, M_MUSTER, "the squad will muster at the origin")
	_post_the_squad()
	_place(departure, M_EXIT, "the departure pad will sit at the origin")
	_fit_ops_table()
	_fit_ride(_fit_lever())
	_audit_walk()


## PUT THE SQUAD AWAY.
##
## A base is not a staging area. With no slot markers, SquadSpawnPoint arcs
## everyone out behind the muster point, which on a train puts four robots
## standing in the corridor of the platform car — the one place you have to
## walk through — and reads as a squad waiting to be told something rather
## than a crew at rest.
##
## TERRAIN laid twelve BarracksRack markers down the barracks car for exactly
## this, so the squad is posted to them. Combined with the DEFEND objective
## the muster point already carries, each robot stands at its own rack and
## stays there: the base looks lived in, the corridor is clear, and you walk
## past your squad on the way to the operations table rather than through it.
##
## SORTED BY NAME, which is why they are BarracksRack_01 and not _1 — plain
## numbers sort 1, 10, 11, 2 and the squad would fill the racks in a jumble.
##
## More squad than racks falls through to the spawner's own arc, which is the
## right failure: twelve is a lot of robots, and the thirteenth standing in
## the corridor is a visible prompt that the base has run out of beds.
const M_RACK_PREFIX := "BarracksRack_"


func _post_the_squad() -> void:
	if muster == null:
		return
	var racks := _markers_named(M_RACK_PREFIX)
	if racks.is_empty():
		push_warning("RailheadLevel: no '%s*' markers in the art, so the squad falls back to an arc behind the muster point." % M_RACK_PREFIX)
		return
	muster.slot_markers = racks
	# And then sort them by size once they exist — see _station_by_size.
	var campaign := get_tree().get_first_node_in_group(&"campaign")
	if campaign == null:
		return
	var spawner = campaign.get("spawner")
	if spawner != null and spawner.has_signal(&"squad_deployed"):
		spawner.squad_deployed.connect(_station_by_size)


## BIG FRAMES DO NOT GO IN THE BUNKS.
##
## The barracks racks are infantry-sized. A Reclaimer, a Walker or a Bulwark
## posted to one stands half inside the bedding and reads as a bug — which is
## exactly what it looked like.
##
## The train already has the right furniture for them: six fabrication mounts
## and four repair bays, all built to take something with a chassis. So the
## squad is sorted on arrival — anything whose frame costs two or more supply
## goes to a bay, everything else keeps a bunk.
##
## SUPPLY AS THE SIZE TEST, rather than measuring collision shapes or listing
## class names. It is already the game's own answer to "how much room does
## this thing take up" — a Bulwark and a Walker are 3, a Rover, Reclaimer and
## Drayman are 2, infantry is 1 — so a frame added later is sorted correctly
## without anybody remembering this function exists.
##
## Done on squad_deployed rather than at _ready: the squad does not exist yet
## when the level loads, and slot_markers alone cannot do this because it is a
## flat list indexed by deploy order, which has nothing to do with size.
const M_BAY_PREFIXES := ["FabricationMount_", "RepairBay_"]
const BIG_FRAME_SUPPLY := 2


func _station_by_size(squad, _count: int) -> void:
	if squad == null or not is_instance_valid(squad):
		return
	var campaign := get_tree().get_first_node_in_group(&"campaign")
	var state = campaign.get("state") if campaign != null else null
	if state == null:
		return
	var bays: Array[Node3D] = []
	for prefix in M_BAY_PREFIXES:
		bays.append_array(_markers_named(prefix))
	if bays.is_empty():
		return

	var next_bay := 0
	for m in squad.squad_members:
		if m == null or not is_instance_valid(m):
			continue
		if next_bay >= bays.size():
			break   # more big frames than bays; the rest keep their bunks
		var record = _record_for(m, state)
		if record == null or state.supply_of(record) < BIG_FRAME_SUPPLY:
			continue
		m.global_position = bays[next_bay].global_position
		next_bay += 1


## The roster entry a deployed body came from. SquadSpawner stamps every one
## it builds with the record's id.
func _record_for(body: Node, state):
	var id = body.get_meta("record_id", &"")
	if id == &"":
		return null
	for r in state.roster:
		if r != null and r.id == id:
			return r
	return null


## Every marker whose name starts with `prefix`, in name order. The padding
## in BarracksRack_01 is why they sort correctly — plain numbers would give
## 1, 10, 11, 2 and fill the racks in a jumble.
func _markers_named(prefix: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	_collect_named(art, prefix, out)
	out.sort_custom(func(a, b): return a.name < b.name)
	return out


func _collect_named(n: Node, prefix: String, out: Array[Node3D]) -> void:
	if n is Node3D and String(n.name).begins_with(prefix):
		out.append(n)
	for c in n.get_children():
		_collect_named(c, prefix, out)


## Move an authored node onto its marker, keeping whatever scale the scene
## gave it — the pad is scaled x(4, 3, 4) to be walk-into-able and a straight
## transform copy would throw that away.
func _place(node: Node3D, marker_name: String, consequence: String) -> void:
	if node == null:
		push_warning("RailheadLevel: nothing wired for '%s', so %s." % [marker_name, consequence])
		return
	var marker := _marker(marker_name)
	if marker == null:
		push_warning("RailheadLevel: the art has no '%s' marker, so %s." % [marker_name, consequence])
		return
	var keep: Vector3 = node.scale
	node.global_position = marker.global_position
	node.scale = keep


## Put the spawn on PlayerArrival.
##
## The node still EXISTS in the scene and is still what `spawn_point` points
## at — World reads that export, not this marker — it is just moved onto the
## marker before World looks. A level whose spawn_point is null drops the
## player at the origin, which on a train is under the trackbed.
func _place_spawn() -> void:
	var target := spawn_marker_target if spawn_marker_target != null else spawn_point
	if target == null:
		push_warning("RailheadLevel: no SpawnPoint node to place, so the player arrives wherever the origin is.")
		return
	var marker := _marker(M_SPAWN)
	if marker == null:
		push_warning("RailheadLevel: the art has no '%s' marker, so the spawn stays where it was authored. Has tools/build_railhead.gd run?" % M_SPAWN)
		return
	target.global_transform = marker.global_transform
	# Turn to face the table, if there is one to face. look_at refuses a
	# target directly overhead or underfoot, so the aim is flattened to the
	# horizon first — the player stands beside the table, not under it.
	var face := _marker(M_SPAWN_FACE)
	if face == null:
		return
	var at := face.global_position
	at.y = target.global_position.y
	if at.distance_to(target.global_position) < 0.05:
		push_warning("RailheadLevel: '%s' and '%s' are the same spot, so the spawn keeps its authored facing." % [M_SPAWN, M_SPAWN_FACE])
		return
	target.look_at(at, Vector3.UP)


## Give the operations table its behaviour.
##
## THE SCRIPT GOES ON AT LEVEL LOAD, not in the car scene. The anchor and its
## Interactible are put there by tools/fit_ops_table.gd, which TERRAIN re-runs
## after every geometry rebuild — anything else added to that scene is wiped
## by the next rebuild. So the car owns the furniture and the empty; this owns
## what the empty does.
##
## The OpsTable is added as a CHILD of the anchor so it inherits its transform
## exactly, and is handed the anchor's existing Interactible rather than
## hunting for one: the Interactible is the anchor's child, which makes it
## this node's SIBLING, and OpsTable._find_interactible only searches its own
## children.
func _fit_ops_table() -> void:
	var anchor := _marker(M_TABLE)
	if anchor == null:
		push_warning("RailheadLevel: no '%s' in the art, so there is no operations table. Run tools/fit_ops_table.gd." % M_TABLE)
		return
	for c in anchor.get_children():
		if c.get_script() == _OpsTable:
			return   # already fitted; a level can be re-entered
	var table = _OpsTable.new()
	table.name = "OpsTable"
	# TURNED TO LIE ALONG THE CAR.
	#
	# The board draws the campaign along its own local X — Hillfort west,
	# the Causeway east — because that is how a map is laid out and the
	# board has no idea it is on a train. The train runs along Godot Z (map
	# +X is Godot +Z, see tools/build_railhead.gd), so the table is seven
	# metres down the car and three across it.
	#
	# Dropped in unturned, the two are exactly perpendicular: a 6.6 m board
	# laid across a 3 m table, hanging off both sides. The car knows its own
	# orientation and the board does not, so the correction belongs here.
	table.rotation.y = deg_to_rad(table_yaw_degrees)
	table.interactible = _interactible_under(anchor)
	if table.interactible == null:
		push_warning("RailheadLevel: '%s' has no Interactible, so the table cannot be used. Run tools/fit_ops_table.gd." % M_TABLE)
	anchor.add_child(table)


## Give the departure lever its handle and its behaviour.
##
## Same arrangement as the operations table and for the same reasons: the car
## scene owns the empty (via tools/fit_ops_table.gd, re-run after every
## rebuild) and this owns what the empty does.
##
## NO YAW CORRECTION, unlike the table. The handle swings about its own local
## X, which under an unrotated car empty IS the car's width axis — so the
## handle already swings along the car, which is the direction a player
## standing at the table's end can actually pull it.
## Returns the lever, or null — _fit_ride needs to know, because a gate with no
## opener would make the whole base undeployable.
func _fit_lever():
	var anchor := _marker(M_LEVER)
	if anchor == null:
		push_warning("RailheadLevel: no '%s' in the art, so there is no departure lever and the only way out is the pad. Run tools/fit_ops_table.gd." % M_LEVER)
		return null
	for c in anchor.get_children():
		if c.get_script() == _DepartureLever:
			return c   # already fitted; a level can be re-entered
	var lever = _DepartureLever.new()
	lever.name = "DepartureLever"
	# Handed over rather than hunted for: the Interactible is the anchor's
	# child, which makes it this node's SIBLING, and the lever only searches
	# its own children.
	lever.interactible = _interactible_under(anchor)
	if lever.interactible == null:
		push_warning("RailheadLevel: '%s' has no Interactible, so the lever cannot be thrown. Run tools/fit_ops_table.gd." % M_LEVER)
	anchor.add_child(lever)
	return lever


## Wire the ride, and only then gate the pad behind it.
##
## THE GATE IS ONLY TURNED ON IF THERE IS SOMETHING TO OPEN IT WITH. Without a
## lever, `requires_arming` would make the departure pad refuse forever and the
## base would be undeployable — which is worse than a pad you can walk onto
## before the train has moved. So the order here matters: no lever, no gate,
## and a warning saying the base is ungated rather than broken.
##
## The ride is a child of THIS level and not of the art. The art is TERRAIN's
## and is replaced wholesale on a rebuild; the ride's generated door leaf and
## tunnel plates are gameplay's and belong on gameplay's side of that line.
func _fit_ride(lever) -> void:
	if lever == null:
		push_warning("RailheadLevel: no lever, so the departure pad is NOT gated — you can walk out of a train that has not moved. Run tools/fit_ops_table.gd to get the lever back.")
		return
	if departure == null:
		push_warning("RailheadLevel: no departure pad wired, so there is nothing for the ride to arm and the train would travel to no purpose.")
		return
	for c in get_children():
		if c.get_script() == _DepartureRide:
			return   # already fitted; a level can be re-entered
	var ride = _DepartureRide.new()
	ride.name = "DepartureRide"
	ride.art = art
	ride.exit_to_arm = departure
	add_child(ride)
	# THE LEVER IS THE ONLY THING THAT STARTS IT. Not the table, not selecting
	# an operation: the commit is the throw.
	lever.thrown.connect(ride.begin)
	departure.requires_arming = true
	# The pad's chevrons and beacons are driven off this, and _refresh_live was
	# last run in the pad's own _ready — before the flag above existed. Without
	# this the pad stays LIT while refusing, which is the one combination that
	# reads as a bug rather than as a gate.
	if departure.has_method(&"disarm"):
		departure.disarm()


## A named node anywhere under the art. By name rather than by path because
## the art's internal structure is TERRAIN's and changes with the rake.
func _marker(named: String) -> Node3D:
	return _named_under(art, named) as Node3D


func _named_under(n: Node, named: String) -> Node:
	if n.name == named:
		return n
	for c in n.get_children():
		var f := _named_under(c, named)
		if f != null:
			return f
	return null


func _interactible_under(n: Node):
	for c in n.get_children():
		if c is Interactible:
			return c
		var f = _interactible_under(c)
		if f != null:
			return f
	return null


# ─────────────────────────────────────────────
# HOW FAR THE PLAYER ACTUALLY HAS TO WALK
# ─────────────────────────────────────────────

## Anything further than this from the operations table is more than a car and
## a half away. The rake is 32 m per car, so the station platform beside the
## next car along reads as 34 m and is fine; the old arrangement read 60 and 65.
## Previously 25, which fired on the correct new layout.
## Anything further than this from the operations table is not "across the
## room" any more. The depot is a train: 25 m is about two cars.
const FAR := 40.0


## CHECKED OUT LOUD, because this failure is completely silent.
##
## Every fitting in here is placed off a named marker in the art, so moving the
## art moves the gameplay with it — and that works. What it does not catch is a
## marker that STAYED BEHIND. The ops car can be rebuilt at one end of the
## train while the muster and the platform door keep the coordinates they had,
## and nothing is missing, nothing is in the air, nothing warns: the base just
## quietly becomes a long walk, and the only way to find out is to play it.
##
## It happened. After one rebuild the table sat at z -32 with the muster at
## -92 and the door at -96 — 60 and 65 metres, through five cars, between
## choosing an operation and leaving on it.
##
## tools/probe_railhead.gd prints every leg with its distance and is the thing
## to run when this fires.
func _audit_walk() -> void:
	var table := _marker(M_TABLE)
	if table == null:
		return   # _fit_ops_table has already said so, and loudly
	for pair in [[muster, "the squad muster"], [departure, "the way out"]]:
		var n = pair[0]
		if n == null or not (n is Node3D):
			continue
		var d: float = table.global_position.distance_to((n as Node3D).global_position)
		if d > FAR:
			push_warning("RailheadLevel: %s is %.0f m from the operations table, which is most of the train. Everything here is placed off a marker in the art, so a distance like this means that marker stayed behind when the table moved. Run tools/probe_railhead.gd for every leg." % [pair[1], d])
