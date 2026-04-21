#!/usr/bin/env bats
# tests/hooks/ralph.bats — bats suite for scripts/ralph/lib.sh
#
# ralph.sh sources lib.sh; the gate only parse-checks ralph.sh, which does
# not dereference the source at parse time, so a syntax error or logic
# regression in lib.sh would otherwise surface only in a live agent run.
# This suite exercises each routing function against the edge cases the
# bead (agent-template-0iy) calls out explicitly, plus adversarial cases
# that exploit the shape of the current checks:
#   - parse_confidence against the prompt.md placeholder
#   - read_auto_land_policy across section-parse edge cases (blank line
#     between heading and value, commented-out alternatives, section
#     bounded by next ##)
#   - should_auto_land matrix including unknown policy
#   - compute_retry_state increment / reset / escalation boundaries
#   - extract_prereq_bead_id excluding the active-bead header line
#     (naive head -1 would return the active bead itself — a no-op update
#     instead of re-opening the real prerequisite)

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/scripts/ralph/lib.sh"
  TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

# --- parse_confidence ----------------------------------------------------

@test "parse_confidence: matches HIGH emission" {
  run parse_confidence 'some preamble <confidence level="HIGH">rationale</confidence> trailing'
  [ "$status" -eq 0 ]
  [ "$output" = "HIGH" ]
}

@test "parse_confidence: matches MEDIUM emission" {
  run parse_confidence '<confidence level="MEDIUM">edge case uncertain</confidence>'
  [ "$status" -eq 0 ]
  [ "$output" = "MEDIUM" ]
}

@test "parse_confidence: matches LOW emission" {
  run parse_confidence '<confidence level="LOW">partial criteria</confidence>'
  [ "$status" -eq 0 ]
  [ "$output" = "LOW" ]
}

@test "parse_confidence: returns empty when no confidence tag present" {
  run parse_confidence 'output without any confidence signal at all'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "parse_confidence: does NOT match the prompt.md placeholder '<confidence level=\"HIGH|MEDIUM|LOW\">'" {
  # scripts/ralph/prompt.md contains the literal placeholder string. If the
  # agent echoes the prompt verbatim, the output contains the placeholder.
  # The closing `>` anchor in each grep is what prevents the placeholder
  # from accidentally satisfying the HIGH/MEDIUM/LOW branch. If a refactor
  # ever drops the closing `>`, this test fires.
  run parse_confidence 'the placeholder is <confidence level="HIGH|MEDIUM|LOW">rationale</confidence> and nothing else'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "parse_confidence: HIGH takes precedence when multiple tags appear" {
  # Documents the cascade: the grep tree checks HIGH → MEDIUM → LOW. If the
  # agent emits more than one tag, HIGH wins. Flag-bearing behavior —
  # worth pinning so a refactor does not flip the precedence.
  run parse_confidence '<confidence level="LOW">oops</confidence> then <confidence level="HIGH">ok</confidence>'
  [ "$status" -eq 0 ]
  [ "$output" = "HIGH" ]
}

@test "parse_confidence: is not fooled by an invalid level like 'HIGHEST'" {
  run parse_confidence '<confidence level="HIGHEST">bogus</confidence>'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- read_auto_land_policy ----------------------------------------------

@test "read_auto_land_policy: returns 'all' when file is missing" {
  run read_auto_land_policy "$TMPDIR_TEST/does-not-exist.md"
  [ "$status" -eq 0 ]
  [ "$output" = "all" ]
}

@test "read_auto_land_policy: returns 'all' when section has no auto-land line" {
  cat > "$TMPDIR_TEST/CLAUDE.md" <<'EOF'
# Proj

## Confidence Routing

prose here, no setting

## Other
EOF
  run read_auto_land_policy "$TMPDIR_TEST/CLAUDE.md"
  [ "$status" -eq 0 ]
  [ "$output" = "all" ]
}

@test "read_auto_land_policy: extracts 'high' across a blank line between heading and value" {
  # Adversarial case from the bead: the previous grep -A1 implementation
  # only captured the heading + 1 line; a blank line between heading and
  # value meant the real setting was silently dropped and the default
  # ("all") was returned regardless of what CLAUDE.md said. The awk
  # implementation walks the whole section so the blank line is harmless.
  cat > "$TMPDIR_TEST/CLAUDE.md" <<'EOF'
# Proj

## Confidence Routing

auto-land: high

## After
EOF
  run read_auto_land_policy "$TMPDIR_TEST/CLAUDE.md"
  [ "$status" -eq 0 ]
  [ "$output" = "high" ]
}

@test "read_auto_land_policy: extracts 'none'" {
  cat > "$TMPDIR_TEST/CLAUDE.md" <<'EOF'
## Confidence Routing

auto-land: none
EOF
  run read_auto_land_policy "$TMPDIR_TEST/CLAUDE.md"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "read_auto_land_policy: ignores a commented-out alternative line" {
  # Adversarial case from the bead: a naive grep "auto-land:" matches the
  # commented line too. The awk regex requires optional whitespace then
  # "auto-land:" at the start of the line, so "# auto-land: high" is
  # skipped and the real setting "all" wins.
  cat > "$TMPDIR_TEST/CLAUDE.md" <<'EOF'
## Confidence Routing

# auto-land: high
auto-land: all
EOF
  run read_auto_land_policy "$TMPDIR_TEST/CLAUDE.md"
  [ "$status" -eq 0 ]
  [ "$output" = "all" ]
}

@test "read_auto_land_policy: stops at the next '## ' heading" {
  # A setting in a later section must not be harvested. Binds the extractor
  # to the routing section specifically, not to "any auto-land: in the file".
  cat > "$TMPDIR_TEST/CLAUDE.md" <<'EOF'
## Confidence Routing

(prose, no setting)

## Other section

auto-land: high
EOF
  run read_auto_land_policy "$TMPDIR_TEST/CLAUDE.md"
  [ "$status" -eq 0 ]
  [ "$output" = "all" ]
}

@test "read_auto_land_policy: strips trailing whitespace from the value" {
  printf '%s\n' \
    '## Confidence Routing' \
    '' \
    'auto-land: high   ' \
    > "$TMPDIR_TEST/CLAUDE.md"
  run read_auto_land_policy "$TMPDIR_TEST/CLAUDE.md"
  [ "$status" -eq 0 ]
  [ "$output" = "high" ]
}

@test "read_auto_land_policy: smoke — real CLAUDE.md yields a known-good policy" {
  # The real CLAUDE.md in this repo declares auto-land: all. Pins the
  # contract that the shipped template is parseable by the extractor.
  run read_auto_land_policy "$PROJECT_ROOT/CLAUDE.md"
  [ "$status" -eq 0 ]
  [[ "$output" == "all" || "$output" == "high" || "$output" == "none" ]]
}

# --- should_auto_land ---------------------------------------------------

@test "should_auto_land: policy=all, any confidence -> true" {
  for c in HIGH MEDIUM LOW ""; do
    run should_auto_land "$c" "all"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ] || { echo "failed for confidence=$c"; return 1; }
  done
}

@test "should_auto_land: policy=high, HIGH -> true" {
  run should_auto_land "HIGH" "high"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "should_auto_land: policy=high, MEDIUM -> false" {
  run should_auto_land "MEDIUM" "high"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "should_auto_land: policy=high, LOW -> false" {
  run should_auto_land "LOW" "high"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "should_auto_land: policy=none -> false for every confidence" {
  for c in HIGH MEDIUM LOW ""; do
    run should_auto_land "$c" "none"
    [ "$status" -eq 0 ]
    [ "$output" = "false" ] || { echo "failed for confidence=$c"; return 1; }
  done
}

@test "should_auto_land: unknown policy falls back to documented default (all -> true)" {
  # A typo in CLAUDE.md (e.g., "auto-land: al") must not silently become
  # "false" — that would pause every iteration unexpectedly. The default
  # is the documented one: "all".
  run should_auto_land "HIGH" "al"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# --- compute_retry_state ------------------------------------------------

@test "compute_retry_state: empty failed_bead -> noop, state unchanged" {
  run compute_retry_state "" "some-bead" "2" "3"
  [ "$status" -eq 0 ]
  [ "$output" = "2|some-bead|noop" ]
}

@test "compute_retry_state: same bead failing again increments count" {
  run compute_retry_state "agent-template-abc" "agent-template-abc" "1" "3"
  [ "$status" -eq 0 ]
  [ "$output" = "2|agent-template-abc|continue" ]
}

@test "compute_retry_state: new bead failing resets count to 1" {
  # Reset-on-new-bead is called out explicitly in the bead acceptance: a
  # fresh bead must not inherit the predecessor's fail count.
  run compute_retry_state "agent-template-xyz" "agent-template-abc" "2" "3"
  [ "$status" -eq 0 ]
  [ "$output" = "1|agent-template-xyz|continue" ]
}

@test "compute_retry_state: reaching MAX_RETRIES triggers escalate" {
  # 2 prior fails + 1 more == 3 == MAX_RETRIES. Caller sees "escalate".
  run compute_retry_state "agent-template-abc" "agent-template-abc" "2" "3"
  [ "$status" -eq 0 ]
  [ "$output" = "3|agent-template-abc|escalate" ]
}

@test "compute_retry_state: first failure of a bead with MAX_RETRIES=1 escalates immediately" {
  # Boundary: when max_retries is 1, any single failure must escalate.
  # A naive strict-less-than check would give the agent one free failure
  # beyond the stated max.
  run compute_retry_state "agent-template-abc" "" "0" "1"
  [ "$status" -eq 0 ]
  [ "$output" = "1|agent-template-abc|escalate" ]
}

@test "compute_retry_state: starting fresh (empty last) -> count=1, continue" {
  run compute_retry_state "agent-template-abc" "" "0" "3"
  [ "$status" -eq 0 ]
  [ "$output" = "1|agent-template-abc|continue" ]
}

# --- extract_prereq_bead_id ---------------------------------------------

@test "extract_prereq_bead_id: excludes the active-bead header, returns the first real prereq" {
  # Adversarial case from the bead: `bd dep list <X>` output begins with
  # "X depends on:" whose bead-id token matches the same regex used to
  # pick the prerequisite. A naive head -1 returns the active bead itself,
  # so ralph.sh would re-update ACTIVE_BEAD to status=open (a no-op since
  # it was just unclaimed) and never re-open the real prerequisite. Binding
  # the extraction to "first id that is NOT the active bead" fixes this.
  input="📋 agent-template-6ij depends on:

  agent-template-4mw: Add pre-push hook that re-runs the verification gate [P1] (closed) via blocks
  agent-template-mhd: Add automated parser tests for hook parsers (bats suite) [P1] (closed) via blocks"
  run bash -c 'source "$0"; echo "$1" | extract_prereq_bead_id "$2"' \
    "$PROJECT_ROOT/scripts/ralph/lib.sh" "$input" "agent-template-6ij"
  [ "$status" -eq 0 ]
  [ "$output" = "agent-template-4mw" ]
}

@test "extract_prereq_bead_id: returns empty when the only match is the active bead" {
  # "X has no dependencies" path — only the active bead id appears in the
  # output. After exclusion, no match remains. Must return empty (not the
  # active bead) so the caller skips the re-open step.
  input="agent-template-6ij has no dependencies"
  run bash -c 'source "$0"; echo "$1" | extract_prereq_bead_id "$2"' \
    "$PROJECT_ROOT/scripts/ralph/lib.sh" "$input" "agent-template-6ij"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "extract_prereq_bead_id: returns empty on input with no bead-id-shaped tokens" {
  # Deliberately free of the pattern `[a-z][-a-z0-9]*-[a-z0-9]{2,}`: no
  # dashed lowercase tokens, no digit-bearing words. Confirms the function
  # does not hallucinate a match when the output is pure prose (e.g., a
  # future bd error message that says only "command failed" or similar).
  run bash -c 'source "$0"; echo "$1" | extract_prereq_bead_id "$2"' \
    "$PROJECT_ROOT/scripts/ralph/lib.sh" "nothing matches here" "agent-template-6ij"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "extract_prereq_bead_id: skips a dashed prose word only when that word is the active bead" {
  # Adversarial case: the regex matches any `[a-z][-a-z0-9]*-[a-z0-9]{2,}`,
  # so a bead title containing a dashed word like "pre-push" is a match.
  # In real `bd dep list` output the prereq bead id always appears before
  # its title on the same line, so grep -o (which returns matches in
  # order) picks the bead id first. This test pins that ordering so a
  # future refactor to multiline or split-word handling does not break it.
  input="  agent-template-4mw: Add pre-push hook for gate re-run [P1] (closed) via blocks"
  run bash -c 'source "$0"; echo "$1" | extract_prereq_bead_id "$2"' \
    "$PROJECT_ROOT/scripts/ralph/lib.sh" "$input" "agent-template-6ij"
  [ "$status" -eq 0 ]
  [ "$output" = "agent-template-4mw" ]
}

@test "extract_prereq_bead_id: handles multiple prereqs, returns only the first" {
  input="agent-template-6ij depends on:

  agent-template-first: title one
  agent-template-second: title two"
  run bash -c 'source "$0"; echo "$1" | extract_prereq_bead_id "$2"' \
    "$PROJECT_ROOT/scripts/ralph/lib.sh" "$input" "agent-template-6ij"
  [ "$status" -eq 0 ]
  [ "$output" = "agent-template-first" ]
}
