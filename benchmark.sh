#!/bin/bash
# benchmark.sh — runs the demo across modes and presets and prints a table.
#
# Each run builds nothing and measures nothing for the first 45 frames, then
# samples for $SECONDS_PER_RUN seconds and quits on its own. Release only:
# a Debug build of this project runs roughly a third of the speed.

set -u
SECONDS_PER_RUN=${1:-10}
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
    "particles rain        ultra"
    "particles snow        ultra"
    "particles fire        ultra"
    "particles sparks      ultra"
    "audio     -           ultra"
    "rendering portals     ultra"
    "rendering materials   ultra"
    "rendering surface     ultra"
)

for run in "${RUNS[@]}"; do
    set -- $run
    scene=$1; selector=$2; preset=$3
    echo "  running $scene / $selector / $preset ..."

    # A plain string, not an array: expanding an empty array under `set -u`
    # is an error in the bash that ships with macOS.
    case "$scene" in
        physics)   selector_flag="--mode $selector" ;;
        particles) selector_flag="--effect $selector" ;;
        rendering) selector_flag="--showcase $selector" ;;
        *)         selector_flag="" ;;
    esac

    # shellcheck disable=SC2086 — intentional splitting; no value has spaces.
    "$APP" --scene "$scene" $selector_flag --quality "$preset" \
           --benchmark "$SECONDS_PER_RUN" >> "$RAW" 2>/dev/null

    # Let the machine settle. Fourteen runs back to back is a sustained load
    # and the later ones measure a warmer chip than the earlier ones.
    sleep 4
done

echo
awk '/^ surface/ { s = substr($0, 13) } /^ display/ { print "Render surface: " s "  at  " substr($0, 13); exit }' "$RAW"
echo
printf "%-14s %-13s %8s %9s %9s %7s %6s %6s\n" \
    MODE PRESET AVG "1% LOW" P99 DROPPED CPU GPU
printf '%.0s-' {1..78}; echo

awk '
# preset is cleared with every new run. An invalid run never prints a preset
# line, so without this it inherited whatever the run before it was using.
# No apostrophes in here: this whole program sits inside a single-quoted
# shell string, and one stray quote ends it and feeds $NF to bash.
/^ scene/   { mode = $NF; preset = "-" }
/^ display/ { display = substr($0, 13) }
/^ preset/  { preset = $2 }
/^ avg/     { avg = $2 }
/^ 1% low/  { low = $3 }
/^ p99/     { p99 = $2 }
/^ dropped/ { dropped = $2 }
/^ cpu/     { cpu = $2 }
# The app says which check failed and for how long; pass it straight through
# rather than restating it as a guess.
/^ INVALID/ { printf "%-14s %-13s   INVALID - %s\n", mode, preset, substr($0, 13) }
/^ gpu/     { gpu = $2
              printf "%-14s %-13s %8s %9s %9s %7s %6s %6s\n",
                     mode, preset, avg, low, p99, dropped, cpu, gpu }
' "$RAW"

echo
echo "Raw output: $RAW   —   rerun with: ./benchmark.sh 20"
