# Failure-mode register

Every module, function, and data flow that can fail must appear here, paired with a mechanical check that catches the failure before merge. See `project-kickoff-prompt.md` §1 for the contract.

**Status values:** `covered` | `proven-impossible` | `out-of-scope`

**Categories:** `correctness` | `concurrency` | `atomicity` | `input` | `resource` | `temporal` | `version` | `dependency` | `operational` | `security`

## Project failure modes

Empty for downstream — fill in as project failure modes are caught and bound to a check.

| Module / function | Failure mode | Category | Check (file:test) | Status |
|-------------------|--------------|----------|-------------------|--------|

## Template-meta rows (downstream: prune)

These rows bind this template's own harness internals (`scripts/ralph/`, `scripts/hooks/`, `tests/hooks/`) and are not relevant to downstream feature work. A fresh repo bootstrapped from this template should review and likely delete them. The integrity hook walks every `^|` row in the file regardless of section, so the schema (single-line, 5-column, valid Status in the last cell) holds across both tables.

| Module / function | Failure mode | Category | Check (file:test) | Status |
|-------------------|--------------|----------|-------------------|--------|
| scripts/hooks/parsers.sh register-integrity parsers | edge cases (escaped pipes, Unicode, trailing whitespace, 5-column rows, multi-line continuation rows) silently accept malformed rows or reject valid ones; drift between the inlined pre-commit awk and the callable parsers | correctness | tests/hooks/parsers.bats exercises every parser against known-good and known-bad fixtures plus smoke tests against the real registers; scripts/hooks/install.sh sources parsers.sh so there is only one implementation | covered |
| CLAUDE.md "## Verification Gate" extractor duplication | the awk that extracts the gate command was duplicated in scripts/hooks/install.sh (pre-push hook heredoc) and tests/gate/gate.bats (setup). Drift between the two makes the gate.bats "gate passes against the current repo" sanity test a proxy for "what gate.bats extracts," not "what the pre-push hook extracts" — so a gate.bats extractor that silently extracts nothing would make every gate assertion vacuously pass while the real pre-push hook happily re-runs a drifted gate | correctness | scripts/hooks/parsers.sh gate_command_extract is the single implementation; the pre-push heredoc in scripts/hooks/install.sh sources parsers.sh and calls the function; tests/gate/gate.bats sources parsers.sh in setup | covered |
| scripts/hooks/install.sh bead-type gate, bd extraction | the pre-commit hook conditioned on `IN_PROGRESS_BEAD` which was populated by `bd list \| grep -o ... \| head -1 \|\| true`. If bd's human-readable format drifted, the grep matched nothing and the entire gate chain (bead-type, scope, register integrity) silently no-opped. A malformed bd output was indistinguishable from "no bead in progress," which is exactly the state that disables the chain | correctness | scripts/hooks/parsers.sh bd_bead_in_progress uses `bd list --status=in_progress --json \| jq` and returns non-zero on extraction failure (bd errored or produced non-parseable JSON). scripts/hooks/install.sh pre-commit sources the function and BLOCKS the commit on non-zero — fail-closed rather than fail-open. Phase 1 bootstrap (no bd installed) still passes because the function short-circuits on `command -v bd`. tests/hooks/parsers.bats covers the non-parseable-JSON reject path and the no-bd-installed accept path | covered |
| scripts/ralph/archive.txt machine-readability | prompt.md mandates the agent append a `## <date> - <bead-id>` block to archive.txt after each BEAD_DONE iteration, but nothing downstream parsed it. "Agent updated the log" was a proxy for "the log is useful"; the agent could write anything (or nothing structured) and the gate stayed green. Future agents discovering prior decisions had to trust that each block was present, complete, and findable | correctness | scripts/hooks/parsers.sh archive_schema_check asserts that every `bead_done=true` entry in confidence.log with a real bead id (not `unknown`) has a matching `## YYYY-MM-DD [HH:MM] - <bead-id>` block in archive.txt. Wired into the verification gate so a BEAD_DONE without a corresponding archive block fails the next push. Phase 1 bootstrap (no confidence.log) and pre-fix logs (all `bead=unknown`) pass. Smoke tested in tests/hooks/parsers.bats | covered |
