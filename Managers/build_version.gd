extends RefCounted

# ─────────────────────────────────────────────
# BUILD VERSION — which export this is.
#
# WRITTEN BY tools/export.ps1 on every export: only the two const lines change,
# so leave their shape alone. The next export takes the higher of VERSION and
# the newest *_v0.NNNx folder in ../Exports, and bumps it: 0.002a -> 0.003a
# (0.002a -> 0.002b with -Hotfix).
#
# Read it through preload, never a class_name, so it works whether or not the
# open editor has registered the script yet.
# ─────────────────────────────────────────────

const VERSION := "0.007a"
const EXPORTED := "2026-09-20"


## "v0.002a" in an exported build. Run from the editor it is "v0.002a+dev":
## work since that export, so a session you played in the editor is never
## mistaken, in the playtest data, for one from the build you sent out.
static func label() -> String:
	return "v%s%s" % [VERSION, "+dev" if OS.has_feature("editor") else ""]
