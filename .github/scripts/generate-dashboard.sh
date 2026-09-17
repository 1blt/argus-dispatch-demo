#!/usr/bin/env bash
# generate-dashboard.sh — Generates a self-contained HTML dashboard + history.json
# for the Argus test suite. Called from the summary job in test-suite.yml.
#
# Expected env vars:
#   ALL_JSON      — merged JSON array of all test results
#   SCOPE         — test scope (all, unit, remote, etc.)
#   RUN_URL       — link to this workflow run
#   RUN_ID        — github.run_id
#   REPO          — owner/repo
#   PAGES_DIR     — directory to write output files into
#   UNIT_JSON, ACTIONS_JSON, REMOTE_JSON, DISCOVER_JSON, COMBO_JSON, EDGE_JSON, WF_JSON, SCN_JSON, REGRESSION_JSON
#   UNIT_RESULT, ACTIONS_RESULT, REMOTE_RESULT, DISCOVER_RESULT, COMBO_RESULT, EDGE_RESULT, SCN_RESULT, I1_RESULT, I2_RESULT, I3_RESULT
#   ARGUS_REPO — upstream repo (e.g., huntridge-labs/argus)
#   ARGUS_REF  — branch/tag being tested (e.g., main)
#   ARGUS_SHA  — full commit SHA of the ref
#   ARGUS_SHA_SHORT — short (7-char) commit SHA
set -euo pipefail

OUT="${PAGES_DIR:?PAGES_DIR not set}"
mkdir -p "$OUT"

# ---------- safe JSON helper (empty string → []) ----------
safe_json() {
  if [ -n "$1" ] && echo "$1" | jq empty 2>/dev/null; then
    echo "$1"
  else
    echo "[]"
  fi
}

UNIT_JSON=$(safe_json "${UNIT_JSON:-}")
ACTIONS_JSON=$(safe_json "${ACTIONS_JSON:-}")
REMOTE_JSON=$(safe_json "${REMOTE_JSON:-}")
DISCOVER_JSON=$(safe_json "${DISCOVER_JSON:-}")
COMBO_JSON=$(safe_json "${COMBO_JSON:-}")
EDGE_JSON=$(safe_json "${EDGE_JSON:-}")
WF_JSON=$(safe_json "${WF_JSON:-}")
SCN_JSON=$(safe_json "${SCN_JSON:-}")
REGRESSION_JSON=$(safe_json "${REGRESSION_JSON:-}")
ALL_JSON=$(safe_json "${ALL_JSON:-}")

# ---------- compute stats ----------
TOTAL=$(echo "$ALL_JSON" | jq 'length')
PASSED=$(echo "$ALL_JSON" | jq '[.[] | select(.status == "pass")] | length')
FAILED=$(echo "$ALL_JSON" | jq '[.[] | select(.status == "FAIL")] | length')
SKIPPED=$(echo "$ALL_JSON" | jq '[.[] | select(.status == "skip" or .status == "cancel")] | length')
RUNNABLE=$((TOTAL - SKIPPED))
[ "$RUNNABLE" -eq 0 ] && RUNNABLE=1
PASS_RATE=$((PASSED * 100 / RUNNABLE))

if [ "$FAILED" -eq 0 ] && [ "$PASSED" -gt 0 ]; then
  VERDICT="PASS"
else
  VERDICT="FAIL"
fi

DATE_STR=$(date -u '+%Y-%m-%d %H:%M UTC')

# ---------- history ----------
HISTORY_FILE="$OUT/history.json"
if [ ! -f "$HISTORY_FILE" ]; then
  echo '[]' > "$HISTORY_FILE"
fi

CURRENT_RUN=$(jq -n -c \
  --arg date "$DATE_STR" \
  --arg scope "$SCOPE" \
  --argjson passed "$PASSED" \
  --argjson total "$TOTAL" \
  --argjson rate "$PASS_RATE" \
  --arg verdict "$VERDICT" \
  --arg url "$RUN_URL" \
  --arg run_id "$RUN_ID" \
  '{date:$date, scope:$scope, passed:$passed, total:$total, rate:$rate, verdict:$verdict, url:$url, run_id:$run_id}')

# Append and cap at 20
jq -c --argjson run "$CURRENT_RUN" '. + [$run] | .[-20:]' "$HISTORY_FILE" > "$HISTORY_FILE.tmp"
mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"

# ---------- build category data for HTML ----------
cat_status() {
  case "${1:-}" in
    success) echo "pass" ;;
    failure) echo "fail" ;;
    skipped) echo "skip" ;;
    cancelled) echo "skip" ;;
    *) echo "unknown" ;;
  esac
}

UNIT_RESULT="${UNIT_RESULT:-skipped}"
ACTIONS_RESULT="${ACTIONS_RESULT:-skipped}"
REMOTE_RESULT="${REMOTE_RESULT:-skipped}"
DISCOVER_RESULT="${DISCOVER_RESULT:-skipped}"
COMBO_RESULT="${COMBO_RESULT:-skipped}"
EDGE_RESULT="${EDGE_RESULT:-skipped}"
WF_RESULT="${WF_RESULT:-skipped}"
SCN_RESULT="${SCN_RESULT:-skipped}"
I1_RESULT="${I1_RESULT:-skipped}"
I2_RESULT="${I2_RESULT:-skipped}"
I3_RESULT="${I3_RESULT:-skipped}"

# Build categories JSON for embedding
CATEGORIES=$(jq -n -c \
  --arg us "$(cat_status "$UNIT_RESULT")" \
  --arg as "$(cat_status "$ACTIONS_RESULT")" \
  --arg rs "$(cat_status "$REMOTE_RESULT")" \
  --arg ds "$(cat_status "$DISCOVER_RESULT")" \
  --arg cs "$(cat_status "$COMBO_RESULT")" \
  --arg es "$(cat_status "$EDGE_RESULT")" \
  --arg ws "$(cat_status "$WF_RESULT")" \
  --arg ss "$(cat_status "$SCN_RESULT")" \
  --arg i1s "$(cat_status "$I1_RESULT")" \
  --arg i2s "$(cat_status "$I2_RESULT")" \
  --arg i3s "$(cat_status "$I3_RESULT")" \
  --argjson u "$UNIT_JSON" \
  --argjson a "$ACTIONS_JSON" \
  --argjson r "$REMOTE_JSON" \
  --argjson d "$DISCOVER_JSON" \
  --argjson co "$COMBO_JSON" \
  --argjson ed "$EDGE_JSON" \
  --argjson wf "$WF_JSON" \
  --argjson sc "$SCN_JSON" \
  --argjson ig "$REGRESSION_JSON" \
  '[
    {name:"Unit Tests (U1–U5)",        status:$us, tests:$u},
    {name:"Direct Action Tests (A1–A5)",status:$as, tests:$a},
    {name:"Remote Mode Tests (R1–R12)", status:$rs, tests:$r},
    {name:"Discover Mode Tests (D1–D4)",status:$ds, tests:$d},
    {name:"Combination Tests (C1–C15)", status:$cs, tests:$co},
    {name:"Edge & Adversarial (E1–E14)", status:$es, tests:$ed},
    {name:"Top-level Workflow Tests (W1–W4)", status:$ws, tests:$wf},
    {name:"SCN Detector Tests (S1–S25)",status:$ss, tests:$sc},
    {name:"Infrastructure Scan (I1)",   status:$i1s,tests:[$ig[0]]},
    {name:"No Hardcoded URLs (I2)",     status:$i2s,tests:[$ig[1]]},
    {name:"Config-Driven Scan (I3)",    status:$i3s,tests:[$ig[2]]}
  ]')

# ---------- test catalog (every test the suite DEFINES, not just what ran) ----
# The run results only contain categories that executed, so on a push (where
# scope=all skips the SCN tests) those 25 tests would vanish from search and the
# page would answer "not tested" about something that is. The catalog is parsed
# straight from the workflow definitions so search is complete regardless of
# scope; run status is layered on top of it in the browser.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WF_DIR="$SCRIPT_DIR/../workflows"

category_for() {
  case "$1" in
    test-unit)            echo "Unit Tests (U1–U5)" ;;
    test-actions-direct)  echo "Direct Action Tests (A1–A5)" ;;
    test-remote)          echo "Remote Mode Tests (R1–R12)" ;;
    test-discover)        echo "Discover Mode Tests (D1–D4)" ;;
    test-combination)     echo "Combination Tests (C1–C15)" ;;
    test-edge)            echo "Edge & Adversarial (E1–E14)" ;;
    test-workflows)       echo "Top-level Workflow Tests (W1–W4)" ;;
    test-scn-detector)    echo "SCN Detector Tests (S1–S25)" ;;
    test-suite)           echo "Regression Tests (I1–I3)" ;;
    *)                    echo "Other" ;;
  esac
}

# Which scope has to be dispatched for a category to run, so the page can say
# WHY a test shows as not run rather than leaving it looking broken.
scope_for() {
  case "$1" in
    test-scn-detector) echo "scn" ;;
    *)                 echo "all" ;;
  esac
}

CATALOG_JSON='[]'
for wf in test-unit test-actions-direct test-remote test-discover test-combination test-edge test-workflows test-scn-detector test-suite; do
  f="$WF_DIR/$wf.yml"
  [ -f "$f" ] || continue
  # Pull the jq array literal the collect step builds, and blank out the shell
  # variable references so it becomes parseable JSON.
  part=$(sed -n "/^ *'\[$/,/^ *\]')$/p" "$f" \
    | sed -e "s/^ *'\[$/[/" -e "s/^ *\]')$/]/" \
    | sed -E 's/:\$[a-z0-9_]+/:null/g' \
    | jq -c --arg cat "$(category_for "$wf")" --arg file ".github/workflows/$wf.yml" \
           --arg scope "$(scope_for "$wf")" \
        '[.[] | {id, name, question: .detail, category: $cat, file: $file, scope: $scope}]' 2>/dev/null) || part=""

  # Line number of each test's job definition, so a row links to the source that
  # defines it instead of repeating the same run URL on every row. Job names look
  # like `name: "R6: fail on critical"`; take the last match per id so E1 lands on
  # the scan job rather than its digest-resolving helper.
  locs=$(grep -nE '^ *name: "[A-Z]+[0-9]+[a-z]?:' "$f" 2>/dev/null \
    | sed -E 's/^([0-9]+): *name: "([A-Z]+[0-9]+)[a-z]?:.*/{"id":"\2","line":\1}/' \
    | jq -s -c 'group_by(.id) | map(max_by(.line))' 2>/dev/null) || locs='[]'
  [ -n "$locs" ] || locs='[]'
  part=$(jq -c -n --argjson p "$part" --argjson l "$locs" \
    '($l | map({(.id): .line}) | add // {}) as $m | $p | map(. + {line: ($m[.id] // null)})')
  if [ -n "$part" ]; then
    CATALOG_JSON=$(jq -c -n --argjson a "$CATALOG_JSON" --argjson b "$part" '$a + $b')
  else
    echo "WARNING: could not parse a test catalog out of $wf.yml"
  fi
done
echo "Test catalog entries: $(echo "$CATALOG_JSON" | jq 'length')"

# ---------- coverage gaps (searchable "is this tested?" corpus) ----------
GAPS_FILE="$SCRIPT_DIR/../data/coverage-gaps.json"
if [ -f "$GAPS_FILE" ] && jq empty "$GAPS_FILE" 2>/dev/null; then
  GAPS_JSON=$(jq -c '.' "$GAPS_FILE")
  echo "Coverage gaps loaded: $(echo "$GAPS_JSON" | jq 'length')"
else
  GAPS_JSON='[]'
  echo "WARNING: no readable $GAPS_FILE — search will not be able to answer 'not covered'"
fi

HISTORY_DATA=$(cat "$HISTORY_FILE")

# ---------- generate HTML ----------
cat > "$OUT/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Argus Test Suite</title>
<link rel="icon" type="image/png" href="favicon.png">
<link rel="apple-touch-icon" href="favicon.png">
<style>
/* Bootswatch Lux-flavoured: Nunito Sans, near-black primary, hairline borders,
   square corners, uppercase letter-spaced labels, generous whitespace.
   Hand-written rather than pulling Bootstrap + Lux (≈250KB) so the page stays a
   single self-contained file; only the typeface is fetched. */
@import url('https://fonts.googleapis.com/css2?family=Nunito+Sans:ital,wght@0,300;0,400;0,600;0,700&display=swap');
:root {
  --bg: #ffffff; --surface: #ffffff; --surface2: #f8f9fa;
  --fg: #1a1a1a; --fg2: #55595c; --fg3: #919aa1;
  --border: #dee2e6; --rule: #ebedef;
  --primary: #1a1a1a;
  --pass: #4bbf73; --pass-bg: #edf9f1; --pass-ink: #2f8f52;
  --fail: #d9534f; --fail-bg: #fdefee; --fail-ink: #b8413d;
  --warn: #f0ad4e; --warn-bg: #fef7ec; --warn-ink: #a3701f;
  --idle: #919aa1; --idle-bg: #f3f5f6;
  --accent: #1a1a1a;
  --radius: 0px;
  --track: 0.08em;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
  /* Night: Lux's geometry and typography, but ink on charcoal rather than a
     mechanical inversion. Warm ivory text on a cool near-black, hairline rules
     that sit just above the background, and semantic hues pulled down in
     saturation so they read as accents rather than alerts. */
  --bg: #101214; --surface: #16191c; --surface2: #1b1f23;
  --fg: #ece9e4; --fg2: #a7adb3; --fg3: #737b82;
  --border: #282d32; --rule: #1f2429;
  --primary: #ece9e4;
  --pass: #5cbf82; --pass-bg: #14241a; --pass-ink: #7fd49f;
  --fail: #e06c69; --fail-bg: #281618; --fail-ink: #ef918e;
  --warn: #e3ad63; --warn-bg: #261e13; --warn-ink: #e8c48c;
  --idle: #737b82; --idle-bg: #1b1f23;
  --accent: #ece9e4;
  }
}
:root[data-theme="dark"] {
  /* Night: Lux's geometry and typography, but ink on charcoal rather than a
     mechanical inversion. Warm ivory text on a cool near-black, hairline rules
     that sit just above the background, and semantic hues pulled down in
     saturation so they read as accents rather than alerts. */
  --bg: #101214; --surface: #16191c; --surface2: #1b1f23;
  --fg: #ece9e4; --fg2: #a7adb3; --fg3: #737b82;
  --border: #282d32; --rule: #1f2429;
  --primary: #ece9e4;
  --pass: #5cbf82; --pass-bg: #14241a; --pass-ink: #7fd49f;
  --fail: #e06c69; --fail-bg: #281618; --fail-ink: #ef918e;
  --warn: #e3ad63; --warn-bg: #261e13; --warn-ink: #e8c48c;
  --idle: #737b82; --idle-bg: #1b1f23;
  --accent: #ece9e4;
}
}
*, *::before, *::after { box-sizing: border-box; }
body {
  font-family: 'Nunito Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
  background: var(--bg); color: var(--fg2); margin: 0;
  font-size: 15px; font-weight: 400; line-height: 1.6;
  -webkit-font-smoothing: antialiased;
}
.container { max-width: 1160px; margin: 0 auto; padding: 36px 28px 72px; }
a { color: var(--primary); text-decoration: none; border-bottom: 1px solid var(--border); }
a:hover { border-bottom-color: var(--primary); }
.mono { font-family: ui-monospace, 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace; font-size: 0.92em; }

/* Lux signature: small, uppercase, widely tracked labels */
.lbl { text-transform: uppercase; letter-spacing: var(--track); font-weight: 600; font-size: 0.7rem; color: var(--fg3); }

header { display: flex; align-items: baseline; gap: 18px; flex-wrap: wrap; margin-bottom: 30px; padding-bottom: 18px; border-bottom: 1px solid var(--border); }
header h1 {
  margin: 0; font-size: 1.05rem; font-weight: 700; color: var(--fg);
  text-transform: uppercase; letter-spacing: 0.12em;
}
.head-meta { margin-left: auto; font-size: 0.78rem; color: var(--fg3); display: flex; gap: 12px; flex-wrap: wrap; align-items: baseline; }
.head-meta .sep { color: var(--border); }
.head-meta a { border-bottom: 0; }
.head-meta a:hover { border-bottom: 1px solid var(--primary); }

.card { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); }

.hero { display: grid; grid-template-columns: minmax(300px, 1fr) minmax(260px, 0.95fr); margin-bottom: 18px; overflow: hidden; }
@media (max-width: 760px) { .hero { grid-template-columns: 1fr; } }
.hero-left { padding: 26px 28px; display: flex; flex-direction: column; gap: 16px; }
.hero-right {
  padding: 22px 26px; border-left: 1px solid var(--border);
  display: flex; flex-direction: column; justify-content: flex-end;
}
@media (max-width: 760px) { .hero-right { border-left: 0; border-top: 1px solid var(--border); } }
.verdict-row { display: flex; align-items: center; gap: 18px; }
.badge {
  font-size: 2.1rem; font-weight: 700; line-height: 1; padding: 12px 20px;
  border-radius: var(--radius); font-variant-numeric: tabular-nums; border: 1px solid transparent;
}
.badge.g-a, .badge.g-b { background: var(--pass-bg); color: var(--pass-ink); border-color: var(--pass); }
.badge.g-c { background: var(--warn-bg); color: var(--warn-ink); border-color: var(--warn); }
.badge.g-d, .badge.g-f { background: var(--fail-bg); color: var(--fail-ink); border-color: var(--fail); }
.rate { font-size: 1.7rem; font-weight: 300; line-height: 1.15; color: var(--fg); letter-spacing: -0.01em; }
.rate .pct { display: block; font-size: 0.7rem; font-weight: 600; color: var(--fg3); text-transform: uppercase; letter-spacing: var(--track); margin-top: 4px; }
.delta { font-size: 0.72rem; text-transform: uppercase; letter-spacing: var(--track); font-weight: 600; color: var(--fg3); }
.delta.up { color: var(--pass-ink); } .delta.down { color: var(--fail-ink); }
.stats { display: flex; gap: 8px; flex-wrap: wrap; }
.stat {
  display: inline-flex; align-items: baseline; gap: 6px; padding: 6px 12px;
  border-radius: var(--radius); font-size: 0.68rem; font-weight: 600;
  text-transform: uppercase; letter-spacing: var(--track);
  background: transparent; border: 1px solid var(--border); color: var(--fg3);
  cursor: pointer; font-family: inherit; --chip: var(--fg3);
}
.stat.pass { --chip: var(--pass); } .stat.fail { --chip: var(--fail); }
.stat.warn { --chip: var(--warn); } .stat.idle { --chip: var(--idle); }
.stat.info { --chip: var(--fg3); }
.stat b { font-size: 0.95rem; font-weight: 700; color: var(--fg); letter-spacing: 0; }
.stat.pass b { color: var(--pass-ink); } .stat.fail b { color: var(--fail-ink); }
.stat.warn b { color: var(--warn-ink); } .stat.idle b { color: var(--fg2); }
.stat:hover { border-color: var(--chip); color: var(--fg2); }
.stat[aria-pressed="true"] { border-color: var(--chip); box-shadow: inset 0 -2px 0 var(--chip); color: var(--fg); }
.grade-note { font-size: 0.75rem; color: var(--fg3); line-height: 1.6; max-width: 52ch; }
.trend-head { display: flex; justify-content: space-between; align-items: baseline; gap: 10px; margin-bottom: 8px; }
.trend-head > span:first-child { text-transform: uppercase; letter-spacing: var(--track); font-weight: 600; font-size: 0.68rem; color: var(--fg3); }
.trend-svg { width: 100%; height: 116px; display: block; overflow: visible; }
.ax-grid { stroke: var(--rule); stroke-width: 1; }
.ax-lbl { font-size: 9px; fill: var(--fg3); font-family: inherit; letter-spacing: 0.04em; }
.pt-lbl { font-size: 9px; font-weight: 600; fill: var(--fg3); font-family: inherit; }
.pt-lbl.last { font-weight: 700; fill: var(--fg); }
.trend-area { fill: var(--fg3); opacity: 0.12; }
.trend-line { fill: none; stroke: var(--fg2); stroke-width: 1.5; }
.trend-dot { fill: var(--fg2); }
.trend-dot.fail { fill: var(--bg); stroke: var(--fg2); stroke-width: 1.4; }
.trend-dot.last { fill: var(--fg); }
.trend-hit { fill: transparent; cursor: pointer; }
.tip {
  position: absolute; background: var(--fg); color: var(--bg); border-radius: var(--radius);
  padding: 8px 11px; font-size: 0.72rem; pointer-events: none; z-index: 50; white-space: nowrap;
}

.search { padding: 18px 20px; margin-bottom: 14px; }
.search:focus-within { border-color: var(--primary); }
.search-row { display: flex; align-items: center; gap: 12px; }
.search-row svg { flex: none; color: var(--fg3); }
.input-wrap { position: relative; flex: 1; display: flex; min-width: 0; }
.ghost {
  position: absolute; inset: 0; display: flex; align-items: center;
  font: inherit; font-size: 0.98rem; font-weight: 400; white-space: pre;
  overflow: hidden; pointer-events: none; padding: 4px 0;
}
.ghost .typed { color: transparent; }
.ghost .rest { color: var(--fg3); }
#q {
  flex: 1; border: 0; background: transparent; color: var(--fg); position: relative;
  font: inherit; font-size: 0.98rem; font-weight: 400; padding: 4px 0; outline: none; min-width: 0;
}
#q::placeholder { color: var(--fg3); font-weight: 300; }
.clear-btn {
  flex: none; background: transparent; border: 0; color: var(--fg3);
  font-family: inherit; font-size: 1.15rem; line-height: 1; cursor: pointer; padding: 0 4px;
}
.clear-btn:hover { color: var(--fg); }
.ghost .tabhint {
  margin-left: 10px; font-size: 0.62rem; font-weight: 600; color: var(--fg3);
  text-transform: uppercase; letter-spacing: var(--track);
  border: 1px solid var(--border); border-radius: var(--radius); padding: 1px 5px;
}
.kbd {
  font-size: 0.64rem; color: var(--fg3); border: 1px solid var(--border);
  border-radius: var(--radius); padding: 2px 7px; text-transform: uppercase; letter-spacing: var(--track);
}
.verdict { margin-top: 16px; padding: 13px 15px; border-radius: var(--radius); font-size: 0.85rem; display: none; border-left: 3px solid transparent; }
.verdict.show { display: block; }
.verdict b { font-weight: 700; text-transform: uppercase; letter-spacing: var(--track); font-size: 0.74rem; display: block; margin-bottom: 3px; }
.verdict.yes { background: var(--pass-bg); border-left-color: var(--pass); color: var(--pass-ink); }
.verdict.no { background: var(--fail-bg); border-left-color: var(--fail); color: var(--fail-ink); }
.verdict.maybe { background: var(--warn-bg); border-left-color: var(--warn); color: var(--warn-ink); }
.verdict .sub { color: var(--fg2); font-weight: 400; }
.try { margin-top: 14px; display: flex; gap: 8px; flex-wrap: wrap; justify-content: center; }
.try-btn {
  font-family: inherit; font-size: 0.68rem; padding: 5px 11px; border-radius: var(--radius);
  cursor: pointer; background: transparent; border: 1px solid var(--border); color: var(--fg3);
  text-transform: uppercase; letter-spacing: var(--track); font-weight: 600;
}
.try-btn:hover { border-color: var(--primary); color: var(--fg); }

.table-bar { display: flex; align-items: baseline; gap: 12px; margin: 0 0 10px; }
#caption { text-transform: uppercase; letter-spacing: var(--track); font-weight: 600; font-size: 0.68rem; color: var(--fg3); }
table { width: 100%; border-collapse: collapse; }
thead th {
  position: sticky; top: 0; z-index: 10; text-align: left; background: var(--bg);
  border-bottom: 2px solid var(--fg); font-size: 0.66rem; font-weight: 700;
  letter-spacing: var(--track); text-transform: uppercase; color: var(--fg); padding: 11px 12px;
}
tbody td { padding: 12px; border-bottom: 1px solid var(--rule); vertical-align: top; }
tbody tr.t:hover td { background: var(--surface2); }
tr.grp td {
  background: var(--surface2); font-size: 0.66rem; font-weight: 700; color: var(--fg);
  letter-spacing: var(--track); text-transform: uppercase; padding: 9px 12px;
  border-bottom: 1px solid var(--border); border-top: 1px solid var(--border);
}
tr.grp .gcount { float: right; font-weight: 600; color: var(--fg3); }
td.c-st { width: 1%; white-space: nowrap; padding-left: 14px; }
.dot { display: inline-block; width: 9px; height: 9px; border-radius: 50%; vertical-align: middle; }
.dot.pass { background: var(--pass); } .dot.fail { background: var(--fail); }
.dot.skip { background: var(--warn); } .dot.idle { background: var(--idle); }
.dot.gap { background: var(--warn); }
.dot.untested { background: var(--fail); }
.dot.upstream { background: var(--idle); }
td.c-id { width: 1%; white-space: nowrap; font-size: 0.72rem; font-weight: 700; color: var(--fg); letter-spacing: 0.04em; }
td.c-q { font-size: 0.875rem; color: var(--fg); font-weight: 400; }
td.c-q .why { color: var(--fg3); font-size: 0.78rem; margin-top: 5px; line-height: 1.55; font-weight: 300; }
td.c-q .checks { color: var(--fg3); font-size: 0.73rem; margin-top: 6px; line-height: 1.6; font-weight: 300; }
td.c-q .checks.empty-checks { color: var(--fail-ink); }
td.c-q .checks .n, td.c-q .checks .bad, td.c-q .checks .dim {
  text-transform: uppercase; letter-spacing: var(--track); font-weight: 700;
  font-size: 0.64rem; margin-right: 8px;
}
td.c-q .checks .n { color: var(--fg2); }
td.c-q .checks .bad { color: var(--fail-ink); }
td.c-q .checks .dim { color: var(--fg3); }
td.c-q .checks .failed-names { color: var(--fail-ink); margin-top: 3px; font-weight: 400; }
td.c-q .checks .all-checks { margin-top: 3px; }
td.c-cat { width: 1%; white-space: nowrap; font-size: 0.68rem; color: var(--fg3); text-transform: uppercase; letter-spacing: var(--track); font-weight: 600; }
td.c-lnk { width: 1%; white-space: nowrap; text-align: right; font-size: 0.68rem; text-transform: uppercase; letter-spacing: var(--track); font-weight: 600; }
td.c-lnk a { margin-left: 10px; border-bottom: 0; color: var(--fg3); }
td.c-lnk a:hover { color: var(--fg); border-bottom: 1px solid var(--fg); }
tr.t.failing td { background: var(--fail-bg); }
tr.t.failing td.c-st { box-shadow: inset 3px 0 0 var(--fail); }
tr.hidden { display: none; }
mark { background: rgba(240,173,78,0.28); color: inherit; padding: 0 2px; }
.empty { padding: 44px 12px; text-align: center; color: var(--fg3); font-size: 0.85rem; }
.none { color: var(--fg3); }
footer { margin-top: 44px; padding-top: 20px; border-top: 1px solid var(--border); font-size: 0.72rem; color: var(--fg3); }

/* theme toggle */
.theme-toggle {
  background: transparent; border: 1px solid var(--border); border-radius: var(--radius);
  color: var(--fg3); font: inherit; font-size: 0.64rem; font-weight: 600;
  text-transform: uppercase; letter-spacing: var(--track); padding: 4px 9px; cursor: pointer;
}
.theme-toggle:hover { border-color: var(--primary); color: var(--fg); }
</style>
</head>
<body>
<div class="container">
  <header>
    <h1>Argus Test Suite</h1>
    <div class="head-meta" id="head-meta"></div>
    <button class="theme-toggle" id="theme-toggle" type="button" title="Switch theme"></button>
  </header>

  <section class="card hero">
    <div class="hero-left">
      <div class="verdict-row">
        <span class="badge" id="badge"></span>
        <span class="rate" id="rate"></span>
      </div>
      <div class="stats" id="stats"></div>
      <div class="grade-note" id="grade-note"></div>
    </div>
    <div class="hero-right">
      <div class="trend-head"><span id="trend-label"></span><span class="delta" id="delta"></span></div>
      <svg id="trend" class="trend-svg"></svg>
    </div>
  </section>

  <section class="card search">
    <div class="search-row">
      <svg width="15" height="15" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M10.68 11.74a6 6 0 01-7.922-8.982 6 6 0 018.982 7.922l3.04 3.04a.749.749 0 01-.326 1.275.749.749 0 01-.734-.215zM11.5 7a4.5 4.5 0 10-9 0 4.5 4.5 0 009 0"/></svg>
      <span class="input-wrap">
        <span class="ghost" id="ghost" aria-hidden="true"></span>
        <input id="q" type="text" autocomplete="off" autocorrect="off" spellcheck="false"
               placeholder="Is this behaviour tested?">
      </span>
      <button class="clear-btn" id="clear" type="button" title="Clear search and filters" hidden>&times;</button>
      <span class="kbd" id="kbd">/</span>
    </div>
    <div id="verdict" class="verdict"></div>
  </section>

  <div class="table-bar"><span id="caption"></span></div>
  <table>
    <thead><tr>
      <th class="c-st"></th><th>ID</th><th>What it checks</th><th>Category</th><th style="text-align:right">Definition</th><th style="text-align:right">Logs</th>
    </tr></thead>
    <tbody id="rows"></tbody>
  </table>
  <div class="empty" id="empty" style="display:none"></div>

  <footer id="foot"></footer>
</div>
<div class="tip" id="tip" style="display:none"></div>
<script>
HTMLEOF

# Inject the data as JS variables
{
  echo "const DATA = {"
  echo "  verdict: \"$VERDICT\","
  echo "  date: \"$DATE_STR\","
  echo "  scope: \"$SCOPE\","
  echo "  passed: $PASSED,"
  echo "  failed: $FAILED,"
  echo "  skipped: $SKIPPED,"
  echo "  total: $TOTAL,"
  echo "  passRate: $PASS_RATE,"
  echo "  runUrl: \"$RUN_URL\","
  echo "  repo: \"$REPO\","
  echo "  argusRepo: \"${ARGUS_REPO:-}\","
  echo "  argusRef: \"${ARGUS_REF:-}\","
  echo "  argusSha: \"${ARGUS_SHA:-}\","
  echo "  argusShaShort: \"${ARGUS_SHA_SHORT:-}\","
  echo "  argusVersion: \"${ARGUS_VERSION:-}\","
  echo "  selfSha: \"${SELF_SHA:-main}\","
  printf '  categories: %s,\n' "$CATEGORIES"
  printf '  gaps: %s,\n' "$GAPS_JSON"
  printf '  catalog: %s,\n' "$CATALOG_JSON"
  printf '  jobs: %s,\n' "${JOBS_JSON:-[]}"
  printf '  history: %s\n' "$HISTORY_DATA"
  echo "};"
} >> "$OUT/index.html"

cat >> "$OUT/index.html" << 'HTMLEOF2'

(function () {
  const d = DATA;
  const server = d.runUrl.split('/').slice(0, 3).join('/');
  const repoUrl = server + '/' + d.repo;
  const srcBase = repoUrl + '/blob/' + (d.selfSha || 'main') + '/';

  const EXAMPLES = ['block the build when a critical CVE is found',
    'scan an image pinned by digest', 'SBOM only, no vulnerability gate',
    'private registry credentials', 'detect secrets in a repo',
    'post a comment on a pull request'];

  function esc(t) {
    return String(t == null ? '' : t).replace(/[&<>"]/g, function (m) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[m];
    });
  }
  const $ = function (id) { return document.getElementById(id); };

  // ---------------------------------------------------------------- header
  var meta = [];
  // On main, every push cuts a release, so the ref, the version and the commit
  // all say the same thing -- collapse to the version and keep the exact commit
  // in the link target and tooltip so no precision is lost. On any other ref a
  // version number would be a lie (the branch predates or postdates the release
  // it reports), so fall back to naming the ref and its commit.
  if (d.argusRepo) {
    const onMain = (d.argusRef || 'main') === 'main';
    const known = d.argusSha && d.argusSha !== 'unknown';
    if (onMain && d.argusVersion) {
      const el = '<a href="' + server + '/' + d.argusRepo + '/releases/tag/' + esc(d.argusVersion) + '"' +
                 (known ? ' title="commit ' + esc(d.argusShaShort) + '"' : '') +
                 '>argus <span class="mono">v' + esc(d.argusVersion) + '</span></a>';
      meta.push(el);
    } else if (known) {
      meta.push('<a href="' + server + '/' + d.argusRepo + '/tree/' + esc(d.argusRef) + '">argus@' + esc(d.argusRef) + '</a>' +
                ' <a class="mono" href="' + server + '/' + d.argusRepo + '/commit/' + d.argusSha + '">' + esc(d.argusShaShort) + '</a>');
    } else {
      meta.push('argus@' + esc(d.argusRef || 'main'));
    }
  }
  meta.push(esc(d.date));
  meta.push('scope <span class="mono">' + esc(d.scope) + '</span>');
  meta.push('<a href="' + d.runUrl + '">view run &#8599;</a>');
  $('head-meta').innerHTML = meta.join('<span class="sep">&middot;</span>');

  // ---------------------------------------------------------------- corpus
  const ran = {};
  d.categories.forEach(function (cat) {
    cat.tests.forEach(function (t) {
      ran[t.id] = { status: t.status, category: cat.name, detail: t.detail,
                    checks: t.checks, stats: t.stats };
    });
  });
  const docs = [];
  const seen = {};
  (d.catalog || []).forEach(function (c) {
    const r = ran[c.id];
    seen[c.id] = true;
    docs.push({
      kind: 'test', id: c.id, name: c.name,
      question: (r && r.detail) || c.question || '',
      status: r ? r.status : 'notrun',
      category: c.category || (r && r.category),
      file: c.file || '', line: c.line || null, why: '', scope: c.scope || 'all',
      checks: (r && r.checks) || c.checks || null,
      stats: (r && r.stats) || null
    });
  });
  d.categories.forEach(function (cat) {
    cat.tests.forEach(function (t) {
      if (seen[t.id]) return;
      docs.push({
        kind: 'test', id: t.id, name: t.name, question: t.detail || '',
        status: t.status, category: cat.name, file: '', line: null, why: '',
        checks: t.checks || null, stats: t.stats || null
      });
    });
  });
  // Named so a reader never has to look up what the word means.
  const KIND_CAT = {
    untested: 'Not tested anywhere',
    gap: 'Deliberately not tested here',
    upstream: 'Tested by argus itself, not here'
  };
  const KIND_ORDER = { untested: 0, gap: 1, upstream: 2 };
  (d.gaps || []).slice().sort(function (a, b) {
    return (KIND_ORDER[a.kind] == null ? 1 : KIND_ORDER[a.kind]) -
           (KIND_ORDER[b.kind] == null ? 1 : KIND_ORDER[b.kind]);
  }).forEach(function (g) {
    const k = KIND_CAT[g.kind] ? g.kind : 'gap';
    docs.push({
      kind: k, id: g.id, name: g.name, question: g.question || '', status: k,
      category: KIND_CAT[k], file: '.github/data/coverage-gaps.json',
      line: null, why: g.why || '', ref: g.ref || ''
    });
  });

  // GitHub gives no per-test URL, but each test is a job, and job names carry
  // the test id ("Remote Mode Tests / R6: fail on critical / ..."). Mapping them
  // makes the Logs column land on the job instead of repeating the run URL.
  // Best-effort: if the jobs API was unavailable, rows fall back to the run.
  const jobUrl = {};
  (d.jobs || []).forEach(function (j) {
    const m = String(j.name || '').match(/(?:^|\/)\s*([A-Z]+\d+[a-z]?)\s*:/);
    if (m && !jobUrl[m[1]]) jobUrl[m[1]] = j.url;
  });

  const tests = docs.filter(function (x) { return x.kind === 'test'; });
  const nGapReal = docs.filter(function (x) { return x.kind === 'gap'; }).length;
  const nUntested = docs.filter(function (x) { return x.kind === 'untested'; }).length;
  const nUpstream = docs.filter(function (x) { return x.kind === 'upstream'; }).length;
  const nPass = tests.filter(function (x) { return x.status === 'pass'; }).length;
  const nFail = tests.filter(function (x) { return x.status === 'FAIL'; }).length;
  const nIdle = tests.filter(function (x) { return x.status === 'notrun' || x.status === 'skip' || x.status === 'cancel'; }).length;


  // ------------------------------------------------------------------ hero
  const ranCount = nPass + nFail;
  const rate = ranCount ? Math.round((nPass / ranCount) * 100) : 0;

  // Grade is passed over every test the suite DEFINES, not just the ones that
  // ran: a test that did not run provides no assurance, so counting only the
  // runners would let a suite that skips most of itself score an A. Failures
  // then cap the letter, because in a security suite "96% passing" is not an A
  // when the 4% is a gate that stopped enforcing.
  function gradeOf(passed, failed, defined) {
    if (!defined) return { letter: '\u2013', score: 0 };
    var score = (passed / defined) * 100;
    if (failed > 0) score = Math.min(score, 89);
    if (failed >= 3) score = Math.min(score, 79);
    return {
      letter: score >= 90 ? 'A' : score >= 80 ? 'B' : score >= 70 ? 'C' : score >= 60 ? 'D' : 'F',
      score: Math.round(score)
    };
  }
  const grade = gradeOf(nPass, nFail, tests.length);
  $('badge').className = 'badge g-' + grade.letter.toLowerCase();
  $('badge').textContent = grade.letter;
  $('badge').title = 'Score ' + grade.score + '/100';
  $('rate').innerHTML = nPass + '<span class="pct">/' + tests.length + ' tests passing</span>';

  var note = 'Grade is passed \u00f7 ' + tests.length + ' defined tests.';
  if (nIdle) note += ' The ' + nIdle + ' not run count as no assurance, not as passes.';
  if (nFail) note += ' A failing test caps the grade at B.';
  $('grade-note').textContent = note;

  const hist = d.history || [];
  if (hist.length >= 2) {
    const prev = hist[hist.length - 2].rate;
    const diff = rate - prev;
    const el = $('delta');
    el.className = 'delta ' + (diff > 0 ? 'up' : diff < 0 ? 'down' : '');
    el.textContent = diff === 0 ? 'no change vs last run'
      : (diff > 0 ? '▲ +' : '▼ ') + diff + ' pts vs last run';
  }

  // Only this run's outcomes. gaps/untested/upstream are editorial notes from
  // coverage-gaps.json, not results -- putting them here mixed "what happened"
  // with "what we chose not to check", and three of the seven chips never moved
  // between runs. They keep their own labelled sections at the foot of the table.
  const STAT_DEFS = [
    { key: 'passing', cls: 'pass', label: 'passing', n: nPass },
    { key: 'failing', cls: 'fail', label: 'failing', n: nFail },
    { key: 'not-run', cls: 'idle', label: 'not run', n: nIdle }
  ];
  const statsEl = $('stats');
  STAT_DEFS.forEach(function (s) {
    if (s.n === 0 && s.key !== 'all') return;
    const b = document.createElement('button');
    b.className = 'stat ' + s.cls;
    b.type = 'button';
    b.dataset.filter = s.key;
    b.setAttribute('aria-pressed', s.key === 'all' ? 'true' : 'false');
    b.innerHTML = '<b>' + s.n + '</b> ' + s.label;
    b.addEventListener('click', function () { toggleFilter(s.key); });
    statsEl.appendChild(b);
  });
  function syncStats(active) {
    Array.prototype.forEach.call(statsEl.children, function (b) {
      const k = b.dataset.filter;
      const on = active.indexOf(k) > -1;
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
  }
  // Clicking a chip edits the query text, so the two can never disagree.
  function toggleFilter(key) {
    const cur = parseQuery(input.value);
    var toks;
    if (key === 'all') toks = [];
    else if (cur.filters.indexOf(key) > -1) toks = cur.filters.filter(function (f) { return f !== key; });
    else toks = [key];                     // statuses are exclusive: one at a time
    input.value = (toks.map(function (f) { return 'is:' + f; }).join(' ') + ' ' + cur.text).trim();
    paintGhost();
    onInput();
  }

  // ----------------------------------------------------------------- trend
  const nFailedRuns = hist.filter(function (p) { return p.verdict !== 'PASS'; }).length;
  $('trend-label').textContent = 'Score by run date, last ' + hist.length + ' run' +
    (hist.length === 1 ? '' : 's') + (nFailedRuns ? ' \u00b7 \u25cb = failed run' : '');
  function drawTrend() {
    const svg = $('trend'), tip = $('tip');
    if (hist.length < 2) {
      svg.innerHTML = '<text x="0" y="34" class="rel" fill="currentColor" font-size="11">Not enough runs yet</text>';
      return;
    }
    // Axes: run date along x, score along y. Without them the sparkline showed a
    // shape but no magnitude -- you could not tell 60% from 95%.
    const W = svg.getBoundingClientRect().width || 340, H = 116;
    const padL = 30, padR = 10, padT = 16, padB = 20;
    const plotW = W - padL - padR, plotH = H - padT - padB;
    svg.setAttribute('viewBox', '0 0 ' + W + ' ' + H);
    const xs = function (i) { return padL + (hist.length === 1 ? plotW / 2 : i * (plotW / (hist.length - 1))); };
    const ys = function (v) { return padT + plotH - (v / 100) * plotH; };
    var g = '';

    [0, 50, 100].forEach(function (v) {
      g += '<line class="ax-grid" x1="' + padL + '" y1="' + ys(v) + '" x2="' + (W - padR) + '" y2="' + ys(v) + '"/>' +
           '<text class="ax-lbl" x="' + (padL - 6) + '" y="' + (ys(v) + 3) + '" text-anchor="end">' + v + '</text>';
    });
    // First, middle and last run date -- enough to orient without crowding.
    var ticks = hist.length > 2 ? [0, Math.floor((hist.length - 1) / 2), hist.length - 1] : [0, hist.length - 1];
    ticks.filter(function (v, i, a) { return a.indexOf(v) === i; }).forEach(function (i) {
      const d0 = String(hist[i].date || '').split(' ')[0].slice(5);   // MM-DD
      const anchor = i === 0 ? 'start' : (i === hist.length - 1 ? 'end' : 'middle');
      g += '<text class="ax-lbl" x="' + xs(i) + '" y="' + (H - 6) + '" text-anchor="' + anchor + '">' + esc(d0) + '</text>';
    });

    var area = 'M' + xs(0) + ',' + (padT + plotH), line = '';
    hist.forEach(function (p, i) {
      area += ' L' + xs(i) + ',' + ys(p.rate);
      line += (i ? ' L' : 'M') + xs(i) + ',' + ys(p.rate);
    });
    area += ' L' + xs(hist.length - 1) + ',' + (padT + plotH) + ' Z';
    g += '<path class="trend-area" d="' + area + '"/><path class="trend-line" d="' + line + '"/>';
    hist.forEach(function (p, i) {
      if (p.verdict !== 'PASS') g += '<circle class="trend-dot fail" cx="' + xs(i) + '" cy="' + ys(p.rate) + '" r="2.8"/>';
    });

    // Label each point with its score. If the runs are packed too tightly for
    // that to be readable, fall back to the points worth calling out: the
    // newest, the best and the worst.
    const spacing = hist.length > 1 ? plotW / (hist.length - 1) : plotW;
    var labelAt;
    if (spacing >= 30) {
      labelAt = hist.map(function (_, i) { return i; });
    } else {
      var best = 0, worst = 0;
      hist.forEach(function (p, i) {
        if (p.rate > hist[best].rate) best = i;
        if (p.rate < hist[worst].rate) worst = i;
      });
      labelAt = [0, best, worst, hist.length - 1];
    }
    labelAt.filter(function (v, i, a) { return a.indexOf(v) === i; }).forEach(function (i) {
      const p = hist[i];
      const anchor = i === 0 ? 'start' : (i === hist.length - 1 ? 'end' : 'middle');
      // Keep the label inside the plot when the point sits near the ceiling.
      const above = ys(p.rate) - 6 > padT + 8;
      g += '<text class="pt-lbl' + (i === hist.length - 1 ? ' last' : '') + '" x="' + xs(i) +
           '" y="' + (above ? ys(p.rate) - 6 : ys(p.rate) + 12) + '" text-anchor="' + anchor + '">' +
           p.rate + '</text>';
    });
    g += '<circle class="trend-dot last" cx="' + xs(hist.length - 1) + '" cy="' + ys(hist[hist.length - 1].rate) + '" r="3.2"/>';
    const bw = plotW / hist.length;
    hist.forEach(function (p, i) {
      g += '<rect class="trend-hit" x="' + (xs(i) - bw / 2) + '" y="0" width="' + bw + '" height="' + H + '" data-i="' + i + '"/>';
    });
    svg.innerHTML = g;
    svg.querySelectorAll('.trend-hit').forEach(function (r) {
      r.addEventListener('mouseenter', function (e) {
        const p = hist[+r.dataset.i];
        tip.innerHTML = '<b>' + esc(p.date) + '</b><br>' + p.verdict + ' &middot; ' + p.passed + '/' + p.total + ' (' + p.rate + '%)';
        tip.style.display = 'block';
        tip.style.left = (e.clientX + window.scrollX + 12) + 'px';
        tip.style.top = (e.clientY + window.scrollY - 44) + 'px';
      });
      r.addEventListener('mouseleave', function () { tip.style.display = 'none'; });
      r.addEventListener('click', function () { window.open(hist[+r.dataset.i].url, '_blank'); });
    });
  }
  drawTrend();
  window.addEventListener('resize', drawTrend);

  // ------------------------------------------------------- search engine
  // Concept-aware lexical search: a domain thesaurus plus IDF-weighted term and
  // concept overlap. Not embeddings — this page is static, has no backend and
  // can hold no API key, and on ~100 short strings of jargon like
  // `allow_failure` a thesaurus beats a general sentence model.
  const STOP = new Set(('a an the is are was were be been being do does did done will would can could ' +
    'should if when whether that this these those it its to for with and or but of on in at by from as ' +
    'my our your i we you what how why there any some argus test tests suite run runs').split(' '));
  const THESAURUS = {
    gate_fail: 'fail fails failing failed failure block blocks blocking blocked reject rejects refuse stop stops break breaks red abort aborts enforce enforces enforced enforcement gate gates gating deny denies prevent prevents catch catches flag flags',
    gate_pass: 'pass passes passing passed succeed succeeds success successful green allow allows allowed tolerate tolerates ignore ignores continue proceed complete completes',
    severity: 'severity severities threshold thresholds critical criticals high medium low cvss level levels fail_on_severity strict',
    vulnerability: 'vulnerability vulnerabilities vuln vulns cve cves finding findings issue issues advisory advisories insecure exploit risky',
    allow_failure: 'allow_failure allowfailure override overrides bypass bypasses bypassed nonblocking informational soft warn warning',
    sbom: 'sbom syft bom inventory components spdx cyclonedx bill materials',
    trivy: 'trivy aquasecurity',
    grype: 'grype anchore',
    dedup: 'dedup deduplicate deduplicated deduplication duplicate duplicates duplicated twice overlap overlapping merged same both',
    discover: 'discover discovery discovers dockerfile dockerfiles build builds building built local repo repository find finds glob search',
    remote: 'remote image images pull pulls pulled registry registries tag tags digest sha256 reference refs nginx alpine distroless',
    auth: 'auth authentication authenticate credential credentials password passwords token tokens login username private registry_username registry_password',
    sarif: 'sarif codescanning scanning upload uploads uploaded alerts enable_code_security tab',
    config: 'config configuration configs yaml yml schema matrix parse parses parsing container_config validate validation',
    scn: 'scn fedramp classification classify classifies classified routine adaptive transformative impact significant notification compliance manual_review',
    iac: 'iac terraform tf kubernetes k8s cloudformation cfn infrastructure checkov kics aws resource resources',
    container: 'container containers docker oci podman',
    empty: 'empty none nothing zero missing blank absent unset null omitted',
    invalid: 'invalid bad wrong malformed typo unknown unrecognised unrecognized bogus nonexistent garbage junk misspelled broken corrupt',
    ghes: 'ghes enterprise onprem selfhosted airgapped hardcoded github.com urls',
    pr_comment: 'comment comments commented pr pullrequest post posts review',
    secrets: 'gitleaks leak leaks leaked secret secrets hardcoded exposed key keys',
    dependency: 'dependency dependencies deps sca osv supplychain supply chain provenance package packages',
    dast: 'zap dast webapp web application endpoint url running',
    lint: 'lint linter linters linting style format hadolint ruff eslint',
    cli: 'cli commandline command terminal locally pip pypi python package sdk',
    ports: 'port ports exposed exposure service services listening network',
    naming: 'name names naming sanitise sanitize sanitisation character characters slash space uppercase special',
    arch: 'arch architecture arm64 amd64 platform multiarch multi'
  };
  function stem(w) {
    if (w.length > 5 && /(isation|ization)$/.test(w)) return w.replace(/(isation|ization)$/, 'ise');
    if (w.length > 5 && w.endsWith('ing')) return w.slice(0, -3);
    if (w.length > 5 && w.endsWith('ed')) return w.slice(0, -2);
    if (w.length > 4 && w.endsWith('es')) return w.slice(0, -2);
    if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) return w.slice(0, -1);
    return w;
  }
  function terms(text) {
    const out = [];
    ((text || '').toLowerCase().match(/[a-z0-9_.]+/g) || []).forEach(function (raw) {
      if (STOP.has(raw)) return;
      out.push(stem(raw));
      if (raw.indexOf('_') > -1) {
        raw.split('_').forEach(function (p) { if (p.length > 2 && !STOP.has(p)) out.push(stem(p)); });
      }
    });
    return out;
  }
  const TERM2C = {};
  Object.keys(THESAURUS).forEach(function (c) {
    THESAURUS[c].split(' ').forEach(function (f) {
      terms(f).forEach(function (t) { (TERM2C[t] = TERM2C[t] || new Set()).add(c); });
    });
  });
  function conceptsOf(ts) {
    const o = new Set();
    ts.forEach(function (t) { const cs = TERM2C[t]; if (cs) cs.forEach(function (c) { o.add(c); }); });
    return o;
  }
  docs.forEach(function (x) {
    const text = x.id + ' ' + x.name + ' ' + x.question + ' ' + x.category + ' ' + x.why +
                 ' ' + (x.checks || []).join(' ');
    x._checkCount = x.checks ? x.checks.length : null;
    x._terms = new Set(terms(text));
    x._concepts = conceptsOf(Array.from(x._terms));
    x._lower = text.toLowerCase();
  });
  const N = docs.length || 1, dfT = {}, dfC = {};
  docs.forEach(function (x) {
    x._terms.forEach(function (t) { dfT[t] = (dfT[t] || 0) + 1; });
    x._concepts.forEach(function (c) { dfC[c] = (dfC[c] || 0) + 1; });
  });
  function idfT(t) { return Math.log(1 + N / (1 + (dfT[t] || 0))); }
  function idfC(c) { return Math.log(1 + N / (1 + (dfC[c] || 0))); }
  const CW = 0.55;

  function search(query) {
    const qT = Array.from(new Set(terms(query)));
    if (!qT.length) return [];
    const qC = Array.from(conceptsOf(qT));
    const raw = query.toLowerCase().trim();
    var norm = 0;
    qT.forEach(function (t) { norm += idfT(t); });
    qC.forEach(function (c) { norm += idfC(c) * CW; });
    if (norm <= 0) return [];
    return docs.map(function (x) {
      var sc = 0; const hits = [];
      qT.forEach(function (t) { if (x._terms.has(t)) { sc += idfT(t); hits.push(t); } });
      qC.forEach(function (c) { if (x._concepts.has(c)) sc += idfC(c) * CW; });
      var rel = sc / norm;
      if (raw.length >= 8 && x._lower.indexOf(raw) > -1) rel = Math.min(1, rel + 0.3);
      return { doc: x, rel: rel, hits: hits };
    }).filter(function (r) { return r.rel >= 0.22; })
      .sort(function (a, b) { return b.rel - a.rel; });
  }

  // ----------------------------------------------------------------- table
  function dotClass(x) {
    if (x.kind !== 'test') return x.kind;
    return x.status === 'pass' ? 'pass' : x.status === 'FAIL' ? 'fail'
      : x.status === 'notrun' ? 'idle' : 'skip';
  }
  function statusTitle(x) {
    if (x.kind === 'gap') return 'Known gap here, and not covered by argus CI either';
    if (x.kind === 'untested') return 'Untested anywhere - neither here nor in argus CI';
    if (x.kind === 'upstream') return 'Covered by argus own CI; out of scope for this suite';
    if (x.status === 'notrun') return 'Defined in the suite but not run in this scope';
    return x.status === 'pass' ? 'Passing' : x.status === 'FAIL' ? 'Failing' : x.status;
  }
  // A not-run test is a scheduling decision, not a defect: say which scope runs it.
  function notRunNote(x) {
    if (x.kind !== 'test' || x.status !== 'notrun') return '';
    return x.scope && x.scope !== 'all'
      ? 'Runs only when the suite is dispatched with scope=' + x.scope + '.'
      : 'Not run in this scope.';
  }
  function srcHref(x) {
    if (!x.file) return null;
    return srcBase + x.file + (x.line ? '#L' + x.line : '');
  }
  function highlight(text, hits) {
    var html = esc(text);
    (hits || []).filter(function (t) { return t.length > 2; }).forEach(function (t) {
      html = html.replace(new RegExp('\\b(' + t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '[a-z]{0,3})\\b', 'gi'), '<mark>$1</mark>');
    });
    return html;
  }

  // A row like "do the unit tests pass?" hides a whole pytest file. Show the
  // assertions the run actually collected, capped so the table stays scannable,
  // with the full list on hover.
  const CHECKS_SHOWN = 6;
  function checksLine(x) {
    const c = x.checks;
    const st = x.stats;
    // A red dot on an aggregate row says nothing about severity: one broken
    // assertion and forty look identical. Lead with the split when we have it.
    if (st && st.total) {
      var summary = '<span class="n">' + st.passed + '/' + st.total + ' passed</span>';
      if (st.failed) summary += '<span class="bad">' + st.failed + ' failed</span>';
      if (st.skipped) summary += '<span class="dim">' + st.skipped + ' skipped</span>';
      const names = (st.failures || []).length
        ? '<div class="failed-names">failed: ' + st.failures.slice(0, 6).map(esc).join(' &middot; ') +
          (st.failures.length > 6 ? ' &middot; +' + (st.failures.length - 6) + ' more' : '') + '</div>'
        : '';
      const rest = (c && c.length)
        ? '<div class="all-checks" title="' + esc(c.join('\n')) + '">' +
          c.slice(0, CHECKS_SHOWN).map(esc).join(' &middot; ') +
          (c.length > CHECKS_SHOWN ? ' &middot; +' + (c.length - CHECKS_SHOWN) + ' more' : '') + '</div>'
        : '';
      return '<div class="checks">' + summary + names + rest + '</div>';
    }
    if (c == null) return '';                       // this test has no sub-checks
    if (!c.length) {
      // It declares sub-checks but collected none: usually the paths it points
      // at have moved or been deleted upstream. Say so rather than showing
      // nothing, which reads as "no detail available".
      return '<div class="checks empty-checks">no checks collected &mdash; ' +
             'the paths this job runs may no longer exist upstream</div>';
    }
    const head = c.slice(0, CHECKS_SHOWN).map(esc).join(' &middot; ');
    const more = c.length > CHECKS_SHOWN ? ' &middot; +' + (c.length - CHECKS_SHOWN) + ' more' : '';
    return '<div class="checks" title="' + esc(c.join('\n')) + '">' +
           '<span class="n">' + c.length + ' checks</span> ' + head + more + '</div>';
  }

  function buildRow(x) {
    const tr = document.createElement('tr');
    tr.className = 't' + (x.status === 'FAIL' ? ' failing' : '');
    // Definition and logs answer different questions -- "what does this test
    // assert?" vs "what did it do on this run?" -- so they get their own columns.
    const href = srcHref(x);
    const defCell = href
      ? '<a href="' + href + '" title="' + esc(x.file + (x.line ? ':' + x.line : '')) + '">' +
        (x.kind === 'test' ? 'test &#8599;' : 'entry &#8599;') + '</a>'
      : '<span class="none">&mdash;</span>';
    const ran = x.kind === 'test' && (x.status === 'pass' || x.status === 'FAIL');
    const logCell = ran
      ? '<a href="' + (jobUrl[x.id] || d.runUrl) + '" title="Job logs for ' + esc(x.id) + '">log &#8599;</a>'
      : '<span class="none">&mdash;</span>';
    tr.innerHTML =
      '<td class="c-st"><span class="dot ' + dotClass(x) + '" title="' + esc(statusTitle(x)) + '"></span></td>' +
      '<td class="c-id mono">' + esc(x.id) + '</td>' +
      '<td class="c-q"><span class="qt">' + esc(x.question || x.name) + '</span>' +
        (x.why ? '<div class="why">' + esc(x.why) + '</div>' : '') +
        (notRunNote(x) ? '<div class="why">' + esc(notRunNote(x)) + '</div>' : '') +
        checksLine(x) + '</td>' +
      '<td class="c-cat">' + esc(x.category) + '</td>' +
      '<td class="c-lnk">' + defCell + '</td>' +
      '<td class="c-lnk">' + logCell + '</td>';
    tr._doc = x;
    tr._qt = tr.querySelector('.qt');
    return tr;
  }

  const rowOf = new Map();
  docs.forEach(function (x) { rowOf.set(x, buildRow(x)); });

  const grouped = [];
  var lastCat = null;
  docs.forEach(function (x) {
    if (x.category !== lastCat) {
      lastCat = x.category;
      const members = docs.filter(function (y) { return y.category === x.category; });
      const mt = members.filter(function (y) { return y.kind === 'test'; });
      const mp = mt.filter(function (y) { return y.status === 'pass'; }).length;
      const tr = document.createElement('tr');
      tr.className = 'grp';
      // "0/25" reads as 25 failures; say what actually happened instead.
      const mIdle = mt.filter(function (y) { return y.status === 'notrun'; }).length;
      var count;
      if (!mt.length) count = members.length + (members.length === 1 ? ' entry' : ' entries');
      else if (mIdle === mt.length) count = mt.length + ' not run';
      else count = mp + '/' + mt.length;
      tr.innerHTML = '<td colspan="6">' + esc(x.category) +
        '<span class="gcount">' + count + '</span></td>';
      grouped.push(tr);
    }
    grouped.push(rowOf.get(x));
  });

  const tbody = $('rows'), captionEl = $('caption'), emptyEl = $('empty'), verdictEl = $('verdict');
  // Status filtering lives INSIDE the query as `is:` tokens rather than as a
  // separate chip state. Two independent filters ANDing together silently was
  // the problem: you could search, get nothing, and never see that a chip set
  // three minutes ago was excluding every match. Now there is one state, it is
  // visible in the box, and clearing the box clears everything.
  const FILTERS = {
    passing: function (x) { return x.kind === 'test' && x.status === 'pass'; },
    failing: function (x) { return x.kind === 'test' && x.status === 'FAIL'; },
    'not-run': function (x) {
      return x.kind === 'test' && (x.status === 'notrun' || x.status === 'skip' || x.status === 'cancel');
    },
    tests: function (x) { return x.kind === 'test'; },
    gap: function (x) { return x.kind === 'gap'; },
    untested: function (x) { return x.kind === 'untested'; },
    upstream: function (x) { return x.kind === 'upstream'; }
  };

  function parseQuery(raw) {
    const toks = [];
    const text = String(raw || '').replace(/\bis:([a-z-]+)/gi, function (m, v) {
      const k = v.toLowerCase();
      if (FILTERS[k]) { toks.push(k); return ''; }
      return m;
    }).replace(/\s+/g, ' ').trim();
    return { text: text, filters: toks };
  }

  function render() {
    const parsed = parseQuery(input.value);
    const query = parsed.text;
    const preds = parsed.filters.map(function (f) { return FILTERS[f]; });
    function keep(x) { return preds.every(function (fn) { return fn(x); }); }
    syncStats(parsed.filters);

    const hits = query ? search(query) : null;
    var list;
    if (hits) {
      list = hits.filter(function (h) { return keep(h.doc); });
    } else {
      list = docs.filter(keep).map(function (x) { return { doc: x, rel: 1, hits: [] }; });
    }

    // restore plain text, then re-highlight only what matched
    docs.forEach(function (x) { const r = rowOf.get(x); if (r) r._qt.innerHTML = esc(x.question || x.name); });

    if (!query && !preds.length) {
      tbody.replaceChildren.apply(tbody, grouped);
    } else {
      tbody.replaceChildren.apply(tbody, list.map(function (h) {
        const r = rowOf.get(h.doc);
        if (query) r._qt.innerHTML = highlight(h.doc.question || h.doc.name, h.hits);
        return r;
      }));
    }

    emptyEl.style.display = list.length ? 'none' : 'block';
    if (!list.length) {
      const hidden = hits ? hits.length : 0;
      if (hidden && preds.length) {
        // The filter, not the corpus, is why this is empty. Saying "untested"
        // here would be a flat lie.
        emptyEl.innerHTML = hidden + ' entr' + (hidden === 1 ? 'y matches' : 'ies match') +
          ' this search, but ' +
          parsed.filters.map(function (f) { return '<b>is:' + esc(f) + '</b>'; }).join(' and ') +
          ' excludes ' + (hidden === 1 ? 'it' : 'them') + '.' +
          '<div class="try"><button type="button" class="try-btn" id="drop-filter">Drop the filter</button></div>';
        const db = emptyEl.querySelector('#drop-filter');
        if (db) db.addEventListener('click', function () {
          input.value = parseQuery(input.value).text; paintGhost(); onInput();
        });
      } else if (query) {
        emptyEl.innerHTML = 'Nothing in the suite or the coverage notes resembles this. Treat it as untested.' +
          '<div class="try">Try: ' + EXAMPLES.slice(0, 3).map(function (ex) {
            return '<button type="button" class="try-btn">' + esc(ex) + '</button>';
          }).join(' ') + '</div>';
        Array.prototype.forEach.call(emptyEl.querySelectorAll('.try-btn'), function (b) {
          b.addEventListener('click', function () { input.value = b.textContent; onInput(); });
        });
      } else {
        emptyEl.textContent = 'Nothing matches this filter.';
      }
    }

    const nT = list.filter(function (h) { return h.doc.kind === 'test'; }).length;
    const nG = list.length - nT;
    captionEl.textContent = (query ? list.length + ' match' + (list.length === 1 ? '' : 'es')
                                   : 'Showing ' + list.length + (list.length === 1 ? ' entry' : ' entries')) +
      ' — ' + nT + ' test' + (nT === 1 ? '' : 's') + ', ' + nG + ' coverage note' + (nG === 1 ? '' : 's') +
      (parsed.filters.length ? ' · ' + parsed.filters.map(function (f) { return 'is:' + f; }).join(' ') : '');

    // verdict
    if (!query) { verdictEl.className = 'verdict'; verdictEl.innerHTML = ''; return; }
    const all = hits || [];
    // A fixed cut punishes long queries: the more words, the more the score is
    // divided, so a real match to "block the build when a critical CVE is found"
    // scores lower than a two-word one. Cut relative to the best hit, with an
    // absolute floor so a field of weak matches still reads as "maybe".
    const cut = all.length ? Math.max(0.32, all[0].rel * 0.85) : 1;
    const st = all.filter(function (h) { return h.doc.kind === 'test' && h.rel >= cut; });
    const sg = all.filter(function (h) { return h.doc.kind !== 'test' && h.rel >= cut; });
    const bestTest = all.find(function (h) { return h.doc.kind === 'test'; });
    const bestGap = all.find(function (h) { return h.doc.kind !== 'test'; });
    var cls, head, sub;
    if (st.length && (!sg.length || (bestTest && bestGap && bestTest.rel >= bestGap.rel))) {
      cls = 'yes';
      head = 'Yes &mdash; covered by ' + st.length + ' test' + (st.length > 1 ? 's' : '');
      const f = st.filter(function (h) { return h.doc.status === 'FAIL'; });
      const nr = st.filter(function (h) { return h.doc.status === 'notrun'; });
      sub = f.length ? f.length + ' of them ' + (f.length > 1 ? 'are' : 'is') + ' failing right now.'
        : (nr.length === st.length ? 'Defined in the suite but not run in this scope.'
          : 'Confirm the match actually asserts what you mean.');
    } else if (sg.length) {
      const k = sg[0].doc.kind;
      if (k === 'upstream') {
        cls = 'maybe'; head = 'Not here &mdash; argus tests this itself';
        sub = 'Out of scope for this suite, which checks the consumer contract. Reason in the row below.';
      } else if (k === 'untested') {
        cls = 'no'; head = 'No &mdash; untested anywhere';
        sub = 'Covered by neither this suite nor argus CI. Reason in the row below.';
      } else {
        cls = 'no'; head = 'No &mdash; this is a known gap';
        sub = 'Considered and deliberately untested here. Reason in the row below.';
      }
    } else if (all.length) {
      cls = 'maybe'; head = 'Maybe &mdash; nothing matches closely';
      sub = 'Nearest entries below. If none fit, treat it as untested.';
    } else {
      cls = 'no'; head = 'No match &mdash; this looks untested';
      sub = 'Consider adding a test, or a gap entry in .github/data/coverage-gaps.json.';
    }
    verdictEl.className = 'verdict show ' + cls;
    verdictEl.innerHTML = '<b>' + head + '</b> <span class="sub">' + sub + '</span>';
  }

  // ---------------------------------------------------------------- search UI
  const input = $('q');
  const ghost = $('ghost');
  const kbd = $('kbd');
  const clearBtn = $('clear');
  clearBtn.addEventListener('click', function () {
    input.value = ''; paintGhost(); onInput(); input.focus();
  });

  // Inline typeahead: the completion is drawn as grey text continuing what you
  // typed, accepted with Tab or Right-arrow. The pool is the example queries
  // first (short, phrased the way someone would ask) then every test question,
  // so typing "does argus fail" can land you on an exact test.
  const POOL = EXAMPLES.concat(docs.map(function (x) { return x.question; })
    .filter(Boolean)).filter(function (v, i, a) { return a.indexOf(v) === i; });

  function suggest(typed) {
    typed = String(typed == null ? '' : typed);
    if (typed.length < 2) return '';
    const low = typed.toLowerCase();
    var best = '';
    for (var i = 0; i < POOL.length; i++) {
      const cand = POOL[i];
      if (cand.length > typed.length && cand.toLowerCase().indexOf(low) === 0) {
        // shortest completion wins: least presumptuous about what you meant
        if (!best || cand.length < best.length) best = cand;
        if (i < EXAMPLES.length) { best = cand; break; }
      }
    }
    return best;
  }

  var suggestion = '';
  function paintGhost() {
    const typed = String(input.value == null ? '' : input.value);
    suggestion = suggest(typed);
    ghost.innerHTML = suggestion
      ? '<span class="typed">' + esc(typed) + '</span>' +
        '<span class="rest">' + esc(suggestion.slice(typed.length)) + '</span>' +
        '<span class="tabhint">&#8677; Tab</span>'
      : '';
    syncSlot();
  }
  // "/" focuses the box, so it is only worth showing when the box is empty;
  // once there is something to clear, the same slot becomes the clear button.
  function syncSlot() {
    const has = !!String(input.value || '').length;
    kbd.hidden = has;
    clearBtn.hidden = !has;
  }
  function acceptSuggestion() {
    if (!suggestion) return false;
    input.value = suggestion;
    paintGhost();
    onInput();
    return true;
  }

  var t = null;
  function onInput() {
    const raw = input.value.trim();
    syncSlot();
    const u = new URL(window.location);
    if (raw) u.searchParams.set('q', raw); else u.searchParams.delete('q');
    history.replaceState(null, '', u);
    render();
  }
  input.addEventListener('input', function () {
    paintGhost();                       // immediate, so the hint never lags
    clearTimeout(t); t = setTimeout(onInput, 110);
  });
  input.addEventListener('keydown', function (e) {
    const atEnd = input.selectionStart === input.value.length &&
                  input.selectionEnd === input.value.length;
    if (e.key === 'Tab' && suggestion) { e.preventDefault(); acceptSuggestion(); }
    else if (e.key === 'ArrowRight' && atEnd && suggestion) { e.preventDefault(); acceptSuggestion(); }
    else if (e.key === 'Enter' && suggestion) { e.preventDefault(); acceptSuggestion(); }
  });
  input.addEventListener('scroll', function () { ghost.scrollLeft = input.scrollLeft; });
  document.addEventListener('keydown', function (e) {
    if (e.key === '/' && document.activeElement !== input) { e.preventDefault(); input.focus(); }
    if (e.key === 'Escape' && document.activeElement === input) {
      input.value = ''; paintGhost(); onInput(); input.blur();
    }
  });

  $('foot').innerHTML = 'Generated by the test suite CI on every push to <span class="mono">main</span>. ' +
    'Coverage gaps live in <span class="mono">.github/data/coverage-gaps.json</span>.';

  // Theme: follow the OS by default, let the reader override, remember it.
  // Storage can throw in private windows, so every access is guarded.
  const root = document.documentElement;
  const tbtn = $('theme-toggle');
  function readTheme() { try { return localStorage.getItem('argus-theme') || 'auto'; } catch (e) { return 'auto'; } }
  function applyTheme(mode) {
    if (mode === 'auto') root.removeAttribute('data-theme');
    else root.setAttribute('data-theme', mode);
    tbtn.textContent = mode === 'auto' ? 'Auto' : mode === 'dark' ? 'Night' : 'Day';
    try { localStorage.setItem('argus-theme', mode); } catch (e) {}
  }
  applyTheme(readTheme());
  tbtn.addEventListener('click', function () {
    const order = ['auto', 'light', 'dark'];
    applyTheme(order[(order.indexOf(readTheme()) + 1) % order.length]);
  });

  // The URL carries the whole query, `is:` tokens included, so a filtered view
  // is a shareable link rather than something you have to re-click.
  const preset = new URL(window.location).searchParams.get('q');
  if (preset) input.value = preset;
  paintGhost();
  render();
})();
</script>
</body>
</html>
HTMLEOF2

# argus's eye as the site icon, copied next to the page so it needs no network
FAVICON_SRC="$SCRIPT_DIR/../data/argus-favicon.png"
if [ -f "$FAVICON_SRC" ]; then
  cp "$FAVICON_SRC" "$OUT/favicon.png"
else
  echo "WARNING: $FAVICON_SRC missing - the page will fall back to no icon"
fi

# .nojekyll
touch "$OUT/.nojekyll"

echo "Dashboard generated: $OUT/index.html"
echo "History entries: $(jq 'length' "$HISTORY_FILE")"
