# Review: agent-template-6ij — Final review of initializer-audit

**Bead:** agent-template-6ij (review)
**Scope (per bead description):** verify the four recommendations in `initializer-recommendations.md` against the shipped implementation. Explicitly out of scope: adding new audit findings.
**Verdict:** GREEN — all four recommendations shipped correctly. Three P2 follow-ups uncovered while adversarially probing the new mechanisms; filed as separate beads, do not block this one.

Findings cite clauses from `docs/skills/review-rubric.md`.

---

## Verification of the four recommendations

### Recommendation 1 — Pre-push hook re-runs the gate

**What the recommendation said:** Add a pre-push hook that parses the gate command from `CLAUDE.md`, runs it, fails the iteration if the observed result diverges from the self-reported `<gate-result>` tag. Promote `Verification truth` from `ritual-bounded` to `bounded`. Remove the prose caveat at the kickoff line that flags the bypass.

**What ships:**
- `scripts/hooks/install.sh:475-543` writes a `pre-push` hook that extracts the gate from CLAUDE.md via the same awk extractor used in the recommendation sketch, runs it under `bash -c`, and exits 1 on observed FAIL.
- The hook reads `.last-gate-result` (written by `scripts/ralph/ralph.sh` from the agent's `<gate-result>` tag) and prints an explicit `DIVERGENCE: agent self-reported PASS but the real gate fails` message when self-report and observed exit diverge.
- The inverse divergence (observed PASS but self-report FAIL) is also caught and blocked.
- `docs/decision-register.md:20` "Verification truth" status is now `bounded`; the Enforcement cell names both `scripts/ralph/ralph.sh` (persistence) and `scripts/hooks/install.sh` (pre-push hook).
- `project-kickoff-prompt.md:196-197` describes the gate as enforced at two points (agent self-report + pre-push hook re-run); the prior `ritual-bounded` self-report caveat has been replaced.

**Live verification (in a clean rsynced worktree, fresh `git init`):**
- Installed CLAUDE.md gate replaced with `false`. Wrote `PASS` to `.last-gate-result`. Ran `bash .git/hooks/pre-push` → exited 1 with `DIVERGENCE: agent self-reported PASS but the real gate fails`. ✓
- Wrote `FAIL` to `.last-gate-result` with the real (passing) gate restored. Ran the hook → exited 1 with `BLOCKED: observed=PASS but agent self-reported FAIL`. ✓
- Wrote `PASS` to `.last-gate-result` with the real (passing) gate. Ran the hook → exited 0 with `pre-push: verification gate PASS.` ✓

**Verdict:** PASS. Cited clauses from rubric: would have flagged `P1.gate-bypass` if the hook hadn't shipped; the hook closes that bypass.

---

### Recommendation 2 — Parser tests (`tests/hooks/` bats suite)

**What the recommendation said:** Add a `tests/hooks/` directory with a bats suite that exercises each parser against known-good and known-bad fixtures including escaped pipes, Unicode, exactly-5-column rows, trailing whitespace, multi-line continuation rows. Wire it into `CONTRIBUTING.md` as the first verification step before the end-to-end ralph run.

**What ships:**
- `tests/hooks/parsers.bats` — 41 tests total (35 unit + 6 smoke). Coverage by parser:
  - `fm_status_check`: 6 tests including "rejects multi-line continuation row (last cell empty)" and "accepts trailing whitespace after status" and "accepts Unicode in cells"
  - `fm_file_refs_check`: 4 tests including "strips pytest-style ::test_name suffix when checking file existence"
  - `dec_required_rows_check`: 2 tests including "rejects register missing a baseline decision"
  - `dec_row_structure_check`: 7 tests including "accepts row with escaped pipes inside a cell" and "rejects row with fewer than 5 columns"
  - `dec_file_refs_check`: 2 tests
  - `claude_model_tags_check`: 6 tests including "does not count prose 'the model' as a tag" and "detects untagged entry at end of section"
  - 6 smoke tests asserting each parser passes against the actual committed registers (drift detector — catches register edits that move out of sync with parser logic).
- `scripts/hooks/parsers.sh` is the single source of truth: `scripts/hooks/install.sh:69-77` sources it into the generated pre-commit hook so unit-tested behavior and production behavior cannot drift.
- `CONTRIBUTING.md:33-50` orders the parser suite as step 1 ("Run the parser suite first") with the explicit rationale "Run this before the end-to-end ralph test below so you don't chase a loop failure that is actually a parser regression."

**Live verification:**
- Ran `bats tests/hooks/` against the current repo: 41/41 passing. ✓
- Re-ran the verification gate from CLAUDE.md (`bash -n scripts/ralph/ralph.sh && bash -n scripts/hooks/install.sh && bash -n scripts/hooks/parsers.sh && bats tests/hooks/`): exit 0. ✓
- Confirmed every fixture cited in the recommendation has a corresponding test — every listed edge case appears in the suite.

**Verdict:** PASS.

---

### Recommendation 3 — Rubric-edit hook

**What the recommendation said:** Add a pre-commit guard that blocks commits while `docs/skills/review-rubric.md` still contains the "This file is a starter rubric" disclaimer once any bead is in_progress. Phase 1 bootstrap (no in-progress bead) exempt. Promote "Review verdict" from `ritual-bounded` to `bounded`.

**What ships:**
- `scripts/hooks/install.sh:155-181` installs the rubric-edit guard. The guard fires when `IN_PROGRESS_BEAD` is non-empty, the rubric file exists, and `grep -qF "This file is a starter rubric"` matches. Exits 1 with a multi-line BLOCKED message referencing the Phase 1 contract.
- `docs/decision-register.md:11` "Review verdict" status is now `bounded`. The Enforcement cell names "review artifact validator hook + rubric-edit guard hook in scripts/hooks/install.sh".
- The shipped `docs/skills/review-rubric.md` has been refined for the template itself: project-named header, the starter disclaimer paragraph removed, and a project-specific clause `P1.hook-bypass` added — so the template's own commits don't trip the new hook.

**Live verification (clean worktree, mocked `bd` returning an in-progress bead):**
- Restored the starter disclaimer to the rubric, set `.current-bead-type=impl`, set scope, mocked `bd` to return an in_progress bead with the proper ID format. Ran `bash .git/hooks/pre-commit` → exited 1 with `BLOCKED: docs/skills/review-rubric.md still contains the starter disclaimer.` ✓
- Removed `.current-bead-type` and the scope file (no in-progress bead). Re-ran the pre-commit hook → exit 0 (Phase 1 bootstrap exempt). ✓

**Verdict:** PASS.

---

### Recommendation 4 — `AGENTS.md` cleanup-block annotation

**What the recommendation said:** Add inline comments under the cleanup command in `CONTRIBUTING.md` so a new contributor knows what produces each artifact: `.beads` from `bd init`, `AGENTS.md` from Amp on first run (analogous to Claude Code's CLAUDE.md), `.pytest_cache` from a pytest-based gate.

**What ships:** `CONTRIBUTING.md:71-75` carries exactly the recommended annotations:
```
rm -rf .beads AGENTS.md .pytest_cache
# .beads: created by `bd init`
# AGENTS.md: created by Amp on first run (analogous to Claude Code's CLAUDE.md)
# .pytest_cache: created if the test bead's verification gate runs pytest
```

**Verdict:** PASS.

---

## Adversarial falsification of the registers

Per the review-bead contract, attempted to construct inputs that trigger a documented failure mode but slip past the listed check, and to find decision points where an agent action could fall inside the bounded mechanism without being constrained.

### Failure-mode register (`docs/failure-modes.md`)

| Row | Probe | Slipped past? |
|-----|-------|---------------|
| 11 (gate-bypass) | Edit `## Verification Gate` heading to something else so awk extractor returns empty | No — pre-push fails closed with `BLOCKED: no verification gate found` |
| 11 (gate-bypass) | Replace gate command with `true` | Partially — `tests/hooks/gate.bats` test 4 (structural) requires the bats clause in the gate, and tests 6/7 require non-zero exit when ralph.sh / parsers.sh are corrupted, which a literal `true` cannot satisfy. The corruption tests are the real defense. |
| 12 (parser drift) | Edit `install.sh` to inline parsers again rather than sourcing | **Slipped past** — no test asserts that `install.sh` sources `parsers.sh` rather than inlining. See P2.weak-test below. |
| 13 (rubric guard) | Replace rubric with stub that omits the disclaimer phrase but contains no project-specific content | **Slipped past** — guard is `grep -qF "This file is a starter rubric"`, bounded only by the disclaimer text. See P2.weak-test below. |
| 14 (gate no-op) | Replace trailing `\|\| true` with trailing `\|\| :` | Bypasses gate.bats test 2; caught by tests 6/7 (corruption). Tightenable, see P2.weak-test below. |
| 15 (bats recursion) | Spawn a sub-shell that explicitly unsets `_BATS_GATE_REENTRY` and re-runs the gate | Mechanically possible but requires the attacker to write the bypass code — no checked-in mechanism does this. Out of scope: the sentinel handles the natural-recursion case it was added for. |
| 16 (parsers.sh syntax) | Introduce syntax error in `parsers.sh` | Caught — gate clause `bash -n scripts/hooks/parsers.sh` exits non-zero. ✓ |

### Decision register (`docs/decision-register.md`)

| Row | Probe | Slipped past? |
|-----|-------|---------------|
| Verification truth (bounded) | Same as failure-mode 11 above | Bounded for the named bypass class; see P2.weak-test for `\|\| :` |
| Review verdict (bounded) | Cite an invented clause name (`P1.totally-made-up-clause`) in a review artifact | **Slipped past** — review artifact validator regex `P[123]\.[a-z][a-z-]*` accepts any well-formed token; doesn't enforce membership in the rubric's actual clause list. See P2.weak-test below. |
| Pattern extraction (bounded) | Tag a pattern with `model: claude-opus-99-99` | Slipped past — model-tag validator only checks tag presence, not value membership. Acceptable: tag presence is the actual contract; tag accuracy is a ritual-bounded social check on the author. |
| Scope creep (bounded) | Touch a file outside `.current-bead-scope` | Caught by scope hook with explicit listing. ✓ |
| Confidence (bounded) | Emit `<confidence level="HIGH">` regardless of actual certainty | Acceptable (by design): confidence is a self-report, like gate-result was before the pre-push hook. Under the current `auto-land: all` policy this doesn't gate anything. Worth noting under `auto-land: high` policies but not P-classifiable here. |

---

## Findings

### P2 (file as new beads — do not block this review)

**P2.weak-test — Rubric-edit guard is bounded only by the disclaimer phrase, not by project-specificity.**
The hook (`scripts/hooks/install.sh:163`) fires only when `grep -qF "This file is a starter rubric"` matches. A future edit that simply deletes that one sentence — without renaming the header, without adding any project-specific clause — passes the guard. Reproduced in a clean worktree: replaced the rubric with a 3-line stub that omits the disclaimer and contains no clauses; pre-commit exited 0. The hook's BLOCKED message accurately describes the Phase 1 contract ("replace the disclaimer + add at least one project-specific clause"), but only the disclaimer half is enforced.

**P2.weak-test — `gate.bats` trailing-`|| true` check has narrower coverage than the bug class it names.**
`tests/hooks/gate.bats` test 2 asserts the gate command does not end with `[[:space:]]*\|\|[[:space:]]*true[[:space:]]*$`. The bug class documented in `docs/failure-modes.md:14` is broader: any soft-fail escape via shell precedence. Reproduced: replacing the gate with `... && bats tests/hooks/ || :` passes test 2 (the colon noop is functionally identical to `|| true` but isn't matched). The test class is rescued by tests 6/7 (corruption tests detect that ralph.sh / parsers.sh syntax errors no longer fail the chain), but the named test 2 has a coverage gap that future agents reading it as the canonical defense will not notice.

**P2.weak-test — Review artifact validator accepts invented clause names.**
The validator (`scripts/hooks/install.sh:397`) requires at least one match of `P[123]\.[a-z][a-z-]*` in a review artifact. It does not check membership against the actual clauses defined in `docs/skills/review-rubric.md`. Reproduced: a review artifact citing `P1.totally-made-up-clause` (no such clause in the rubric) passes the validator. The decision-register row "Review verdict" claims `bounded` by "each finding cites a clause" — but the binding is to clause-shaped strings, not to clauses that exist.

### P3 (note in archive.txt)

None beyond the P2 set.

---

## Recommendations

- File three follow-up beads (one per P2). All three are tightenings of mechanisms that already exist; none invalidate the four recommendations being verified here.
- Do not re-open agent-template-4mw, -mhd, -kjy, or -p3n. Each shipped what its bead specified; the P2s are about taking the next step from "named contract" to "fully mechanically-bounded contract."

## Pare-down notes

This review is itself read-only. No source files modified; this artifact and the archive entry are the only outputs.
