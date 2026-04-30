#!/usr/bin/env bats
# tests/hooks/gate_clause_count.bats — pin the verification gate's clause count.
#
# Cross-cutting invariant #2 from docs/upstream-harness-improvements.md
# § "Cross-cutting invariants": gate-clause count is fixed. Adding a
# top-level && clause inflates parse cost, multiplies CI runtime, and makes
# failure-attribution noisier. New harness checks land as functions in
# scripts/hooks/parsers.sh and absorb into the existing `bats tests/hooks/`
# clause — gate-string length unchanged. A change that adds a new clause
# earns a separate entry in the back-port doc naming why bats cannot
# absorb it.
#
# This test pins the count at the template's current value with zero
# headroom. Adding a clause forces the author to bump the constant here in
# the same diff — a visible, reviewable change rather than silent growth.
# The bats sweep that runs this test is itself one of the counted clauses,
# so the cap-and-test live in the same gate-clause budget by design.

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/scripts/hooks/parsers.sh"
}

@test "verification gate has at most 7 top-level && clauses" {
  # Current clauses (2026-04-30):
  #   1. bash -n scripts/ralph/ralph.sh
  #   2. bash -n scripts/ralph/lib.sh
  #   3. bash -n scripts/hooks/install.sh
  #   4. bash -n scripts/hooks/parsers.sh
  #   5. shellcheck -x <four files>
  #   6. bd --version pin
  #   7. bats tests/hooks/
  # Bumping this cap requires a back-port-doc entry naming why the new
  # clause cannot fold into the bats sweep — the gate-clause invariant.
  local gate
  gate=$(gate_command_extract "$PROJECT_ROOT/CLAUDE.md")
  [ -n "$gate" ]
  # Top-level && separator count: clauses = separators + 1.
  local sep_count clause_count
  sep_count=$(printf '%s' "$gate" | grep -oE ' && ' | wc -l | tr -d ' ')
  clause_count=$((sep_count + 1))
  if [ "$clause_count" -gt 7 ]; then
    echo "Gate has $clause_count top-level && clauses (cap=7)." >&2
    echo "Bumping the cap requires a docs/upstream-harness-improvements.md entry" >&2
    echo "naming why the new clause cannot fold into 'bats tests/hooks/'." >&2
    return 1
  fi
}
