# Sourced by sync.sh and release-tree.sh. Needs UPSTREAM_REPO and
# GITHUB_REPOSITORY_OWNER (set by Actions).
: "${UPSTREAM_REPO:?}" "${GITHUB_REPOSITORY_OWNER:?}"
out=${GITHUB_OUTPUT:-/dev/stdout}

# Records a one-line failure reason for the workflow's report job and exits.
fail() {
	echo "report=$1" >>"$out"
	echo "::error::$1"
	exit 1
}

unmerged_paths() {
	git diff --name-only --diff-filter=U | paste -sd, -
}

# Bot identity, CHANGELOG union merges (every fix adds a line under the same
# [Unreleased] heading), and upstream main plus its release tags.
prepare_repo() {
	git config user.name "github-actions[bot]"
	git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
	echo 'packages/*/CHANGELOG.md merge=union' >>"$(git rev-parse --git-dir)/info/attributes"
	git remote add upstream "https://github.com/$UPSTREAM_REPO.git" 2>/dev/null || true
	git fetch --quiet --no-tags upstream main
	git fetch --quiet --no-tags upstream '+refs/tags/v*:refs/tags/v*'
}

# The latest upstream release tag (vX.Y.Z, no prerelease suffix).
latest_release_tag() {
	git tag -l 'v[0-9]*' --sort=-v:refname | grep -v -- - | sed -n 1p
}

# Prints the upstream merge commit of the PR opened from fork branch $1, or
# nothing while it is unmerged.
upstream_merge_of() {
	gh api "repos/$UPSTREAM_REPO/pulls?head=$GITHUB_REPOSITORY_OWNER:$1&state=closed" \
		--jq '[.[] | select(.merged_at != null)][0].merge_commit_sha // empty'
}
