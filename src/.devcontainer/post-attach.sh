#!/bin/bash
#
# post-attach.sh — backs `postAttachCommand` in every devcontainer variant.
# Fires EVERY time a tool attaches (every reopen), so keep it lightweight:
# no indexing, no dep installs, no heavy I/O — those belong in post-create.sh.
# Candidate uses: status echoes, ephemeral-state refresh.
#
set -euo pipefail
