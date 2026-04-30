#!/usr/bin/env bats
# tests/hooks/pause_rate_budget.bats — pause-rate ceiling on the recorded fixture.
#
# Cross-cutting invariant #1 from docs/upstream-harness-improvements.md
# § "Cross-cutting invariants": any change that adds a compute_confidence
# downgrade source — or tightens an existing threshold — ships with a
# bracket test asserting the auto_land=false rate against a representative
# fixture stays at or below a baseline. The aggregate rate across the
# harness is the bind, not any single axis: additions are paid for by
# removals or threshold-raises elsewhere.
#
# This test replays tests/hooks/fixtures/confidence.log.sample through
# compute_confidence + should_auto_land (under 'high' policy, the shipped
# default) and asserts the auto_land=false count stays at or below the
# pinned baseline. Threshold tightening (e.g., diff>500 → diff>200) flips
# additional fixture rows into the downgrade branch and surfaces here as
# a count regression. The fixture is fixed; raising the cap requires a
# back-port-doc entry naming the retirement or threshold-raise that pays
# for the new pause source.

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/scripts/ralph/lib.sh"
  FIXTURE="$BATS_TEST_DIRNAME/fixtures/confidence.log.sample"
}

@test "pause-rate budget: auto_land=false count on fixture <= 7 under 'high' policy" {
  # Current state (2026-04-30): 15 fixture iters, 7 downgrades.
  #   - 1 gate FAIL (LOW)
  #   - 4 single-axis downgrades (MEDIUM): diff>500, hooks, claude_md, retry
  #   - 1 threshold-edge downgrade (501-line diff, MEDIUM)
  #   - 1 two-axis collapse (LOW)
  # Bumping this cap requires a back-port-doc entry naming the retirement
  # (axis dropped or threshold raised) that pays for the new pause source.
  [ -f "$FIXTURE" ]
  local total=0 false_count=0
  local name gate diff hooks claude retry confidence land
  while IFS='|' read -r name gate diff hooks claude retry; do
    case "$name" in
      ''|'#'*) continue ;;
    esac
    confidence=$(compute_confidence "$gate" "$diff" "$hooks" "$claude" "$retry")
    land=$(should_auto_land "$confidence" "high")
    total=$((total + 1))
    if [ "$land" = "false" ]; then
      false_count=$((false_count + 1))
    fi
  done < "$FIXTURE"

  # Sanity: the fixture must have iters or the budget is vacuous.
  [ "$total" -ge 10 ]

  if [ "$false_count" -gt 7 ]; then
    echo "Pause-rate budget exceeded: $false_count auto_land=false in $total iters (cap=7)." >&2
    echo "A new downgrade source or threshold tightening must pay for itself" >&2
    echo "with a retirement elsewhere — see invariant #1 in" >&2
    echo "docs/upstream-harness-improvements.md." >&2
    return 1
  fi
}

@test "pause-rate budget: fixture has at least 10 iter shapes" {
  # Structural assertion: the fixture is the contract. A degenerate
  # fixture (one iter, one shape) makes the rate test vacuous. Pinning
  # the minimum size forces a future maintainer who edits the fixture to
  # keep coverage diverse enough that threshold tightening still surfaces.
  local count
  count=$(grep -cE '^[a-z][a-z0-9-]*\|' "$FIXTURE")
  [ "$count" -ge 10 ]
}
