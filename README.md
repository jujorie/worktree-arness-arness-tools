# worktree-arness-arness-tools

An [arness](https://github.com/jujorie/worktree-arness) plugin with tools to work on arness itself and on its
plugins: checks for the conventions their scripts and tests must follow.

| Skill | What it does |
|---|---|
| `tools-check-bats` | Check the bats tests of a repo or worktree (and the scripts they test) for silent assertions, GNU-only or bash 4 code, unportable awk, SIGPIPE-prone pipes, tests that leak outside their temporary folder or reach the network, commands missing from a minimal runtime, timing dependencies and style; optionally run them under bash 3.2. Only reports |

## Install

From the arness repo, with its `plugin-manage` skill: "instala el plugin https://github.com/jujorie/worktree-arness-arness-tools.git".
It shows the skills and permission rules and asks before installing. Update it the same way ("actualiza el
plugin worktree-arness-arness-tools").

Requires `bash`, `awk`, `dirname`, `find`, `grep`, `mktemp`, `sed`, `sort` and `tr`; `bats` to run tests with
`tools-check-bats --run`.

## Layout

```
arness-plugin.conf          plugin manifest (format: plugins/README.md of arness)
skills/tools-check-bats/    SKILL.md, README.md, scripts/, references/, tests/
tests/                      repo-wide checks of the skills and scripts
scripts/test.sh             runs the whole suite
```

Every skill starts with the prefix `tools-`, so the plugin does not collide with other plugins. Scripts follow
the arness rules: bash 3.2 (macOS) and Linux, no GNU-only flags. The suite checks the plugin with its own
`tools-check-bats`.

## Tests

Requires `bats-core`, `shellcheck` and `uv` (`brew install bats-core shellcheck uv`; uv on Linux:
https://docs.astral.sh/uv/getting-started/installation/). `scripts/test.sh` fails with `missing: <tool>`
without one of them. The suite runs the [Agent Skills](https://agentskills.io/specification) reference
validator (`uvx --from skills-ref agentskills validate <skill>`) on every skill.

```bash
./scripts/test.sh
```
