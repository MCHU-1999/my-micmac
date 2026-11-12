#!/usr/bin/env bash
# Run the MicMac pipeline (GrapheHom -> Tapioca -> C3DC -> DSM -> Ortho -> Tawny)
# and log how long each step takes.
#
# Usage:
#   pixi run ./run_pipeline.sh <project_dir>
#
# Each step's wall-clock time is printed and appended to <project_dir>/timings.txt.
# Stops at the first step that fails.
#
# DSM and Ortho are separate PIMs2Mnt runs. The ortho run uses Purge=0 so it
# does not delete the DSM it needs (Purge is an option added in this fork).

set -euo pipefail

[[ $# -eq 1 ]] || { sed -n '5,7p' "$0"; exit 1; }
cd "$1"

PAT='20FE.*\.tif'
ORI=Compense-Figee5
OFFSET='[574000,6276000,0]'
LOG=timings.txt

echo "=== run $(date '+%F %T')" | tee -a "$LOG"

step() {                       # step <name> <command...>
  local name=$1; shift
  local t0=$SECONDS rc=0
  "$@" || rc=$?
  local dt=$((SECONDS - t0))
  printf '%-10s %02d:%02d:%02d  exit=%d\n' "$name" $((dt/3600)) $((dt%3600/60)) $((dt%60)) $rc | tee -a "$LOG"
  return $rc
}

step GrapheHom mm3d GrapheHom ./ "$PAT" "$ORI" Out=overlap.xml
step Tapioca   mm3d Tapioca File overlap.xml 2000
step C3DC      mm3d C3DC MicMac "$PAT" "$ORI" OffsetPly="$OFFSET"
step DSM       mm3d PIMs2Mnt MicMac
step Ortho     mm3d PIMs2Mnt MicMac DoMnt=0 DoOrtho=1 Purge=0
step Tawny     mm3d Tawny PIMs-ORTHO/

echo "=== done $(date '+%F %T')" | tee -a "$LOG"
