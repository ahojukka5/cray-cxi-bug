#!/bin/bash
# Outcome by node count for the fixed-payload bracket.
printf "%6s %6s  %-5s %-6s %s\n" NODES RANKS CLEAN FAILED DETAIL
for n in 8 16 32 64 96; do
    clean=0; bad=0; d=""
    for f in cxi-s${n}x[0-9]-*.out; do
        [ -f "$f" ] || continue
        jid="${f##*-}"; jid="${jid%.out}"
        if grep -q "PROBE OK" "$f" 2>/dev/null; then clean=$((clean+1)); d="$d ok"
        elif grep -q ": FAILED" "$f" 2>/dev/null; then bad=$((bad+1)); d="$d abort"
        else
            st=$(sacct -j "$jid" --format=State -n -X 2>/dev/null|tr -d ' '|head -1)
            case "$st" in TIMEOUT|CANCELLED*) bad=$((bad+1)); d="$d hang";;
                RUNNING|PENDING) d="$d -";; *) d="$d ?";; esac
        fi
    done
    printf "%6s %6s  %-5s %-6s %s\n" "$n" "$((n*8))" "$clean" "$bad" "$d"
done
