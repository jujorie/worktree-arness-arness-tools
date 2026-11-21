# tools-check-bats

Checks the bats test files of a repo (and the shell scripts they test) against the rules in
`references/rules.md`, and optionally runs them under bash 3.2. It only reports. Procedure in `SKILL.md`.

```
check-bats.sh [--rules R1,R4,...] [--allowed-commands "<cmd> ..."] [--run] <path>...
  R1        silent assertions (exact)
  R4-R11    line heuristics: GNU-only/bash 4, gawk, SIGPIPE pipes, isolation, network, minimal
            runtime (R9, needs --allowed-commands), timing, style
  --run     R2/R3: bats with /bin and /usr/bin first in PATH, judged by exit code
→ FINDING <rule> <file>:<line> <text> ... then CLEAN files=<n> (0) | FINDINGS <n> files=<n> (1)
  | CHECK_FAILED <why> [<path>] (5): a file not read or a check broken, never reported clean
```

A false positive is silenced on its line: `# check-bats: ignore R6 small input`.

## Files

| Path | What |
|---|---|
| `SKILL.md` | The procedure the agent follows |
| `scripts/check-bats.sh` | Options, file discovery, `--run` and the report |
| `scripts/lib/silent-assertions.sh` | R1: the exact parser of bats assertions |
| `scripts/lib/patterns.sh` | R4-R11: one awk pass per file list |
| `references/rules.md` | Each rule: why, what is flagged, how to fix it |
| `tests/` | bats tests: `bats skills/tools-check-bats/tests/` |

Requires bash, awk, dirname, find, grep, mktemp, rm, sort and tr; `bats` for `--run`.
