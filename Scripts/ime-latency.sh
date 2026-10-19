#!/bin/bash
# Shows Xmac IME latency logs (summaries, slow keys, tap timeouts) and, when
# "Ghi nhật ký chẩn đoán" is on, the per-key trace (category IME-Debug).
#   Scripts/ime-latency.sh          live stream while typing
#   Scripts/ime-latency.sh 30m      history for the last 30 minutes
set -euo pipefail

PREDICATE='subsystem == "vn.xmac.app" AND category BEGINSWITH "IME"'

if [[ $# -gt 0 ]]; then
    log show --last "$1" --info --style compact --predicate "$PREDICATE"
else
    log stream --level info --style compact --predicate "$PREDICATE"
fi
