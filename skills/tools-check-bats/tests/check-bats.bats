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
  set -o pipefail
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
  set -o pipefail
EOF
  run "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "FINDING R6 $f:2 sleep 1 | head -1  # check-bats: ignore R10" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "--rules keeps only the rules given" {
  fixture f rules.bats <<'EOF'
  sleep 1 | head -1
  set -o pipefail
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

# Review of PR #1, PRRT_kwDOV2aggM66UX3N: an empty rule list checks nothing and must not give CLEAN.
@test "an empty --rules list is a usage error" {
  run "$SCRIPT" --rules "" "$W"
  [ "$status" -eq 2 ]
  run "$SCRIPT" --rules , "$W"
  [ "$status" -eq 2 ]
}

# PRRT_kwDOV2aggM66UX28: arness links plugin skills into skills/, so a path given as a link must be read.
@test "a folder given through a symbolic link is searched" {
  mkdir -p "$W/b"
  printf '  sleep 1\n' > "$W/b/z.bats"
  ln -s "$W/b" "$W/link"
  run "$SCRIPT" --rules R10 "$W/link"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "FINDING R10 $W/link/z.bats:1 sleep 1" ]
}

# PRRT_kwDOV2aggM66UX29: a file that cannot be read must never end in CLEAN.
@test "a file that cannot be read gives CHECK_FAILED, never CLEAN" {
  [ "$(id -u)" -ne 0 ] || skip "root reads any file"
  printf 'echo ok\n' > "$W/a.sh"
  printf '  true\n' > "$W/a.bats"
  chmod 000 "$W/a.sh" "$W/a.bats"
  run "$SCRIPT" "$W/a.sh"
  chmod 644 "$W/a.sh" "$W/a.bats"
  [ "$status" -eq 5 ]
  [ "$output" = "CHECK_FAILED unreadable $W/a.sh" ]
  chmod 000 "$W/a.bats"
  run "$SCRIPT" --rules R10 "$W"
  chmod 644 "$W/a.bats"
  [ "$status" -eq 5 ]
  [ "$output" = "CHECK_FAILED unreadable $W/a.bats" ]
}

# PRRT_kwDOV2aggM66UX2_: the text of an R1 finding may itself hold file:line: pairs.
@test "R1 keeps file:line and the text when the text holds file:line:" {
  fixture f r1c.bats <<'EOF'
  run lint
  [[ "$output" == *"a.sh:3: x"* ]]
  [[ "$output" == *": unterminated x"* ]]
EOF
  run "$SCRIPT" --rules R1 "$f"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "FINDING R1 $f:2 [[ \"\$output\" == *\"a.sh:3: x\"* ]]" ]
  [ "${lines[1]}" = "FINDING R1 $f:3 [[ \"\$output\" == *\": unterminated x\"* ]]" ]
}

# PRRT_kwDOV2aggM66UX3B: a command inside "$(...)" is still a command for R6, R8 and R10.
@test "R6, R8 and R10 see commands inside double-quoted command substitutions" {
  fixture f subst.bats <<'EOF'
  first="$(printf '%s\n' "$out" | head -1)"
  body="$(curl -s https://example.com)"
  x="$(timeout 5 cmd)"
  [ "$output" = "FINDING R6 x: sleep 1 | head -1" ]
  set -o pipefail
EOF
  run "$SCRIPT" --rules R6,R8,R10 "$f"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -d' ' -f2,3 | tr '\n' ' ')" = "R6 $f:1 R8 $f:2 R10 $f:3 3 files=1 " ]
}

# PRRT_kwDOV2aggM66UX3E: a command right after if, elif, while or until is at command position.
@test "commands after if, elif, while and until are at command position" {
  fixture s kw.sh <<'EOF'
if grep -q x "$f"; then :; fi
while sort f; do :; done
EOF
  run "$SCRIPT" --rules R9 --allowed-commands awk "$s"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -d' ' -f3 | tr '\n' ' ')" = "$s:1 $s:2 files=1 " ]
  fixture f kw.bats <<'EOF'
  if gh auth status; then :; fi
  until timeout 5 cmd; do :; done
EOF
  run "$SCRIPT" --rules R8,R10 "$f"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -d' ' -f2,3 | tr '\n' ' ')" = "R8 $f:1 R10 $f:2 2 files=1 " ]
}

# PRRT_kwDOV2aggM66UX3I: R7 reads only code lines, and any spelling of rm -rf is a cleanup.
@test "R7 ignores mktemp and rm -rf in comments and heredocs, and accepts rm -Rf and rm -r -f" {
  fixture f fix.bats <<'EOF'
  # d="$(mktemp -d)"
  cat > "$BATS_TEST_TMPDIR/s.sh" <<'IN'
d="$(mktemp -d)"
IN
EOF
  run "$SCRIPT" --rules R7 "$f"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  fixture g hid.bats <<'EOF'
  d="$(mktemp -d)"
  cat > "$d/s.sh" <<'IN'
rm -rf "$x"
IN
EOF
  run "$SCRIPT" --rules R7 "$g"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "FINDING R7 $g:1 d=\"\$(mktemp -d)\" (mktemp with no teardown or rm -rf)" ]
  for rm in 'rm -Rf' 'rm -r -f' 'rm -fR'; do
    printf '  d="$(mktemp -d)"\n  %s "$d"\n' "$rm" > "$W/rm.bats"
    run "$SCRIPT" --rules R7 "$W/rm.bats"
    [ "$status" -eq 0 ] || { echo "$rm: $output"; false; }
  done
}

# PRRT_kwDOV2aggM66UX3L: pointing HOME at the temporary folder is the documented fix of R7.
@test "R7 does not flag HOME in a file that sets HOME" {
  fixture f home.bats <<'EOF'
setup() { export HOME="$BATS_TEST_TMPDIR"; }
  [ -f "$HOME/.cfg" ] || false
EOF
  run "$SCRIPT" --rules R7 "$f"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "findings of a file come in line order, the file-level R7 included" {
  fixture f order.bats <<'EOF'
  sleep 1
  d="$(mktemp -d)"
EOF
  run "$SCRIPT" --rules R7,R10 "$f"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -d' ' -f2,3 | tr '\n' ' ')" = "R10 $f:1 R7 $f:2 2 files=1 " ]
}

# Local review of 751a238: quotes are paired by a scanner, so a command between two quoted strings is seen,
# literal text is never taken for code, and "$(...)" stays code.
@test "commands between quoted strings are seen and literal text is not code" {
  fixture f quotes.bats <<'EOF'
  body="$(cat f)"; curl -s "$url"
  v="$(a)"; sleep 5 && echo "$y"
  printf "don't\n" | head -1; grep 'x' f
  a="$(x)" b="sed -i"
  echo "cost $" | head -1
  x="$(printf '%s' "$(timeout 5 cmd)")"
  echo "a \" | head -1 \""
  set -o pipefail
EOF
  run "$SCRIPT" --rules R4,R6,R8,R10 "$f"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -d' ' -f2,3 | tr '\n' ' ')" = "R8 $f:1 R10 $f:2 R6 $f:3 R6 $f:5 R10 $f:6 5 files=1 " ]
  fixture s quotes.sh <<'EOF'
x="$(a)" && sort "$f"
EOF
  run "$SCRIPT" --rules R9 --allowed-commands awk "$s"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "FINDING R9 $s:1 x=\"\$(a)\" && sort \"\$f\" (uses sort)" ]
}

@test "HOME set for one command does not count as setting it for the file" {
  fixture f home1.bats <<'EOF'
  HOME="$T" run git config --global x y
  cat "$HOME/.gitconfig"
EOF
  run "$SCRIPT" --rules R7 "$f"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "FINDING R7 $f:2 cat \"\$HOME/.gitconfig\"" ]
  fixture g home2.bats <<'EOF'
  HOME="$BATS_TEST_TMPDIR"
  cat "$HOME/.gitconfig"
EOF
  run "$SCRIPT" --rules R7 "$g"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a subfolder find cannot read gives CHECK_FAILED find" {
  [ "$(id -u)" -ne 0 ] || skip "root reads any folder"
  mkdir -p "$W/d"
  printf '  true\n' > "$W/ok.bats"
  chmod 000 "$W/d"
  run "$SCRIPT" --rules R10 "$W"
  chmod 755 "$W/d"
  [ "$status" -eq 5 ]
  # find's own error goes to stderr, which run mixes in: the status line is the last one.
  [ "${lines[${#lines[@]}-1]}" = "CHECK_FAILED find $W" ]
}

@test "a check that breaks gives CHECK_FAILED, never CLEAN" {
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  for c in bash sed find sort tr dirname cat grep mktemp rm; do ln -s "$(command -v "$c")" "$bin/$c"; done
  printf '#!/bin/sh\nexit 2\n' > "$bin/awk"
  chmod +x "$bin/awk"
  printf '  true\n' > "$W/ok.bats"
  PATH="$bin" run "$bin/bash" "$SCRIPT" --rules R1 "$W/ok.bats"
  [ "$status" -eq 5 ]
  [ "$output" = "CHECK_FAILED R1 $W/ok.bats" ]
  PATH="$bin" run "$bin/bash" "$SCRIPT" --rules R10 "$W/ok.bats"
  [ "$status" -eq 5 ]
  [ "$output" = "CHECK_FAILED patterns" ]
}

# Local review of cd4259f: backticks and $'...' are paired as the shell does.
@test "backticks and ANSI-C quotes are paired as the shell does" {
  fixture f tick.bats <<'EOF'
  x="`sed -i s/a/b/ f`"
  out=`timeout 5 cmd`
  echo $'don\'t'; cmd | head -1
  echo "a ` b"
  set -o pipefail
EOF
  run "$SCRIPT" --rules R4,R6,R10 "$f"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -d' ' -f2,3 | tr '\n' ' ')" = "R4 $f:1 R10 $f:2 R6 $f:3 3 files=1 " ]
  fixture s tick.sh <<'EOF'
n="`sort f`"
EOF
  run "$SCRIPT" --rules R9 --allowed-commands awk "$s"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "FINDING R9 $s:1 n=\"\`sort f\`\" (uses sort)" ]
}

@test "HOME counts as set only when the whole command is the assignment, whatever its value" {
  fixture f h1.bats <<'EOF'
  HOME="${T}" run git config --global x y
  cat "$HOME/.gitconfig"
EOF
  run "$SCRIPT" --rules R7 "$f"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "FINDING R7 $f:2 cat \"\$HOME/.gitconfig\"" ]
  for set in 'HOME="$(mktemp -d)"; trap "rm -rf $HOME" EXIT' 'export HOME="$T"' 'local HOME="$T"' '[ -n "$T" ] && HOME="$T"'; do  # check-bats: ignore R7 fixture text
    printf '  %s\n  cat "$HOME/.gitconfig"\n' "$set" > "$W/h2.bats"  # check-bats: ignore R7 fixture text
    run "$SCRIPT" --rules R7 "$W/h2.bats"
    [ "$status" -eq 0 ] || { echo "$set: $output"; false; }
  done
}

@test "HOME inside single quotes counts, an escaped \$HOME does not" {
  fixture f h3.bats <<'EOF'
  run bash -c 'cat "$HOME/.cfg"'
  echo "\$HOME is not used"
EOF
  run "$SCRIPT" --rules R7 "$f"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -d' ' -f3 | tr '\n' ' ')" = "$f:1 files=1 " ]
}

@test "R7 reads mktemp and rm -rf in code, not in literal text" {
  fixture f lit.bats <<'EOF'
  command -v mktemp >/dev/null || skip "needs mktemp"
EOF
  run "$SCRIPT" --rules R7 "$f"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  fixture g lit2.bats <<'EOF'
  d="$(mktemp -d)"
  echo "no rm -rf here"
EOF
  run "$SCRIPT" --rules R7 "$g"
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "FINDING R7 $g:1 "* ]] || false
}

# PR #1 review of 21a5cfa, PRRT_kwDOV2aggM66UkVS: bats does not turn pipefail on, so a pipe ending in grep -q
# only fails on SIGPIPE in a file that does.
@test "R6 flags a pipe only in a file that turns pipefail on" {
  fixture f nopf.bats <<'EOF'
  echo "$output" | grep -q x
EOF
  run "$SCRIPT" --rules R6 "$f"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  fixture g pf.sh <<'EOF'
set -euo pipefail
cmd | head -1
EOF
  run "$SCRIPT" --rules R6 "$g"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "FINDING R6 $g:2 cmd | head -1" ]
}

# PRRT_kwDOV2aggM66UkVW: a trailing comment is not code.
@test "a trailing comment is not code, a # inside a word or an expansion is" {
  fixture f cmt.bats <<'EOF'
  sed 's/a/b/' f > f.tmp && mv f.tmp f  # not sed -i (BSD)
  run cmd  # avoid sleep 5 here
  n=${#arr[@]}; sleep 1
  x=a#b; timeout 5 cmd
EOF
  run "$SCRIPT" --rules R4,R10 "$f"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -d' ' -f2,3 | tr '\n' ' ')" = "R10 $f:3 R10 $f:4 2 files=1 " ]
}

# PRRT_kwDOV2aggM66UkVT: a temporary file --run cannot create is a broken check, not a finding.
@test "--run gives CHECK_FAILED mktemp when it cannot create its log" {
  command -v bats >/dev/null || skip "bats not installed"
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  for c in bash awk find sort tr dirname cat grep rm bats; do ln -s "$(command -v "$c")" "$bin/$c"; done
  printf '#!/bin/sh\nexit 1\n' > "$bin/mktemp"
  chmod +x "$bin/mktemp"
  printf '@test "a" {\n  true\n}\n' > "$W/good.bats"
  PATH="$bin" run "$bin/bash" "$SCRIPT" --run --rules R1 "$W/good.bats"
  [ "$status" -eq 5 ]
  [ "${lines[${#lines[@]}-1]}" = "CHECK_FAILED mktemp" ]
}
