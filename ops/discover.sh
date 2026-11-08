#!/usr/bin/env bash
# Passive discovery over validated operator config and caller-verified evidence.
# Source policy.sh first. No implicit source, network, agent or credential access.

loom_discover() {
    [[ $# == 3 || $# == 4 ]] || return 2
    declare -F loom_policy_resolve >/dev/null || {
        printf 'loom discovery: source policy.sh first\n' >&2; return 2;
    }
    local pin scope profile_digest evidence='null' now
    pin=$(loom_policy_resolve "$1" "$2" "$3") || return 2
    scope=$(loom_policy_scope <<< "$pin") || return 2
    profile_digest=$(jq -r .profile_digest <<< "$pin") || return 2
    if [[ $# == 4 ]]; then
        loom_policy_validate discovery-evidence "$4" || return 2
        evidence=$(cat -- "$4") || return 2
    fi
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ) || return 2
    jq -cn --argjson p "$pin" --argjson e "$evidence" --arg scope "$scope" \
      --arg pd "$profile_digest" --arg now "$now" '
      def dim($which):
        ([$e.observations[]? | select(.dimension == $which)] | first) as $o |
        if $o == null then {value:null,source:"not_probed",observed_at:$now,scope_digest:$scope}
        elif $e.scope_digest != $scope then {value:null,source:"scope_mismatch",observed_at:$now,scope_digest:$scope}
        elif (($now | fromdateiso8601) - ($o.observed_at | fromdateiso8601)) as $age | $age < 0 or $age > 300
        then {value:null,source:"stale_or_future",observed_at:$now,scope_digest:$scope}
        else {value:$o.value,source:$o.source,observed_at:$o.observed_at,scope_digest:$scope} end;
      dim("installed") as $installed | dim("launch_verified") as $launch | dim("reachable") as $reachable |
      {schema:2,scope_digest:$scope,
       provider:{id:$p.provider,capabilities:null},
       host:{id:$p.host.id,transport:$p.transport,reachable:$reachable},
       authentication:{value:null,source:"not_inspected",observed_at:$now,scope_digest:$scope},
       profiles:[{profile_id:$p.profile.id,agent_id:$p.profile.id,host_id:$p.host.id,
         profile_digest:$pd,model:$p.model,effort:$p.effort,
         configured:{value:true,source:"operator_config",observed_at:$now,scope_digest:$scope},
         installed:$installed,launch_verified:$launch,
         unknown_reason:(if $installed.value == null or $launch.value == null or $reachable.value == null
           then "Missing, inaccessible, stale or differently scoped evidence; model availability and authentication remain unknown"
           else "Model availability and authentication remain unknown" end)}]}'
}
