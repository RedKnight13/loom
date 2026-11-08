#!/usr/bin/env bash
# Bounded binary spool. Source-safe; public calls isolate options and traps.
loom_output_atomic() (
    umask 077
    local path=$1 tmp
    tmp=$(mktemp "${path%/*}/.tmp.XXXXXXXXXXXX") || return 1
    if ! cat > "$tmp" || ! sync -f "$tmp" || ! mv -T -- "$tmp" "$path" || ! sync -f "${path%/*}"; then
        rm -f -- "$tmp"; return 1
    fi
)

# One writer, separately owned from the worker group. Always drains after quota.
loom_output_drain() (
    umask 077
    local dir=$1 quota=$2 generation=$3 total=0 first=0 size keep file start
    local -a chunks=()
    [[ $quota =~ ^[0-9]+$ ]] && (( quota>0 && quota<=1073741824 )) || return 2
    mkdir -m 700 -- "$dir" || return 1
    exec 8> "$dir/lock"
    printf '{"generation":"%s","first":0,"end":0,"eof":false}\n' "$generation" | loom_output_atomic "$dir/index" || return 1
    while :; do
        # fd 0 is a FIFO opened once by the caller; reopening could strand writers.
        dd bs=4096 count=1 iflag=fullblock status=none > "$dir/incoming" || return 1
        size=$(stat -c %s "$dir/incoming")
        (( size>0 )) || break
        flock -x 8 || return 1
        start=$total; total=$((total+size)); keep=$size
        (( total<=9007199254740991 )) || return 1
        (( keep<=quota )) || keep=$quota
        start=$((total-keep)); file=$dir/$start.chunk
        tail -c "$keep" "$dir/incoming" > "$file" || return 1
        chunks+=("$start")
        # Retain whole chunks. Missing bytes form one exact contiguous prefix.
        while (( ${#chunks[@]}>1 && total-chunks[0]>quota )); do
            rm -f -- "$dir/${chunks[0]}.chunk" || return 1
            chunks=("${chunks[@]:1}")
        done
        first=${chunks[0]}
        sync -f "$file" || return 1
        printf '{"generation":"%s","first":%s,"end":%s,"eof":false}\n' "$generation" "$first" "$total" | loom_output_atomic "$dir/index" || return 1
        flock -u 8
    done
    flock -x 8 || return 1
    rm -f -- "$dir/incoming"
    printf '{"generation":"%s","first":%s,"end":%s,"eof":true}\n' "$generation" "$first" "$total" | loom_output_atomic "$dir/index"
)

# Binary output is base64 in data; limit bounds encoded wire bytes. Cursor counts
# original bytes and binds generation (a per-attempt nonce), not file names.
loom_output_read() (
    local dir=$1 cursor=$2 limit=$3 generation first end eof offset gap=null n file start size skip take data tmp
    [[ $limit =~ ^[0-9]+$ ]] && (( limit>=4 && limit<=65536 )) || return 2
    [[ -f $dir/index && ! -L $dir/index && ! -L $dir/lock ]] || return 2
    exec 8< "$dir/lock"; flock -s -w 2 8 || return 1
    read -r generation first end eof < <(jq -r '[.generation,.first,.end,.eof]|@tsv' "$dir/index")
    if [[ -z $cursor ]]; then offset=0
    elif [[ $cursor == "$generation:"* && ${cursor#*:} =~ ^[0-9]{1,15}$ ]]; then offset=$((10#${cursor#*:}))
    else return 2; fi
    (( offset<=end )) || return 2
    if (( offset<first )); then gap=$(printf '{"from_byte":%s,"to_byte":%s}' "$offset" "$first"); offset=$first; fi
    # shellcheck disable=SC2017 # base64 emits complete four-byte groups
    n=$((limit/4*3)); (( n<=end-offset )) || n=$((end-offset))
    tmp=$(mktemp "$dir/.read.XXXXXXXXXXXX") || return 1
    trap 'rm -f -- "$tmp"' EXIT
    while IFS= read -r file; do
        start=${file%.chunk}; file=$dir/$file
        [[ $start =~ ^[0-9]+$ && ! -L $file ]] || return 2
        size=$(stat -c %s "$file")
        (( start+size>offset && n>0 )) || continue
        skip=$((offset-start)); (( skip>=0 )) || return 2
        take=$((size-skip)); (( take<=n )) || take=$n
        dd if="$file" bs=1 skip="$skip" count="$take" status=none >> "$tmp" || return 1
        offset=$((offset+take)); n=$((n-take))
    done < <(find "$dir" -maxdepth 1 -name '*.chunk' -type f -printf '%f\n' | sort -n)
    data=$(base64 -w0 < "$tmp") || return 1
    jq -cn --arg source combined.base64 --arg generation "$generation" --arg data "$data" --arg cursor "$generation:$offset" --argjson eof "$eof" --argjson end "$end" --argjson offset "$offset" --argjson gap "$gap" '{source:$source,generation:$generation,data:$data,next_cursor:$cursor,eof:($eof and $offset==$end),truncated:($gap!=null),gap:$gap}'
)

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    case ${1:-} in
        drain) shift; loom_output_drain "$@" ;;
        read) shift; loom_output_read "$@" ;;
        *) exit 2 ;;
    esac
fi
