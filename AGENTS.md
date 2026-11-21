# worktree-arness-arness-tools

arness plugin: the skills in `skills/` are installed into an arness checkout with its `plugin-manage` skill. See `README.md`.

## Repo rules

- Every skill lives in `skills/tools-<name>/` with `SKILL.md` (`name: tools-<name>`), `README.md`, its scripts in `scripts/` (sourced blocks in `scripts/lib/`) and bats tests in `tests/` (one `<script>.bats` per entry script). Keep `skills=` in `arness-plugin.conf` in sync with `skills/`; `tests/repo.bats` checks it.
- A skill with a script lists it in `allowed-tools` as `Bash(skills/<skill>/scripts/<script>.sh *)`. Paths are relative to the arness root, where the plugin's skills are linked.
- The skills are generic: they take paths or repos as input and never depend on a specific repo of the arness workspace, its private skills or one provider.
- Shell scripts must run on macOS (bash 3.2) and Linux/WSL: no GNU-only flags (`sed -i`, `readlink -f`, `mapfile`). Run `./scripts/test.sh` after changing them; it needs `bats`, `shellcheck` and `uvx` and fails without them. The suite runs `tools-check-bats` on this repo, so every test and script passes its own rules.
- bats rewrites every `@test "..." {` line of a test file, heredocs included: a fixture with `@test` lines is written with `printf`, not a heredoc. In bash 3.2 a heredoc inside `$( )` can be misparsed: write fixtures to a file first.
- Write a skill's `description` as a folded block (`description: >-`, lines indented by two spaces). The suite checks every `SKILL.md` with the Agent Skills validator.
- Never push to `main`; work on a branch and open a pull request. Bump `version` in `arness-plugin.conf` with each change that users should get.
