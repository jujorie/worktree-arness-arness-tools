#!/usr/bin/env bats
# Repo-wide checks of every script and test: portability, shellcheck, and the plugin's own bats check.

load helpers/repo

@test "every script has a bash shebang, LF endings and is executable" {
  while IFS= read -r f; do
    [ "$(head -1 "$f")" = "#!/usr/bin/env bash" ] || { echo "shebang: $f"; false; }
    ! grep -q $'\r' "$f" || { echo "CRLF: $f"; false; }
    [ -x "$f" ] || { echo "not executable: $f"; false; }
  done < <(entry_scripts)
}

@test "every library declares bash for shellcheck, has LF endings and is not executable" {
  while IFS= read -r f; do
    [ "$(head -1 "$f")" = "# shellcheck shell=bash" ] || { echo "no shell=bash: $f"; false; }
    ! grep -q $'\r' "$f" || { echo "CRLF: $f"; false; }
    [ ! -x "$f" ] || { echo "executable: $f"; false; }
  done < <(lib_scripts)
}

@test "shellcheck passes" {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
  run shellcheck -x -P SCRIPTDIR $(entry_scripts)
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # shellcheck reports nothing inside a sourced file: each library is checked on its own, without the
  # checks that need the whole script (a global set in one block and read in another).
  [ -n "$(lib_scripts)" ] || return 0
  run shellcheck -e SC2034,SC2153,SC2154 $(lib_scripts)
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}


# The plugin checks itself with its own skill: every rule of tools-check-bats (R1 silent assertions, GNU-only
# code, pipes, isolation...) on every test, helper and script of this repo.
@test "the plugin passes its own tools-check-bats" {
  run "$REPO_ROOT/skills/tools-check-bats/scripts/check-bats.sh" "$REPO_ROOT/scripts" "$REPO_ROOT/skills" "$REPO_ROOT/tests"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
