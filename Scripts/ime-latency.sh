#!/bin/bash
# Shows Xmac IME latency logs: per-window summaries, slow keys, tap timeouts.
#   Scripts/ime-latency.sh          live stream while typing
#   Scripts/ime-latency.sh 30m      history for the last 30 minutes
set -euo pipefail

PREDICATE='subsystem == "vn.xmac.app" AND category == "IME"'

if [[ $# -gt 0 ]]; then
    log show --last "$1" --info --style compact --predicate "$PREDICATE"
else
    log stream --level info --style compact --predicate "$PREDICATE"
fi
