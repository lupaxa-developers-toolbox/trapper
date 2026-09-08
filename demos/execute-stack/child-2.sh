#!/usr/bin/env bash

# -------------------------------------------------------------------------------- #
# Failing leaf of an execute stack.                                                #
# -------------------------------------------------------------------------------- #

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/src/trapper.sh"

fail_demo()
{
    ls /no/such/trapper/demo/path
}

fail_demo
