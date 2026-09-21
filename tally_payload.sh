#!/bin/bash
printf "%7s  %-5s %-6s %s\n" PAYLOAD CLEAN FAILED DETAIL
for mb in 4 8 12 16; do
    clean=0; bad=0; d=""
    for f in cxi-p${mb}x[0-9]-*.out; do
        [ -f "$f" ] || continue
        jid="${f##*-}"; jid="${jid%.out}"
        if grep -q "PROBE OK" "$f" 2>/dev/null; then clean=$((clean+1)); d="$d ok"
        elif grep -q ": FAILED" "$f" 2>/dev/null; then bad=$((bad+1)); d="$d abort"
        else st=$(sacct -j "$jid" --format=State -n -X 2>/dev/null|tr -d ' '|head -1)
            case "$st" in TIMEOUT|CANCELLED*) bad=$((bad+1)); d="$d hang";;
                RUNNING|PENDING) d="$d -";; *) d="$d ?";; esac; fi
    done
    printf "%4s MB  %-5s %-6s %s\n" "$mb" "$clean" "$bad" "$d"
done
