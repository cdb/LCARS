#!/usr/bin/env bash
# =============================================================================
# tests/narrowing-proof.test.sh — S364: A PROOF THAT CAN NARROW.
# =============================================================================
# THE DEFECT, measured on the live capstone of 18 Nov 2026. `lcars init`
# auto-records a test command by WRAPPING the project's own script:
#
#     npm test -- ${LCARS_TESTS_DIR:+"${LCARS_TESTS_DIR}"}
#
# When that project script carries its OWN FIXED FILE SELECTION
# (`node --test "tests/**/*.test.js"`), the per-ticket scope is APPENDED, not
# APPLIED. Measured: a ticket declaring 53 tests ran 7,400 — the whole
# repository — at ~6 minutes a leg, and one ticket consumed 114 minutes and all
# three of its sessions. It also disabled the flip-flop's first half while
# leaving its rejection power intact (`parentLeg.ran=false`, `parent.rc=null`,
# and the ticket bounced anyway): a gate that can fail work but cannot honestly
# pass it.
#
# THE CORRECT FORM ALREADY EXISTS IN THE WILD. The captain's own SproutAndSpire
# records `node --test … "${LCARS_TESTS_DIR:-tests/**/*.test.js}"`, where the
# scope REPLACES the glob rather than being appended to it. Its own package.json
# script, though, is the fixed-glob shape — so that one real repo is BOTH halves
# of this measurement.
#
# AND ITS TWIN, in the proof gate's narrowing control, same capstone:
#     scopeControl: { executed: "7393", narrowingProven: true }
# against a leg that executed 7,400 and a full suite of 7,381. BOTH numbers were
# the whole suite, and it printed "narrowing proven". The logic was sound and
# missing exactly one comparison: it never consulted the FULL-SUITE SIZE.
#
# WHAT THIS SUITE PINS:
#   1. init REFUSES a project whose test script cannot narrow, BY NAME, and
#      names the correct form to use instead — at SETUP, not at the first
#      bounced ticket.
#   2. init ACCEPTS a project whose script consumes the scope, and records the
#      full-suite size it measured.
#   3. the gate's control REDS when BOTH its numbers are the whole suite.
#   4. it stays GREEN on a genuine narrowing (the 0-vs-53 shape).
#   5. a PLANTED over-wide control REDS (the known-fail control for row 4).
#   6. KNOWN-GOOD CONTROLS — a genuinely narrowed leg still passes, and a repo
#      with no recorded suite size behaves exactly as it did before.
#
# WHY THE CONTROL'S OWN NUMBER CANNOT DECIDE ALONE — MEASURED, 20 Nov 2026.
# The brief for this session said "if the empty-scope control executed thousands
# of tests, nothing was excluded, whatever the delta says". Driven against this
# repo's OWN known-good fixture (tests/fixtures/mkflatrepo.sh, section 1 of
# tests/gate-scope.test.sh) the control reads `executed: 10` against a suite of
# 10 — because an empty scope leaves `find` with nothing and `node --test` falls
# back to its own discovery — while the leg honestly executed 2. That narrowing
# is REAL. A control-only rule would have turned that row, and two more like it,
# from PASS to INCONCLUSIVE. So the comparison this suite pins is BOTH numbers:
# the control ran the whole suite AND SO DID THE LEG. That is the capstone's
# exact evidence, and it is the narrowest tightening that catches it.
#
# Fast, SCOPED, zero-token: real `skills/lcars-init/init.sh`, real
# `skills/lcars-run/run.sh`, real git repos, real `node` runner, stubbed CLIs.
#
# Usage: bash tests/narrowing-proof.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INIT_SH="${LCARS_INIT_SCRIPT:-$REPO_ROOT/skills/lcars-init/init.sh}"
RUN_SH="${LCARS_RUN_SCRIPT:-$REPO_ROOT/skills/lcars-run/run.sh}"
MKFLAT="$REPO_ROOT/tests/fixtures/mkflatrepo.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/lcars-narrowing.XXXXXX")"
BASEFILE="$(mktemp "${TMPDIR:-/tmp}/lcars-narrowing-bases.XXXXXX")"
cleanup() {
  local b
  while IFS= read -r b; do [ -n "$b" ] && rm -rf "$b"; done <"$BASEFILE"
  rm -f "$BASEFILE"; rm -rf "$TMPROOT"
}
trap cleanup EXIT

# Never let a stray value from the invoking shell decide a timeout assertion.
unset LCARS_GATE_TIMEOUT
unset LCARS_GATE_TIMEOUT_DEFAULT
unset LCARS_TESTS_DIR

echo "S364 — a recorded test command must be able to narrow"
[ -f "$INIT_SH" ] || { echo "init.sh not found at $INIT_SH"; exit 1; }
[ -f "$RUN_SH" ]  || { echo "run.sh not found at $RUN_SH"; exit 1; }
[ -f "$MKFLAT" ]  || { echo "fixture builder not found at $MKFLAT"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "node is required for this suite"; exit 1; }
command -v npm  >/dev/null 2>&1 || { echo "npm is required for this suite";  exit 1; }

# ===========================================================================
# PART ONE — THE INIT PROBE (DEFECT A)
# ===========================================================================
# Two real repos, identical in every way EXCEPT the one line that matters: the
# project's own `test` script. init auto-records the SAME wrapper for both
# (`npm test -- <scope>`), so nothing but a live probe can tell them apart —
# which is the whole point.
mkjs() { # name test-script → repo path
  local name="$1" script="$2" repo
  repo="$TMPROOT/$name"
  mkdir -p "$repo/tests" "$repo/src"
  ( cd "$repo" && git init -q -b main && git config user.email t@t && git config user.name t )
  "${LCARS_PYTHON_BIN:-python3}" - "$repo/package.json" "$script" <<'PY'
import json, sys
json.dump({"name": "probe-fixture", "private": True, "scripts": {"test": sys.argv[2]}},
          open(sys.argv[1], "w"), indent=2)
PY
  printf 'exports.add = (a, b) => a + b;\n' >"$repo/src/calc.js"
  local f
  for f in alpha beta gamma; do
    cat >"$repo/tests/$f.test.js" <<JS
const { test } = require('node:test');
const assert = require('node:assert');
const { add } = require('../src/calc.js');
test('$f adds', () => { assert.strictEqual(add(2, 2), 4); });
JS
  done
  ( cd "$repo" && git add -A && git commit -qm "probe fixture ($name)" )
  printf '%s' "$repo"
}

run_init() { # repo → INITOUT / INITRC
  local repo="$1"
  # A HARD FIXTURE GUARD. With an empty path, `cd "$repo"` is a no-op and the
  # real `lcars init` would run against THE CHECKOUT THIS SUITE LIVES IN —
  # measured 20 Nov 2026, it wrote a config into this repo's own gitdir. A rig
  # that can touch the repo under test is not a rig.
  if [ -z "$repo" ] || [ ! -e "$repo/.git" ]; then
    INITOUT="FIXTURE MISSING: '$repo' is not a git repo"; INITRC=99; return 0
  fi
  cat >"$repo/claude" <<'EOF'
#!/usr/bin/env bash
echo "2.0.44 (Claude Code)"
EOF
  cat >"$repo/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = repo ] && [ "$2" = view ] && { echo "owner/repo"; exit 0; }
exit 0
EOF
  chmod +x "$repo/claude" "$repo/gh"
  INITRC=0
  INITOUT="$( cd "$repo" && LCARS_CLAUDE_BIN="$repo/claude" LCARS_GH_BIN="$repo/gh" \
      LCARS_PROBE_TIMEOUT=120 bash "$INIT_SH" 2>&1 )" || INITRC=$?
}
cfg_of() { printf '%s' "$1/.git/lcars/config.json"; }
cfg_get() { # repo key → value
  "${LCARS_PYTHON_BIN:-python3}" - "$(cfg_of "$1")" "$2" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
v = d.get(sys.argv[2])
sys.stdout.write("" if v is None else str(v))
PY
}

# ---------------------------------------------------------------------------
# 1. A FIXED-GLOB SCRIPT IS REFUSED AT INIT, BY NAME, WITH THE CURE NAMED.
#    `node --test tests/` already selects the whole suite, so the appended scope
#    cannot take anything away: MEASURED 20 Nov 2026, 3 tests with the whole
#    suite in scope and 4 with one file in scope (node re-runs the file named a
#    second time). The scope excluded NOTHING, which is the verdict's whole
#    basis — the SIGN of the difference, never its magnitude.
# ---------------------------------------------------------------------------
echo "-- 1. a project script with its own fixed selection is REFUSED at init --"
RA="$(mkjs fixedglob 'node --test --test-concurrency=1 tests/')"
run_init "$RA"
case "$INITOUT" in
  *"CANNOT NARROW"*) ok "1a. init says the recorded command CANNOT NARROW" ;;
  *) bad "1a. init never said the command cannot narrow: $(printf '%s' "$INITOUT" | tail -12 | tr '\n' '|')" ;;
esac
case "$INITOUT" in
  *'TEST SYSTEMS ONLINE'*) bad "1b. init still certified TEST SYSTEMS ONLINE on a command that cannot narrow" ;;
  *) ok "1b. and it does NOT certify TEST SYSTEMS ONLINE" ;;
esac
case "$INITOUT" in
  *'npm test --'*) ok "1c. it names the offending command" ;;
  *) bad "1c. the refusal must name the command it measured" ;;
esac
case "$INITOUT" in
  *'LCARS_TESTS_DIR:-'*) ok "1d. it names the CORRECT FORM (the scope REPLACING the selection)" ;;
  *) bad "1d. the refusal must name the correct form to use instead: $(printf '%s' "$INITOUT" | tail -12 | tr '\n' '|')" ;;
esac
case "$INITOUT" in
  *'lcars update --test-command'*) ok "1e. and the one command that records the cure" ;;
  *) bad "1e. the refusal must say how to record the cure" ;;
esac
# THE NUMBERS ARE SHOWN, not just a verdict: 3 tests whole-suite, 3 with one
# file in scope. A verdict with no measurement behind it is the thing this
# session exists to delete.
case "$INITOUT" in
  *" 3 "*|*"3 test"*) ok "1f. the measurement itself is printed (both counts)" ;;
  *) bad "1f. the refusal shows no numbers: $(printf '%s' "$INITOUT" | tail -12 | tr '\n' '|')" ;;
esac
# A refusal is not a stop: init's other side effects are done and correct.
[ -f "$(cfg_of "$RA")" ] \
  && ok "1g. init still completed its setup (config.json written)" \
  || bad "1g. a narrowing refusal blocked setup — config.json is missing"

# ---------------------------------------------------------------------------
# 2. A SCRIPT THAT CONSUMES THE SCOPE IS ACCEPTED.
# ---------------------------------------------------------------------------
echo "-- 2. a project script that CONSUMES the scope is accepted --"
RB="$(mkjs consumes 'node --test --test-concurrency=1 "${LCARS_TESTS_DIR:-tests}"')"
run_init "$RB"
case "$INITOUT" in
  *"CANNOT NARROW"*) bad "2a. init REFUSED a command that genuinely narrows: $(printf '%s' "$INITOUT" | tail -12 | tr '\n' '|')" ;;
  *) ok "2a. init does not refuse a command that narrows" ;;
esac
case "$INITOUT" in
  *'TEST SYSTEMS ONLINE'*) ok "2b. and it still certifies TEST SYSTEMS ONLINE" ;;
  *) bad "2b. the accepted repo lost its certification: $(printf '%s' "$INITOUT" | tail -12 | tr '\n' '|')" ;;
esac
case "$INITOUT" in
  *'narrow'*|*'NARROW'*) ok "2c. the narrowing is stated as a measured fact, not assumed" ;;
  *) bad "2c. nothing in the readout says the narrowing was measured" ;;
esac
[ "$(cfg_get "$RB" suiteSize)" = 3 ] \
  && ok "2d. and the measured FULL-SUITE SIZE is recorded (suiteSize=3)" \
  || bad "2d. suiteSize was '$(cfg_get "$RB" suiteSize)' (expected the measured 3)"

# ===========================================================================
# PART TWO — THE GATE'S NARROWING CONTROL (DEFECT B)
# ===========================================================================
mkbase() { # args… → base dir (recorded for teardown)
  local b; b="$(bash "$MKFLAT" "$@" 2>/dev/null)"
  printf '%s\n' "$b" >>"$BASEFILE"
  printf '%s' "$b"
}
parent_of() { git -C "$1/repo" rev-parse HEAD~1; }
ffj_of()    { printf '%s' "$1/repo/.git/lcars/missions/m-001/tickets/t-001/flip-flop.json"; }
ff() { # base [env-pairs…] → FFRC + FFOUT
  local base="$1"; shift
  FFOUT="$( cd "$base/repo" && env PATH="$base/shim:$PATH" \
            LCARS_GH_BIN=true LCARS_GIT_BIN=git "$@" \
            bash "$RUN_SH" flip-flop-gate-test --mission m-001 --ticket t-001 \
              --sha "$(parent_of "$base")" 2>&1 )"
  FFRC="$(printf '%s\n' "$FFOUT" | sed -n 's/^FFRC=//p' | tail -1)"
}
jq_ff() { # base python-expr → value
  "${LCARS_PYTHON_BIN:-python3}" - "$(ffj_of "$1")" "$2" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
try:
    v = eval(sys.argv[2], {"d": d})
except Exception:
    v = None
sys.stdout.write("" if v is None else str(v))
PY
}
# ONE KEY PER LINE with nested objects inline: run.sh's config readers are
# line-oriented greps, so a pretty-printer that split `numberOne` across lines
# would corrupt the very file under test (lcars-common.sh warns about this).
cfg_put() { # base key json-value
  "${LCARS_PYTHON_BIN:-python3}" - "$1/repo/.git/lcars/config.json" "$2" "$3" <<'PY'
import json, sys
p, k, v = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(p))
d[k] = json.loads(v)
body = ",\n".join('  %s: %s' % (json.dumps(a), json.dumps(b)) for a, b in d.items())
open(p, "w").write("{\n" + body + "\n}\n")
PY
}

# THE BROKEN COMMAND, built to the capstone's exact shape: the project's own
# fixed selection (`find tests -name "slow_*.test.js"`) runs whatever happens,
# and the ticket's scope is APPENDED to it. So
#   empty scope  → the 8 slow modules                     (the whole suite)
#   ticket scope → the 8 slow modules + the ticket's file, ONCE PER DECLARED
#                  FILE: 9 + 9 = 18                        (the whole suite, twice)
# 8 vs 18 — different numbers, which is exactly why "narrowingProven" went true
# on the capstone (7393 vs 7400), and every one of them is the whole suite.
BROKEN_CMD='node --test --test-concurrency=1 $(find tests -name "slow_*.test.js") $(find "$LCARS_TESTS_DIR" -name "*.test.js" 2>/dev/null)'

# ---------------------------------------------------------------------------
# 3. THE CONTROL REDS WHEN BOTH ITS NUMBERS ARE THE WHOLE SUITE.
# ---------------------------------------------------------------------------
echo "-- 3. both numbers the whole suite → the narrowing is NOT proven --"
B3="$(mkbase --files 8 --sleep 0 --tip flat2)"
cfg_put "$B3" testCommand "$(printf '%s' "$BROKEN_CMD" | "${LCARS_PYTHON_BIN:-python3}" -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
cfg_put "$B3" suiteSize 8
ff "$B3" LCARS_GATE_TIMEOUT=60
# CONTROL FOR THE CONTROL: prove the fixture really produced the capstone shape
# before any row below is allowed to mean anything.
C3="$(jq_ff "$B3" 'd["scopeControl"]["executed"]')"
E3="$(jq_ff "$B3" 'd["executed"]["tip"]')"
if [ "$C3" = 8 ] && [ "$E3" = 18 ]; then
  ok "3a. CONTROL: the fixture reproduces the capstone shape (control 8, leg 18, suite 8)"
else
  bad "3a. the fixture did NOT reproduce the shape — control='$C3' leg='$E3' (expected 8 / 18; nothing below proves anything)"
fi
[ "$(jq_ff "$B3" 'd["scopeControl"]["narrowing"]')" = unproven ] \
  && ok "3b. the narrowing is UNPROVEN, not 'proven'" \
  || bad "3b. narrowing was '$(jq_ff "$B3" 'd["scopeControl"]["narrowing"]')' (expected unproven)"
[ "$(jq_ff "$B3" 'd["scopeControl"]["narrowingProven"]')" = False ] \
  && ok "3c. and narrowingProven is false" \
  || bad "3c. narrowingProven was '$(jq_ff "$B3" 'd["scopeControl"]["narrowingProven"]')'"
[ "$(jq_ff "$B3" 'd["verdict"]')" = inconclusive ] \
  && ok "3d. the leg is INCONCLUSIVE — never a pass" \
  || bad "3d. verdict was '$(jq_ff "$B3" 'd["verdict"]')': $(jq_ff "$B3" 'd["reason"]' | head -c 250)"
case "$(jq_ff "$B3" 'd["scopeControl"]["narrowingWhy"]')$(jq_ff "$B3" 'd["reason"]')" in
  *"full suite"*|*"FULL SUITE"*|*"whole suite"*) ok "3e. and it says WHY: both numbers are the repo's whole suite" ;;
  *) bad "3e. the reason never mentions the full suite: $(jq_ff "$B3" 'd["scopeControl"]["narrowingWhy"]' | head -c 250)" ;;
esac
case "$(jq_ff "$B3" 'd["scopeControl"]["narrowingWhy"]')$(jq_ff "$B3" 'd["reason"]')" in
  *8*) ok "3f. and it names the recorded suite size it compared against" ;;
  *) bad "3f. the recorded suite size is nowhere in the record" ;;
esac

# ---------------------------------------------------------------------------
# 4. IT STAYS GREEN ON A GENUINE NARROWING — the 0-vs-53 shape, at fixture
#    scale: the leg executes 2 of a recorded 10-test suite.
# ---------------------------------------------------------------------------
echo "-- 4. a genuine narrowing stays PROVEN --"
B4="$(mkbase --files 8 --sleep 0 --tip flat2)"
cfg_put "$B4" suiteSize 10
ff "$B4" LCARS_GATE_TIMEOUT=60
E4="$(jq_ff "$B4" 'd["executed"]["tip"]')"
[ "$E4" = 2 ] \
  && ok "4a. CONTROL: the leg really did narrow to its 2 declared tests of 10" \
  || bad "4a. the leg executed '$E4' (expected 2) — nothing below proves anything"
[ "$(jq_ff "$B4" 'd["scopeControl"]["narrowing"]')" = proven ] \
  && ok "4b. the narrowing is still PROVEN" \
  || bad "4b. narrowing was '$(jq_ff "$B4" 'd["scopeControl"]["narrowing"]')' — a genuine narrowing was weakened"
[ "$(jq_ff "$B4" 'd["verdict"]')" = pass ] \
  && ok "4c. and the honest ticket still PASSES" \
  || bad "4c. verdict was '$(jq_ff "$B4" 'd["verdict"]')': $(jq_ff "$B4" 'd["reason"]' | head -c 250)"

# ---------------------------------------------------------------------------
# 5. A PLANTED OVER-WIDE CONTROL REDS — the known-fail control for row 4.
#    Same repo, same leg, same real narrowing; only the recorded suite size is
#    planted at 2, so the LEG's 2 is "the whole suite" too. If row 4's green
#    came from the comparison never firing, this row would be green as well.
# ---------------------------------------------------------------------------
echo "-- 5. KNOWN-FAIL CONTROL: a planted over-wide control reds --"
B5="$(mkbase --files 8 --sleep 0 --tip flat2)"
cfg_put "$B5" suiteSize 2
ff "$B5" LCARS_GATE_TIMEOUT=60
[ "$(jq_ff "$B5" 'd["scopeControl"]["narrowing"]')" = unproven ] \
  && ok "5a. the planted over-wide control is UNPROVEN (the comparison is live)" \
  || bad "5a. narrowing was '$(jq_ff "$B5" 'd["scopeControl"]["narrowing"]')' — the comparison never fired"
[ "$(jq_ff "$B5" 'd["verdict"]')" = inconclusive ] \
  && ok "5b. and the leg is INCONCLUSIVE" \
  || bad "5b. verdict was '$(jq_ff "$B5" 'd["verdict"]')'"

# ---------------------------------------------------------------------------
# 6. KNOWN-GOOD CONTROLS — no recorded suite size, no change.
#    Every repo initialized before this session has no `suiteSize`, so the new
#    comparison must be INERT there: the gate behaves exactly as it did.
# ---------------------------------------------------------------------------
echo "-- 6. KNOWN-GOOD CONTROLS: an unrecorded suite size changes nothing --"
B6="$(mkbase --files 8 --sleep 0 --tip flat2)"
ff "$B6" LCARS_GATE_TIMEOUT=60
[ "$(cfg_get "$B6/repo" suiteSize)" = "" ] \
  && ok "6a. CONTROL: this fixture records NO suiteSize" \
  || bad "6a. the fixture already carries suiteSize='$(cfg_get "$B6/repo" suiteSize)'"
[ "$(jq_ff "$B6" 'd["verdict"]')" = pass ] \
  && ok "6b. the flat two-file ticket still PASSES, unchanged" \
  || bad "6b. verdict was '$(jq_ff "$B6" 'd["verdict"]')': $(jq_ff "$B6" 'd["reason"]' | head -c 250)"
[ "$(jq_ff "$B6" 'd["scopeControl"]["narrowing"]')" = proven ] \
  && ok "6c. with its narrowing still proven by the control alone" \
  || bad "6c. narrowing was '$(jq_ff "$B6" 'd["scopeControl"]["narrowing"]')'"
B7="$(mkbase --files 8 --sleep 0 --tip nested)"
cfg_put "$B7" suiteSize 10
ff "$B7" LCARS_GATE_TIMEOUT=60
[ "$(jq_ff "$B7" 'd["verdict"]')" = pass ] \
  && ok "6d. an honest NESTED (ancestor-scoped) ticket still passes with a suite size recorded" \
  || bad "6d. the guard parked an honest nested ticket: $(jq_ff "$B7" 'd["reason"]' | head -c 250)"
B8="$(mkbase --files 8 --sleep 0 --tip flat1)"
cfg_put "$B8" suiteSize 9
ff "$B8" LCARS_GATE_TIMEOUT=60
[ "$(jq_ff "$B8" 'd["verdict"]')" = pass ] \
  && ok "6e. an honest SINGLE-file ticket still passes with a suite size recorded" \
  || bad "6e. the guard parked an honest single-file ticket: $(jq_ff "$B8" 'd["reason"]' | head -c 250)"
# The moot shape that parked five honest tickets in S308 round 2: the ticket's
# one declared file IS the whole suite, so the leg legitimately runs all of it.
# A naive "the leg ran the whole suite" rule would park it all over again.
B9="$(mkbase --files 0 --sleep 0 --tip flat1)"
cfg_put "$B9" suiteSize 1
ff "$B9" LCARS_GATE_TIMEOUT=60
[ "$(jq_ff "$B9" 'd["verdict"]')" = pass ] \
  && ok "6f. and a repo whose WHOLE suite is the ticket's one declared file still passes" \
  || bad "6f. the guard parked the moot one-file shape: $(jq_ff "$B9" 'd["reason"]' | head -c 250)"

# ===========================================================================
echo
printf 'narrowing-proof: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
