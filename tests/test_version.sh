#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRAPPER="${ROOT}/src/trapper.sh"

# Source in a child so trapper's stderr redirect does not wrap this runner.
version="$(bash -c "source \"${TRAPPER}\"; get_version")"
pkg_version="$(bash -c "source \"${TRAPPER}\"; printf '%s\\n' \"\${TRAPPER_VERSION}\"")"

if [[ "${version}" != "${pkg_version}" ]]; then
    echo "FAIL: get_version does not match TRAPPER_VERSION" >&2
    exit 1
fi

if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+ ]]; then
    echo "FAIL: version is not dotted semver (major.minor…): ${version}" >&2
    exit 1
fi

major="${version%%.*}"
rest="${version#*.}"
minor="${rest%%[.-]*}"
if [[ ! "${major}" =~ ^[0-9]+$ || ! "${minor}" =~ ^[0-9]+$ ]]; then
    echo "FAIL: major/minor are not numeric: ${version}" >&2
    exit 1
fi

echo "PASS: test_version.sh"
