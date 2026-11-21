#!/usr/bin/env bash
# Check bats test files (and the scripts they test) against the rules of references/rules.md. Only reports:
# it never changes a file.
#
# check-bats.sh [--rules R1,R4,...] [--allowed-commands "<cmd> ..."] [--run] <path>...
#   <path>                a directory (searched for *.bats, *.bash and *.sh, skipping .git and node_modules)
#                         or a file with one of those extensions
#   --rules               only these rules (default: all of R1 R4 R5 R6 R7 R8 R9 R10 R11)
#   --allowed-commands    commands the scripts may run (R9, for a minimal runtime); without it R9 is skipped
#   --run                 also run each bats file with bats, /bin and /usr/bin first in PATH (bash 3.2 on
#                         macOS), and judge it by its exit code (R2, R3)
#
# Stdout, one line each:
#   FINDING <rule> <file>:<line> <text>     a rule broken (line 0: the whole file)
#   RUN_FAILED <file> exit=<n> not_ok=<n>    --run: the file failed under bats
#   NOTE R9 skipped: no --allowed-commands
#   CLEAN files=<n>                         last line, exit 0
#   FINDINGS <n> files=<n>                  last line, exit 1
#   NO_FILES                                no file to check, exit 3
#   MISSING_TOOL <tool>                     exit 4
# Usage errors: message on stderr, exit 2.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/silent-assertions.sh
. "$HERE/lib/silent-assertions.sh"
# shellcheck source=lib/patterns.sh
. "$HERE/lib/patterns.sh"

ALL_RULES="R1 R4 R5 R6 R7 R8 R9 R10 R11"

usage() {
  echo "usage: check-bats.sh [--rules R1,R4,...] [--allowed-commands \"<cmd> ...\"] [--run] <path>..." >&2
  exit 2
}

rules="$ALL_RULES"
allowed=""
run_bats=0
paths=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --rules)
      [ "$#" -ge 2 ] || usage
      rules="$(printf '%s' "$2" | tr ',' ' ')"
      for r in $rules; do
        case " $ALL_RULES " in *" $r "*) ;; *) echo "unknown rule: $r (known: $ALL_RULES)" >&2; exit 2 ;; esac
      done
      shift 2 ;;
    --allowed-commands)
      [ "$#" -ge 2 ] || usage
      allowed="$(printf '%s' "$2" | tr ',' ' ')"
      [ -n "${allowed// /}" ] || { echo "--allowed-commands needs at least one command" >&2; exit 2; }
      shift 2 ;;
    --run) run_bats=1; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do paths+=("$1"); shift; done ;;
    -*) echo "unknown option: $1" >&2; usage ;;
    *) paths+=("$1"); shift ;;
  esac
done
[ "${#paths[@]}" -gt 0 ] || usage

wanted() { case " $rules " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

tests=()
scripts=()
add_file() {
  case "$1" in
    *.bats|*.bash) tests+=("$1") ;;
    *.sh) scripts+=("$1") ;;
    *) return 1 ;;
  esac
}
for p in "${paths[@]}"; do
  if [ -d "$p" ]; then
    list="$(find "$p" \( -name .git -o -name node_modules \) -prune -o -type f \
      \( -name '*.bats' -o -name '*.bash' -o -name '*.sh' \) -print | LC_ALL=C sort)"
    while IFS= read -r f; do
      [ -z "$f" ] || add_file "$f"
    done <<< "$list"
  elif [ -f "$p" ]; then
    add_file "$p" || { echo "not a .bats, .bash or .sh file: $p" >&2; exit 2; }
  else
    echo "no such file or directory: $p" >&2
    exit 2
  fi
done

nfiles=$(( ${#tests[@]} + ${#scripts[@]} ))
[ "$nfiles" -gt 0 ] || { echo NO_FILES; exit 3; }
if [ "$run_bats" -eq 1 ]; then
  command -v bats >/dev/null 2>&1 || { echo "MISSING_TOOL bats"; exit 4; }
fi

found=0
emit() {
  # Reads "<rule> <file>:<line> <text>" lines and prints those of the wanted rules as FINDING lines.
  local rule rest
  while IFS=' ' read -r rule rest; do
    [ -n "$rule" ] || continue
    wanted "$rule" || continue
    printf 'FINDING %s %s\n' "$rule" "$rest"
    found=$((found + 1))
  done
}

if [ "${#tests[@]}" -gt 0 ]; then
  if wanted R1; then
    r1="$(silent_assertions "${tests[@]}" | sed -E \
      -e 's/^(.*): (unterminated .*)$/R1 \1:0 \2/' \
      -e 's/^(.*):([0-9]+):[ ]*(.*)$/R1 \1:\2 \3/')"
    emit <<< "$r1"
  fi
  emit <<< "$(pattern_findings test "" "${tests[@]}")"
fi
if [ "${#scripts[@]}" -gt 0 ]; then
  emit <<< "$(pattern_findings script "$allowed" "${scripts[@]}")"
fi
if wanted R9 && [ -z "$allowed" ] && [ "${#scripts[@]}" -gt 0 ]; then
  echo "NOTE R9 skipped: no --allowed-commands"
fi

if [ "$run_bats" -eq 1 ] && [ "${#tests[@]}" -gt 0 ]; then
  log="$(mktemp)"
  trap 'rm -f "$log"' EXIT
  for f in "${tests[@]}"; do
    case "$f" in *.bats) ;; *) continue ;; esac
    code=0
    PATH="/bin:/usr/bin:$PATH" bats "$f" > "$log" 2>&1 || code=$?
    if [ "$code" -ne 0 ]; then
      bad="$(grep -c '^not ok' "$log" || true)"
      printf 'RUN_FAILED %s exit=%s not_ok=%s\n' "$f" "$code" "$bad"
      found=$((found + 1))
    fi
  done
fi

if [ "$found" -eq 0 ]; then
  echo "CLEAN files=$nfiles"
  exit 0
fi
echo "FINDINGS $found files=$nfiles"
exit 1
