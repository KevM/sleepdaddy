#!/usr/bin/env bash
set -euo pipefail

tag="${1:-}"
project_file="${2:-project.yml}"

if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: release tag must have the form v<major>.<minor>.<patch>: $tag" >&2
  exit 1
fi

marketing="$(
  sed -nE 's/^[[:space:]]*MARKETING_VERSION: "([0-9]+\.[0-9]+\.[0-9]+)"[[:space:]]*$/\1/p' \
    "$project_file"
)"

if [[ -z "$marketing" ]]; then
  echo "error: MARKETING_VERSION not found in $project_file" >&2
  exit 1
fi

if [[ "$tag" != "v${marketing}" ]]; then
  echo "error: tag $tag does not match MARKETING_VERSION $marketing" >&2
  exit 1
fi

echo "release tag $tag matches MARKETING_VERSION $marketing"
