#!/usr/bin/env bash
# Convert the DSM from ellipsoidal heights to altitudes (NGF-IGN69) with the IGN geoid grid RAF20.
#
# Usage:
#   ./dsm_to_altitude.sh <project_dir>
#
# Reads  <project_dir>/results/DSM.tif          (from run_cleanup.sh; ellipsoidal heights,
#                                                 because Ori-Compense-Figee5 is ellipsoidal
#                                                 and MicMac doesn't change heights)
# Writes <project_dir>/results/DSM_IGN69.tif    altitude = h - N, CRS EPSG:2154+5720
#                                                 (Lambert-93 + NGF-IGN69 height),
#                                                 same grid, nodata and compression as DSM.tif
# DSM.tif itself is left unchanged.
#
# N (geoid height) comes from fr_ign_RAF20.tif next to this script; set RAF20=/path/to/grid
# to use another copy. N varies slowly (a few cm per km), so the geoid is reprojected to a
# 10 m grid over the DSM, then interpolated (bilinear) to each DSM pixel on the fly.
# Uses the GDAL >= 3.11 "gdal raster" commands.

set -euo pipefail

export PATH="$HOME/.pixi/bin:$PATH"   # GDAL from pixi global
NODATA=-9999                          # nodata used in results/DSM.tif
COARSE=10                             # metres; resolution of the intermediate geoid grid
RAF20=${RAF20:-$(dirname "$(realpath "$0")")/fr_ign_RAF20.tif}

[[ $# -eq 1 ]] || { sed -n '4,5p' "$0"; exit 1; }
PROJ=$(realpath "$1")
cd "$PROJ"

command -v gdal >/dev/null || { echo "Missing GDAL (gdal command)" >&2; exit 1; }
[[ -f $RAF20 ]] || { echo "Geoid grid not found: $RAF20" >&2; exit 1; }

IN=results/DSM.tif
OUT=results/DSM_IGN69.tif
[[ -f $IN ]]    || { echo "No $IN - run run_cleanup.sh first" >&2; exit 1; }
[[ ! -e $OUT ]] || { echo "$OUT already exists - delete it first to rebuild" >&2; exit 1; }
rm -f "$OUT.aux.xml"   # stale statistics from a previous run would be shown as the new ones

TMPD=$(mktemp -d results/geoid.XXXX)
trap 'rm -rf "$TMPD"' EXIT

# ---- geoid on the DSM grid -------------------------------------------------
echo "== Reprojecting RAF20 to a ${COARSE} m Lambert-93 grid over the DSM"
# Template: the DSM's extent and CRS at 10 m (a VRT, nothing is written)
gdal raster resize -q -f VRT --resolution "$COARSE,$COARSE" "$IN" "$TMPD/grid_coarse.vrt"
gdal raster reproject -q --like "$TMPD/grid_coarse.vrt" -r bilinear "$RAF20" "$TMPD/N_coarse.tif"
gdal raster info --stats "$TMPD/N_coarse.tif" | grep -E -i 'minimum|maximum|mean' \
  | sed 's/^/   geoid height N: /' || true

# Same grid as the DSM, one value per DSM pixel, interpolated when read (a VRT, no big file)
gdal raster reproject -q -f VRT --like "$IN" -r bilinear "$TMPD/N_coarse.tif" "$TMPD/N.vrt"

# ---- altitude = h - N ------------------------------------------------------
TMP=results/DSM_IGN69.tmp.tif
rm -f "$TMP"
echo "== Writing $TMP"
gdal raster calc \
  -i "A=$IN" -i "B=$TMPD/N.vrt" \
  --calc "A - B" --propagate-nodata --nodata "$NODATA" --ot Float32 \
  --co COMPRESS=DEFLATE --co PREDICTOR=3 --co TILED=YES --co BIGTIFF=IF_SAFER \
  "$TMP"

echo "== Setting CRS EPSG:2154+5720 (Lambert-93 + NGF-IGN69 height)"
gdal raster edit --crs "EPSG:2154+5720" "$TMP"

echo "== Building overviews"
gdal raster overview add -r average --levels 2,4,8,16,32,64 "$TMP"

mv "$TMP" "$OUT"

echo "== Done: $OUT"
gdal raster info --stats "$OUT" | grep -E -i 'size is|ID\["EPSG"|minimum|maximum|mean' || true
