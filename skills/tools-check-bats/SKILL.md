---
name: tools-check-bats
description: >-
  Check the bats test files of a repo or worktree (and the shell scripts they test) for silent
  assertions, GNU-only or bash 4 code, unportable awk, SIGPIPE-prone pipes, tests that leak outside
  their temporary folder or reach the network, commands missing from a minimal runtime, timing
  dependencies and style, and optionally run them under bash 3.2. Only reports findings, never
  edits. Use when asked to check, verify, audit or review bats tests, e.g. "revisa los bats de X",
  "verifica los tests bats del worktree", "¿hay aserciones silenciosas?", "check the bats files".
  Fails with NO_FILES, MISSING_TOOL or CHECK_FAILED.
allowed-tools: Bash(skills/tools-check-bats/scripts/check-bats.sh *)
---

# tools-check-bats

> Use this skill; do not grep the tests by hand or edit them. The procedure below decides what to run and what to report.

Checks `*.bats`, `*.bash` (test helpers) and `*.sh` files against the rules in `references/rules.md`
(R1-R11) with `scripts/check-bats.sh` (in this skill's folder). It **only reports**: fixing is for whoever
gets the report (the user, or a coding agent given the findings and the rule sections).

## Procedure

1. From the user's message, get:
   - **paths**: folders or files to check, relative to the current folder (e.g. a repo or worktree, or its
     `tests/`). A folder is searched for `*.bats`, `*.bash` and `*.sh`, skipping `.git` and `node_modules`;
     a folder given as a link (a plugin skill linked into `skills/`) is searched too.
     If none is given and it is not clear which repo, ask.
   - **allowed commands** (R9), only when the scripts must run in a minimal runtime (a slim image, a
     restricted runner) and the repo's docs list its commands: pass that list. Never invent it; without
     it R9 is skipped.
   - **run**: add `--run` when the user wants the tests run too, or asks whether they pass.
   - **rules**: `--rules R1,R6` only if the user asks for some rules.
2. Run it. With `--run`, use the Bash tool's `run_in_background` (a suite can take minutes):
   ```bash
   skills/tools-check-bats/scripts/check-bats.sh [--rules <list>] [--allowed-commands "<cmd> ..."] [--run] <path>...
   ```
3. Read each line by its first word:

| Output | Exit | What to do |
|---|---|---|
| `FINDING <rule> <file>:<line> <text>` | — | A rule broken at that line (`line 0`: the whole file, e.g. an unterminated heredoc). Collect them. |
| `RUN_FAILED <file> exit=<n> not_ok=<n>` | — | `--run`: the file fails under bats with bash 3.2 first in `PATH`. Collect it. |
| `NOTE R9 skipped: no --allowed-commands` | — | Say R9 was not checked. Offer it only if the repo documents a minimal runtime. |
| `CLEAN files=<n>` | 0 | Report that the n files pass every rule checked. Done. |
| `FINDINGS <n> files=<n>` | 1 | Report (below). |
| `NO_FILES` | 3 | No `.bats`, `.bash` or `.sh` under the paths. Tell the user; ask for the right path. |
| `CHECK_FAILED <why> [<path>]` | 5 | A file or folder could not be read (`unreadable`, `find`), the file list could not be sorted (`sort`), `--run` could not create its temporary log (`mktemp`: check `TMPDIR` and free disk), or a check broke (`R1`, `patterns`). stderr says why. Nothing was reported as clean: show it, fix the cause, and run again |
| `MISSING_TOOL bats` | 4 | `--run` needs bats-core. Tell the user to install it (`brew install bats-core`, `apt-get install bats`). |
| message on stderr | 2 | Bad option or path. Show it and fix the call. |

4. Report the findings grouped by rule, most important first: `RUN_FAILED`, R1, R8, R7, R6, R9, R4, R5,
   R10, R11. For each rule: count, the `file:line` list (quote the text when it helps), and the fix from
   its section in `references/rules.md`. Say which rules are heuristics (R4-R11): each finding is a line to
   look at; a false positive is silenced on its line with `# check-bats: ignore <rule> <reason>`.
5. Offer to hand the report to whoever fixes it (a coding skill or agent, or the user). Do not edit the
   tests or the scripts yourself from this skill.

## Rules

- Never edit, format or commit the checked files: this skill only reads.
- Report every finding the script printed; do not drop one because it looks minor. You may say a finding
  looks like a false positive, with the reason, after reading the line.
- Never pass `--allowed-commands` from memory or guesswork: only from the repo's docs or the user.

## Findings

This skill improves with use. When a run teaches something durable (a false positive pattern, a rule that
misses a real case, a trap in a repo's tests), update the skill before going on: a wrong detection goes into
`scripts/` with a test in `tests/`; a fix or explanation goes into `references/rules.md`; anything with no
place yet goes in `references/findings.md` with one line here: `- <when it applies>: [<title>](references/findings.md#<anchor>)`.
Admit only what is not obvious from the rules and holds beyond one run.
