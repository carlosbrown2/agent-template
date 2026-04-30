#!/usr/bin/env bats
# tests/hooks/compute_confidence_arity.bats — pin compute_confidence's surface.
#
# Cross-cutting invariant #3 from docs/upstream-harness-improvements.md
# § "Cross-cutting invariants": confidence-axis budget is one in, one out.
# compute_confidence accepts a fixed number of axes; adding one without
# retiring one bloats the function's surface and dilutes each axis's
# signal-to-noise. A future maintainer should be able to hold every axis
# in working memory and know what real-risk class it catches.
#
# This test pins two structural counts with zero headroom:
#   1. the number of positional parameters consumed by the function
#   2. the number of `[[ ... ]] && downgrades=...` axis lines
# Adding a parameter or axis forces the author to bump the constants here
# in the same diff. A retirement (parameter dropped, axis line removed)
# does not fail this test on its own — that is the "one out" half of the
# invariant — but the back-port doc is the place where retirements are
# recorded.

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "compute_confidence body uses at most 5 positional parameters" {
  # Current axes (2026-04-30):
  #   $1 gate_result, $2 diff_lines, $3 touched_hooks,
  #   $4 touched_claude_md, $5 retry_count.
  # The 2026-04-27 back-port entry retires $5 (retry_count) and the
  # 2026-04-29 runaway entry adds loop_saturation as the new $5 — net
  # axis count preserved. Any change that raises this cap earns an
  # explicit back-port-doc entry naming the retirement that pays for it.
  local body max_pos
  body=$(awk '
    /^compute_confidence\(\)[[:space:]]*\{/ { in_fn=1; next }
    in_fn && /^\}[[:space:]]*$/ { exit }
    in_fn { print }
  ' "$PROJECT_ROOT/scripts/ralph/lib.sh")
  [ -n "$body" ]
  # Highest positional param referenced in the body. grep extracts $N or
  # ${N} or ${N:-default}; sed strips the punctuation so sort -n compares
  # integers, not strings.
  max_pos=$(printf '%s\n' "$body" \
    | grep -oE '\$\{?[0-9]+' \
    | sed 's/[${]//g' \
    | sort -un \
    | tail -1)
  [ -n "$max_pos" ]
  if [ "$max_pos" -gt 5 ]; then
    echo "compute_confidence references \$$max_pos (cap=5 positional params)." >&2
    echo "Adding an axis requires retiring one — see invariant #3 in" >&2
    echo "docs/upstream-harness-improvements.md (one in, one out)." >&2
    return 1
  fi
}

@test "compute_confidence body has at most 4 downgrade-axis lines" {
  # Current downgrade axes (2026-04-30):
  #   retry_count > 0
  #   diff_lines > 500
  #   touched_hooks == "true"
  #   touched_claude_md == "true"
  # The pattern matched here is `[[ ... ]] && downgrades=...` — the exact
  # line shape every axis uses inside compute_confidence. A new axis added
  # in any other shape would slip past this count, which is itself a
  # signal that the new axis is not pulling from the same budget.
  local body axis_count
  body=$(awk '
    /^compute_confidence\(\)[[:space:]]*\{/ { in_fn=1; next }
    in_fn && /^\}[[:space:]]*$/ { exit }
    in_fn { print }
  ' "$PROJECT_ROOT/scripts/ralph/lib.sh")
  [ -n "$body" ]
  axis_count=$(printf '%s\n' "$body" \
    | grep -cE '\[\[[[:space:]].*[[:space:]]\]\][[:space:]]+&&[[:space:]]+downgrades=')
  if [ "$axis_count" -gt 4 ]; then
    echo "compute_confidence has $axis_count downgrade-axis lines (cap=4)." >&2
    echo "Adding an axis requires retiring one — see invariant #3 in" >&2
    echo "docs/upstream-harness-improvements.md (one in, one out)." >&2
    return 1
  fi
}
