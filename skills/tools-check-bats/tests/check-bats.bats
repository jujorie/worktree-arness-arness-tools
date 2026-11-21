#!/usr/bin/env bats
# check-bats.sh: options, file discovery, one case per rule, ignore markers and --run.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/check-bats.sh"
  W="$BATS_TEST_TMPDIR/w"
  mkdir -p "$W"
}

# fixture <var> <name>: writes stdin to $W/<name> and sets <var> to its path.
fixture() {
  cat > "$W/$2"
  printf -v "$1" '%s' "$W/$2"
}

@test "usage errors exit 2" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  run "$SCRIPT" --rules R3 "$W"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown rule: R3"* ]] || false
  run "$SCRIPT" --bogus "$W"
  [ "$status" -eq 2 ]
  run "$SCRIPT" --allowed-commands " " "$W"
  [ "$status" -eq 2 ]
  run "$SCRIPT" "$W/missing"
  [ "$status" -eq 2 ]
  touch "$W/notes.txt"
  run "$SCRIPT" "$W/notes.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a .bats, .bash or .sh file"* ]] || false
}

@test "a folder with no test or script gives NO_FILES" {
  touch "$W/notes.txt"
  run "$SCRIPT" "$W"
  [ "$status" -eq 3 ]
  [ "$output" = NO_FILES ]
}

@test "a clean file gives CLEAN with the file count" {
  fixture f ok.bats <<'EOF'
@test "passes" {
  run true
  [ "$status" -eq 0 ]
  [[ "$output" == "" ]] || false
}
EOF
  run "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "CLEAN files=1" ]
}

@test "R1 flags a silent assertion and an unterminated heredoc, as file:line" {
  fixture f r1.bats <<'EOF'
@test "x" {
  [[ "$output" == *a* ]]
  [ "$status" -eq 0 ]
  cat <<IN
EOF
  run "$SCRIPT" --rules R1 "$f"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "FINDING R1 $f:2 [[ \"\$output\" == *a* ]]" ]
  [ "${lines[1]}" = "FINDING R1 $f:0 unterminated heredoc IN" ]
  [ "${lines[2]}" = "FINDINGS 2 files=1" ]
}

@test "R4 flags GNU-only flags and bash 4 expansions in tests and scripts, not a pattern in quotes" {
  fixture f r4.bats <<'EOF'
  sed -i 's/a/b/' f
  echo "${name,,}"
  echo "${arr[-1]}"
  run grep -nE 'readlink -f|sed -i' x
  [ "$a" ] || [ "$b" ] && echo ok
EOF
  fixture s r4.sh <<'EOF'
dir="$(readlink -f "$0")"
cmd |& tee log
EOF
  run "$SCRIPT" --rules R4 "$f" "$s"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -d' ' -f3 | tr '\n' ' ')" = "$f:1 $f:2 $f:3 $s:1 $s:2 files=2 " ]
}

@test "R5 flags gawk extensions" {
  fixture f r5.sh <<'EOF'
awk '{ print gensub(/a/, "b", "g") }' f
awk '{ print toupper($0) }' f
EOF
  run "$SCRIPT" --rules R5 "$f"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "FINDING R5 $f:1 awk '{ print gensub(/a/, \"b\", \"g\") }' f" ]  # check-bats: ignore R5
  [ "${#lines[@]}" -eq 2 ]
}

@test "R6 flags grep -q and head at the end of a pipe, not after ||" {
  fixture f r6.bats <<'EOF'
  cmd | grep -q x
  cmd | grep -Fxq -- x
  cmd | head -1
  cmd || grep -q x f
  out="$(cmd)"; grep -q x <<<"$out"
EOF
  run "$SCRIPT" --rules R6 "$f"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -d' ' -f3 | tr '\n' ' ')" = "$f:1 $f:2 $f:3 files=1 " ]
}

@test "R7 flags mktemp with no cleanup, writes to HOME and a fixed /tmp path" {
  fixture f r7.bats <<'EOF'
@test "x" {
  d="$(mktemp -d)"
  echo x > "$HOME/.x"
  run env HOME="$d" cmd
  echo x > /tmp/fixed
  echo x > "$TMP/fine"
}
EOF
  run "$SCRIPT" --rules R7 "$f"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -d' ' -f3 | tr '\n' ' ')" = "$f:2 $f:3 $f:5 files=1 " ]
  [[ "${lines[0]}" == *"(mktemp with no teardown or rm -rf)" ]] || false
  fixture g r7ok.bats <<'EOF'
setup() { TMP="$(mktemp -d)"; }
teardown() { rm -rf "$TMP"; }
EOF
  run "$SCRIPT" --rules R7 "$g"
  [ "$status" -eq 0 ]
}

@test "R8 flags network tools with no stub and real remotes" {
  fixture f r8.bats <<'EOF'
  run gh pr view 1
  curl -s https://example.com
  git clone https://example.com/r.git
  git clone "$TMP/remote.git" c
EOF
  run "$SCRIPT" --rules R8 "$f"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -d' ' -f3 | tr '\n' ' ')" = "$f:1 $f:2 $f:3 files=1 " ]
  fixture g r8ok.bats <<'EOF'
  printf '#!/bin/sh\n' > "$TMP/bin/gh"
  run gh pr view 1
EOF
  run "$SCRIPT" --rules R8 "$g"
  [ "$status" -eq 0 ]
}

@test "R9 is skipped without --allowed-commands and flags the commands outside the list" {
  fixture f r9.sh <<'EOF'
n="$(printf '%s\n' "$x" | wc -l)"
v="$(jq -r .a f)"
awk '{ print "sed in a program" }' f
echo "find me"
cd "$d" && printf '%s\n' ok
EOF
  run "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "NOTE R9 skipped: no --allowed-commands" ]
  run "$SCRIPT" --allowed-commands "awk,jq" "$f"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "FINDING R9 $f:1 n=\"\$(printf '%s\n' \"\$x\" | wc -l)\" (uses wc)" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "R10 flags fixed sleeps, timeouts and elapsed-time checks" {
  fixture f r10.bats <<'EOF'
  sleep 1
  timeout 5 cmd
  start="$(date +%s)"
  [ "$SECONDS" -lt 3 ]
  echo "no sleep here"
EOF
  run "$SCRIPT" --rules R10 "$f"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -d' ' -f3 | tr '\n' ' ')" = "$f:1 $f:2 $f:3 $f:4 files=1 " ]
}

@test "R11 flags skip with no reason and test names that start with a capital" {
  # bats rewrites every @test line of a test file, heredocs included: the fixture is written with printf.
  f="$W/r11.bats"
  printf '%s\n' '@test "Checks it" {' '  command -v git >/dev/null || skip' \
    '  command -v git >/dev/null || skip "git not installed"' '}' \
    '@test "NO_AUTH when gh is logged out" {' '  true' '}' > "$f"
  run "$SCRIPT" --rules R11 "$f"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -d' ' -f3 | tr '\n' ' ')" = "$f:1 $f:2 files=1 " ]
}

@test "comments and heredoc bodies are not checked by the pattern rules" {
  fixture f body.bats <<'EOF'
  # sleep 5 | head -1
  cat > "$TMP/f" <<'IN'
  sed -i x f
  sleep 5
IN
  cat <<-OUT
	cmd | grep -q x
	OUT
EOF
  run "$SCRIPT" "$f"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "check-bats: ignore skips a line for every rule or only for the rules listed" {
  fixture f ign.bats <<'EOF'
  sleep 1 | head -1  # check-bats: ignore
  sleep 1 | head -1  # check-bats: ignore R10
EOF
  run "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "FINDING R6 $f:2 sleep 1 | head -1  # check-bats: ignore R10" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "--rules keeps only the rules given" {
  fixture f rules.bats <<'EOF'
  sleep 1 | head -1
EOF
  run "$SCRIPT" --rules R6 "$f"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "FINDING R6 $f:1 sleep 1 | head -1" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "a folder is searched for .bats, .bash and .sh files, sorted, skipping .git and node_modules" {
  mkdir -p "$W/b" "$W/.git" "$W/node_modules/m"
  printf '  sleep 1\n' > "$W/b/z.bats"
  printf '  sleep 1\n' > "$W/a.bash"
  printf 'echo ok\n' > "$W/b/run.sh"
  printf '  sleep 1\n' > "$W/.git/x.bats"
  printf '  sleep 1\n' > "$W/node_modules/m/y.bats"
  run "$SCRIPT" --rules R10 "$W"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -d' ' -f3 | tr '\n' ' ')" = "$W/a.bash:1 $W/b/z.bats:1 files=3 " ]
}

@test "--run reports a bats file that fails and passes one that does not" {
  command -v bats >/dev/null || skip "bats not installed"
  printf '@test "a" {\n  false\n}\n@test "b" {\n  true\n}\n' > "$W/bad.bats"
  printf '@test "a" {\n  true\n}\n' > "$W/good.bats"
  run "$SCRIPT" --run --rules R1 "$W/bad.bats" "$W/good.bats"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "RUN_FAILED $W/bad.bats exit=1 not_ok=1" ]
  [ "${lines[1]}" = "FINDINGS 1 files=2" ]
}

@test "--run without bats gives MISSING_TOOL" {
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  for c in bash awk sed find sort tr dirname cat grep mktemp rm; do ln -s "$(command -v "$c")" "$bin/$c"; done
  printf '@test "a" {\n  true\n}\n' > "$W/good.bats"
  PATH="$bin" run "$bin/bash" "$SCRIPT" --run "$W/good.bats"
  [ "$status" -eq 4 ]
  [ "$output" = "MISSING_TOOL bats" ]
}
