# MARKETING — session reports

**Only the MARKETING agent writes this file.** The coordinator reads it and folds
it into `docs/BOARD.md`. Nobody else touches it, which is why two lanes can
close a session at the same moment and never conflict.

**Append a new entry at the TOP, under this header.** Newest first. Keep old
entries — the point of this file is that the board has a memory.

Template — copy it, keep the four headings, delete what does not apply:

```
## YYYY-MM-DD — one line on what this session was about

**Landed.** What is different now, in plain terms. Not "worked on the depot" —
say what changed and where. Name the files you touched if it is not obvious.

**Gates.** check.sh: PASS/FAIL. test.sh and smoke.sh if you ran them, and what
they said. If you did not run one, say so rather than leaving it blank.

**Needs the human.** Anything to verify in-editor — scene wiring, inspector
values, a look at the thing in-game. This is the most valuable line in the
report; it is the one that used to die in chat scrollback.

**Blocked / next.** What you would do next, and anything stopping you.
```

Two things worth saying out loud, because they are the reports the coordinator
most wants and least often gets:

- **Say when something is unverified.** "Built it, did not run it" is a useful
  report. "Done" when it was never launched is not.
- **Say when you were wrong.** A reversal recorded here saves the next agent
  from repeating it. A claim made about the game that turned out not to be in
  the build is exactly that kind of thing.

---

## 2026-10-06 — paste-ready HTML for the itch profile and the project page

**Landed.** Two fragments, both paste-ready, both verified rendering in a browser.

- **`docs/marketing/itch_profile.html`** — the user profile bio. Short: who you
  are, what the game is, Godot, one link. Two bracketed placeholders.
- **`docs/marketing/itch_page.html`** — the project page description, built from
  `PITCH.md`'s one-page structure: tagline, the opening paragraph, the
  "Something points you" card, then Compute is capacity / The squad is the only
  thing you chose / They come back / Two health bars / Places, not a place.
  Plus a Feedback section and a **Before you run it** section carrying the
  SmartScreen instruction and the keep-the-folder-together warning.

**"Profile" was ambiguous** — it could mean the user profile or the project page,
and the session has been about the latter while the word points at the former. I
wrote both rather than ask, since both are short and guessing wrong would have
cost a round trip.

**No CSS, deliberately, and this is the load-bearing decision.** itch sanitizes
HTML in descriptions and **strips any class not prefixed `custom-`**, so a styled
block arrives as a mess. Everything in both files is semantic tags only —
`h2`, `p`, `ul`, `blockquote`, `strong`, `em`, `code`, `hr` — which itch themes
itself and no sanitiser can break. Checked rather than assumed; the custom-class
rule is in itch's own CSS guide.

**Three sections are deliberately blank**, marked `FILL THIS IN` with guidance
and an example shape in the comment: what is in this build, controls, known
issues. These are the three I flagged last session as the human's own. The
controls one specifically says **do not guess** and points at
`Character/hud/lesson_prompts.gd`, which already renders readable key names at
runtime, so reading them off the in-game prompts is the cheap route. Rendered,
the blanks show as bare headings, which is a visible reminder not to publish with
them empty.

**Gates.** `check.sh --changed`: **PASS**. HTML and Markdown only. Also opened
both files in a browser and read the rendered text back: headings, lists,
blockquote and entities all resolve, and the commented sections correctly do not
render.

**Needs the human.** The same three blanks, plus the two bracketed links in the
profile file. Nothing new.

**Blocked / next.** Unchanged from last session: the page can go up now with the
`environments/` frames as the gallery; the reshoot at 1920×1080 upgrades it
rather than gating it, and the revive video for the GIF is still the one missing
asset with no substitute.

## 2026-10-01 (sixth pass) — the cover, and an honest look at the first shot set

**Landed.**

- **`brand/itch_cover_630x500.png`** — the itch cover. Built from
  `environments/mutaha_wip_14_quarter_street.png` (cropped, knocked back, gradient
  bands top and bottom) with the title lockup over it. Checked at **315×250**,
  which is the only size that matters, by generating the downscale: the title
  stays legible and the street still reads. A flat logo-and-squad fallback sits
  beside it.
- **`SHOT_BRIEF.md` Revision 2** — what went wrong with the first set and what to
  change.
- **`ITCH_SETUP.md` §13** — the full "what else do you need" checklist.

**The shot set, honestly.** The brief was followed: all five, both HUD passes,
named correctly. The brief was the problem.

- **One objective failure: every file is 1152×648.** The brief asked 2560×1440.
  That is **below Steam's 1920×1080 minimum**, so as taken they cannot go on a
  Steam page at all. Looks like the capture grabs the window rather than
  rendering to a fixed-size SubViewport. Nothing else matters until that changes.
- **Four things my brief failed to say**, and the human was right to be
  unhappy: I wrote "time of day as authored", and what came back is bright midday
  under a clear blue sky — the most off-tone thing possible for this game. I never
  said the subject must be unoccluded (a wall fills 60% of shot 01; the capsules
  in shot 03 are behind a parapet with only their domes showing), never said it
  must fill a share of the frame, and never said the *action* must be happening
  — shot 03 is two robots standing, not a revive.
- **The `environments/` set is far better and solves exactly those problems.**
  Dark, cold, composed. `mutaha_wip_14_quarter_street.png` is the best image in
  the project and is now the cover. So the tone is clearly achievable by the same
  person; my brief simply did not ask for it.
  `pittsburgh_03_the_whole_valley.png` is unusable — a high-altitude top-down that
  reads as a debug map, with the terrain edge and void visible along the top.

**Where I was wrong.** The standing orders give a worked example of a good ask
versus a bad one, and I wrote a brief that named places and framing but left
light, occlusion, subject size and whether the action was happening to be
inferred. A brief that can be followed exactly and still produce the wrong
picture is a bad brief. Revision 2 fixes those four and makes resolution
non-negotiable.

**Gates.** `check.sh --changed`: **PASS**. Markdown and PNGs.

**Needs the human.**

1. **Three blanks only you can fill** for the page body: what is in this build
   (mission count, rough length, what is absent), known issues, and the controls.
   The actions are in `project.godot` but I have not guessed keys — a wrong
   controls list is worse than none, and `lesson_prompts.gd` already renders them
   readably at runtime, so screenshotting that is the cheap route.
2. **Send Revision 2** for the reshoot. If only one shot is redone, make it the
   Mechanic revive — it is the gallery GIF and the current set misses it entirely.
3. **6–8 s of video of the revive.** Nothing to cut a GIF from today.
4. rcedit; the WeaponMount mismatch; delete the old builds in `..\Exports`.

**Blocked / next.** The page can go up now with the `environments/` frames as the
gallery — cover, logo, avatar, tagline, description, tags and the build are all
ready. The reshoot upgrades it rather than gating it.

## 2026-10-01 (fifth pass) — the shot brief, the logo, and the DS-Digital ruling

**Landed.**

- **`docs/marketing/SHOT_BRIEF.md`** — a standalone, sendable brief for the five
  itch screenshots. One shot per level, with **real node names** pulled out of the
  level scenes so whoever shoots it can select them in the editor rather than
  guess: `Coast_Hill`/`Coast_Bridge`, `Mutaha_CrossWest`/`Mutaha_CorePlaza`/
  `Mutaha_Compute`, `Basin_Anchor`/`Basin_GarrisonW`, `Pitt_Bridgehead`/
  `HiveBridge`/`Pitt_Point`, `ChassisBays`/`DummyTerminal`. Plus the technical
  spec, the do-not-shoot list from CLAIMS, and two blockers.
- **`docs/marketing/brand/logo_dcw2109_*.png`** — the title lockup, in three
  variants (on near-black, transparent, white-on-transparent), 1854×545.

**The logo is the title screen, not an invention.** Read the layout out of
`Managers/master.gd`: `_play_card` draws the headline at size 64 in
`HUDPalette.BRIGHT` over the suffix at size 40 in `WARN`. So the lockup is
`DATA CENTER WARS` in `Color(0.62,0.95,0.66)` above `2109` in
`Color(0.95,0.78,0.35)`, same 64:40 ratio, in DS-DIGII — the project's own
`theme/custom_font`. It matches what a player sees on boot.

One rendering note worth keeping: DS-Digital's space glyph measures near-zero
through GDI+, so the first render came out `DATACENTERWARS`. Spaces are given an
explicit advance now.

**A blocker found while writing the brief, and it would have hit the hero shot.**
`soldier_chassis.tscn`'s `WeaponMount` is scaled **0.4**; `mechanic_chassis.tscn`'s
is still **0.25**. The board's record blocker says all the infantry mounts want
the same new value. Shot 3 is the Mechanic standing a downed soldier back up —
both in one frame, which is exactly where a mismatch shows. It may be deliberate,
since the Mechanic's mount holds a welder rather than a rifle, so the brief asks
for it to be checked in-editor rather than asserting a bug.

**Also verified while there:** the spotter blocker looks addressed —
`spotter_drone.gd` now keys its parked state off the campaign's `in_mission`,
with a comment matching the fix the board asked for. Not run, so not confirmed
behaving.

**DS-Digital — ruled by the human, 2026-10-01.** I had this on the open list
three passes running. The human checked: the licence is shareware asking $45 for
commercial use, and both contact routes in `DIGITAL.TXT` are long dead —
`ds-font.hypermart.net` and a `mailcity.com` address, a 1998 font. **Ruled:
ignore it going forward.** Removed from the needs-the-human list and will not be
raised again. Recording it here because a ruling that is written down stops the
next agent re-raising it.

**Gates.** `check.sh --changed`: **PASS**. Markdown and PNGs only this pass.

**Needs the human.**

1. **Send the brief** — dispatch is draft-only. `SHOT_BRIEF.md` is written to go
   as-is to GAMEPLAY.
2. **The WeaponMount mismatch** — one value, and it decides whether the best shot
   in the set is usable.
3. **rcedit**, still the highest-value five minutes available: it fixes the exe
   icon and the three version strings together.
4. Carried over: old builds in the Exports folder, `config/name="Roboto"`,
   sound-pack licences, asset provenance for the AI disclosure, salvage, rain,
   GDD §7 recruitment row.

**Blocked / next.** Marketing's remaining asset is the itch **cover image** at
630×500, which wants shot 1 to exist first — it has to read at 315×250, so it is
a recompose rather than a crop. Everything else for the page is written.

## 2026-10-01 (fourth pass) — the export button already existed and was switched off

**Landed.** Asked for a native Godot export the human could run themselves. It
was already built, in September, and it is better than the headless invocations I
had been running by hand. It was simply never enabled, so nobody could see it.

- `tools/export.ps1` — 9 KB, the whole pipeline, carefully written and documented
  at the top. Version bump, release export, `build_info.txt` with the git commit,
  zip, open folder. Fails safe: a failed export restores `build_version.gd` and
  removes the half-made folder, so a bad run never burns a version number.
- `tools/export_build.bat` — double-click wrapper.
- `addons/export_build/plugin.gd` — editor toolbar button that saves open scenes
  first, then runs the bat.
- **The missing piece: `project.godot` did not list the plugin as enabled.** One
  line. Now enabled, and that is the entire change.

**`docs/marketing/ITCH_SETUP.md`** — new §12 documenting it; **§7c rewritten**,
because my hand-rolled zip command was now stale and wrong. The upload step is
simply "press the button, upload the zip it made". §7d's butler path updated to
the versioned folder.

**Gates.** `check.sh --changed`: **PASS**. `smoke.sh`: **PASS** (booted clean,
15 s, 3 warnings) — run because `project.godot` loads at startup, even though an
`EditorPlugin` only affects the editor.

**Verified, not assumed.** Ran `tools\export.ps1 -DryRun`: it found Godot, found
the 4.3 templates, read `build_version.gd`, scanned `../Exports` and computed
`0.008a`. **I did not run it for real on purpose** — that would consume v0.008a
and write to `Managers/build_version.gd`, which is GAMEPLAY's path, and the point
of the ask was that the human pulls the build rather than me. Both halves are
separately proven: the dry run covers version logic and tool discovery, the raw
headless export covers the export itself.

**Worth correcting from an earlier pass.** The script passes an explicit output
path to Godot, so it ignores the preset's `export_path` entirely — meaning the
`2019` filename bug I found and fixed **only ever affected the editor's own
Export dialog**, never the one-button path. The fix stands, because that dialog
is a route someone will take, but I implied it was on the critical path for the
playtest build and it was not.

**Shared file touched.** `project.godot` is on the board's shared list. Backed up
to the session scratchpad first, one line changed, both gates green. Second file
this lane has touched outside `docs/marketing/**`, both on direct instruction.

**Needs the human.**

1. **Press "Export build"** in the editor toolbar and confirm the button appears
   and the run completes. The plugin is enabled in the project file but the editor
   has to be restarted or the plugin toggled for the button to show.
2. **rcedit is still unset** — until it is, every build carries the Godot Engine
   icon and `Godot Engine` in its file properties, whichever route made it. §11.
3. **Commit `Managers/build_version.gd` with each build** so a reported version
   maps to a commit.
4. Carried over: old builds in the Exports folder, `config/name="Roboto"`,
   DS-Digital licence, sound-pack licences, asset provenance, salvage, rain,
   GDD §7.

**Blocked / next.** Nothing blocking. The whole chain is now: press the button,
upload the zip, tick Windows, set the page password, send the `?password=` link.

## 2026-10-01 (third pass) — company name set, page password found, rcedit missing

**Landed.**

- **`application/company_name` → `Dana Entertainment Products`** in
  `export_presets.cfg`, on instruction. **It does not apply yet — see below.**
- **`ITCH_SETUP.md` §9** — how to password-lock the page without authorized users,
  which is the thing the human could not find. It is not a visibility mode; it is
  a checkbox nested under Restricted: **"Also allow a password to view page"**.
  The password can ride in the link as `?password=...`, confirmed from itch's own
  founder in their forum, so friends click once and are in. No itch account
  needed, which is what download keys and authorized users both require.
  Answered the self-hosting question: **no** — bandwidth on a 411 MB build, you
  would be rebuilding auth to reach the same checkbox, and you lose butler's
  differential push, which is what decides whether builds keep shipping.
- **`ITCH_SETUP.md` §10** — Windows SmartScreen. Unsigned exe from any source
  shows "Windows protected your PC" with Run anyway hidden behind More info. Tell
  friends in advance; do not buy a cert for a playtest.
- **`ITCH_SETUP.md` §11** — the rcedit finding.

**The finding.** I set the company name, re-exported to confirm, and checked the
exe's actual metadata rather than trusting the setting. It still read
`Godot Engine` three times. The log says why:

```
ERROR: Could not create child process: rcedit ... --set-icon ...
  --set-version-string CompanyName "Dana Entertainment Products" ...
WARNING: Resources Modification: Could not start rcedit executable.
```

Godot shells out to **rcedit** to rewrite a Windows exe's resources, and
`editor_settings-4.3.tres` line 58 has `export/windows/rcedit = ""`. Unset, not
misconfigured.

**The part that matters more than the company name: `--set-icon` is in the same
failed command.** The icon and the version strings are applied by one rcedit
call, so **the build currently carries the Godot Engine icon, not `icon.ico`** —
in Downloads, on the desktop, in the taskbar during play. Against M1's "nothing
on screen reads as unfinished" that outranks a string nobody opens.

**Gates.** `bash tools/check.sh --changed`: **PASS**. A full headless re-export
also completed (exit 0).

**Where I was wrong.** Last pass I reported the filename fix and the exclude
filter as verified — correctly, I had grepped the pck. But I listed
`company_name="Roboto"` as a thing to decide without checking whether the
mechanism that applies it even worked. It did not, and had I not been asked to
change the value I would not have found that the icon is missing too. Verify the
artefact, not the setting — the same lesson as the exclude filter, and I only
applied it to half the problem.

**Needs the human.**

1. **Install rcedit and point Godot at it** — `rcedit-x64.exe` somewhere
   permanent, then Editor Settings → Export → Windows → rcedit. Five minutes,
   free, once per machine, and it fixes the icon and all three strings in one
   re-export. **I did not download it** — fetching and placing an executable is
   not something to hand to an agent. It lives in editor settings, which are
   per-machine and not committed.
2. Decide whether to also set `application/file_version` /
   `product_version` (empty, so rcedit would stamp `1.0.0.0`; `0.0.7.0` matches
   `v0.007a`) and `application/copyright`. All inert until rcedit exists.
3. Carried over: the old 20 Sept build still in the export folder,
   `config/name="Roboto"`, DS-Digital licence, sound-pack licences, asset
   provenance for the AI disclosure, salvage, rain, GDD §7.

**Blocked / next.** Nothing blocking. The page can be made today: create as
Restricted, tick the password box, upload, send the `?password=` link —
`ITCH_SETUP.md` §7 and §9 have it end to end. Worth doing the rcedit fix before
the build goes to anyone, because the icon is the one part a friend sees before
the game even starts.

## 2026-10-01 (second pass) — a real export, a clean pck, and an itch walkthrough

**Landed.** Four asks, all done, plus one finding that justified the session.

- **`export_presets.cfg` edited** — first time this lane has touched anything
  outside `docs/marketing/**`, on the human's direct instruction. Original backed
  up to the session scratchpad before any change.
  1. Output filename **`2019` → `2109`**. It was writing
     `DataCenterWars2019_v0.007a.exe` into a folder named 2109.
  2. **`exclude_filter` was empty** and is now populated — `tools/*`, the dead
     maps, homebase, scaffolding, docs.
- **The export was actually run, headless, and completed.** 80.3 MB exe +
  331.2 MB pck + two DLLs. It prints a wall of `mesh_get_surface_count` errors
  from the dummy renderer that `--headless` substitutes; those appear on a
  *successful* export. Check for files, not for a clean log.
- **`docs/marketing/brand/` — four profile marks**, drawn from the game's own
  palette with no external assets and no font. The recommended one is three
  capsules in a wedge, lead bright and flankers dimmer; it still reads as three
  shapes at 32 px, which I checked by generating downscales rather than assuming.
- **`ITCH_SETUP.md` §7 and §8** — the actual field-by-field walkthrough (project
  creation, the four files that must travel together, platform checkboxes, butler)
  and a full record of the export.

**The finding that mattered.** `tools/` holds 31 untracked probe scripts, and
three of them — `probe_place_mutaha_core.gd`, `_objs.gd`, `_wip.gd` — carry
hard-coded absolute paths into a **Claude scratchpad directory, session UUID and
all**, as string constants. GDScript is a resource, so with an empty
`exclude_filter` every one was going into the next build. The 20 September build
was clean only because those files did not exist yet. Nothing in `Campaign/`,
`Character/`, `Managers/` or `Env/` references `res://tools/`, so excluding it is
safe.

**Verified, not assumed.** Grepped the shipped `.pck` rather than trusting the
setting: `tools/test_` 18 → **0**, `tools/probe` **0**, `Temp/claude` **0**,
`probe_place_mutaha` **0**.

**Gates.** `bash tools/check.sh --changed`: **PASS**. The headless export itself
is the stronger evidence this pass — it completed and produced a build.
`test.sh` / `smoke.sh` not run; nothing touched that they cover.

**What I did NOT fully fix, said plainly.** A few dead-map path strings survive —
`homebase_level` ×1, `WIP_TERRAIN` ×1, `oyster-bay` ×5, `civil-unrest` ×5. They
are path strings, not map data, and they persist because
`export_filter="all_resources"` lets Godot's dependency walk pull back things the
filter excluded. The clean fix is moving off `all_resources` to scene-dependency
export, which is bigger than a filter edit and wants a run test. Filed as ask 3b.

**Also: this does not retire board risk #1.** That risk is "runs on a machine
that is not this one". An export completing and an export running are different
claims, and I can only make the first.

**Needs the human.**

1. **The old 20 September build is still in the export folder** —
   `DataCenterWars2019_*`, 353 MB. Left alone deliberately; delete it when you are
   sure, and keep it out of any zip.
2. **`application/company_name="Roboto"`** in the preset shows in the `.exe` file
   properties. The splash says DANA ENTERTAINMENT PRODUCTS. I do not know which is
   real, so I left it.
3. **411 MB unzipped is heavy for a playtest**, and the dead maps are not the
   cause — it went 273 → 331 MB since September on real TERRAIN content. Textures
   and terrain data carry the weight.
4. Carried over: `config/name="Roboto"`, DS-Digital licence, sound-pack licences,
   asset provenance for the AI disclosure, the salvage question, whether rain is
   wanted, the stale GDD §7 recruitment row.

**Blocked / next.** Nothing blocking. The page can be created today as Restricted
and the build uploaded; everything needed is in `ITCH_SETUP.md` §7. The open
question that would change the next piece of work is whether any playtest friend
is on a Mac.

## 2026-10-01 — how hard is an itch page with Windows and Mac downloads

**Landed.** `docs/marketing/ITCH_SETUP.md` — a runbook, and `DISPATCH.md` gained
ask 3b.

**The answer.** itch page an hour; Windows an afternoon; Mac is two separate
questions and the obstacle is neither of them.

- **Will it export to Mac? Probably, today.** Export templates 4.3.stable are
  installed, and — the genuinely good news — **both GDExtensions already ship
  complete macOS universal frameworks**: `libdd3d.macos.template_release.universal.framework`
  and `godot-jolt_macos.framework`. Jolt is the live physics engine
  (`3d/physics_engine="Jolt Physics (Extension)"`), so that one matters. The usual
  Mac blocker for a Godot project is absent here. No Windows-only code either —
  only two `OS.shell_open`, which is cross-platform.
- **Will it open? Not without signing.** Unsigned + quarantined reads as "damaged
  and should be moved to the Bin", not as a security prompt. Apple Developer
  Program is **$99/year**; Godot 4.3's macOS preset can sign from Windows via
  rcodesign so no Mac is needed *to sign* — flagged as recollection, not verified.
- **The real obstacle: there is no Mac here to test on**, and
  `renderer/rendering_method="gl_compatibility"` runs on macOS through ANGLE,
  which is exactly the thing that cannot be checked from Windows.
- **Recommended: Windows only for 8 Oct.** Ask the friends what they are on. Do
  not spend the $99 until January 2027 when the Steam demo is real, and it may
  never be worth it — Mac is low single digits of the Steam market with
  disproportionate support cost.

**Four export-config findings, handed to GAMEPLAY as ask 3b.** These are the
useful part of the session:

1. **`export_filter="all_resources"`** — the build currently ships every resource
   in the project, including `causeway_level` (4.1 MB, no mission), the three
   OBSOLETE maps, the `WIP_TERRAIN`/`tb_level`/`test_01` scaffolding and the 15
   missions outside the live campaign.
2. **`maps/homebase_level.tscn` holds an absolute path** —
   `D:/Godot Games/roboto/maps/homebase/homebase_level.map`. A dependency that
   exists on one machine on Earth, and it is in the build today because of (1).
3. **The output filename says 2019**, not 2109, inside a folder named 2109. That
   is the name on the download page.
4. **There is one export preset, not two.** `docs/BOARD.md` says two — stale, and
   M2 leans on it.

**Gates.** `bash tools/check.sh --changed`: **PASS**. Markdown only, so it means
nothing broke rather than anything was verified. `test.sh` / `smoke.sh` not run —
nothing touched that they cover.

**Needs the human.**

1. **Are any of the playtest friends on Mac?** One question, and it decides
   whether the Mac work happens at all this year.
2. The four export findings above, which are GAMEPLAY's and `project.godot`'s —
   both outside marketing's paths.
3. Carried over: asset provenance for the AI disclosure, the DS-Digital licence,
   the sound-pack licences, `config/name="Roboto"`, the salvage question, whether
   rain is wanted, and the stale GDD §7 recruitment row.

**Blocked / next.** Nothing blocking. Doing the Windows export to put a file on
itch **retires board risk #1** — "the export has never been proven" — which the
board says to do this week, so this is a well-timed question. Marketing's own next
artefact is still the DIY capsule set and the one-shot-per-locale screenshot pass,
both waiting on Gate B and the capture tool.

## 2026-09-28 (third pass) — four decisions taken, and the plan refitted to them

**Landed.** The human answered the four open questions. `docs/marketing/PLAN.md`
rewritten around them; `DISPATCH.md` updated.

**The decisions, recorded so no future session re-asks:**

1. **Free demo on Steam *and* itch, then a paid 1.0.** Puts Next Fest in play and
   turns the licence audits from housekeeping into blockers.
2. **Go dark until a trailer.** Reason given: a devlog looks expensive — "I'd need
   a website and YouTube and it's a lot."
3. **Lean in on the AI premise.**
4. **As close to free as possible.** Would spend on a score if the friend
   reception after M2 is good.

**Landed against those:**

- **Calendar rebuilt.** June 2027 Next Fest (14–21 June, registration closes
  **25 April 2027**). Steam page public January 2027, trailer April 2027 as the
  reveal, demo by the April deadline. October 2026's Fest has closed; February
  2027 needs a demo by 10 January and I do not believe in it.
- **One carve-out argued on decision 2, and one correction to it.** *Dark does not
  mean no page* — a store page collects wishlists passively from Steam's own
  discovery, tag pages and themed fests, with no posting and no cadence, and
  arriving at Next Fest with a cold list is the failure mode that makes the Fest
  worthless. So: page in January, trailer in April, Fest in June. Separately, the
  devlog was priced as a website plus a YouTube channel plus edited video, which
  is the expensive version and **my fault for not making the cheap one explicit**
  — the version meant is ~300 words and a GIF on the itch page you are building
  anyway, monthly, drafted by me from the commit history, about twenty minutes of
  your time per post. Offered, not pushed; the plan works without it.
- **Budget plan is now near-free.** Only unavoidable cost is the $100 Steam fee.
  Added a **DIY capsule brief** — wordmark, one line-art silhouette from
  `icon_studio.gd`, one amber accent, designed at 462×174 first and crop upward.
  This game can carry DIY capsules better than most because the identity is
  already strict and already generated. Spend trigger recorded: **first money
  goes to the score, not the art** — the trailer is wordless so audio carries it
  alone, and `darkdrone` already proves the register.
- **AI premise leaned into.** `Artificial Intelligence` added at tag #6. Added §7,
  prepared answers — because a game about agentic AI built with AI agents is a
  story someone writes whether or not you raise it, Valve requires a disclosure
  anyway, and the honest split here is favourable: art and audio are licensed
  packs, AI is in code and docs. **That split needs the human's confirmation — I
  cannot verify every asset's provenance by reading the repo.**

**Gates.** `bash tools/check.sh --changed`: **PASS**. Markdown only, so it means
nothing broke rather than anything was verified. `test.sh` / `smoke.sh` not run —
nothing touched that they cover.

**Where I was wrong.** I proposed a devlog without ever saying what it cost, and
the human reasonably priced the most expensive interpretation and declined it.
That is a failure of the proposal, not the decision. Corrected in `PLAN.md` §2
with an actual time estimate and an offer to draft the posts.

**Needs the human.**

1. **Confirm the asset provenance split** — that no art or audio in the repo is
   AI-generated. The prepared answer in `PLAN.md` §7 rests on it and it goes on a
   public store page.
2. **Check the DS-Digital licence.** New this pass and it is the one I missed
   first time. It is the game's entire visual voice — HUD, capsules, screenshots,
   trailer — and that class of font is commonly free for personal use only. If it
   does not clear commercially, the substitute has to be chosen *before* anything
   is built on it.
3. **The sound-pack licences**, now a hard blocker rather than a nicety.
4. Still open from earlier passes: the salvage question, `config/name="Roboto"`,
   whether rain is wanted, and the GDD §7 recruitment row.

**Blocked / next.** Unchanged and deliberate: nothing public until Gate B, and
now nothing public until April 2027 by choice. The next thing marketing actually
produces is the **DIY capsule set and the screenshot pass**, both of which wait on
Gate B and on the capture tool (ask #4). If the human takes the devlog offer, four
drafts from the commit history is the cheapest useful thing I can do next.

## 2026-09-28 (second pass) — the frame was wrong; refit on "you are a gun too"

**Landed.** The human corrected three things and one of them was structural.

- **`POSITIONING.md` — rewritten, not patched.** The GDD pillar *you are not the
  gun, you are the commander* is retired from all outward copy. The human's read:
  the player is an agent-AI taking compute from other AIs and is therefore a
  weapon itself. The replacement is two lines splitting one failed job — **"Something
  points you. You point them."** for theme, and "the rifle in your hands is not the
  point" for expectation-setting. The bigger win is that **compute is the spine**:
  compute buys seats, seats are how many robots you can field, so taking compute
  makes you *larger*. That is a motivation with no story attached, it is topical
  for free in 2026, and it makes the attachment thematic — the squad is the only
  thing in the chain the player ever chose. Old draft's errors listed at the
  bottom of the file rather than deleted.
- **`PITCH.md` — rewritten at all three lengths.** New lead: "A first-person
  squad-command shooter: you are an agent taking compute from other AIs, and
  compute is how many robots you can be at once." Steam short description redrafted
  to 296 characters. The recruitment fallback is deleted — see below.
- **`PLAN.md` — new, and the main deliverable this pass.** The human markets for a
  living and asked for specifics, not fundamentals. Next Fest calendar with real
  dates and a recommendation; Steam tag order as a strategic choice; named
  creators and outlets with fit and risk; budget ranges; dependency-ordered asset
  build; three draft posts.
- **`CLAIMS.md`** — ASK #1 resolved, three new SAY IT rows, ASK #3 expanded (see
  below), and a fifth distinctive claim the brief did not have.
- **`DISPATCH.md`** — ask #1 rewritten from a question into a GDD correction; the
  screenshot list rebuilt one-shot-per-locale.
- **`RUNWAY.md`** — note at the top pointing at PLAN.md, and the calendar anchored
  to the June 2027 Fest.

**Gates.** `bash tools/check.sh --changed`: **PASS**. Markdown only again, so it
means nothing was broken rather than anything was verified. `test.sh` / `smoke.sh`
not run — nothing touched that they cover.

**Where I was wrong.** Four things, all from the first pass this same day:

1. **"You are not the gun" as the headline.** Thematically false and the human
   caught it. You are an agent handed objectives; you are a weapon too. The line
   was trying to be a theme and an expectations-setter at once and was failing
   at the first.
2. **"A dead city", singular.** The campaign spans unlike places — arena, basin,
   coast road, three bridges, Mutaha, causeway. The plural is both correct and the
   better idea, and it is operational too: five screenshots from five places read
   as a big game, five from one map read as a demo.
3. **Under-read compute.** I filed it as an economy row. It is the spine of the
   whole positioning and it was in the build and in the tutorial the entire time.
4. **Recruitment.** I was right that GDD §7 is stale — the human confirmed the
   factory works — but I should note the cost: I spent a document's worth of
   hedging on a question one line of chat settled. Ask sooner.

**Also found, and it is worse than I first reported.** The pillar is untrue in
**two** independent directions, not one. Three of four squad orders lose 100% of
the time (GDD §8) **and** the board names a *"long-range-god problem"* — the
player can currently out-range the whole thing alone. So the honest description of
today's build is closer to "an FPS with a squad you get attached to" than to "a
command game". That is why the copy says "the rifle is not the point" rather than
"aiming is not how you win": the second is the sentence you want and it becomes
true when those two close. It is the strongest argument yet for the runway being
gated rather than dated.

**Needs the human.** Four questions asked in chat this session — launch model,
audience priority, build-in-public vs go-dark, and budget. The plan in `PLAN.md`
assumes: free demo into a paid Steam release, tactics audience first,
build-in-public, ~$1,000. **Every one of those is a guess and three of them change
the plan materially.** Carried over and still open: the salvage question (ASK #2),
`config/name="Roboto"`, the sound-pack licences, the AI content disclosure, and
whether rain is wanted.

**Blocked / next.** Unchanged and deliberate: nothing until Gate B. The single
dated item now on the calendar is **Steam Next Fest registration, 25 April 2027**,
for the 14–21 June 2027 Fest — October 2026's has closed and February 2027's needs
a demo by 10 January, which I do not believe in. Everything else works backwards
from that. Sourced in `PLAN.md` §1 and worth re-checking against Valve directly
before anything is planned around it.

## 2026-09-28 — the runway: when to market, itch, TikTok, Steam

**Landed.** Five new files, all under `docs/marketing/`. Nothing else touched.

- `RUNWAY.md` — the four answers. **Recommendation: zero marketing before
  2026-10-08**, with three named gates rather than dates. Gate A a build that
  runs elsewhere → a *private* itch page as the M2 delivery mechanism. Gate B
  one mission judged fun and squad orders not losing 0/0/0 → public capture and
  the devlog, where marketing actually starts. Gate C a ladder plus a clean
  first run → the Steam page, not before. Then itch assets and page structure
  concretely (630×500 cover, the autoplaying GIF as the real conversion lever,
  eight-section scroll, free not paid); an honest no on TikTok as a primary
  channel with the four clips that *would* work and the tone conflict stated;
  and Steam in full — $100 Direct fee, the tax interview and the ITIN trap, the
  30-day hold, page review with two bounces budgeted, the ten-asset capsule set
  with sizes, and seven things found out late ranked by damage.
- `CLAIMS.md` — the ledger every future session should read before writing a
  word. SAY IT / HOLD / ASK.
- `PITCH.md` — one line, one paragraph, one page, plus a 277-character Steam
  short description. Built only on SAY IT mechanics; no Argus, no Algie, no plot.
- `POSITIONING.md` — the argument that the vagueness is a strength, its costs,
  six discipline rules, and worked samples: store blurb, a wordless 90-second
  trailer beat sheet, briefing copy, the memorised answer to "what's the story?".
- `DISPATCH.md` — six drafted asks, draft-only as required.

**Gates.** `bash tools/check.sh --changed`: **PASS** (see the run note below —
only Markdown changed, so this is a weak signal, and I am saying so rather than
presenting it as coverage). `test.sh` and `smoke.sh`: **not run.** I touched no
script, resource, scene or anything that loads at startup, so neither has
anything to say about this session. Not skipped for convenience.

**Needs the human.** Six items, all drafted in `docs/marketing/DISPATCH.md`.
Ranked:

1. **Can the player buy a new robot?** GDD §7 says recruitment is "not built".
   The build disagrees: `campaign_state.gd:624` defines `recruit()`,
   `factory_page.gd:240` calls it, FACTORY is a real tab, and
   `lesson_prompts.gd:36` teaches it. **This gates the pitch at all three
   lengths** — a fallback wording is written if the answer is no.
2. **The pillar may not be true yet.** Three of four squad orders lose 100% of
   the time (GDD §8). Every line of copy rests on "you are not the gun, you are
   the commander," and one of the four commands works. Already on YOUR DESK;
   flagged here because it does not look like a marketing problem from the board
   and it is marketing's single largest exposure.
3. **`config/name="Roboto"`.** Window title, `.exe` basename, and what the Steam
   overlay reads. The 2026-10-08 build says Roboto while the title screen says
   DATA CENTER WARS 2109. Shared file, so not mine — five-minute fix.
4. **No sound pack in the repo has a licence.** All twelve folders under
   `sounds/sfx/` carry no licence or credit file, `darkdrone` (the title music)
   included. `textures/` has two. A `CREDITS.md` is an hour now and a week in six
   months, and it is a hard gate on any paid release.
5. **The AI content disclosure.** Valve requires it, it appears publicly on the
   store page, and this game has four AI lanes. A decision to make in writing
   long before there is a page.
6. **Is salvage the economy, or just where money comes from?** One
   undifferentiated `earned` pool, free resupply. I wrote the narrow claim.

**Two things I should say out loud.**

- **There is no rain in the game.** The most evocative line in my own brief —
  "rain falls on a planet bereft of the people that constructed it" — describes
  something that does not exist. I grepped `Env/`, `Character/`, `Managers/` and
  `Campaign/` for rain, precipitation, weather and fog; the only matches are the
  letters inside "terrain". Not a criticism, but it means no rain in any capture
  or key art, and if it is the tonal centre it is a board item rather than a
  brief line. Drafted as ask #5.
- **`check.sh` cannot verify anything in this session.** It parses scripts and
  loads resources. I changed five Markdown files. PASS here means "I broke
  nothing", not "this is right". Everything in `RUNWAY.md` §4 about Steam is
  recalled knowledge, not fetched — the shape of the process is stable but the
  individual figures should be re-checked against Valve's documentation before
  money moves. Said in the file too.

**Blocked / next.** Not blocked; deliberately idle. The recommendation is that
this lane does nothing until Gate B, and I would rather hold to that than
generate work. Three things I did not do, on purpose:

- **No shot list for the 2026-10-01 recording missions**, though the brief lists
  it as deliverable #2. You said those clips are yours and your friends do not
  need marketing. The board's MARKETING NOW line still reads "pitch + shot lists
  for the three recording missions" and the pitch half is done; the coordinator
  may want to retire the other half.
- **No devlog drafts.** They want Gate B footage and a real capture tool
  (ask #4), and writing them now would date them.
- **No capsule or cover art.** Needs a logo lockup that does not exist. It is the
  longest lead time on the Steam list — two to four weeks with revisions — and
  the one thing on it worth paying a person for.

When Gate B clears, the first move is the devlog, not the page.
