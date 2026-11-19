#!/usr/bin/env bash
# Turn the PIMs2Mnt DSM into one GeoTIFF, then delete MicMac's working files.
#
# Usage:
#   ./run_cleanup.sh <project_dir> [--delete-ortho] [--delete-pims]
#
#   <project_dir>     folder where C3DC / PIMs2Mnt ran (e.g. ~/Documents/projects/Toulouse_EO)
#   --delete-ortho    also delete PIMs-ORTHO/ (88 GB). Refused unless results/Ortho.tif was
#                     made: the per-image orthos can't be rebuilt without re-running
#                     PIMs2Mnt DoOrtho=1.
#   --delete-pims     also delete PIMs-MicMac/ (14 GB). After this you can't re-run
#                     PIMs2Mnt / PIMs2Ply without re-running C3DC.
#
# Step 1 writes  <project_dir>/results/DSM.tif :
#   Float32, Z in metres, 10 cm pixels, EPSG:2154 (Lambert-93), nodata = -9999
#   (pixels where PIMs-Merged_Masq.tif is 0 or fewer than 15 depth maps contributed,
#   per PIMs-Merged_Cptr.tif), DEFLATE-compressed, tiled, with overviews.
# Step 2 writes  <project_dir>/results/Ortho.tif  from Tawny's PIMs-ORTHO/Orthophotomosaic.tif
#   (skipped if Tawny hasn't run): RGB, EPSG:2154, DEFLATE, tiled, BigTIFF, with overviews.
#   Tawny writes mosaics over 20000 px as a MicMac split TIFF (a header GDAL can't read plus
#   Orthophotomosaic_Tile_<x>_<y>.tif), so each tile gets a world file and GDAL merges them.
# Then moves C3DC_MicMac.ply into results/.
# Step 3 lists what will be deleted with sizes and asks you to type "yes".
# Nothing is deleted unless steps 1 and 2 succeeded.

set -euo pipefail

# GDAL comes from pixi global (gdal_calc, gdal_edit, gdal)
export PATH="$HOME/.pixi/bin:$PATH"

CRS="EPSG:2154"     # Lambert-93; the .tfw has coordinates but no CRS
NODATA=-9999

# ---- arguments -------------------------------------------------------------
[[ $# -ge 1 ]] || { sed -n '4,12p' "$0"; exit 1; }
PROJ=$(realpath "$1"); shift
DELETE_ORTHO=no
DELETE_PIMS=no
for a in "$@"; do
  case "$a" in
    --delete-ortho) DELETE_ORTHO=yes ;;
    --delete-pims)  DELETE_PIMS=yes ;;
    *) echo "Unknown option: $a" >&2; exit 1 ;;
  esac
done

for t in gdal_calc gdal_edit gdal; do
  command -v "$t" >/dev/null || { echo "Missing GDAL tool: $t" >&2; exit 1; }
done

cd "$PROJ"
BASC=PIMs-TmpBasc
PROF=$BASC/PIMs-Merged_Prof.tif
MASQ=$BASC/PIMs-Merged_Masq.tif
CPTR=$BASC/PIMs-Merged_Cptr.tif
MIN_CPTR=15         # keep only cells where at least this many depth maps agreed
OUT=results/DSM.tif

# ---- step 1: DSM -> GeoTIFF ------------------------------------------------
if [[ -f "$OUT" ]]; then
  echo "== $OUT already exists, skipping conversion"
else
  for f in "$PROF" "${PROF%.tif}.tfw" "$MASQ" "$CPTR"; do
    [[ -f "$f" ]] || { echo "Missing $PROJ/$f - did PIMs2Mnt finish?" >&2; exit 1; }
  done
  mkdir -p results
  TMP=results/DSM.tmp.tif
  rm -f "$TMP"

  echo "== Masking DSM (Masq > 0 and Cptr >= $MIN_CPTR) and writing $TMP (2.6 GB in, takes a few minutes)"
  # GDAL reads the georeferencing from PIMs-Merged_Prof.tfw automatically;
  # gdal_calc copies it from input A to the output.
  gdal_calc \
    -A "$PROF" -B "$MASQ" -C "$CPTR" \
    --calc="numpy.where((B > 0) & (C >= $MIN_CPTR), A, $NODATA)" \
    --type=Float32 --NoDataValue=$NODATA \
    --co COMPRESS=DEFLATE --co PREDICTOR=3 --co TILED=YES --co BIGTIFF=IF_SAFER \
    --outfile="$TMP"

  echo "== Setting CRS $CRS"
  gdal_edit -a_srs "$CRS" "$TMP"

  echo "== Building overviews (for fast display in QGIS)"
  gdal raster overview add -r average --levels 2,4,8,16,32,64 "$TMP"

  mv "$TMP" "$OUT"
fi

echo "== Checking $OUT"
gdal raster info --stats "$OUT" | grep -E -i 'size is|origin|pixel size|ID\["EPSG"|nodata|minimum|maximum|mean' || true
# Fail here (before deleting anything) if the output has no CRS or no georeferencing
INFO=$(gdal raster info --format json "$OUT")
grep -q '"geoTransform"' <<<"$INFO" || { echo "No georeferencing in $OUT - not deleting anything" >&2; exit 1; }
grep -q '2154'           <<<"$INFO" || { echo "No CRS in $OUT - not deleting anything" >&2; exit 1; }

# ---- step 2: Tawny mosaic -> GeoTIFF ---------------------------------------
MOSAIC=PIMs-ORTHO/Orthophotomosaic.tif
ORTHO=results/Ortho.tif
if [[ -f "$ORTHO" ]]; then
  echo "== $ORTHO already exists, skipping conversion"
elif [[ ! -f "$MOSAIC" ]]; then
  echo "== No $MOSAIC (Tawny not run?), skipping ortho"
else
  TFW=PIMs-ORTHO/Orthophotomosaic.tfw
  [[ -f "$TFW" ]] || { echo "Missing $PROJ/$TFW" >&2; exit 1; }
  TMP=results/Ortho.tmp.tif
  rm -f "$TMP"
  CO=(--co COMPRESS=DEFLATE --co PREDICTOR=2 --co TILED=YES --co BIGTIFF=YES)

  shopt -s nullglob
  TILES=(PIMs-ORTHO/Orthophotomosaic_Tile_*_*.tif)
  shopt -u nullglob

  if [[ ${#TILES[@]} -eq 0 ]]; then
    echo "== Mosaic is a single file, converting to $TMP"
    gdal raster convert "${CO[@]}" "$MOSAIC" "$TMP"
  else
    # Every tile is TWxTH px except the last column/row. Tile <x>_<y> starts
    # x*TW, y*TH pixels from the mosaic's top-left corner.
    read -r TW TH < <(gdal raster info PIMs-ORTHO/Orthophotomosaic_Tile_0_0.tif \
                      | sed -n 's/^Size is \([0-9]*\), *\([0-9]*\).*/\1 \2/p')
    [[ -n ${TW:-} && -n ${TH:-} ]] || { echo "Can't read size of Orthophotomosaic_Tile_0_0.tif" >&2; exit 1; }
    echo "== Mosaic is split into ${#TILES[@]} tiles of ${TW}x${TH} px, writing a world file for each"
    for t in "${TILES[@]}"; do
      [[ $t =~ _Tile_([0-9]+)_([0-9]+)\.tif$ ]] || { echo "Bad tile name $t" >&2; exit 1; }
      # .tfw lines: 1 pixel width, 2-3 rotation, 4 pixel height (negative), 5-6 X/Y of top-left pixel
      # LC_ALL=C: with a French locale awk reads "574000.025" as 574000 and prints commas
      tr -d '\r' < "$TFW" | LC_ALL=C awk -v tx="${BASH_REMATCH[1]}" -v ty="${BASH_REMATCH[2]}" -v tw="$TW" -v th="$TH" '
        NR <= 4 { v[NR] = $1; print }
        NR == 5 { printf "%.10f\n", $1 + tx * tw * v[1] }
        NR == 6 { printf "%.10f\n", $1 + ty * th * v[4] }' > "${t%.tif}.tfw"
    done
    echo "== Merging tiles into $TMP"
    gdal raster mosaic "${CO[@]}" "${TILES[@]}" "$TMP"
  fi

  echo "== Setting CRS $CRS"
  gdal_edit -a_srs "$CRS" "$TMP"

  echo "== Building overviews"
  gdal raster overview add -r average --levels 2,4,8,16,32,64 "$TMP"

  mv "$TMP" "$ORTHO"
fi

if [[ -f "$ORTHO" ]]; then
  echo "== Checking $ORTHO"
  gdal raster info "$ORTHO" | grep -E -i 'size is|origin|pixel size|ID\["EPSG"' || true
  INFO=$(gdal raster info --format json "$ORTHO")
  grep -q '"geoTransform"' <<<"$INFO" || { echo "No georeferencing in $ORTHO - not deleting anything" >&2; exit 1; }
  grep -q '2154'           <<<"$INFO" || { echo "No CRS in $ORTHO - not deleting anything" >&2; exit 1; }
elif [[ $DELETE_ORTHO == yes ]]; then
  echo "--delete-ortho given but there is no $ORTHO - run Tawny first. Not deleting anything" >&2
  exit 1
fi

# ---- move the point cloud next to the DSM ----------------------------------
# Same disk, so this is an instant rename, not a 2.4 GB copy.
if [[ -f C3DC_MicMac.ply ]]; then
  if [[ -e results/C3DC_MicMac.ply ]]; then
    echo "results/C3DC_MicMac.ply already exists - leaving C3DC_MicMac.ply where it is" >&2
  else
    echo "== Moving C3DC_MicMac.ply to results/"
    mv C3DC_MicMac.ply results/
  fi
fi

# ---- step 3: cleanup -------------------------------------------------------
# Always kept: images, Ori-*, Homol/, MicMac-LocalChantierDescripteur.xml,
# overlap.xml/.txt, mm3d-LogFile.txt (record of every command run), results/
TARGETS=(
  PIMs-TmpBasc        # per-image reprojected depth maps + raw DSM (now in results/DSM.tif).
  PIMs-TmpMnt         # Malt ground grid, only used to set up the DSM
  PIMs-TmpMntOrtho    # ortho working folder; Tawny doesn't need it
  Pyram               # image pyramids for matching
  Tmp-MM-Dir          # MicMac scratch (image metadata cache, etc.)
  Pastis              # Tapioca scratch; tie points are in Homol/
  cAppliMMByPair_0 MMByPairCAWSI.xml MMByPairFiles.xml   # MMByP bookkeeping
  SauvApero.xml WarnApero.txt   # parameters + warnings of the last Apero run; nothing reads them
  Ori-InterneScan     # empty; only used for scanned film photos (fiducial marks). MicMac recreates it on each run
)
if [[ $DELETE_ORTHO == yes ]]; then TARGETS+=(PIMs-ORTHO); fi
if [[ $DELETE_PIMS  == yes ]]; then TARGETS+=(PIMs-MicMac); fi

EXISTING=()
for t in "${TARGETS[@]}"; do
  if [[ -e "$t" ]]; then EXISTING+=("$t"); fi
done

if [[ ${#EXISTING[@]} -eq 0 ]]; then
  echo "== Nothing to delete"; exit 0
fi

echo
echo "== Will delete from $PROJ:"
du -sch "${EXISTING[@]}"
if [[ $DELETE_ORTHO == no && -d PIMs-ORTHO ]]; then
  echo "(keeping PIMs-ORTHO/ - add --delete-ortho to remove it)"
fi
if [[ $DELETE_PIMS == no && -d PIMs-MicMac ]]; then
  echo "(keeping PIMs-MicMac/ - add --delete-pims to remove it)"
fi
echo
read -r -p "Type 'yes' to delete: " ans
[[ $ans == yes ]] || { echo "Nothing deleted."; exit 0; }

rm -rf -- "${EXISTING[@]}"
echo "== Done. Space left:"
df -h "$PROJ" | tail -1