#!/usr/bin/env bash
# Events are immutable journal projections. Reading never consumes mail.
loom_events_read() (
    # shellcheck source=ops/state.sh
    source "$(dirname -- "${BASH_SOURCE[0]}")/state.sh"
    _loom_state_call events "$@"
)
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then loom_events_read "$@"; fi
