#!/bin/bash
# benchmark.sh — runs the demo across modes and presets and prints a table.
#
#   ./benchmark.sh [seconds per run] [repeats per row]
#
# Each run builds nothing and measures nothing for the first 45 frames, then
# samples for $SECONDS_PER_RUN seconds and quits on its own. Release only:
# a Debug build of this project runs roughly a third of the speed.
#
# Repeats exist because one pass is not reproducible. The same scene, at the
# same window size on the same panel, came out at 87 fps at the end of a
# sweep and at 66-72 fps run on its own: the chip is warmer by the sixteenth
# run than the first, and ordering alone moves a row by a fifth. A single
# number hides that. With repeats > 1 each row reports the median and the
# slowest and fastest pass behind it, so the spread is on the page instead of
# in a footnote.

set -u
SECONDS_PER_RUN=${1:-10}
REPEATS=${2:-1}
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Building Release..."
BUILD_DIR=$(xcodebuild -project "$PROJECT_DIR/RealityEsceneTestV3.xcodeproj" \
    -scheme RealityEsceneTestV3 -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')

xcodebuild -project "$PROJECT_DIR/RealityEsceneTestV3.xcodeproj" \
    -scheme RealityEsceneTestV3 -configuration Release \
    -destination 'platform=macOS,arch=arm64' build >/dev/null 2>&1 || {
        echo "Build failed."; exit 1; }

APP="$BUILD_DIR/RealityEsceneTestV3.app/Contents/MacOS/RealityEsceneTestV3"
[ -x "$APP" ] || { echo "Binary not found at $APP"; exit 1; }

# Hold the display awake for the whole sweep, and let go the moment this
# script exits.
#
# A sleeping display is not a cosmetic problem here. macOS reports every
# window as not visible once the screen is off and throttles what they draw,
# so a sweep left politely alone - which is exactly what a careful person
# does, and exactly what this script asks for - puts the machine to sleep
# partway through and discards everything after it. The first full run of
# this script lost at least one pass on all seventeen rows that way, and the
# last four rows lost two of three.
# -u wakes it first. -di only stops a display going to sleep; it will not
# wake one that is already asleep, and a sweep started against a dark screen
# measures nothing at all. Two full passes - seventeen rows each, ten
# minutes of this machine - were lost that way before the third woke up and
# measured cleanly, which is a thing no result should ever depend on.
caffeinate -u -t 2
caffeinate -di -w $$ &

# Name the machine. A frame rate without one is not a result, and the whole
# point of shipping this script is that someone else can run it and say what
# their own Mac did.
echo
echo "Machine: $(sysctl -n machdep.cpu.brand_string), \
$(sysctl -n hw.logicalcpu) logical cores, macOS $(sw_vers -productVersion)"

# A benchmark on a busy Mac measures the other thing. This sweep was once run
# to completion while macOS staged a six gigabyte system update in the
# background - installd at 84% of a core, UpdateBrainService at 62% - and
# every demo came out low enough to look like a regression in the project.
# Nothing in the output said so, which is the part worth fixing.
BUSY=$(ps -Ao %cpu,comm -r \
    | awk 'NR > 1 && $1 > 40 { sub(/.*\//, "", $2); print $1 "% " $2 }' \
    | grep -v RealityEsceneTestV3)

if [ -n "$BUSY" ]; then
    echo
    echo "WARNING  something else is using this Mac right now:"
    echo "$BUSY" | sed 's/^/           /'
    echo
    echo "         Numbers measured against a busy machine are not comparable"
    echo "         with anyone else and should not be quoted. A pending system"
    echo "         update is the usual culprit: check System Settings first."
fi

# Kept, not discarded on exit. Every number in the table is derived from
# this file, and a typo in the awk below once threw away a five-minute sweep
# that had already finished measuring. Reformatting costs nothing; measuring
# again costs five minutes of not touching the Mac.
RAW="$PROJECT_DIR/benchmark-results.txt"
: > "$RAW"

# scene : selector : preset
RUNS=(
    "physics   balls       ultra"
    "physics   breakable   ultra"
    "physics   tower       ultra"
    "physics   joints      ultra"
    "physics   forcefield  ultra"
    "physics   stress      ultra"
    "physics   stress      balanced"
    "physics   stress      performance"
    "physics   instancing  ultra"
    "physics   shooter     ultra"
    "particles rain        ultra"
    "particles snow        ultra"
    "particles fire        ultra"
    "particles sparks      ultra"
    "audio     -           ultra"
    "rendering portals     ultra"
    "rendering materials   ultra"
    "rendering surface     ultra"
)

# Passes on the outside, rows on the inside. Running a row three times back
# to back measures it three times at the same temperature, so the median
# looks tight and the spread says nothing. Spread across the sweep instead,
# a row is sampled once on a cool chip, once warm and once hot, and its min
# and max describe what the demo actually does on this machine.
for (( pass = 1; pass <= REPEATS; pass++ )); do
for run in "${RUNS[@]}"; do
    set -- $run
    scene=$1; selector=$2; preset=$3

    # A plain string, not an array: expanding an empty array under `set -u`
    # is an error in the bash that ships with macOS.
    case "$scene" in
        physics)   selector_flag="--mode $selector" ;;
        particles) selector_flag="--effect $selector" ;;
        rendering) selector_flag="--showcase $selector" ;;
        *)         selector_flag="" ;;
    esac

    label="$selector"
    [ "$selector" = "-" ] && label="$scene"

    if [ "$REPEATS" -gt 1 ]; then
        echo "  running $label / $preset  (pass $pass of $REPEATS) ..."
    else
        echo "  running $label / $preset ..."
    fi

    # The reporter keys off this line rather than off the app's own
    # output. Inferring the configuration from what the app prints
    # breaks on an invalid run, which prints no preset line at all and
    # so used to inherit whatever the run before it was using.
    printf '### %s %s\n' "$label" "$preset" >> "$RAW"

    # shellcheck disable=SC2086 — intentional splitting; no value has spaces.
    "$APP" --scene "$scene" $selector_flag --quality "$preset" \
           --benchmark "$SECONDS_PER_RUN" >> "$RAW" 2>/dev/null

    # Let the machine settle. Seventeen runs back to back is a sustained
    # load and the later ones measure a warmer chip than the earlier. Six
    # seconds rather than four because this is a laptop: the GPU sits
    # near 90% for the whole of every run, and a gap that lets the fan
    # catch up costs a couple of minutes and buys a steadier chip.
    sleep 6
done
done

echo
awk '/^ surface/ { s = substr($0, 13) } /^ display/ { print "Render surface: " s "  at  " substr($0, 13); exit }' "$RAW"
echo

if [ "$REPEATS" -gt 1 ]; then
    printf "%-14s %-13s %8s %7s %7s %9s %9s %7s %6s %6s\n" \
        MODE PRESET AVG MIN MAX "1% LOW" P99 DROPPED CPU-PK GPU-PK
    printf '%.0s-' {1..94}; echo
else
    printf "%-14s %-13s %8s %9s %9s %7s %6s %6s\n" \
        MODE PRESET AVG "1% LOW" P99 DROPPED CPU-PK GPU-PK
    printf '%.0s-' {1..78}; echo
fi

# No apostrophes anywhere in this program: it sits inside a single-quoted
# shell string, and one stray quote ends it and hands the rest to bash.
awk -v repeats="$REPEATS" '
function median(a, n,   i, j, t, m) {
    for (i = 2; i <= n; i++) {
        t = a[i]
        for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]
        a[j + 1] = t
    }
    m = int((n + 1) / 2)
    return (n % 2) ? a[m] : (a[m] + a[m + 1]) / 2
}

function number(s) { sub(/%/, "", s); return s + 0 }

/^### / {
    key = $2 SUBSEP $3
    if (!(key in seen)) { seen[key] = 1; order[++keys] = key; mode[key] = $2; preset[key] = $3 }
    next
}

# avg comes first in every valid block, so it opens the slot the rest fill.
/^ avg/     { n = ++count[key]; avg[key, n] = $2 + 0; next }
/^ 1% low/  { low[key, count[key]] = $3 + 0; next }
/^ p99/     { p99[key, count[key]] = $2 + 0; next }
/^ dropped/ { drop[key, count[key]] = $2 + 0; next }
/^ cpu/     { cpu[key, count[key]] = number($2); next }
/^ gpu/     { gpu[key, count[key]] = number($2); next }

# Carried through verbatim: the app says which check failed and for how
# long, which is worth more than restating it as a guess.
/^ INVALID/ { why[key] = substr($0, 13); next }

END {
    for (i = 1; i <= keys; i++) {
        k = order[i]
        n = count[k]

        if (n == 0) {
            printf "%-14s %-13s   INVALID - %s\n", mode[k], preset[k],
                   (k in why) ? why[k] : "no run produced a measurement"
            continue
        }

        delete A; delete L; delete P; delete D; delete C; delete G
        for (j = 1; j <= n; j++) {
            A[j] = avg[k, j]; L[j] = low[k, j]; P[j] = p99[k, j]
            D[j] = drop[k, j]; C[j] = cpu[k, j]; G[j] = gpu[k, j]
        }

        lo = A[1]; hi = A[1]
        for (j = 2; j <= n; j++) {
            if (A[j] < lo) lo = A[j]
            if (A[j] > hi) hi = A[j]
        }

        # Median, not mean: one pass that lost the GPU to something else
        # should not drag the row with it.
        if (repeats > 1)
            printf "%-14s %-13s %8.1f %7.1f %7.1f %9.1f %9.2f %7d %5d%% %5d%%\n",
                   mode[k], preset[k], median(A, n), lo, hi,
                   median(L, n), median(P, n), median(D, n), median(C, n), median(G, n)
        else
            printf "%-14s %-13s %8.1f %9.1f %9.2f %7d %5d%% %5d%%\n",
                   mode[k], preset[k], median(A, n),
                   median(L, n), median(P, n), median(D, n), median(C, n), median(G, n)

        if (repeats > 1 && n < repeats)
            printf "%-14s %-13s   (only %d of %d passes measured: %s)\n",
                   "", "", n, repeats, (k in why) ? why[k] : "throttled"
    }
}
' "$RAW"

echo
echo "Raw output: $RAW   —   rerun with: ./benchmark.sh 20 3"
