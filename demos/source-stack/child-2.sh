#!/usr/bin/env bash

# -------------------------------------------------------------------------------- #
# Failing leaf of a source stack (does not source trapper).                        #
# -------------------------------------------------------------------------------- #

fail_demo()
{
    ls /no/such/trapper/demo/path
}

fail_demo
