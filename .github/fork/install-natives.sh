#!/usr/bin/env bash
# Installs upstream's published native addon for one target into
# packages/natives/native. The fork never builds Rust: it ships only
# TypeScript fixes, so it uses the addon npm already carries for the version
# in packages/natives/package.json.
#
# Usage: install-natives.sh <linux-x64|darwin-arm64> [--allow-latest]
#   --allow-latest  fall back to the newest published addon when this version
#                   is not on npm (tests on main between upstream releases).
set -euo pipefail

target=${1:?target}
version=$(jq -r .version packages/natives/package.json)
pkg="@oh-my-pi/pi-natives-$target"
work=$(mktemp -d)

if ! (cd "$work" && npm pack --silent "$pkg@$version" >/dev/null 2>&1); then
	[ "${2:-}" = --allow-latest ] || {
		echo "::error::$pkg@$version is not published"
		exit 1
	}
	echo "::warning::$pkg@$version is not published; using the latest release"
	(cd "$work" && npm pack --silent "$pkg@latest" >/dev/null)
fi
tar -xzf "$work"/*.tgz -C "$work"
cp "$work"/package/*.node packages/natives/native/
ls -l packages/natives/native/*.node
