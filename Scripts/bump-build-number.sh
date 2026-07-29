#!/usr/bin/env bash
set -euo pipefail

project_file="${1:-project.yml}"

if [[ ! -f "$project_file" ]]; then
  echo "error: project file not found: $project_file" >&2
  exit 1
fi

current="$(
  sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION: "([0-9]+)"[[:space:]]*$/\1/p' \
    "$project_file"
)"
marketing="$(
  sed -nE 's/^[[:space:]]*MARKETING_VERSION: "([0-9]+\.[0-9]+\.[0-9]+)"[[:space:]]*$/\1/p' \
    "$project_file"
)"

if [[ ! "$current" =~ ^[0-9]+$ ]]; then
  echo "error: expected one quoted integer CURRENT_PROJECT_VERSION in $project_file" >&2
  exit 1
fi

if [[ ! "$marketing" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: expected one quoted semantic MARKETING_VERSION in $project_file" >&2
  exit 1
fi

next="$((current + 1))"
next_marketing="1.0.${next}"

sed -i.bak -E \
  -e "s/^([[:space:]]*CURRENT_PROJECT_VERSION: \")[0-9]+(\")/\1${next}\2/" \
  -e "s/^([[:space:]]*MARKETING_VERSION: \")[0-9]+\.[0-9]+\.[0-9]+(\")/\1${next_marketing}\2/" \
  "$project_file"
rm -f "${project_file}.bak"

grep -Fq "CURRENT_PROJECT_VERSION: \"${next}\"" "$project_file" || {
  echo "error: failed to write CURRENT_PROJECT_VERSION" >&2
  exit 1
}
grep -Fq "MARKETING_VERSION: \"${next_marketing}\"" "$project_file" || {
  echo "error: failed to write MARKETING_VERSION" >&2
  exit 1
}

echo "$next"
