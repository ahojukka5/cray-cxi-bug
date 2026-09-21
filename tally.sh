#!/bin/bash
# Outcome of each probe run. Three outcomes, not two: a run can finish
# its rounds, abort with an MPI error, or hang until the wall clock with
# no error at all. All three matter, and only the first is a success.
printf "%-10s %-9s %-9s %s\n" ARM CLEAN FAILED DETAIL
for arm in "$@"; do
    clean=0; bad=0; detail=""
    for f in cxi-${arm}[0-9]*-*.out; do
        [ -f "$f" ] || continue
        jid="${f##*-}"; jid="${jid%.out}"
        if grep -q "PROBE OK" "$f" 2>/dev/null; then
            clean=$((clean+1)); detail="$detail ok"
        elif grep -q ": FAILED" "$f" 2>/dev/null; then
            bad=$((bad+1)); detail="$detail abort"
        else
            st=$(sacct -j "$jid" --format=State -n -X 2>/dev/null | tr -d ' ' | head -1)
            case "$st" in
                TIMEOUT|CANCELLED*) bad=$((bad+1)); detail="$detail hang" ;;
                RUNNING|PENDING) detail="$detail -" ;;
                *) bad=$((bad+1)); detail="$detail ?$st" ;;
            esac
        fi
    done
    printf "%-10s %-9s %-9s %s\n" "$arm" "$clean" "$bad" "$detail"
done
