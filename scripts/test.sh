#!/usr/bin/env bash
# Run the whole suite: repo checks (tests/) and every skill's bats tests. Requires bats-core, shellcheck and
# uvx (uv), for the Agent Skills validator.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for tool in bats shellcheck uvx; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing: $tool (see README, 'Tests')" >&2; exit 1; }
done

exec bats -r "$ROOT/tests" "$ROOT/skills"
