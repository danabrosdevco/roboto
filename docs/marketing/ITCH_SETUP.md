# itch page + Windows and Mac downloads — a runbook

Written 2026-10-01 by MARKETING, answering "how hard would it be to set up an
itch page with a demo and downloads for Mac and Windows."

**Short answer.** The itch page is an hour. Windows is an afternoon, most of it
spent on the first export failing. **Mac splits into two different questions** —
*does it export* (yes, probably, today) and *does it open without a frightening
warning* (no, and that costs $99/year) — and the real obstacle is neither of
those: it is that there is no Mac here to test it on.

Everything below was read out of the repo on 2026-10-01 unless marked otherwise.

---

## 1. What is already in your favour

This is better than it usually is, and the reasons are specific.

- **Export templates `4.3.stable` are installed.** The templates download is one
  bundle covering every platform, so the macOS templates are already on disk.
  Nothing to fetch.
- **Both native extensions ship complete macOS universal frameworks.** This is
  normally *the* blocker for a Godot project going to Mac and you do not have it:
  - `addons/debug_draw_3d/libs/libdd3d.macos.template_release.universal.framework`
  - `addons/godot-jolt/macos/godot-jolt_macos.framework`
  - Jolt matters especially, because `project.godot` sets
    `3d/physics_engine="Jolt Physics (Extension)"` — it is your actual physics
    engine, not an optional addon.
- **No Windows-only code.** The only OS calls in gameplay are two
  `OS.shell_open` in `Managers/master.gd` (648, 695), which is cross-platform.
- No `D:`-style absolute paths anywhere in `Campaign/`, `Character/` or `Env/`.
  One in `maps/` — see §4.

---

## 2. The itch page — genuinely easy

| Step | Cost |
|---|---|
| Create the page | Free, instant, no review, no fee |
| Set visibility | **Restricted** (link or key only) for the playtest; Public later |
| Upload builds | Web uploader, or `butler` — see below |
| Platform tagging | **Per upload.** Tick Windows on one, macOS on the other, and itch shows the right button to each visitor |

**One page holds both builds.** You do not need separate pages per platform.

**Demo vs eventual paid 1.0.** Make the demo its own free page now, since there is
no paid page to hang it off yet. itch lets you add a paid page later and link the
two, or convert pricing on the existing page.

**Set up `butler`.** It is itch's free CLI and it does differential uploads:

```bash
butler push "D:/Godot Games/Exports/DCW_win" yourname/data-center-wars:windows
```

Fifteen minutes to install and authenticate, and after that shipping a new build
is one command. That is the difference between pushing builds weekly and pushing
them never. Worth doing on the first build, not the fifth.

---

## 3. Mac — the two questions, separated

### Question one: will it export? Probably, today.

The templates and the native frameworks are present, so the export itself should
run from this Windows machine right now. Two settings to get right:

- **Architecture: universal** (arm64 + x86_64), so it covers Apple Silicon and
  Intel. Godot's macOS preset defaults to universal.
- **Export to `.zip`, and never zip a folder yourself.** A `.app` is a directory,
  and zipping it with Windows Explorer or PowerShell drops the Unix executable
  bit on `Contents/MacOS/<binary>` — producing an app that cannot launch at all.
  Godot's macOS export writes the zip with the right permissions. (`.dmg`
  generation needs macOS tooling, so it is not available from here; `.zip` is
  what itch wants anyway.)

### Question two: will it open? Not without signing.

An unsigned, un-notarized app downloaded through a browser gets quarantined by
Gatekeeper. The message the user sees is not a polite "unidentified developer" —
for a quarantined unsigned bundle it is closer to **"damaged and should be moved
to the Bin"**, which reads as a corrupt download rather than a security prompt.
That is a meaningful share of Mac users who simply leave.

Three options:

| Option | Cost | Reality |
|---|---|---|
| **Ship unsigned with instructions** | Free | Right-click → Open, or `xattr -dr com.apple.quarantine <app>`. Common on itch and that audience tolerates it better than Steam's. Still loses people |
| **Apple Developer Program → sign + notarize** | **$99/year** + first-time certificate wrangling | Godot 4.3's macOS preset can sign from Windows via **rcodesign**, and notarize with an App Store Connect API key — so you do *not* need a Mac to sign. Confirm the options in the export dialog; this is my recollection of 4.3's preset, not something I can verify from here |
| **Skip Mac** | Free | See the recommendation |

### Question three, the one that actually matters: you cannot test it

There is no Mac in this setup. An untested Mac build handed to a friend is a
support conversation, not a demo — and one thing makes that sharper:

**`project.godot` sets `renderer/rendering_method="gl_compatibility"`.** macOS
deprecated OpenGL, so Godot runs the Compatibility backend there through ANGLE.
It generally works in 4.3, but it is the single most likely thing to render
differently or misbehave, and it is precisely what cannot be checked from
Windows. If you care about one Mac risk, care about this one.

---

## 4. Four things to fix before any build leaves, Mac or not

Found while reading the export config. None is marketing's to change — drafted as
an ask in `docs/marketing/DISPATCH.md`.

1. **`export_filter="all_resources"`.** You are shipping *every* resource in the
   project. That includes `causeway_level` (4.1 MB, no mission), `valley_level`,
   `arena_level`, `homebase_level`, `civil-unrest_level`, `oyster-bay_level`, all
   the `WIP_TERRAIN` / `tb_level` / `test_01` scaffolding, and the 15 mission
   files outside the live campaign. Switch to selected-scenes-with-dependencies,
   or add an `exclude_filter`. Smaller download, faster export, and fewer things
   that can fail at export time.
2. **`maps/homebase_level.tscn` holds an absolute path** —
   `D:/Godot Games/roboto/maps/homebase/homebase_level.map`. A dependency that
   exists on exactly one machine. `homebase_level` is OBSOLETE per GDD §2, so
   excluding it fixes this and item 1 at once — but with `all_resources` on, it is
   in the build today.
3. **The output filename says 2019.** The preset writes
   `DataCenterWars2019_v0.007a.exe` into a folder named `..._2109_...`. That is
   the filename on the download page and in the friend's Downloads folder.
4. **`config/name="Roboto"`** — still the window title and the Steam overlay
   name. Raised on 2026-09-28 and still open.

**There is only one export preset** (`Windows Desktop`). The board says two; that
is stale.

---

## 5. Effort, honestly

| Task | Estimate |
|---|---|
| itch page, private, one Windows build | **~1 hour** — most of it the first export surfacing something |
| The four fixes in §4 | ~30 min |
| `butler` setup | ~15 min |
| Mac `.zip`, unsigned | ~30 min to produce, **unknown to validate** — the unknown is the real cost |
| Mac signed + notarized | **$99/year** + half a day the first time |

**This retires board risk #1.** "The export has never been proven" is the largest
unbounded item on the roadmap, and the board says to do the throwaway export
*this week*. Doing it to put a file on itch is the cheapest possible excuse to do
it at all.

---

## 6. Recommendation

**Windows only for the 8 October playtest.** Then:

- **Ask the friends what they are on.** If none are on Mac, the question is moot
  and stays moot for months. If one or two are, give them an unsigned `.zip`
  labelled plainly as untested, with the right-click → Open instruction, as an
  extra rather than a supported download.
- **Do not spend the $99 yet.** Revisit it in January 2027 when the Steam demo is
  real (`docs/marketing/PLAN.md` §1), because by then you will have a reason to
  know whether the Mac build actually works.
- **It may never be worth it.** macOS is a low single-digit share of the Steam
  market and carries a disproportionate support cost — a Windows-only Steam
  release is completely unremarkable. The case for Mac here is a specific person
  who wants to play, not a market.

The spend that beats $99/year on Mac, if money appears: the score. Argued in
`docs/marketing/PLAN.md` §5.

---

## 7. Step by step — making the page and hosting the Windows download

Added 2026-10-01. Written against the real export, which now exists — see §8.

### 7a. Your profile picture

**itch.io → your name (top right) → Settings → Profile → Profile image.** Square;
512×512 is safe and scales down cleanly.

Marks are in `docs/marketing/brand/`, drawn from the game's own palette:
near-black `#080C0A` (the boot splash colour, read out of `project.godot`), player
pale cyan, and one amber accent used sparingly because amber is the enemy colour.

| File | What it is | Use it when |
|---|---|---|
| **`itch_avatar_squad.png`** | **Three capsules in a wedge, lead bright, flankers dimmer.** Recommended | It says *squad* instantly, it is literally your units, and it still reads as three shapes at 32 px |
| `itch_avatar_squad_flat.png` | Same, all one cyan, no depth | If the dimmed flankers look muddy wherever itch renders it |
| `itch_avatar_capsule_cyan.png` | One capsule, outlined, amber sensor band | If you want the single-unit read rather than the squad |
| `preview_*_32.png` / `_64.png` | Downscales | To judge small-size legibility before committing |

No text in any of them, deliberately — an avatar has no room for a wordmark, and
the DS-Digital licence is unresolved (`docs/marketing/DISPATCH.md` ask 3), so
nothing should be built on it until it clears.

### 7b. Create the project

**itch.io → Dashboard → Create new project.**

| Field | Value |
|---|---|
| **Title** | `Data Center Wars 2109` |
| **Project URL** | `data-center-wars-2109` |
| **Short description / tagline** | `Compute is how many robots you can be at once.` — shown in listings and every embed |
| **Classification** | Games |
| **Kind of project** | **Downloadable** |
| **Release status** | **In development** |
| **Pricing** | **No payments** (or `$0 or donate`). Do not charge for a playtest |
| **Genre** | **Strategy** — *not* Shooter. Same reasoning as the Steam tag order in `docs/marketing/PLAN.md` §3: filed as a shooter brings the wrong audience |
| **Tags** | `tactical`, `squad-based`, `real-time-tactics`, `robots`, `post-apocalyptic`, `singleplayer`, `godot`, `fps` — put `fps` last |
| **Community** | Comments on. It is a playtest; you want the feedback somewhere |
| **Visibility & access** | **Restricted** for the playtest — the page exists, is not indexed, and opens only for people with the link. Flip to Public at Gate B |

**Cover image** is required before the page can go public: **630×500**, displayed
at 315×250. Not needed while Restricted. Not a wide gameplay screenshot — it
turns to mud at that size.

### 7c. Build it yourself — the button, not me

**Superseded 2026-10-01.** This section used to give a hand-rolled zip command.
Throw that away: the project already has a proper export pipeline, written in
September, and it is better than anything done by hand. It was simply never
switched on. **See §12** for what it does and how it was verified.

**Press "Export build" in the editor's top toolbar.** It saves open scenes, bumps
the version, exports release, writes `build_info.txt`, zips the folder and opens
it. One zip comes out, named for the version:

```
..\Exports\DataCenterWars2109_v0.008a\DataCenterWars2109_v0.008a.zip
```

That zip is what you upload. It already contains exactly the right things and
nothing else:

| In the zip | What it is |
|---|---|
| `DataCenterWars.exe` | the game |
| `DataCenterWars.pck` | all the content — **the exe alone will not start** |
| `godot-jolt_windows-x64.dll` | your physics engine |
| `libdd3d.windows.template_release.x86_64.dll` | debug draw |
| `build_info.txt` | version, date, and the git commit it was built from |

No file-picking, no risk of grabbing the wrong build, and `build_info.txt` means
that when a friend reports something you can tell which code they were on.

Then on the project page: **Uploads → Upload files**, pick the zip, and **tick
`Windows` in that file's platform checkboxes.** Skipping that shows no download
button to anyone, which is the most common first-time mistake on itch.

**Housekeeping, unrelated to the script:** the Exports folder still holds the old
20 September build (`DataCenterWars2019_*`, 353 MB) and the `v0.007a` build I
made by hand. Delete them when you are sure; I have left both alone. New builds
go in their own versioned folder and never touch an existing one.

### 7d. Set up butler on this first build, not the fifth

itch's free CLI. Differential uploads, so the second push sends only what changed:

```bash
butler login
```

```bash
butler push "/d/Godot Games/Exports/DataCenterWars2109_v0.008a" yourname/data-center-wars-2109:windows
```

Point it at the **versioned folder** the Export build button made — not at the
zip inside it. butler will include `build_info.txt` too, which is what you want.

- **Push the folder, not the zip.** butler packages it itself and can then diff
  against the previous build. Pushing a zip defeats that and re-sends 400 MB
  every time.
- **The channel name sets the platform.** A channel containing `windows` or `win`
  is tagged Windows automatically, so `:windows` is right.

### 7e. What to write on the page

An itch page is one scroll and the order is the design. Full structure in
`docs/marketing/RUNWAY.md` §2; for a restricted playtest page:

1. The tagline.
2. **What is in this build** — how many missions, roughly how long, what is
   absent. The highest-trust block on an itch page and the one devs skip.
3. **Known issues.** On itch this reads as competence.
4. Controls.
5. **Where to send feedback.**

Public-facing copy is in `docs/marketing/PITCH.md`.

---

## 8. The export, actually run — 2026-10-01

Not theory any more. A headless release export was run from this machine:

```bash
"/d/Godot Games/Godot_v4.3-stable_win64.exe/Godot_v4.3-stable_win64_console.exe" --headless --path . --export-release "Windows Desktop" "/d/Godot Games/Exports/DataCenterWars2109_v0.007a/DataCenterWars2109_v0.007a.exe"
```

**It completed and produced a build.** It prints a wall of
`mesh_get_surface_count` / `Parameter "m" is null` errors and a
`p_child->data.parent != this` at the end — those come from the dummy renderer
`--headless` substitutes, they appear on a *successful* export, and they are not
a reason to think it failed. Check for the files, not for a clean log.

**This does not retire board risk #1.** That risk is "runs on a machine that is
not this one", and an export completing is a different claim from an export
*running*. What it retires is the unknown underneath it: the project exports at
all, and nothing in it is unexportable.

### What changed in `export_presets.cfg`, and what it is verified to have done

Original backed up to the session scratchpad first. Three edits:

1. **Output filename `2019` → `2109`.** It was writing
   `DataCenterWars2019_v0.007a.exe` into a folder named `2109`.
2. **`exclude_filter` populated** — it was empty, so the build shipped everything
   in the project.
3. Dead-map minimaps and terrain data added to the same filter.

**Verified by grepping the shipped `.pck` itself**, not by trusting the setting:

| Pattern | Old build (20 Sep) | New build |
|---|---|---|
| `tools/test_` | 18 | **0** |
| `tools/probe` | 0 | **0** |
| `Temp/claude` | 0 | **0** |
| `probe_place_mutaha` | 0 | **0** |
| `homebase_level` | 4 | 1 |

**The thing that was actually at risk.** `tools/` holds 31 untracked probe
scripts, and three of them — `probe_place_mutaha_core.gd`, `_objs.gd`, `_wip.gd`
— carry hard-coded absolute paths into a Claude scratchpad directory, session
UUID and all, as string constants. GDScript is a resource, so with an empty
`exclude_filter` every one of them was going into the next build. The 20
September build was clean only because those files did not exist yet. Nothing in
`Campaign/`, `Character/`, `Managers/` or `Env/` references `res://tools/`, so
excluding it is safe.

### What is still imperfect, stated rather than hidden

- **A few dead-map path strings remain**: `homebase_level` ×1, `WIP_TERRAIN` ×1,
  `oyster-bay` ×5, `civil-unrest` ×5. These are path strings rather than map
  data, and they survive because `export_filter="all_resources"` lets Godot's
  dependency walk pull back things the filter excluded. **The clean fix is
  switching `export_filter` off `all_resources` to scene-dependency export**,
  which is a bigger change than a filter edit and wants a run test behind it.
  Filed for GAMEPLAY as ask 3b in `docs/marketing/DISPATCH.md`.
- **411 MB unzipped is a lot for a playtest**, and the dead maps are not what is
  driving it — the build went 273 → 331 MB since September because TERRAIN added
  real content. Textures and terrain data carry the weight. Worth a look, not
  worth blocking on.
- **`application/company_name="Roboto"`** is still in the preset, so it shows in
  the `.exe` file properties. The splash says DANA ENTERTAINMENT PRODUCTS. Left
  alone because I do not know which is the real one — your call.
- **`config/name="Roboto"`** in `project.godot` is untouched and still the window
  title. It is on the board's shared-files list, so it is not mine to change.

---

## 9. Locking the page — password, not "authorized users"

Added 2026-10-01. The option exists on itch and it is genuinely hard to find:
it is not a visibility mode of its own, it is a **checkbox nested under
Restricted**.

### Where it is

**Edit project → Visibility & access → Restricted →
"Also allow a password to view page"**, then type a password in the field that
appears. Save.

That is the whole thing. It is not under Draft, it is not a separate access
level, and it is easy to miss because picking "Restricted" first shows you the
authorized-users list — which is the mechanism you said you did not want.

### What each option actually requires of the visitor

| Mechanism | Visitor needs | Fits what you asked for |
|---|---|---|
| **Password** | Nothing. No account, no sign-in | **Yes — this is the one** |
| Authorized users | An itch.io account, added by you one at a time | No |
| Download keys | An itch.io account to claim the key against | No |
| Draft | To be you | No |

### Put the password in the link

itch supports passing it as a query parameter, so nobody has to type anything —
confirmed by itch's founder in their own forum:

```
https://yourname.itch.io/data-center-wars-2109?password=whateveryoupick
```

One link to your friends, they click, they are in. That is as close to "a private
download" as itch gets, and it is close enough.

### Three caveats, none of which should stop you

- **The itch desktop app does not handle password-protected pages.** Browser
  download only. Irrelevant for a handful of friends; worth knowing before you
  tell anyone to use the app.
- **A password in a URL is a gate, not security.** It lands in browser history,
  in referrer headers, and in whatever chat app you paste it into. That is fine
  for keeping strangers off an unfinished build, and it is not fine for anything
  you would actually mind leaking. For this, it is the right tool.
- **Comments.** If you leave the community section on, anyone past the password
  can post. That is usually what you want for a playtest.

### Should you self-host behind a password instead?

**No.** Specifically:

- **Bandwidth.** The build is ~411 MB unzipped. itch serves it on a CDN for free.
  Self-hosting means you pay for every download and distant friends get it slowly.
- **You would be building auth.** Even `.htpasswd` is setup, maintenance and a
  thing to get wrong, to arrive at exactly what the itch checkbox already does.
- **You lose butler**, so every new build is a fresh 400 MB upload instead of a
  differential push. That single difference is what decides whether you ship
  builds weekly or stop shipping them.
- **No version history, no update path, no download counts.**

A cloud-drive share link is also worse than itch here: large files trip virus-scan
interstitials, there is no install flow, and there is no update story.

The only honest reason to self-host would be wanting a password that never
appears in a URL. For an unfinished build going to friends, that is not worth
what it costs.

### So the sequence is

1. Create the project (§7b), set **Visibility: Restricted**.
2. Tick **"Also allow a password to view page"**, set a password.
3. Upload the zip, tick **Windows** on the file (§7c).
4. Send `https://yourname.itch.io/data-center-wars-2109?password=...`.
5. Flip to Public at Gate B, delete the password, and the same page carries on
   with its view count and comments intact.

---

## 10. One more thing your friends will hit: Windows SmartScreen

Not an itch problem — it happens from any download source, including your own
website, and it is the Windows equivalent of the macOS Gatekeeper issue in §3.

An unsigned `.exe` downloaded from the internet triggers **"Windows protected
your PC"**, a blue full-screen dialog with only a **Don't run** button visible.
The **Run anyway** button is hidden behind a **More info** link that most people
do not notice.

**Tell them in advance, in the page body and in the message you send:**

> Windows will say "Windows protected your PC". Click **More info**, then
> **Run anyway**. The build is not signed — a code-signing certificate costs a few
> hundred a year and this is a playtest.

Saying it up front converts a scary dialog into an expected one. Saying nothing
means at least one person quietly does not play and does not tell you why.

Signing it properly needs a Windows code-signing certificate — a few hundred a
year, and an OV certificate still accumulates SmartScreen reputation slowly, so
it does not even fix it immediately. **Not worth it for a playtest.** Revisit when
there is a paid release; Steam's own launcher sidesteps most of this.

`export_presets.cfg` already has `codesign/enable=false`, which is correct for now.

---

## 11. The company name is set, and it does not apply yet — rcedit is missing

Added 2026-10-01, after setting `application/company_name="Dana Entertainment
Products"` and re-exporting to confirm it landed. **It did not**, and the reason
is worth knowing because it also explains something more visible.

### What the exe actually says right now

```
CompanyName  : Godot Engine
ProductName  : Godot Engine
FileDescr    : Godot Engine
```

### Why

Godot builds the right command. The preset is correct. It simply cannot run it:

```
ERROR: Could not create child process: rcedit "...DataCenterWars2109_v0.007a.exe"
  --set-icon C:/Users/User/AppData/Local/Godot/_rcedit.ico
  --set-version-string CompanyName "Dana Entertainment Products"
  --set-version-string ProductName "Data Center Wars 2109"
  --set-version-string FileDescription "Data Center Wars 2109"

WARNING: Resources Modification: Could not start rcedit executable. Configure
rcedit path in the Editor Settings (Export > Windows > rcedit), or disable
"Application > Modify Resources" in the export preset.
```

Godot does not rewrite a Windows executable's version resources itself — it
shells out to **rcedit**, a small standalone tool. Checked:
`C:\Users\User\AppData\Roaming\Godot\editor_settings-4.3.tres` line 58 has
`export/windows/rcedit = ""`. It is unset, not misconfigured.

### The bit that matters more than the company name

Look at the failed command again: **`--set-icon` is in it.** The icon and the
version strings are applied by the same rcedit call, so the one failure costs
both.

**Your build currently has the Godot Engine icon**, not `res://icon.ico`. That is
what a friend sees in their Downloads folder, on their desktop, and in the
taskbar while they play. Against M1's "nothing on screen reads as unfinished",
that is a bigger deal than a string in a properties dialog that nobody opens.

### The fix — free, five minutes, once per machine

1. Get `rcedit-x64.exe` — it is the standalone release binary of the `rcedit`
   project (from Electron), and it is what Godot's own documentation points at.
   Put it somewhere permanent, e.g. `D:\Godot Games\rcedit-x64.exe`.
2. In the Godot editor: **Editor → Editor Settings → Export → Windows → rcedit**,
   and set it to that path.
3. Re-export. The icon and all three strings apply in the same pass.

**I have not downloaded it** — fetching and placing an executable is yours to do,
not something to hand to an agent. Once the path is set, nothing in the repo
changes: `export/windows/rcedit` lives in your editor settings, which are
per-machine and not committed, so each machine that exports needs it set once.

### Verify it took, rather than assuming

```bash
powershell -Command "(Get-Item 'D:\Godot Games\Exports\DataCenterWars2109_v0.007a\DataCenterWars2109_v0.007a.exe').VersionInfo | Select CompanyName,ProductName,FileDescription"
```

Should read `Dana Entertainment Products` / `Data Center Wars 2109` /
`Data Center Wars 2109`. It reads `Godot Engine` three times today.

**The alternative, if you would rather not install anything:** set
`application/modify_resources=false` in the preset. That silences the warning and
accepts the Godot icon and strings. I would not — the icon is worth five minutes.

### Two neighbouring fields worth setting while you are in there

Both are empty in the preset and both show in the same properties dialog:

- `application/file_version` and `application/product_version` — currently `""`,
  so rcedit falls back to `1.0.0.0`. `0.0.7.0` would match `v0.007a`.
- `application/copyright` — empty.

Neither matters until rcedit works, since none of them apply without it.

---

## 12. The export you run yourself — it already existed

Added 2026-10-01. Asked for a native Godot export the human could run themselves
rather than asking me. **It was already built, in September, and it is better
than what I had been doing by hand.** It was never switched on, so nobody could
see it.

### What was already there

| File | What it is |
|---|---|
| `tools/export.ps1` | 9 KB, the whole pipeline. Carefully written, with its own documentation at the top |
| `tools/export_build.bat` | double-click wrapper that runs it in a console window and pauses so you can read the result |
| `addons/export_build/plugin.gd` | an editor toolbar button that saves open scenes, then runs the `.bat` |
| `Managers/build_version.gd` | the version the script stamps, shown in every menu corner and on every playtest and lab report |

### The one thing missing

`project.godot` had `enabled=PackedStringArray("res://addons/func_godot/plugin.cfg")`
— the `export_build` plugin was not in the list, so the toolbar button did not
exist. **Now enabled.** That is the entire change; nothing else was touched.

`project.godot` is on the board's shared-files list, so this is flagged rather
than quiet. Gates run after: `check.sh --changed` **PASS**, `smoke.sh` **PASS**
(booted clean, 15 s, 3 warnings). An `EditorPlugin` affects the editor only and
not the running game, but `project.godot` loads at startup, so smoke is the right
gate per CLAUDE.md.

### How to use it

**Press "Export build" in the editor's top toolbar.** That is it.

Or double-click `tools\export_build.bat` — but then **save in the editor first**,
because the export reads what is on disk. The toolbar button saves open scenes
for you, which is the reason to prefer it.

It then: works out the next version, writes it into `build_version.gd`, exports
release to `..\Exports\DataCenterWars2109_v0.00Na\`, writes `build_info.txt`
with the git commit, zips the folder, and opens it.

**Options**, from a terminal — `tools\export_build.bat -Hotfix`:

| Flag | Does |
|---|---|
| `-DryRun` | says what would happen, changes nothing. **Run this first if unsure** |
| `-Hotfix` | same number, next letter: `0.008a` → `0.008b` |
| `-Version 0.010a` | exactly this version |
| `-DebugBuild` | debug export: slower, adds a console exe, ships debug DLLs |
| `-NoZip` / `-NoOpen` | skip zipping / skip opening the folder |
| `-ExportsDir path` | somewhere other than `..\Exports` |

### Verified, not assumed

Ran `tools\export.ps1 -DryRun`. It found Godot, found the 4.3 export templates,
read `build_version.gd`, scanned `..\Exports`, and worked out the next version:

```
DATA CENTER WARS 2109 - export
  last version  0.007a
  this version  0.008a (release)
  folder        D:\Godot Games\Exports\DataCenterWars2109_v0.008a

Dry run: nothing was changed.
```

**I deliberately did not run it for real.** Doing so would consume v0.008a and
write to `Managers/build_version.gd`, which is GAMEPLAY's path — and the point of
the ask was that you pull the build, not me. v0.008a is yours. Every component is
separately proven: the dry run covers version logic and tool discovery, and the
raw headless export in §8 covers the export itself.

### Two things worth knowing about it

- **It ignores the preset's `export_path`.** The script passes an explicit output
  path to Godot, so it was always going to name things correctly. Which means the
  `2019` filename bug I fixed in §8 **only ever affected the editor's own
  Export dialog**, not this script. The fix is still right — that dialog is a
  route someone will use — but it was never going to bite the one-button path.
- **It is safe to fail.** A failed export puts `build_version.gd` back and removes
  the half-made folder, so a bad run never burns a version number. It refuses to
  touch a folder that already exists.

### After each export

`Managers/build_version.gd` will have changed — **commit it with the build**, so
the version a playtester reports maps to a commit. `build_info.txt` in the folder
records the commit and whether the tree was dirty when you built.

---

## 13. What you still need — the full checklist

Added 2026-10-01, answering "is there anything else I need?". Everything for the
itch page, in one place.

### Done — nothing more needed

| | Where |
|---|---|
| **Profile picture** | `brand/itch_avatar_squad.png` |
| **Logo**, three variants | `brand/logo_dcw2109_*.png` |
| **Cover image, 630×500** | `brand/itch_cover_630x500.png` — the Mutaha street with the title over it. A flat fallback is beside it |
| **Tagline** | *Compute is how many robots you can be at once.* |
| **Page description** | `docs/marketing/PITCH.md` |
| **Classification, kind, genre, tags, visibility** | §7b above |
| **Password locking** | §9 above |
| **A build, and a way to make the next one** | the Export build button — §12 |

### Needed from you — nobody else can write these

These are the three blanks in the page body, and they are the parts that earn
trust on itch:

1. **"What is in this build"** — how many missions, roughly how long, what is
   obviously absent. I cannot write it: I have never played it and the GDD does
   not say how long a mission takes.
2. **Known issues** — three to six lines. On itch this reads as competence, not
   weakness. You know what is broken; I only know what is unfinished.
3. **Controls** — the actions exist in `project.godot`: move, `jump`, `aim`,
   `fire`, `reload`, `zoom`, `lean_left` / `lean_right`, `scan`, `command`,
   `interact`, `squad_manager`, `1`–`6`, `fullscreen`. I have deliberately not
   guessed the key for each, because a wrong controls list is worse than none.
   **Cheapest route: the game already renders these as readable key names** —
   `Character/hud/lesson_prompts.gd` substitutes `{squad_manager}` and friends at
   runtime. Screenshot the lesson prompts, or read them off and paste them in.

### Needed from whoever shoots — the real gap

4. **Screenshots at 1920×1080 or better.** The current set is 1152×648, which is
   **below Steam's minimum** and soft on itch. See the Revision 2 notes in
   `docs/marketing/SHOT_BRIEF.md`.
5. **The five gameplay shots reshot** at dusk, subject unoccluded, action
   happening. The `environments/` set is good and can fill the gallery, but not
   one frame in it shows the squad, an order, or the revive — which is the
   entire thing the page has to sell.
6. **6–8 seconds of video of the Mechanic revive.** The gallery GIF, and the
   single biggest conversion lever on itch. There is nothing to cut it from
   today.

### Worth doing before the build leaves

7. **rcedit** — five minutes, free, fixes the exe icon and the three version
   strings together. §11. Right now the download carries the Godot Engine icon.
8. **The WeaponMount mismatch** — `soldier_chassis` 0.4 vs `mechanic_chassis`
   0.25. One value, and it is in frame on the revive shot.
9. **Delete the old builds** in `..\Exports` so nothing stale gets uploaded.

### Not needed, despite what you might assume

- **A trailer.** Not for itch, and not before the game is judged fun. The GIF
  does the work a trailer would.
- **A press kit.** Nothing to send it to yet.
- **A Discord.** Not before there are people to put in it.
- **Steam anything.** January 2027 at the earliest — `docs/marketing/PLAN.md` §1.

### The shortest path to a live page

1. Set rcedit, re-export (§11, §12).
2. Create the project, Restricted, password on (§7b, §9).
3. Upload the zip, tick Windows (§7c).
4. Cover image, profile picture — both ready.
5. Paste the tagline and description; write the three blanks above.
6. Gallery: the good `environments/` frames now, the reshot five when they exist.
7. Send the `?password=` link.

Steps 1–5 are an evening. Step 6 is the one waiting on someone else.
