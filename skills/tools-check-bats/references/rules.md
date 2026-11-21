# check-bats rules

What each rule checks, why, and how a finding is fixed. `check-bats.sh` only reports; whoever fixes the
findings (a person or a coding agent) gets the `FINDING` lines and the matching section below.

R1 is exact. R4-R11 are heuristics on single lines: a finding is a line to look at, not a proven bug. A
false positive is silenced on its line with `# check-bats: ignore <rule>` and a reason the reader can follow.

| Rule | Checked on | How |
|---|---|---|
| R1 | `.bats`, `.bash` | exact parser of bats assertions |
| R2, R3 | `.bats` | `--run`: runs bats with bash 3.2 first in `PATH` |
| R4, R5, R6 | `.bats`, `.bash`, `.sh` | line patterns |
| R7, R8, R10, R11 | `.bats`, `.bash` | line patterns (R7's missing cleanup: per `.bats` file) |
| R9 | `.sh` | commands at command position outside `--allowed-commands` |

Comment lines and heredoc bodies (where tests keep their fixtures) are never checked by R4-R11. Each line is
read as the shell pairs its quotes: literal text is not code (single-quoted and `$'...'` text such as a grep
pattern or an awk program, and the literal parts of double-quoted text), while what runs is, inside double
quotes too: `$(...)`, backticks and `$var` / `${...}` expansions. Commands count at command position: first on
the line, after an operator, `$(` or a backtick, or after a keyword (`if`, `while`, `then`, `run`...). A `#`
that starts a word outside quotes starts a comment. R1 has its own parser; R5, and R7's `$HOME` and `/tmp/`,
R8's git remotes, R10's `$SECONDS` / `date +%s`, R4's bash 4 expansions (`${x,,}`, `${a[-1]}`) and R11's
`@test` names, and R7's cleanup on a `trap` line, read the raw line, trailing comment included.

Known limits of the heuristics (silence a false positive with `check-bats: ignore`):
- The text of `bash -c "..."` / `sh -c "..."` is read as literal text, so R4, R6, R8 and R10 do not look
  inside it (R7 still finds `$HOME` there).
- R6's `pipefail` is per file: a `set -o pipefail` anywhere in the file turns R6 on for all of it, and a
  `pipefail` set by a sourced library or a `load`ed helper, or turned on right after `(` or `$(` (a
  subshell), is not seen.
- A `#` that starts a word inside backticks or an unquoted `${...}` is taken for a comment and ends the line.
- R7 counts HOME as set only for a quoted or plain value: `HOME=$(mktemp -d)` unquoted, or an assignment
  right after `then` / `do`, is not seen; quote the value (`HOME="$(mktemp -d)"`) or put it on its own line.

## R1. Every assertion that is not the last line must be able to fail

- **Why**: in bash 3.2 (macOS `/bin/bash`) a failing `[[ ]]` or `(( ))` that is not the last command of a
  test does not trigger `set -e`; a bare `! cmd`, or checks joined with `&&`, never do in any bash. The
  test passes while the assertion fails.
- **Rule**: a line that starts with `[`, `[[`, `((` or `!` is an assertion and must end in `|| false` (or a
  `|| { ...; false; }` block; `return N` / `exit N` with N > 0 also count), with only checks joined by `||`
  before it, and no `;` outside quotes. Exception: a lone `[ ]` with no `&&` or `;` (`[` is a command and
  does trigger `set -e`). Control flow goes in `if`.
- **Fix**:
  ```bash
  [[ "$output" == *x* ]]                      [[ "$output" == *x* ]] || false
  ! grep -q x "$f"                            ! grep -q x "$f" || false
  [ "$status" -eq 4 ] && [ "$output" = x ]    [ "$status" -eq 4 ] && [ "$output" = x ] || false
  [[ "$output" == *x* ]] || echo "$output"    [[ "$output" == *x* ]] || { echo "$output"; false; }
  ```
- **Prove it now fails**: change the expected value of the assertion (`*x*` → `*NOPE*`), run the file with
  bash 3.2 and see `not ok`; undo. If adding `|| false` makes a test fail for real, the test was hiding a
  bug: fix the test or the code, never loosen the assertion.
- `line 0` findings are a heredoc or a `|| {` block still open at the end of the file.

## R2. Judge a run by its exit code, not its tail

- **Why**: `bats ... | tail -n N` hides an earlier `not ok`.
- **Check**: `--run` reports each `.bats` file that exits non-zero (`RUN_FAILED`), with its `not ok` count.
  By hand: `bats -r tests; echo "exit=$?"`.

## R3. Run with bash 3.2 and with Linux

- **Why**: `#!/usr/bin/env bash` takes Homebrew's bash when it exists and skips 3.2.
- **Check**: `--run` puts `/bin:/usr/bin` first in `PATH` (bash 3.2 on macOS). Linux is covered by CI on
  `ubuntu-latest`, or a container with bats.

## R4. No GNU-only flags or bash 4 in tests, helpers and scripts

- **Flags**: `readlink -f`, `sed -i`, `date -d`, `grep -P`, `stat -c`, `mapfile`, `readarray`,
  `declare -A` / `-n`, `${var,,}` / `${var^^}`, `${arr[-1]}`, `&>>`, `|&`.
- **Fix**: `sed 's/a/b/' f > f.tmp && mv f.tmp f`; `cd -P dir && pwd -P` instead of `readlink -f`;
  `sed -E` instead of `\|` in basic sed; `${arr[${#arr[@]}-1]}`; `tr '[:upper:]' '[:lower:]'`; a
  `while IFS= read -r` loop instead of `mapfile`. Also: no `case ... esac` inside `$(...)` (bash 3.2 does
  not parse it).

## R5. Portable awk (BSD on macOS, GNU on Linux, mawk)

- **Flags**: `gensub`, `asort`, `asorti`, `strftime`, `systime`, `PROCINFO`.
- **Also by hand**: a literal `&` in a `gsub` replacement is `"\\&"`; a regex with backslashes goes through
  the environment (`RE='\(' awk '$0 ~ ENVIRON["RE"]'`), not `-v`, which eats them.

## R6. `grep -q` and `head` at the end of a pipe under `pipefail`

- **Flags**: a pipe that ends in `grep -q` or `head`, in a file that turns `pipefail` on (`set -o pipefail`,
  `set -euo pipefail`). bats does not turn it on, so a test file is flagged only when it does it itself.

- **Why**: they stop reading; with more than 64 KB of output the writer dies of SIGPIPE and the condition
  comes out false. The small data of tests hides it.
- **Fix**: `out="$(cmd)"; grep -q x <<<"$out"`; `awk 'NR <= N'` instead of `head`. Test with large data too.
  A pipe whose input is known to be small (one `printf` of a variable) may be marked
  `# check-bats: ignore R6 small input`.

## R7. A world of its own per test

- **Flags**: a `.bats` file that calls `mktemp` (at command position, `"$(mktemp -d)"` included) with no
  `teardown` and no `rm -rf` in its code or in a `trap` string (any spelling: `-rf`, `-Rf`, `-fr`, `-r -f`);
  a line that uses `$HOME`, single quotes included (`bash -c '...'` runs it with the real HOME; an escaped
  `\$HOME` is text), in a file that never sets it: `export HOME=...`, or `HOME=...` / `local HOME=...` as a
  whole command (`HOME=x cmd` sets it for one command only; `env HOME=x cmd` on the line itself is fine);
  a fixed `/tmp/` path.
- **Fix**: `TMP="$(mktemp -d)"` in `setup`, `teardown() { rm -rf "$TMP"; }`, or `$BATS_TEST_TMPDIR` (bats
  removes it); point `HOME` at the temporary folder. No real network, no real remotes, no writes outside
  the temporary folder.
- macOS: `mktemp -d` returns `/var/folders/...`, a link to `/private/var/...`; when the code prints
  physical paths, compare with `cd -P`.

## R8. Network and external tools: a stub first in `PATH`

- **Flags**: `gh`, `curl` or `wget` at command position in a file that never writes `bin/<tool>` (a stub);
  `git clone|fetch|pull|push|ls-remote` against `https://` or `git@`.
- **Fix**: a stub in `$TMP/bin`, put first in `PATH`, that logs each call and fails with its own code on an
  unexpected one (`*) echo "gh stub: unexpected call: $*" >&2; exit 99`); environment variables of the
  stub for the error paths (`GH_FAIL=1 run ...`). Remotes are local bare repos (`git init --bare`).

## R9. Scripts that must run in a minimal runtime

- **When**: the scripts run where only some commands exist (a slim container image, a CI runner): pass the
  list with `--allowed-commands "bash awk jq ..."`, taken from the repo's own docs. Without it R9 is skipped
  (`NOTE` line).
- **Flags**: a watched external command (`awk basename cat cut date dirname find grep head jq mktemp
  readlink sed sort tail tee tr uniq wc xargs`...) at command position in a `.sh` file, not in the list.
  Literal text (awk or jq programs in single quotes, messages in double quotes) is not checked; `$(...)` and
  backticks are. Shell builtins are never reported.
- **Why**: with `set -e` a missing command breaks the script; inside an `if` it silently takes the other
  branch.
- **Fix**: a builtin instead (`${f##*/}` for `basename`, `${f%/*}` for `dirname`, `while read` for `wc -l`,
  `${s//a/b}` for `tr`/`sed` on one value), or add the command to the runtime. Guard it with a test that
  runs the script with `PATH` set to a folder of links to only the allowed commands and asserts
  `[[ "$output" != *"command not found"* ]] || { echo "$output"; false; }`; each new code path of the script
  goes into that test.

## R10. No timing dependencies

- **Flags**: `sleep <n>`, `timeout`, `$SECONDS`, `date +%s` in tests.
- **Why**: a test that expects something to finish "within 1 s", or sleeps a fixed time and then asserts,
  fails at random on a slow CI runner.
- **Fix**: poll a condition with a limit instead of a fixed sleep
  (`for _ in $(seq 50); do [ -f "$done" ] && break; sleep 0.1; done; [ -f "$done" ]`); expose a threshold
  of the code as a variable and raise it in the test. A poll loop like that is fine: mark its `sleep` with
  `# check-bats: ignore R10 polled`.

## R11. Style and structure

- **Flags**: `skip` with no reason; a test name that starts with a capital letter followed by lowercase.
- **Rules**: a test name is a lowercase sentence with the behavior (`@test "remove skips DIRTY without
  --force"`; identifiers like `NO_AUTH` are fine); `skip` always with a reason, and only for a missing
  tool (`command -v git >/dev/null || skip "git not installed"`); diagnostics as
  `[ "$status" -eq 0 ] || { echo "$output"; false; }`, never a bare `|| echo ...` (R1); cover error paths
  and unsafe input, not only the happy path; explicit locale when counting bytes or sorting
  (`LC_ALL=C wc -c`, `LC_ALL=C sort`).
