#!/usr/bin/env bash
# Regenerates build_info.json (repo root) from git + project.godot so the
# main menu's version/date label and "Проверить обновления" check are never
# stale.
#
# Run by:
#   - .github/workflows/ci.yml's export-desktop job, before each platform
#     export -- AUTHORITATIVE. This is what real shipped builds embed.
#   - the local pre-commit hook installed by scripts/install-hooks.sh --
#     dev convenience only. Its "commit" field necessarily reflects the
#     PARENT commit (the new commit's own hash doesn't exist yet at
#     pre-commit time), so treat it as approximate; CI's stamp on the
#     actual pushed/tagged commit is the one that matters.
#
# Version precedence: nearest reachable git tag (stripped of a leading
# "v") if one exists, else project.godot's config/version -- so a tagged
# release always shows its real tag, and untagged commits (most PR/dev
# builds) fall back to whatever config/version currently says rather than
# showing nothing.
set -euo pipefail
cd "$(dirname "$0")/.."

# Shallow CI checkouts (actions/checkout@v4 default fetch-depth) don't fetch
# tags at all -- try to grab them; harmless no-op if already present, and
# swallowed (|| true) if there's no remote configured (e.g. a tarball
# checkout) or the fetch is otherwise not possible.
git fetch --tags --force --quiet 2>/dev/null || true

VERSION=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot | head -n1)
VERSION="${VERSION:-0.0.0}"

TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
if [[ -n "$TAG" ]]; then
	VERSION="${TAG#v}"
fi

COMMIT=$(git rev-parse --short=8 HEAD 2>/dev/null || echo "unknown")
# The commit's own date (not "when CI happened to run") so re-running CI on
# the same commit reproduces the same stamp.
DATE=$(git log -1 --format=%cd --date=short HEAD 2>/dev/null || date -u +%Y-%m-%d)

cat > build_info.json <<EOF
{
	"version": "$VERSION",
	"commit": "$COMMIT",
	"date": "$DATE"
}
EOF

echo "Stamped build_info.json: version=$VERSION commit=$COMMIT date=$DATE"
