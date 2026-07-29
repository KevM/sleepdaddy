#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/sleepdaddy-release-tests.XXXXXX")"
trap 'rm -rf "$fixture_dir"' EXIT

assert_contains() {
  local expected="$1"
  local file="$2"
  grep -Fq "$expected" "$file" || {
    echo "expected '$expected' in $file" >&2
    exit 1
  }
}

cp "$repo_root/project.yml" "$fixture_dir/project.yml"
new_build="$("$repo_root/Scripts/bump-build-number.sh" "$fixture_dir/project.yml")"
[[ "$new_build" == "2" ]]
assert_contains 'CURRENT_PROJECT_VERSION: "2"' "$fixture_dir/project.yml"
assert_contains 'MARKETING_VERSION: "1.0.2"' "$fixture_dir/project.yml"

"$repo_root/Scripts/validate-release-version.sh" \
  "v1.0.2" "$fixture_dir/project.yml"

if "$repo_root/Scripts/validate-release-version.sh" \
  "v1.0.3" "$fixture_dir/project.yml"; then
  echo "mismatched release tag unexpectedly passed" >&2
  exit 1
fi

if "$repo_root/Scripts/validate-release-version.sh" \
  "release-1.0.2" "$fixture_dir/project.yml"; then
  echo "malformed release tag unexpectedly passed" >&2
  exit 1
fi

printf 'name: MissingVersions\n' > "$fixture_dir/missing.yml"
if "$repo_root/Scripts/bump-build-number.sh" "$fixture_dir/missing.yml"; then
  echo "missing version keys unexpectedly passed" >&2
  exit 1
fi

cp "$repo_root/project.yml" "$fixture_dir/malformed.yml"
sed -i.bak -E \
  's/CURRENT_PROJECT_VERSION: "[0-9]+"/CURRENT_PROJECT_VERSION: "one"/' \
  "$fixture_dir/malformed.yml"
rm -f "$fixture_dir/malformed.yml.bak"
if "$repo_root/Scripts/bump-build-number.sh" "$fixture_dir/malformed.yml"; then
  echo "malformed build number unexpectedly passed" >&2
  exit 1
fi

echo "release script tests passed"
