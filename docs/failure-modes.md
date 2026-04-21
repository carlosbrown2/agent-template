# Failure-mode register

Every module, function, and data flow that can fail must appear here, paired with a mechanical check that catches the failure before merge. See `project-kickoff-prompt.md` §1 for the contract.

**Status values:** `covered` | `proven-impossible` | `out-of-scope`

**Categories:** `correctness` | `concurrency` | `atomicity` | `input` | `resource` | `temporal` | `version` | `dependency` | `operational` | `security`

| Module / function | Failure mode | Category | Check (file:test) | Status |
|-------------------|--------------|----------|-------------------|--------|
| scripts/ralph/ralph.sh gate-result parsing | agent emits `<gate-result>PASS</gate-result>` without running the gate (Goodhart / gate-bypass) | correctness | scripts/hooks/install.sh pre-push hook re-runs the gate command from CLAUDE.md and blocks push on non-zero exit; divergence against scripts/ralph/ralph.sh-persisted .last-gate-result is reported in the block message | covered |
| scripts/hooks/parsers.sh register-integrity parsers | edge cases (escaped pipes, Unicode, trailing whitespace, 5-column rows, multi-line continuation rows) silently accept malformed rows or reject valid ones; drift between the inlined pre-commit awk and the callable parsers | correctness | tests/hooks/parsers.bats exercises every parser against known-good and known-bad fixtures plus smoke tests against the real registers; scripts/hooks/install.sh sources parsers.sh so there is only one implementation | covered |

<!--
Rows are added as the template grows. One audit bead remains open for the template itself
(see `bd list --labels initializer-audit`):

  - unedited review-rubric starter lets "Review verdict" claim bounded falsely  → agent-template-kjy

Each bead's DoD includes adding a row here once the check ships.
-->
