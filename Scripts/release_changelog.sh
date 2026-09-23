#!/usr/bin/env bash
# Generates release notes from the squash-merged commits between the previous
# tag and the release tag (issue #7). Squash merges preserve the PR number in
# the commit subject ("feat: … (#14)"), so plain subject lines are already
# user-facing changelog entries.
#
# Usage: release_changelog.sh REF
#   REF is a tag name (preferred). If it is not an annotated/known tag, the
#   range falls back to "last tag..HEAD" so workflow_dispatch dry runs can
#   preview the same output.
set -euo pipefail
cd "$(dirname "$0")/.."

ref="${1:?usage: release_changelog.sh TAG_OR_REF}"

if git rev-parse -q --verify "refs/tags/$ref" >/dev/null; then
    prev="$(git describe --tags --abbrev=0 "$ref^" 2>/dev/null || true)"
    range="$prev..$ref"
    title="$ref"
    [ -n "$prev" ] || range="$ref"
else
    prev="$(git describe --tags --abbrev=0 'HEAD^' 2>/dev/null || true)"
    range="${prev:+$prev..}HEAD"
    title="$ref (unreleased preview)"
fi

{
    echo "## What's new in $title"
    echo
    git log --no-merges --pretty=format:'- %s' "$range"
    echo
}
