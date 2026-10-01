#!/usr/bin/env bash
# Builds the fork's release tree: the latest upstream release tag plus the
# commits of every fix branch in .github/fork/fixes on origin/main. Fixes the
# tag already contains drop out as empty cherry-picks. Releasing from the tag
# rather than main keeps the native addons identical to the ones upstream
# published for that version.
#
# Outputs ($GITHUB_OUTPUT): base=<upstream tag>, tag=<new fork tag, or empty
# when the latest fork release already ships this tree>, report=<one-line
# failure reason>, commit=<release commit>. When a release is due, writes
# $RUNNER_TEMP/release-notes.md and, if any fix applies, $RUNNER_TEMP/release.bundle
# (base..commit). With no fixes left the release is upstream's code under a
# fork tag, so installs that follow fork releases keep tracking upstream.
set -euo pipefail

source "$(dirname "$0")/lib.sh"
fixes=$(git show origin/main:.github/fork/fixes)

prepare_repo
base=$(latest_release_tag)
echo "base=$base" >>"$out"

git checkout --quiet --detach "$base"
notes=()
for branch in $fixes; do
	git fetch --quiet --no-tags origin "refs/heads/$branch"
	# The fix's own commits: everything on the branch that upstream main did not
	# have when the PR merged (or does not have yet).
	merged=$(upstream_merge_of "$branch")
	since=upstream/main
	[ -z "$merged" ] || since="$merged^1"
	commits=$(git rev-list --reverse --no-merges "$since..FETCH_HEAD")
	[ -n "$commits" ] || continue
	applied_from=$(git rev-parse HEAD)
	for commit in $commits; do
		git cherry-pick -x "$commit" >/dev/null 2>&1 && continue
		# Already in the base release: the pick is empty, skip it.
		if [ -z "$(unmerged_paths)" ] && git diff --cached --quiet; then
			git cherry-pick --skip
			continue
		fi
		conflicts=$(unmerged_paths)
		git cherry-pick --abort
		fail "Applying $branch ($commit) onto $base conflicts in: $conflicts"
	done
	if [ "$(git rev-parse HEAD)" != "$applied_from" ]; then
		notes+=("- $(git log -1 --format=%s "${commits%%$'\n'*}") ($branch)")
	fi
done

tree=$(git rev-parse 'HEAD^{tree}')
latest=$(gh release list --repo "$GITHUB_REPOSITORY" --limit 100 --json tagName \
	--jq "[.[].tagName | select(startswith(\"$base-theo.\"))] | sort_by(ltrimstr(\"$base-theo.\") | tonumber) | last // empty")
shipped=
[ -z "$latest" ] || shipped=$(gh release view "$latest" --repo "$GITHUB_REPOSITORY" --json body --jq .body)
if [ "${FORCE_RELEASE:-false}" != true ] && grep -qx "Tree: $tree" <<<"$shipped"; then
	echo "tag=" >>"$out"
	echo "$latest already ships tree $tree."
	exit 0
fi

n=1
[ -z "$latest" ] || n=$((${latest#"$base-theo."} + 1))
tag="$base-theo.$n"
commit=$(git rev-parse HEAD)
echo "tag=$tag" >>"$out"
echo "commit=$commit" >>"$out"
[ "$commit" = "$(git rev-parse "$base^{commit}")" ] || git bundle create "$RUNNER_TEMP/release.bundle" "$base..HEAD"
{
	echo "Upstream $base plus the fork's fixes that are not in an upstream release yet:"
	echo
	if [ ${#notes[@]} -eq 0 ]; then echo "- none (same code as $base)"; else printf '%s\n' "${notes[@]}"; fi
	echo
	echo "Tree: $tree"
} >"$RUNNER_TEMP/release-notes.md"
cat "$RUNNER_TEMP/release-notes.md"
