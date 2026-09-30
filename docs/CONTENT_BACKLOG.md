# CONTENT BACKLOG — 400 ideas

Written for a morning review. Nothing here is built. Rankings are at the end
(§6); if you only read one section, read that one.

## How to read this

- **°** means it needs NEW CODE — a hook that does not exist yet. Everything
  without a ° can be authored today as a `.tres` plus a scene.
- **[n]** after a frame is its supply cost.
- Ideas are numbered 1–400 continuously so the count is checkable.

## The gaps, measured

This is what the catalogue actually contains today, which is what the ideas
below are shaped around.

**Frames (17, of which 6 are player-buyable).** Supply 1: soldier, chaser,
leaper, mechanic, marksman, spotter, gunship, rifleman, shotgunner. Supply 2:
rover, rover_gl, reclaimer, mortar_track, rifleman_armoured. Supply 3: walker.
**Supply 4, 5 and 6 are empty.** The walker at [3] shreds, and it is the top of
the ladder — there is nothing to want after it.

**Player handheld weapons: two.** The Ancient Rifle and the Mark One. Every
other weapon in the game is a turret or an AI mount. The shotgun and pistol were
removed from the player faction, which left the close-range slot empty and never
refilled it — there is currently nothing your squad can carry that wants to be
inside 20m.

**Modules can pull 13 levers**, and only 13: `health_bonus`, `accuracy_bonus`,
`damage_bonus`, `speed_multiplier`, `signal_bonus`, `sensor_bonus`,
`signal_resistance_bonus`, `self_revive_seconds`, `equipment_slot_bonus`,
`suppressive_fire`, `required_rank`, `requires_chassis`, `chassis_whitelist`.
Ten of those are "a number goes up". **That is why nothing currently redefines a
frame** — the system can only make things better, not different. Most of §5 is
proposals for new hooks, not new numbers.

**Roles with nothing in them:** artillery you own, transport, command/buff,
anti-air, fortification, breaching, ammunition resupply, stealth, shielding,
minelaying, and anything at all that occupies ground rather than crossing it.

---

# §1 · WEAPONS — PLAYER HANDHELD (1–60)

The triangle you set up is Ancient Rifle = medium, Mark One = cold. **Hot is
empty.** 1–12 are candidates for it; the rest widen the board.

## Hot — close, fast, unforgiving past 30m

1. **Scrapgun** — 22 dmg, very high cyclic, 18 mrad. Empties a magazine in ~3s. Loses past 40m, wins inside 15m. *The missing third point.*
2. **Hornet** — burst-fire machine pistol, 3-round bursts, tiny recoil, one-handed so it never blocks the sight picture.
3. **Coil Carbine** — no ammo type; charges between shots. Free to feed, punished for panic.
4. **Ancient SMG** — scavenged human, 9mm, 30 rounds, terrible accuracy, very cheap. The "you can afford this at minute one" hot gun.
5. **Cutter** — continuous beam, damage ramps the longer it stays on one target. Rewards not flinching.
6. **Slug Repeater** — pump-action single slug, 70 dmg, 0.9s cycle. The shotgun's damage without the pellet spread.
7. **Nailer** — pneumatic, silent, no muzzle flash, does not wake squads outside 20m.°
8. **Twin Bore** — two barrels, both fire at once, then a long reload. All-or-nothing.
9. **Riot Gun** — fires a wide low-damage cone that staggers rather than kills; sets up melee. °(stagger)
10. **Furnace Gun** — short-range incendiary, damage over time, no burst. Good against packs, useless on one target.
11. **Bolt Thrower** — silent, high damage, very slow, ammo is recoverable from corpses.°
12. **Handcannon** — 90 dmg, 6 rounds, brutal recoil walk. Rewards the new recoil system.

## Medium — the Ancient Rifle's neighbourhood

13. **Foundry Rifle** — AI-made copy of the Ancient Rifle. Slightly worse accuracy, half the price, infinite supply in the fiction.
14. **Ancient Carbine** — shorter, faster to bring up, less damage past 60m. *(exists as `carbine`, not in shop.)*
15. **Battle Rifle** — 7.62 semi-auto, 45 dmg, 20 rounds. Between the Rifle and the Mark One.
16. **Service Rifle** — 3-round burst only. Trades sustained fire for accuracy per trigger pull.
17. **Auto-Rifle** — the Ancient Rifle with a bipod: deadly prone/stationary, poor moving. °(stance)
18. **Marksman Rifle** — 10 rounds, 2× zoom, semi-auto. *(exists as `dmr`, not in shop.)*
19. **Conversion Rifle** — accepts any ammo type at an accuracy penalty. Logistics as a stat.°
20. **Rail Carbine** — hitscan through one body into the next. Rewards lining enemies up.°
21. **Sweeper** — rifle with a 5-round underslung buckshot tube on a second trigger.°
22. **Pattern Rifle** — its accuracy improves the longer you hold the same target. °(ramp)

## Cold — long, slow, deliberate

23. **Mark Two** — the Mark One with a 5-round magazine and a scope. The obvious upgrade path.
24. **Ancient Sniper** — 120 dmg, 5 rounds, punishing sway unless stationary.
25. **Anti-Materiel Rifle** — 200 dmg, penetrates armour and light vehicles, two-shot magazine.
26. **Long Nine** — breech-loaded single shot, 150 dmg, 2.5s reload. Every shot is a decision.
27. **Spotter's Rifle** — low damage, but a hit marks the target for the whole squad for 8s.°
28. **Ranging Rifle** — first shot on a target is weak; every subsequent hit on that same target is stronger.°
29. **Whisper** — suppressed sniper, does not break stealth or wake reserves.°
30. **Piercer** — ignores cover. Hits through the thin walls the levels are full of.°

## Support and specialist

31. **Ancient LMG** — 100 rounds, suppressive, must be set up before it is accurate.
32. **Squad Automatic** — the machine gun as a *carryable* weapon rather than a turret mount.
33. **Repair Lance** — the repair tool, weaponised: heals allies, damages enemies at half rate.
34. **Signal Jammer** — a held emitter that degrades enemy signal integrity in a cone.°
35. **Arc Projector** — chains between close targets. Made for the chaser swarms.°
36. **Shield Lance** — deployable frontal barrier on the player, blocks while stationary.°
37. **Welder Pike** — melee that repairs a squadmate on contact instead of hurting.
38. **Breaching Gun** — demolishes level geometry (gates, hesco, thin walls) and nothing else.°
39. **Grapnel** — pulls the player up ledges. Changes how every up-and-out map plays.°
40. **Scatter Launcher** — fires the hatchling canister as a direct-fire weapon.

## Thrown / launched (player)

41. **Ancient Grenade** — what `frag` is now, kept for the baseline.
42. **Thermite Stick** — burns through a vehicle's underside; useless against infantry.
43. **Smoke Canister** — breaks line of sight. *The single most missing item in the game.*
44. **Flashbang** — enemies inside it lose their target for 3s.°
45. **Sticky Charge** — adheres to a vehicle and detonates on a timer.
46. **Beacon Grenade** — a thrown point your squad advances on. Ordering without line of sight.°
47. **Decoy Emitter** — makes noise and a fake signal; enemies investigate it.°
48. **EMP Grenade** — what `emp` is now.
49. **Mine, Anti-Personnel** — placed, triggers on proximity.°
50. **Mine, Anti-Vehicle** — placed, only triggers on `vehicle` frames.°

## Exotics

51. **Nanite Cloud** — a thrown volume that slowly repairs allies standing in it.°
52. **Rust Gun** — does no damage but permanently reduces a target's max health.°
53. **Tether Gun** — links two enemies; damage to one bleeds to the other.°
54. **Gravity Well** — drags nearby light frames toward a point. Answers a chaser rush.°
55. **Siren** — a placed noisemaker that pulls every squad in earshot to it. Bait.°
56. **Overclock Injector** — a held tool that doubles one squadmate's speed for 10s.°
57. **Recall Unit** — teleports one downed squadmate to you.°
58. **Scrambler** — enemies within it cannot call reinforcements. *Counters the Watcher.*°
59. **Ammunition Printer** — a placed box your squad refills from.°
60. **Salvage Torch** — lets the player personally grind wrecks like a Reclaimer.°

---

# §2 · WEAPONS — AI INFANTRY MOUNTS (61–100)

Given to enemy frames, and to your squad through the armoury.

61. **Trooper Rifle** — the current `ai-wep_m4`, baseline.
62. **Trooper Carbine** — shorter reach, faster reaction time, for close maps.
63. **Heavy Trooper Rifle** — the armoured rifleman's gun, more damage, slower.
64. **Sustained-Fire Rifle** — long bursts, poor accuracy, high suppression value.
65. **Marksman Rifle (AI)** — exists; give it a visible laser so you can see who is aiming at you.°
66. **Counter-Sniper Rifle** — extreme range, very slow, only fires at stationary targets.°
67. **Squad LMG** — bipod, sets up, then pins a lane.
68. **Grenadier Rifle** — underslung launcher, arcs into cover.
69. **Shotgun (AI)** — exists.
70. **Auto-Shotgun** — the shotgunner as a genuine threat instead of a speed bump.
71. **Breacher Shotgun** — opens doors and gates; changes how enemies enter a fort.°
72. **Flamer** — area denial; forces the squad out of a held position.
73. **Arc Prod** — melee that disables rather than kills; downs without destroying.°
74. **Riot Shield + Pistol** — frontal immunity, must be flanked. °(directional armour)
75. **Twin SMG** — chaser upgrade: it can actually shoot now.
76. **Claws** — the current melee baseline.
77. **Heavy Claws** — slower, hits far harder, staggers.°
78. **Saw Arm** — continuous melee damage while in contact.
79. **Harpoon** — pulls a target toward the wielder.°
80. **Net Launcher** — immobilises one squadmate for 4s.°
81. **Signal Lance** — melee that strips signal integrity instead of health.
82. **Mortar (AI)** — exists.
83. **Light Mortar** — shorter range, much faster cycle, infantry-portable.
84. **Smoke Mortar** — denies you sight of an objective.°
85. **Incendiary Mortar** — area denial on a captured point.
86. **Rocket Tube** — single anti-vehicle shot, then a long reload.
87. **Guided Rocket** — tracks a vehicle; can be broken by cover.°
88. **Cluster Launcher** — one arc, several small blasts.
89. **Sentry Deployer** — an enemy that places turrets. Turns a garrison into a fortification.°
90. **Drone Carrier Pack** — hatches small drones like a mobile nest.
91. **Repair Gun (AI)** — the mechanic's welder, baseline.
92. **Shield Projector** — protects one other enemy at a time. Priority-target design.°
93. **Signal Amp** — boosts nearby enemies' accuracy. A buffer worth killing first.
94. **Jammer Pack** — degrades your squad's signal in a radius.
95. **Painter** — marks your squad for the mortar tracks.°
96. **Autocannon (AI)** — exists.
97. **Coax MG** — exists as a concept in `coax_weapon_id`; underused.
98. **Anti-Air Gun** — only engages the spotter and gunship. °(air targeting)
99. **Recoilless (AI)** — exists as `recoilless`.
100. **Siege Cannon** — very slow, very long range, demolishes cover.°

---

# §3 · FRAMES (101–180)

Supply in brackets. **Everything above [3] is new ground.**

## [1] — light, cheap, specialised

101. **Soldier** — exists, 50.
102. **Scout** — [1] fast, 40hp, huge sensor range, no weapon slot. Sees, does not fight.
103. **Sapper** — [1] carries demolition; the only frame that can breach walls.°
104. **Runner** — [1] very fast, unarmed, carries ammunition to the squad.°
105. **Picket** — [1] cheap, stationary, high sensor. A watcher you own.
106. **Sniper Frame** — [1] 50hp, accuracy 1.4, one weapon slot, no equipment.
107. **Medic** — [1] mechanic variant that revives at double speed and cannot repair.
108. **Hauler** — [1] +2 equipment slots for the squad's shared kit.
109. **Decoy** — [1] cheap, draws fire, worth nothing. Ablative.
110. **Jammer** — [1] mobile signal disruption. Counters the Watcher.
111. **Climber** — [1] can traverse steep ground the rest cannot. °(nav)
112. **Pack Mule** — [1] +1 module slot to every squadmate in its team.°
113. **Spotter** — exists, 180.
114. **Interceptor** — [1] fast, only engages light frames.
115. **Trencher** — [1] digs cover where it stands.°

## [2] — line units

116. **Rover** — exists, 150.
117. **Lobber Rover** — exists as `rover_gl`.
118. **Reclaimer** — exists, 130.
119. **Scout Car** — [2] fast wheeled, no turret, carries two passengers.°
120. **Gun Truck** — [2] open-topped, weapon slot usable by a rider.°
121. **Hunter** — [2] 120hp, anti-vehicle specialist, poor against infantry.
122. **Missile Rover** — [2] turret carries guided rockets only.
123. **Sentry Rover** — [2] deploys into a fixed turret and cannot move again until recovered.°
124. **Ambulance** — [2] recovers destroyed frames instead of repairing damaged ones.°
125. **Bunker Buster** — [2] short-range demolition vehicle.
126. **Signal Truck** — [2] extends the squad's command range; orders reach further.°
127. **Screen** — [2] deploys a physical barrier you and the squad can shelter behind.°
128. **Mine Layer** — [2] places anti-vehicle mines along a route.°
129. **Flak Rover** — [2] anti-air; the answer to bombers.°
130. **Recovery Rover** — [2] tows a stuck or destroyed vehicle out.°
131. **Armoured Trooper** — [2] exists as `rifleman_armoured`; make it player-buyable.
132. **Mortar Track** — [2] exists; make it player-buyable. *You have no artillery.*
133. **Shield Rover** — [2] projects cover for the squad while stationary.°
134. **Scrambler Truck** — [2] no enemy within its radius can call reinforcements.°
135. **Command Car** — [2] the player rides it; orders issue from it.°

## [3] — heavy

136. **Walker** — exists, 320. *You said it shreds; it is the ceiling and nothing sits above it.*
137. **Siege Walker** — [3] slower, two heavy mounts, cannot enter tight streets.
138. **Assault Walker** — [3] frontal armour, weak rear. Positional. °(directional)
139. **Engineer Walker** — [3] builds fortifications in the field.°
140. **Carrier** — [3] transports four infantry; they fight from inside.°
141. **Artillery Piece** — [3] cannot move once deployed; enormous range.°
142. **Breacher** — [3] exists to open walls and nothing else.
143. **Hive** — [3] a nest you own. Produces chasers over time.
144. **Bastion** — [3] deploys into cover the whole squad uses.°
145. **Repair Station** — [3] stationary; heals everything nearby continuously.°
146. **Flame Walker** — [3] area denial on legs.
147. **Radar Walker** — [3] reveals the whole map's enemy positions while alive.°
148. **Relay Walker** — [3] your own Watcher — calls in *your* reserves.°
149. **Gun Platform** — [3] four weapon slots, immobile.
150. **Sapper Walker** — [3] minelaying at scale.°

## [4] — the first real step up

151. **Heavy Walker** — [4] 500hp, three weapon slots, very slow.
152. **Siege Tank** — [4] cannot fire while moving; demolishes anything it hits.°
153. **Command Walker** — [4] every squadmate in its team gets +accuracy and +signal.°
154. **Carrier Walker** — [4] six infantry, deployable in the field.°
155. **Artillery Walker** — [4] mobile artillery; the mortar track grown up.
156. **Fortress** — [4] deploys once into a permanent strongpoint.°
157. **Foundry Walker** — [4] builds frames in the field from salvage.°
158. **Aegis** — [4] projects a shield over an area the squad holds.°
159. **Dreadnought** — [4] slow, 600hp, short range, terrifying up close.
160. **Ghost** — [4] invisible to enemy sensors until it fires.°

## [5] — army-defining

161. **Land Battleship** — [5] four turrets, crewed by your own squad.°
162. **Mobile Base** — [5] a forward armoury; refit mid-mission.°
163. **Siege Engine** — [5] reduces a fort to rubble over a minute.°
164. **Titan** — [5] 900hp, walks over terrain the rest must go around.°
165. **Carrier Mother** — [5] launches and recovers drones continuously.°
166. **Storm Battery** — [5] saturation artillery; one order, a whole grid square.°
167. **Command Bastion** — [5] the squad's orders originate here; killing it blinds you.°
168. **Reclamation Rig** — [5] converts wrecks into resources during the mission.°
169. **Shield Generator** — [5] blanket protection, enormous supply cost.°
170. **Excavator** — [5] reshapes terrain to make a route.°

## [6] — one per campaign

171. **Leviathan** — [6] the whole squad's supply on one frame. All or nothing.
172. **Arsenal** — [6] carries and switches between every weapon you own.°
173. **The Foundry** — [6] builds a new frame every 60s for the rest of the mission.°
174. **Warmind** — [6] you possess it directly; the squad becomes its limbs.°
175. **Siege Crawler** — [6] slow enough to be a plan rather than a unit.°
176. **Ark** — [6] the squad deploys *from* it, anywhere on the map.°
177. **Null Field** — [6] no signal, no reinforcements, no calls, in a huge radius.°
178. **Colossus** — [6] 1500hp. A mission is "escort it" or "stop it".°
179. **Gravemaker** — [6] every wreck on the map becomes yours.°
180. **The Quiet** — [6] unarmed; while alive, no enemy on the map can be reinforced.°

---

# §4 · EQUIPMENT (181–290)

Consumables and gadgets. The ones that **redefine a frame** are marked ★.

## Offensive

181. **Frag** — exists.
182. **EMP** — exists.
183. **Hatchling Canister** — exists.
184. **Thermite** — burns vehicles, ignores infantry.
185. **Sticky Charge** — timed, adheres.
186. **Shaped Charge** — directional, anti-armour.
187. **Cluster Pod** — several small blasts.
188. **Incendiary Pot** — area denial.
189. ★ **Bombardment Marker** — any frame carrying it can call one artillery strike. *Turns any unit into a forward observer.*°
190. ★ **Launch Rack** — a non-turret frame gains one rocket. *Gives infantry an anti-vehicle answer.*°
191. **Drone Swarm** — three tiny attackers for 20s.°
192. **Tripwire Charge** — placed, triggered by the first enemy through.°
193. **Detonator Pack** — every charge the squad has placed, at once.°
194. **Gas Pot** — denies a room rather than a field.°
195. **Shrapnel Mine** — cheap, anti-infantry only.°

## Defensive and sustain

196. **Repair Kit** — exists.
197. **Repair Tool** — exists.
198. **Nanite Pack** — heals over time instead of at once.
199. ★ **Field Rebuild Kit** — recovers a DESTROYED frame once per mission. *Changes what losing a robot means.*°
200. **Smoke Canister** — breaks line of sight.
201. **Smoke Launcher** — vehicle-mounted, covers the whole squad.°
202. ★ **Deployable Cover** — a placed barrier. *Any frame becomes able to hold open ground.*°
203. ★ **Entrenching Tool** — digs a fighting position where it stands. *Turns a mobile frame into a garrison.*°
204. **Signal Booster** — restores signal integrity in the field.
205. **Decoy Beacon** — pulls fire for 10s.°
206. **Ablative Plates** — one-use: absorbs a single killing blow.°
207. **Shield Pack** — regenerating overshield while not taking fire.°
208. **Coolant Pack** — clears overheating; pairs with beam weapons.°
209. **Emergency Thrusters** — one long leap, any frame.°
210. **Recovery Winch** — pulls a stuck frame free. *Answers the rover getting wedged.*°

## Vision and information

211. **Scanner** — exists.
212. **Optics Pod** — temporary sensor boost.
213. ★ **Periscope** — see over cover without leaving it. °
214. **Thermal Sight** — sees through smoke.°
215. **Motion Tracker** — shows moving enemies through walls, briefly.°
216. ★ **Uplink Mast** — while placed, the whole map's enemy reserves are visible. *Turns one frame into intelligence.*°
217. **Sound Ranging Kit** — locates any enemy that fires. *Uses the audio bands you already have.*°
218. **Target Painter** — marks one enemy for the squad.°
219. **Recon Drone** — a flyable scout you control for 15s.°
220. **Map Relay** — shares one frame's vision with the whole squad.°

## Command and squad
221. ★ **Order Relay** — extends command range hugely. *Lets you split the squad across a map.*°
222. **Rally Banner** — placed; squadmates fall back to it when hurt.°
223. **Advance Beacon** — a thrown point to order onto.°
224. **Formation Kit** — tightens or spreads the squad's spacing.°
225. ★ **Autonomy Core** — the frame acts on its own objectives without orders. *Removes it from your management entirely.*°
226. **Watchdog Protocol** — holds fire until you do.°
227. **Overwatch Kit** — covers a chosen arc rather than following.°
228. **Escort Protocol** — locks one frame to protecting another.°
229. **Last Stand Protocol** — on death, detonates.°
230. **Salvage Orders** — the frame prioritises wrecks over enemies.°

## Mobility
231. **Overclock Injector** — burst of speed.
232. **Grapnel** — vertical movement.°
233. **Jump Jets** — one leap, high.°
234. **Ram Plate** — damages what it drives into.°
235. ★ **Amphibious Kit** — crosses water. *Every river in every level stops being a wall.*°
236. **Tow Cable** — drags a wreck or a stuck ally.°
237. **Climbing Gear** — steeper ground becomes passable.°
238. **Silent Running** — halves detection range while moving slowly.°
239. **Burst Thrusters** — dodge sideways.°
240. **Bridging Kit** — places a crossing over a gap.°

## Logistics
241. ★ **Ammunition Box** — placed; the squad rearms from it. *Makes sustained fights possible.*°
242. **Field Armoury** — swap one weapon mid-mission.°
243. **Fuel Cell** — extends any vehicle's operating time.°
244. **Salvage Claw** — grind wrecks at half a Reclaimer's rate.°
245. **Supply Drop Marker** — calls one crate of your choosing.°
246. **Spare Parts** — one free self-repair.°
247. **Scavenger Kit** — recovers weapons from enemy wrecks.°
248. **Compute Siphon** — drains compute from captured objectives faster.°
249. **Cargo Frame** — carries another frame's equipment for it.°
250. **Requisition Chit** — one free mid-mission purchase.°

## Denial and control
251. **Signal Jammer** — area signal degradation.
252. ★ **Scrambler** — *no enemy in radius can call reinforcements. The direct counter to the Watcher.*°
253. **Minefield Kit** — several mines at once.°
254. **Razor Wire** — slows infantry through it.°
255. **Tanglefoot** — immobilises light frames.°
256. **Siren** — pulls enemies toward a point.°
257. **False Signal** — spawns a fake contact on their sensors.°
258. **Blackout Charge** — disables enemy sensors in a radius for 10s.°
259. **Lockdown Field** — nothing enters or leaves a radius.°
260. **Null Pulse** — cancels one incoming artillery strike.°

## Frame-redefining ★ (the brief's actual ask)
261. ★ **Turret Conversion** — a non-turret frame gains a 360° mount.°
262. ★ **Second Mount** — +1 weapon slot on anything.°
263. ★ **Passenger Rack** — a vehicle carries two infantry.°
264. ★ **Garrison Kit** — the frame stops following and holds ground permanently.°
265. ★ **Artillery Conversion** — any weapon fires indirect.°
266. ★ **Drone Bay** — any frame hatches drones like a nest.°
267. ★ **Welder Arm** — any frame can repair.°
268. ★ **Salvage Rig** — any frame becomes a Reclaimer.°
269. ★ **Command Antenna** — any frame becomes the squad's order origin.°
270. ★ **Sensor Mast** — any frame becomes a Spotter.°
271. ★ **Shield Emitter** — any frame projects cover.°
272. ★ **Breaching Ram** — any frame can open walls.°
273. ★ **Medical Bay** — any frame revives the downed.°
274. ★ **Bomb Rack** — any frame drops the quadcopter's bomb.°
275. ★ **Relay Core** — any frame calls *your* reserves, like a Watcher in reverse.°

## Miscellaneous
276. **Rope Kit** — descend a cliff without damage.°
277. **Flare** — lights an area at night.°
278. **Signal Mirror** — silent order to one squadmate.°
279. **Camouflage Net** — stationary frames are not detected.°
280. **Sandbags** — placed, low cover.°
281. **Barricade** — placed, blocks a street.°
282. **Ladder** — lets infantry up one level of geometry.°
283. **Zipline** — one-way fast descent.°
284. **Pontoon** — a crossing for one vehicle.°
285. **Winch Anchor** — self-recovery from a pit. *Answers the rover problem directly.*°
286. **Tow Bar** — one vehicle pulls another.°
287. **Spare Track** — repairs a mobility kill.°
288. **Blast Shield** — immunity to one explosion.°
289. **Fire Suppression** — clears burning.°
290. **Emergency Beacon** — a downed frame calls the squad to it.°

---

# §5 · MODULES (291–400)

Passive, refundable, returned to the pool on death. **Ten of the thirteen
existing hooks are "a number goes up" — the interesting ones below need new
code, and that is the point.**

## Existing-hook modules (buildable today)

291. **Armor Plating** — exists.
292. **Optics** — exists.
293. **Overclock Servos** — exists.
294. **Hardened Uplink** — exists.
295. **Nanite Reboot** — exists.
296. **Utility Harness** — exists.
297. **Cyclic Feed** — exists.
298. **Heavy Plating** — more health, less speed.
299. **Light Frame** — less health, more speed.
300. **Long Optics** — accuracy and sensor range, no health.
301. **Marksman Barrel** — accuracy only, large.
302. **Sensor Array** — sensor range only.
303. **Signal Shielding** — signal resistance.
304. **Redundant Core** — self-revive, slow.
305. **Fast Reboot** — self-revive, quick, once.
306. **Second Harness** — another equipment slot.
307. **Suppressor Kit** — grants suppressive fire.
308. **Veteran Plate** — health, requires rank 2.
309. **Match Barrel** — accuracy, requires rank 3.
310. **Vehicle Plating** — health, vehicles only (`requires_chassis`).
311. **Infantry Webbing** — equipment slot, infantry only.
312. **Turret Stabiliser** — accuracy, turret frames only.
313. **Reinforced Legs** — speed, walker only.
314. **Gunner's Sight** — accuracy, weapon-slot frames only.
315. **Scout Package** — speed and sensors, health penalty.

## New-hook modules — defence

316. ★ **Directional Armour** — frontal immunity, weak rear. *Positioning becomes a stat.*°
317. **Reactive Plates** — first hit each engagement does nothing.°
318. **Spall Liner** — halves explosion damage.°
319. **Ablative Skin** — absorbs damage, degrades permanently.°
320. **Self-Sealing** — regenerates to a threshold out of combat.°
321. **Crumple Zones** — survives a killing blow at 1hp, once.°
322. **Blast Baffles** — immune to its own explosions.°
323. **Fireproofing** — immune to incendiary.°
324. **EMP Hardening** — immune to signal weapons.°
325. **Redundant Limbs** — cannot be mobility-killed.°

## New-hook modules — offence

326. **Armour Piercing** — damage against vehicles only.°
327. **Hollow Point** — damage against infantry only.°
328. **Stabiliser** — no accuracy penalty while moving.°
329. **Auto-Loader** — halves reload time.°
330. **Extended Magazine** — more rounds per magazine.°
331. **Target Lead** — the AI leads moving targets properly.°
332. **Rangefinder** — no damage falloff.°
333. **Overcharge** — more damage, takes self-damage.°
334. **Twin Link** — fires two weapons at once on a two-slot frame.°
335. **Tracer Rounds** — allies gain accuracy against what it shoots.°
336. **Penetrator** — shots pass through one body.°
337. **Burst Governor** — converts automatic fire to bursts, more accurate.°
338. **Recoil Damper** — halves the recoil walk.°
339. **Barrel Shroud** — sustained fire without accuracy loss.°
340. **Match Ammunition** — accuracy, costs resources per mission.°

## New-hook modules — perception and command

341. ★ **Threat Library** — the frame identifies and calls out enemy types on sight. *Information as an upgrade.*°
342. **Sound Ranging** — locates any enemy that fires. *Built on the audio bands.*°
343. **Counter-Battery** — reveals mortars and artillery that fire.°
344. **Shared Sight** — its vision is the squad's vision.°
345. **Thermal Core** — sees through smoke.°
346. **Signal Triangulation** — reveals anything transmitting. *Finds Watchers.*°
347. **Command Repeater** — extends order range for its team.°
348. **Initiative Core** — acts before the rest of the squad on contact.°
349. **Veteran Protocols** — gains accuracy for each mission survived.°
350. **Pack Instinct** — accuracy scales with nearby allies.°

## New-hook modules — behaviour (the real "redefines the frame" territory)

351. ★ **Aggression Core** — never takes cover; always closes. *Turns a line trooper into a chaser.*°
352. ★ **Caution Core** — never leaves cover; holds and shoots. *Turns anything into a garrison.*°
353. ★ **Overwatch Core** — holds fire until an enemy enters a chosen arc.°
354. ★ **Escort Core** — protects the nearest damaged ally instead of fighting.°
355. ★ **Hunter Core** — ignores all targets except vehicles.°
356. ★ **Executioner Core** — ignores everything except the downed.°
357. ★ **Scavenger Core** — breaks off to grind wrecks. *A soldier that funds the squad.*°
358. ★ **Sentinel Core** — will not follow; holds its ground for the mission.°
359. ★ **Swarm Core** — always moves toward the nearest ally. Packs of cheap frames.°
360. ★ **Lone Core** — accuracy improves the further it is from allies.°
361. **Last Stand Core** — detonates on death.°
362. **Retreat Core** — falls back to the squad below 30% health.°
363. **Relentless Core** — cannot be suppressed.°
364. **Silent Core** — does not wake reserves.°
365. **Bait Core** — actively draws fire.°

## New-hook modules — economy and logistics

366. **Salvage Processor** — grinds wrecks passively while walking past.°
367. **Compute Core** — generates compute over a mission.°
368. **Efficient Frame** — costs one less supply. *Directly changes the squad size.*°
369. **Requisition Core** — returns full value when sold.°
370. **Field Repair** — repairs itself between missions for free.°
371. **Ammunition Store** — the squad rearms from it.°
372. **Cheap Build** — halves the frame's cost, halves its health.°
373. **Veteran Frame** — gains XP at double rate.°
374. **Trainer Core** — nearby allies gain XP faster.°
375. **Insurance Core** — if destroyed, refunds its cost.°

## New-hook modules — mobility

376. **All-Terrain Kit** — steep ground is passable. *Answers the rover in pits.*°
377. **Amphibious Kit** — crosses water.°
378. **Climbing Servos** — raises `step_height` sharply.°
379. **Low Profile** — fits through gaps others cannot.°
380. **Stabilised Suspension** — no speed loss cornering.°
381. **Sprint Core** — double speed when not in combat.°
382. **Silent Servos** — halves the distance it can be heard.°
383. **Jump Core** — a leap, on any frame.°
384. **Hover Kit** — ignores ground entirely.°
385. **Anchor Kit** — cannot be shoved or pushed.°

## New-hook modules — support

386. **Repair Aura** — heals nearby allies slowly.°
387. **Shield Aura** — nearby allies take less damage.°
388. **Signal Aura** — nearby allies resist signal damage.°
389. **Accuracy Aura** — nearby allies shoot better.°
390. **Speed Aura** — nearby allies move faster.°
391. **Revive Aura** — the downed nearby get up on their own.°
392. **Supply Aura** — nearby allies do not run out of ammunition.°
393. **Fear Aura** — nearby enemies are less accurate.°
394. **Jam Aura** — nearby enemies cannot be reinforced.°
395. **Sensor Aura** — nearby allies see further.°

## New-hook modules — wildcards

396. ★ **Possession Core** — you can take direct control of this frame. *You already have possession code.*°
397. ★ **Split Core** — on death, becomes two weaker frames.°
398. ★ **Mimic Core** — copies the loadout of the last enemy it killed.°
399. ★ **Overload Core** — double everything for 20s, then it dies.°
400. ★ **Legacy Core** — when it dies, its modules transfer to the nearest ally.°

---

*Rankings continue in §6.*

---

# §6 · REVIEW AND RANKING

## What writing 400 of these revealed

**The module system can only make numbers bigger.** Ten of its thirteen hooks
are a stat going up. That is the whole reason nothing in the game currently
"redefines a frame" — the system cannot express *different*, only *more*. Every
genuinely interesting module in §5 needed a new hook, and most of them needed
the *same* new hook.

**One field unlocks about fifteen ideas.** A `behaviour_override` on
ItemDefinition — read once by `Soldier` at spawn to swap which movement and
combat options the frame rolls — gives you the entire Behaviour Cores block
(351–365). Aggression, Caution, Overwatch, Hunter, Scavenger, Sentinel. The
machinery is already there: `AllowedMovementOptions`, `AllowedCombatOptions`,
`aggressive`, `defensive_mode` are all fields on `Enemy` that the nest and the
watcher already clear and set at `_ready()`. **This is the single highest
leverage change in the document.**

**Supply 4–6 is not just empty, it is the reason the ladder stops.** The Walker
at [3] is the last thing to want. Anything at [4]+ has to be worth more than two
Walkers, which forces real design rather than bigger numbers.

**Several of these are fixes for things you have already hit.** All-Terrain Kit
and Winch Anchor are the rover in a pit. Scrambler is the Watcher counter.
Sound Ranging is the audio-band work made actionable. Amphibious Kit means every
river stops being a wall.

## The ten I would build first

Ranked by (what it fixes) × (how little it costs):

1. **#43 Smoke Canister** — the single most missing item in the game. No code: it is a thrown volume that blocks line of sight. Fixes the Hillfort climb, every open approach, and gives a non-lethal answer to the Watcher.
2. **#1 Scrapgun** — the empty third point of your weapon triangle. Authorable today. Your squad currently has nothing that wants to be inside 20m.
3. **Behaviour cores (#351–365)** — one new field, fifteen items, and the first content that actually changes what a frame *is*.
4. **#132 Mortar Track, player-buyable** — already exists as an enemy frame. You have no artillery. This is a `purchasable = true` and a price.
5. **#131 Armoured Trooper, player-buyable** — same: already built, already balanced, one flag.
6. **#376 All-Terrain Kit** — the rover-in-a-pit complaint as a purchasable decision rather than a bug report.
7. **#202 Deployable Cover** — turns any frame into one that can hold open ground. The maps are full of ground with nothing to hide behind.
8. **#252 Scrambler** — the Watcher is about to become the most annoying thing in the game; it should have an answer you can buy.
9. **#241 Ammunition Box** — makes long fights possible instead of a slow decline.
10. **#151 Heavy Walker [4]** — one frame above the ceiling, so there is something to save for.

## Best in each category

- **Best player weapon:** #1 Scrapgun. Runner-up #23 Mark Two — the obvious upgrade path from a gun you already like.
- **Best AI weapon:** #89 Sentry Deployer. An enemy that fortifies changes what a garrison means; everything else on that list is a different damage number.
- **Best [1] frame:** #103 Sapper. A frame that opens walls changes the shape of every level without TERRAIN touching a thing.
- **Best [2] frame:** #134 Scrambler Truck, closely followed by #129 Flak Rover once bombers matter.
- **Best [3] frame:** #140 Carrier. Infantry that arrive where you choose is a different game.
- **Best [4]:** #153 Command Walker. Supply cost that buys the *squad* something.
- **Best [5]:** #162 Mobile Base. Refitting mid-mission changes the whole loop.
- **Best [6]:** #180 The Quiet. Unarmed, and it turns off the enemy's entire reinforcement system. The most interesting thing in the document.
- **Best equipment:** #199 Field Rebuild Kit. It changes what losing a robot *means*, which is the emotional core of a squad game.
- **Best module:** #316 Directional Armour. Makes positioning a stat.
- **Best wildcard:** #396 Possession Core — you already have possession code; this makes it a purchase.

## What I would cut

- **Most of the auras (#386–395).** Ten items, one idea, and stacking auras is a balance tar pit.
- **The [5] and [6] tiers beyond two or three picks.** They are fun to write and each is a month of work. Pick one as a campaign capstone and drop the rest.
- **#52 Rust Gun, #53 Tether Gun, #54 Gravity Well** — clever, but they need systems (permanent max-health loss, damage linking, physics pulls) that exist nowhere and serve one item each.
- **Weapon variants that are only a damage number** — #62, #63, #83, #88 and similar. Fold them into existing guns as modules instead.

## Build order

**Phase 1 — no new code.** Smoke, Scrapgun, Mark Two, player-buyable Mortar
Track and Armoured Trooper, and the existing-hook modules 298–315. That is
roughly twenty items from `.tres` files and two new scenes, and it doubles the
player's options.

**Phase 2 — one hook each, highest leverage first.** `behaviour_override`
(fifteen items), then deployable objects (cover, ammunition, mines — one
placement system, about twelve items), then directional armour.

**Phase 3 — the supply ladder.** Heavy Walker [4], Carrier [3], Command Walker
[4]. This is where armour needs to exist, so it lands after Phase 2.

**Phase 4 — one capstone.** The Quiet, or Mobile Base. One, not both.

## Honest caveat

Roughly 300 of the 400 are marked °, which means they need code that does not
exist. That ratio is not padding — it is the finding. The catalogue is not short
of *items*, it is short of *verbs*. Phase 1 is the only part of this document
you can act on without writing new systems, and it is deliberately the part I
ranked first.
