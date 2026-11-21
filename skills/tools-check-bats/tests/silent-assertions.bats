#!/usr/bin/env bats
# R1: silent_assertions (scripts/lib/silent-assertions.sh) flags every bats assertion that cannot fail
# the test in bash 3.2, and nothing else.

setup() {
  # shellcheck source=../scripts/lib/silent-assertions.sh
  . "$BATS_TEST_DIRNAME/../scripts/lib/silent-assertions.sh"
}

@test "the silent assertion check flags lines starting with [, [[, (( or ! that do not end in || false, and nothing else" {
  d="$(mktemp -d)"
  cat > "$d/x.bats" <<'EOF'
  [[ "$output" == *a* ]]
  ! grep -q a f
  ! grep -q a \
      f
  [ "$status" -eq 0 ] && [[ "$output" == *a* && "$output" == *b* ]]
  [[ "$output" == *a* ]] && [ "$status" -eq 0 ]
  [ -f x ] && [ -d y ]
  [ -f x ] && rm x
  [ -f x ] && [ -d y ] && rm x
  [[ "$output" == *a* ]]  # c
  (( x > 1 ))
  [ -n "$x" ] && (( x > 1 ))
  [[ "$output" == "a # b" ]]
  [ "$x" = 'a ] && [ b' ] && echo "] && ["
  [ "$status" -eq 0 ]
  [ "$x" = "a && b" ]
  [ "$x" = "a # b" ]  # c
  [[ "$output" == *a* ]] || false
  ! grep -q a f || false
  ! grep -q a f || { echo no; false; }
  ! grep -q a f || false  # c
  (( x > 1 )) || false
  ! grep -q a \
      f || false
  if [[ "$output" == *a* ]]; then :; fi
  if [ -f x ] && [ -d y ]; then :
  elif [ -f y ]; then :; fi
  while [[ -n "$x" ]]; do :; done
  until [ -f x ]; do :; done
  [ "$status" -eq 0 ] && [ -z "$output" ] || false
  [ "$status" -eq 4 ] && [[ "$output" == *a* ]] || { echo no; false; }
  [[ "$output" == *a* && "$output" == *b* ]] || false
  grep -q a f && grep -q b f
  [[ "$output" == a || "$output" == b ]]
  (( x > 1 || y > 1 ))
  ! [[ -n "$a" || -n "$b" ]]
  [ -n "$a" ] && [[ -n "$b" || -n "$c" ]]
  [ -n "$a" ] &&
    [ -n "$b" ]
  [[ "$output" == a || "$output" == b ]] || false
  [ -n "$a" ] &&
    [ -n "$b" ] || false
  if [[ -n "$a" ]] &&
     [[ -n "$b" ]]; then :; fi
  [[ "$output" == a ]] || [[ "$output" == b ]]
  ! grep -q a f || ! grep -q b f
  [[ -n "$a" ]] || false && [[ -n "$b" ]]
  [ "$status" -eq 0 ]; [[ "$output" == *a* ]]
  [ -n "$a" ] || [ -n "$b" ]
  [[ -n "$a" ]] || { echo no; false; }
  [ -n "$a" ] || [[ -n "$b" ]]
  [ -n "$a" ] || ! grep -q b f
  [ "$status" -eq 0 ] || echo "$output"
  [[ -n "$a" ]] || { echo no; }
  [[ -n "$a" ]] || { echo; }; [[ -n "$b" ]] || { echo no; false; }
  [[ -z "$output" ]] || {
    echo "$output"
  }
  [ -x /bin/bash ] || skip "no bash"
  [[ -n "$a" ]] || { echo no; return 1; }
  [[ -z "$output" ]] || {
    echo "$output"; false
  }
  [ -n "$a" ] || echo no || [ -n "$b" ]
  [[ -n "$a" ]] || { false; }
  ! grep -q a f || { exit 1; }
  [[ -n "$a" ]] || { echo ${#lines[@]}; false; }
  [[ -z "$output" ]] || {  # c
    echo "$output"; false  # d
  }
  [[ "$output" == *z* ]]
  [[ -n "$a" ]] || { echo no; return 0; }
  ! grep -q a f || { exit 0; }
  [ -f x ] || return
  [ -f x ] || continue
  [ -f x ] || exit 1
  [ "$status" -eq 0 ] || echo "$output" || false
  [[ -n "$a" ]] || echo no || { echo; false; }
  [[ -n "$a" ]] || [[ -n "$b" ]] || false
  run cmd  # x \
  [[ "$output" == *a* ]]
  cat > f <<'IN'
  [[ heredoc text, not an assertion ]]
  ! neither is this
IN
EOF
  run silent_assertions "$d/x.bats"
  rm -rf "$d"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "${lines[@]}" | cut -d: -f2 | tr '\n' ' ')" = "1 2 4 5 6 7 8 9 10 11 12 13 14 34 35 36 37 39 45 46 47 48 51 52 53 54 55 58 64 71 72 73 77 78 81 " ]
  [ "${lines[2]}" = "$d/x.bats:4:   ! grep -q a       f" ]
  [ "${lines[8]}" = "$d/x.bats:10:   [[ \"\$output\" == *a* ]]  # c" ]
}

@test "the silent assertion check handles column-0 comments, closed quoted heredocs and continuations across files" {
  d="$(mktemp -d)"
  printf '# cat <<EOF\n  [[ a ]]\n' > "$d/a.bats"
  printf '  cat <<"EOF"\n  [[ in ]]\nEOF\n  cat <<-'\''X'\''\n\t[[ in ]]\n\tX\n  [[ b ]]\n' > "$d/b.bats"
  printf '  ! grep -q a \\\n' > "$d/c.bats"
  printf '  [[ d ]]\n' > "$d/d.bats"
  run silent_assertions "$d/a.bats" "$d/b.bats" "$d/c.bats" "$d/d.bats"
  rm -rf "$d"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[0]}" = "$d/a.bats:2:   [[ a ]]" ]
  [ "${lines[1]}" = "$d/b.bats:7:   [[ b ]]" ]
  [ "${lines[2]}" = "$d/d.bats:1:   [[ d ]]" ]
}

@test "the silent assertion check skips no file after a heredoc look-alike and fails on an unterminated one" {
  d="$(mktemp -d)"
  printf '  # cat <<EOF\n  [[ a ]]\n' > "$d/a.bats"
  printf '  [[ b ]]\n' > "$d/b.bats"
  printf '  echo "<<EOF"\n  [[ c ]]\n  cat <<EOF\n' > "$d/c.bats"
  printf '  [[ d ]]\n' > "$d/d.bats"
  run silent_assertions "$d/a.bats" "$d/b.bats" "$d/c.bats" "$d/d.bats"
  rm -rf "$d"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 5 ]
  [ "${lines[0]}" = "$d/a.bats:2:   [[ a ]]" ]
  [ "${lines[1]}" = "$d/b.bats:1:   [[ b ]]" ]
  [ "${lines[2]}" = "$d/c.bats:2:   [[ c ]]" ]
  [ "${lines[3]}" = "$d/c.bats: unterminated heredoc EOF" ]
  [ "${lines[4]}" = "$d/d.bats:1:   [[ d ]]" ]
}

@test "the silent assertion check reports a || { block left open at the end of a file" {
  d="$(mktemp -d)"
  printf '  [[ a ]] || {\n    echo no; false\n' > "$d/a.bats"
  printf '  [[ b ]]\n' > "$d/b.bats"
  run silent_assertions "$d/a.bats" "$d/b.bats"
  rm -rf "$d"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "$d/a.bats: unterminated || { block" ]
  [ "${lines[1]}" = "$d/b.bats:1:   [[ b ]]" ]
}

@test "the silent assertion check reports a heredoc left open at the end of the last file" {
  d="$(mktemp -d)"
  printf '  cat <<'\''EOF'\''\n  [[ a ]]\n' > "$d/a.bats"
  run silent_assertions "$d/a.bats"
  rm -rf "$d"
  [ "$status" -eq 0 ]
  [ "$output" = "$d/a.bats: unterminated heredoc EOF" ]
}
