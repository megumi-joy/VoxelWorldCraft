#!/usr/bin/env bash
# One-time per clone: installs a local pre-commit hook that keeps
# build_info.json fresh between CI runs, for dev convenience.
#
# .git/hooks isn't tracked by git, so a committed hook script can't install
# itself -- run this once after cloning:
#   ./scripts/install-hooks.sh
#
# CI's own stamp (see .github/workflows/ci.yml + scripts/stamp_build_info.sh)
# is the authoritative one for actual shipped builds -- this hook is just so
# a local editor run's version/date label doesn't sit stale for days between
# CI-triggering pushes.
set -euo pipefail
cd "$(dirname "$0")/.."

HOOKS_DIR=".git/hooks"
if [[ ! -d "$HOOKS_DIR" ]]; then
	echo "error: $HOOKS_DIR not found -- run this from inside a git checkout of the repo." >&2
	exit 1
fi

cat > "$HOOKS_DIR/pre-commit" <<'HOOK'
#!/usr/bin/env bash
# Installed by scripts/install-hooks.sh -- see that file + RELEASING.md.
set -euo pipefail
repo_root="$(git rev-parse --show-toplevel)"
"$repo_root/scripts/stamp_build_info.sh"
git -C "$repo_root" add build_info.json
HOOK
chmod +x "$HOOKS_DIR/pre-commit"

echo "Installed pre-commit hook -> $HOOKS_DIR/pre-commit"
