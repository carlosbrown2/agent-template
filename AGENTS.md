# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

This file covers **session-completion ritual** (landing the plane). Per-iteration work is governed by `scripts/ralph/prompt.md` and the structural rules in `CLAUDE.md`. Where this file and `CLAUDE.md` overlap, `CLAUDE.md` is authoritative.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds **AND** the pre-push gate has printed `pre-push: verification gate PASS.`

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** — Create issues for anything that needs follow-up.
2. **Run quality gates** (if code changed) — Run the `## Verification Gate` command declared in `CLAUDE.md` locally before pushing. This is the same command the pre-push hook will re-run; catching a failure here is cheaper than being rejected at push time. The gate includes `bash -n`, `shellcheck -x`, the `bd` version pin, `bats tests/hooks/`, and `bats tests/gate/` — all clauses must pass.
3. **Update issue status** — Close finished work, update in-progress items.
4. **PUSH TO REMOTE** — This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
   The pre-push hook will re-run the verification gate from `CLAUDE.md`. If the hook prints a `BLOCKED:` message, resolve the failing clause and retry — never bypass with `--no-verify`. If the hook reports a **DIVERGENCE** between `.last-gate-result` and the push-time observed gate result, investigate before pushing; the tree, environment, or gate behavior changed between the iteration-time run and push.
5. **Clean up** — Clear stashes, prune remote branches.
6. **Verify** — All changes committed AND pushed, and the pre-push hook printed `PASS`.
7. **Hand off** — Provide context for next session.

**CRITICAL RULES:**

- Work is NOT complete until `git push` succeeds **and** the pre-push gate passed.
- A PASS from the pre-push hook is the single source of truth. `.last-gate-result` is the bash-observed iteration-time result written by `scripts/ralph/lib.sh` `run_gate` after `BEAD_DONE`; it is useful evidence, not proof. The agent emits no gate-result tag.
- NEVER stop before pushing — that leaves work stranded locally.
- NEVER say "ready to push when you are" — YOU must push.
- If push fails, resolve and retry until it succeeds.
- NEVER pass `--no-verify` to bypass the pre-push hook. If the hook is wrong, fix the hook in a separate bead.
