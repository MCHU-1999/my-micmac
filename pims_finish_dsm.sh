#!/usr/bin/env bash
# Turn the PIMs2Mnt DSM into one GeoTIFF, then delete MicMac's working files.
#
# Usage:
#   ./pims_finish_dsm.sh <project_dir> [--delete-ortho] [--delete-pims]
#
#   <project_dir>     folder where C3DC / PIMs2Mnt ran (e.g. ~/Documents/projects/Toulouse_EO)
#   --delete-ortho    also delete PIMs-ORTHO/ (88 GB). Only do this after Tawny, or if you
#                     don't want an orthophoto: the per-image orthos can't be rebuilt without
#                     re-running PIMs2Mnt DoOrtho=1.
#   --delete-pims     also delete PIMs-MicMac/ (14 GB). After this you can't re-run
#                     PIMs2Mnt / PIMs2Ply without re-running C3DC.
#
# Step 1 writes  <project_dir>/results/DSM.tif :
#   Float32, Z in metres, 10 cm pixels, EPSG:2154 (Lambert-93), nodata = -9999
#   (pixels where PIMs-Merged_Masq.tif is 0), DEFLATE-compressed, tiled, with overviews.
# Then moves C3DC_MicMac.ply into results/.
# Step 2 lists what will be deleted with sizes and asks you to type "yes".
# Nothing is deleted unless step 1 succeeded.

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
OUT=results/DSM.tif

# ---- step 1: DSM -> GeoTIFF ------------------------------------------------
if [[ -f "$OUT" ]]; then
  echo "== $OUT already exists, skipping conversion"
else
  for f in "$PROF" "${PROF%.tif}.tfw" "$MASQ"; do
    [[ -f "$f" ]] || { echo "Missing $PROJ/$f - did PIMs2Mnt finish?" >&2; exit 1; }
  done
  mkdir -p results
  TMP=results/DSM.tmp.tif
  rm -f "$TMP"

  echo "== Masking DSM and writing $TMP (2.6 GB in, takes a few minutes)"
  # GDAL reads the georeferencing from PIMs-Merged_Prof.tfw automatically;
  # gdal_calc copies it from input A to the output.
  gdal_calc \
    -A "$PROF" -B "$MASQ" \
    --calc="numpy.where(B > 0, A, $NODATA)" \
    --type=Float32 --NoDataValue=$NODATA --hideNoData \
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

# ---- step 2: cleanup -------------------------------------------------------
# Always kept: images, Ori-*, Homol/, MicMac-LocalChantierDescripteur.xml,
# overlap.xml/.txt, mm3d-LogFile.txt (record of every command run), results/
TARGETS=(
  PIMs-TmpBasc        # per-image reprojected depth maps + raw DSM (now in results/DSM.tif).
                      # Tawny needs PIMs-Merged_Masq.* from here; pims_ortho.sh rebuilds it from DSM.tif
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
