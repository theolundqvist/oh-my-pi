#!/usr/bin/env bash
# Builds the fork's next main in the current checkout of origin/main: merge
# upstream/main, then each fix branch in .github/fork/fixes. A fix whose
# upstream PR is merged stops being merged here (upstream/main has it) but stays
# listed so release-tree.sh still ships it; once an upstream release contains
# it, it leaves the list. Never pushes; the workflow pushes the result only
# after the checks pass.
#
# Outputs ($GITHUB_OUTPUT): changed=true|false, report=<one-line failure reason>.
# Writes $RUNNER_TEMP/candidate.bundle (origin/main..HEAD) when changed.
set -euo pipefail

source "$(dirname "$0")/lib.sh"
list=.github/fork/fixes

prepare_repo
release_tag=$(latest_release_tag)

before=$(git rev-parse HEAD)

if ! git merge --quiet --no-edit -m "Merge upstream/main into fork main" upstream/main; then
	conflicts=$(unmerged_paths)
	git merge --abort
	fail "Merging upstream/main conflicts in: $conflicts"
fi

kept=()
while IFS= read -r branch; do
	[ -n "$branch" ] || continue
	merged=$(upstream_merge_of "$branch")
	if [ -n "$merged" ] && git merge-base --is-ancestor "$merged" "$release_tag" 2>/dev/null; then
		echo "Dropping $branch: merged upstream as $merged and released in $release_tag"
		continue
	fi
	kept+=("$branch")
	if [ -n "$merged" ] && git merge-base --is-ancestor "$merged" upstream/main 2>/dev/null; then
		echo "Skipping $branch: merged upstream as $merged, not yet released"
		continue
	fi
	git fetch --quiet --no-tags origin "refs/heads/$branch"
	if ! git merge --quiet --no-edit -m "Merge fix branch $branch" FETCH_HEAD; then
		conflicts=$(unmerged_paths)
		git merge --abort
		fail "Merging $branch into upstream/main conflicts in: $conflicts"
	fi
done <"$list"

if [ "${kept[*]-}" != "$(grep -v '^$' "$list" | paste -sd' ')" ]; then
	{ [ ${#kept[@]} -eq 0 ] || printf '%s\n' "${kept[@]}"; } >"$list"
	git commit --quiet -m "chore(fork): drop fixes released upstream" -- "$list"
fi

if [ "$(git rev-parse HEAD)" = "$before" ]; then
	echo "changed=false" >>"$out"
	echo "Fork main is already up to date."
	exit 0
fi
echo "changed=true" >>"$out"
git bundle create "$RUNNER_TEMP/candidate.bundle" "$before..HEAD"
git log --oneline --first-parent "$before..HEAD"
