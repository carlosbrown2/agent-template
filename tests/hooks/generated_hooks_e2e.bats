#!/usr/bin/env bats
# End-to-end tests for the generated git hooks written by scripts/hooks/install.sh.

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPDIR_TEST="$(mktemp -d)"
  TEST_REPO="$TMPDIR_TEST/repo"
  BIN_DIR="$TMPDIR_TEST/bin"
  mkdir -p "$TEST_REPO/scripts/hooks" "$BIN_DIR"

  cp "$PROJECT_ROOT/scripts/hooks/install.sh" "$TEST_REPO/scripts/hooks/install.sh"
  cp "$PROJECT_ROOT/scripts/hooks/parsers.sh" "$TEST_REPO/scripts/hooks/parsers.sh"

  git -C "$TEST_REPO" init -q
  git -C "$TEST_REPO" config user.email test@example.com
  git -C "$TEST_REPO" config user.name "Test User"

  printf '[]\n' > "$TMPDIR_TEST/bd-state.json"
  printf '0\n' > "$TMPDIR_TEST/gitleaks-status"
  printf '0\n' > "$TMPDIR_TEST/dep-status"

  cat > "$BIN_DIR/bd" <<EOF
#!/bin/bash
if [ "\$1" = "--version" ]; then
  printf 'bd version 0.3.0\\n'
  exit 0
fi
if [ "\$1" = "--no-daemon" ] && [ "\$2" = "list" ] && [ "\$3" = "--status=in_progress" ] && [ "\$4" = "--json" ]; then
  cat "$TMPDIR_TEST/bd-state.json"
  exit 0
fi
echo "unexpected bd invocation: \$*" >&2
exit 1
EOF
  chmod +x "$BIN_DIR/bd"

  cat > "$BIN_DIR/gitleaks" <<EOF
#!/bin/bash
status=\$(cat "$TMPDIR_TEST/gitleaks-status")
if [ "\$status" -ne 0 ]; then
  echo "mock gitleaks finding" >&2
  exit "\$status"
fi
exit 0
EOF
  chmod +x "$BIN_DIR/gitleaks"

  cat > "$BIN_DIR/dep-hallucinator" <<EOF
#!/bin/bash
status=\$(cat "$TMPDIR_TEST/dep-status")
if [ "\$status" -ne 0 ]; then
  echo "mock dep-hallucinator finding: \$*" >&2
  exit "\$status"
fi
exit 0
EOF
  chmod +x "$BIN_DIR/dep-hallucinator"

  cat > "$TEST_REPO/CLAUDE.md" <<'EOF'
# Scratch Project

## Verification Gate

```
printf gate-pass > .gate-ran
```
EOF

  PATH="$BIN_DIR:$PATH" bash "$TEST_REPO/scripts/hooks/install.sh" >/dev/null
  git -C "$TEST_REPO" add CLAUDE.md scripts/hooks/install.sh scripts/hooks/parsers.sh
  git_commit "chore: init"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

git_commit() {
  ( cd "$TEST_REPO" && PATH="$BIN_DIR:$PATH" git commit -q -m "$1" )
}

set_in_progress_bead() {
  printf '[{"id":"agent-template-3ne"}]\n' > "$TMPDIR_TEST/bd-state.json"
  printf '%s\n' "$1" > "$TEST_REPO/.current-bead-type"
}

@test "generated pre-commit blocks out-of-scope impl commits and permits in-scope commits" {
  set_in_progress_bead impl
  printf 'allowed.txt\n' > "$TEST_REPO/.current-bead-scope"

  printf 'allowed\n' > "$TEST_REPO/allowed.txt"
  git -C "$TEST_REPO" add allowed.txt
  run git_commit "feat: [agent-template-3ne] - Add allowed file"
  [ "$status" -eq 0 ]

  printf 'blocked\n' > "$TEST_REPO/blocked.txt"
  git -C "$TEST_REPO" add blocked.txt
  run git_commit "feat: [agent-template-3ne] - Add blocked file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCKED: Files outside the current bead's declared scope"* ]]
  [[ "$output" == *"blocked.txt"* ]]
}

@test "generated commit-msg blocks malformed bead messages after pre-commit passes" {
  set_in_progress_bead impl
  printf 'allowed.txt\n' > "$TEST_REPO/.current-bead-scope"
  printf 'allowed\n' > "$TEST_REPO/allowed.txt"
  git -C "$TEST_REPO" add allowed.txt

  run git_commit "feat: [bad] missing separator"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCKED: Bead commit message does not match"* ]]
}

@test "generated pre-commit fail-closes when gitleaks reports a finding" {
  printf '1\n' > "$TMPDIR_TEST/gitleaks-status"
  printf 'token = "secret"\n' > "$TEST_REPO/config.txt"
  git -C "$TEST_REPO" add config.txt

  run git_commit "chore: add config"
  [ "$status" -ne 0 ]
  [[ "$output" == *"mock gitleaks finding"* ]]
  [[ "$output" == *"BLOCKED: gitleaks detected potential secrets"* ]]
}

@test "generated pre-commit fail-closes when dep-hallucinator reports a finding" {
  printf '1\n' > "$TMPDIR_TEST/dep-status"
  printf '{"dependencies":{"definitely-fake-package":"1.0.0"}}\n' > "$TEST_REPO/package.json"
  git -C "$TEST_REPO" add package.json

  run git_commit "chore: add package manifest"
  [ "$status" -ne 0 ]
  [[ "$output" == *"mock dep-hallucinator finding"* ]]
  [[ "$output" == *"BLOCKED: dep-hallucinator detected suspect dependencies"* ]]
}

@test "generated pre-commit warns but permits commit when optional scanners are missing" {
  rm "$BIN_DIR/gitleaks" "$BIN_DIR/dep-hallucinator"
  printf '{"dependencies":{"left-pad":"1.3.0"}}\n' > "$TEST_REPO/package.json"
  git -C "$TEST_REPO" add package.json

  run git_commit "chore: add package manifest"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: gitleaks not installed"* ]]
  [[ "$output" == *"WARNING: dep-hallucinator not installed"* ]]
}

@test "generated pre-push extracts and runs the CLAUDE.md verification gate" {
  git -C "$TMPDIR_TEST" init --bare -q remote.git
  git -C "$TEST_REPO" remote add origin "$TMPDIR_TEST/remote.git"

  run bash -c 'cd "$0" && PATH="$1:$PATH" git push --dry-run origin HEAD:main' "$TEST_REPO" "$BIN_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pre-push: verification gate PASS."* ]]
  [ -f "$TEST_REPO/.gate-ran" ]
}

@test "generated pre-push blocks when the extracted verification gate fails" {
  cat > "$TEST_REPO/CLAUDE.md" <<'EOF'
# Scratch Project

## Verification Gate

```
echo gate-failed
exit 42
```
EOF
  git -C "$TEST_REPO" add CLAUDE.md
  git_commit "chore: make gate fail"
  git -C "$TMPDIR_TEST" init --bare -q remote.git
  git -C "$TEST_REPO" remote add origin "$TMPDIR_TEST/remote.git"

  run bash -c 'cd "$0" && PATH="$1:$PATH" git push --dry-run origin HEAD:main' "$TEST_REPO" "$BIN_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"gate-failed"* ]]
  [[ "$output" == *"BLOCKED: verification gate failed on pre-push"* ]]
}
