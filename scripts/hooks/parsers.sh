#!/bin/bash
# scripts/hooks/parsers.sh — register-integrity parser library
#
# Functions exposed for callers (the generated .git/hooks/pre-commit script and
# the bats suite under tests/hooks/). Each function:
#   - takes a register/file path as $1 (and project-root + staged-list where needed)
#   - prints offending rows / missing references to stdout
#   - returns 0 on pass, 1 on fail
#
# This file is sourced, not executed. Callers manage their own set -e state.

# fm_status_check <register-path>
fm_status_check() {
  local fm_register="$1"
  local bad
  bad=$(awk '
    /^\|/ {
      line = $0
      stripped = line
      gsub(/[|:\- \t]/, "", stripped)
      if (stripped == "") next
      if (line ~ /Failure mode/ || line ~ /Status[ \t]*\|/) next

      n = split(line, cells, "|")
      last_cell = cells[n-1]
      sub(/^[ \t]+/, "", last_cell)
      sub(/[ \t]+$/, "", last_cell)
      if (last_cell != "covered" && last_cell != "proven-impossible" && last_cell != "out-of-scope") {
        print NR ": " line
      }
    }
  ' "$fm_register" 2>/dev/null) || true

  if [ -n "$bad" ]; then
    printf '%s\n' "$bad"
    return 1
  fi
  return 0
}

# fm_file_refs_check <register-path> <project-root> [<staged-files-newline-separated>]
fm_file_refs_check() {
  local fm_register="$1"
  local project_root="$2"
  local staged="${3:-}"
  local missing=""
  local ref file_part
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    file_part="${ref%%::*}"
    if [ ! -f "$project_root/$file_part" ]; then
      if ! printf '%s\n' "$staged" | grep -qx "$file_part"; then
        missing="${missing}
    ${ref}"
      fi
    fi
  done < <(grep -oE '(tests?|proofs|src|spec|docs|tasks|scripts|lib|pkg)/[a-zA-Z0-9_/.-]+\.[a-zA-Z0-9]+(::[a-zA-Z0-9_]+)?' "$fm_register" 2>/dev/null | sort -u)

  if [ -n "$missing" ]; then
    printf '%s\n' "$missing"
    return 1
  fi
  return 0
}

# dec_required_rows_check <register-path>
dec_required_rows_check() {
  local dec_register="$1"
  local required=(
    "Solution selection"
    "Acceptance interpretation"
    "Sampling variance"
    "Verification truth"
    "Scope creep"
  )
  local missing="" d
  for d in "${required[@]}"; do
    if ! grep -qF "$d" "$dec_register"; then
      missing="${missing}
    ${d}"
    fi
  done
  if [ -n "$missing" ]; then
    printf '%s\n' "$missing"
    return 1
  fi
  return 0
}

# dec_row_structure_check <register-path>
dec_row_structure_check() {
  local dec_register="$1"
  local bad
  bad=$(awk '
    /^\|/ {
      line = $0
      stripped = line
      gsub(/[|:\- \t]/, "", stripped)
      if (stripped == "") next
      if (line ~ /Decision point/) next

      count_line = line
      gsub(/\\\|/, "", count_line)
      n_pipes = gsub(/\|/, "|", count_line)
      if (n_pipes < 6) {
        print NR ": (too few columns) " $0
        next
      }

      n = split(line, cells, "|")
      last_cell = cells[n-1]
      sub(/^[ \t]+/, "", last_cell)
      sub(/[ \t]+$/, "", last_cell)
      if (last_cell != "bounded" && last_cell != "ritual-bounded" && last_cell != "agent-discretion" && last_cell != "escalation-only") {
        print NR ": (bad status) " $0
      }
    }
  ' "$dec_register" 2>/dev/null) || true

  if [ -n "$bad" ]; then
    printf '%s\n' "$bad"
    return 1
  fi
  return 0
}

# dec_file_refs_check <register-path> <project-root> [<staged-files-newline-separated>]
dec_file_refs_check() {
  local dec_register="$1"
  local project_root="$2"
  local staged="${3:-}"
  local missing="" ref
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    if [ ! -f "$project_root/$ref" ]; then
      if ! printf '%s\n' "$staged" | grep -qx "$ref"; then
        missing="${missing}
    ${ref}"
      fi
    fi
  done < <(grep -oE '(tests?|proofs|src|spec|docs|tasks|scripts|lib|pkg)/[a-zA-Z0-9_/.-]+\.[a-zA-Z0-9]+' "$dec_register" 2>/dev/null | sort -u)

  if [ -n "$missing" ]; then
    printf '%s\n' "$missing"
    return 1
  fi
  return 0
}

# claude_model_tags_check <claude-md-path>
claude_model_tags_check() {
  local claude_md="$1"
  local bad
  bad=$(awk '
    BEGIN { in_section = 0; current_entry = ""; current_line = 0; has_model = 0 }
    /^## Discovered Patterns/ {
      in_section = 1
      current_entry = ""
      has_model = 0
      next
    }
    in_section && /^## / {
      if (current_entry != "" && !has_model) {
        print current_line ": " current_entry
      }
      in_section = 0
      next
    }
    in_section && /^### / {
      if (current_entry != "" && !has_model) {
        print current_line ": " current_entry
      }
      current_entry = $0
      current_line = NR
      has_model = 0
      next
    }
    in_section && /^[[:space:]]*model:[[:space:]]/ { has_model = 1 }
    END {
      if (in_section && current_entry != "" && !has_model) {
        print current_line ": " current_entry
      }
    }
  ' "$claude_md" 2>/dev/null) || true

  if [ -n "$bad" ]; then
    printf '%s\n' "$bad"
    return 1
  fi
  return 0
}
