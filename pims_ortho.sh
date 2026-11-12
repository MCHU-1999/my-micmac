#!/usr/bin/env bash
# Build one orthophoto GeoTIFF from the per-image orthos made by PIMs2Mnt DoOrtho=1.
#
# Usage:
#   ./pims_ortho.sh <project_dir>
#
# Needs: <project_dir>/PIMs-ORTHO/ (from PIMs2Mnt DoOrtho=1) and <project_dir>/results/DSM.tif
# (from pims_finish_dsm.sh). Writes <project_dir>/results/Ortho.tif:
#   RGB, EPSG:2154, DEFLATE-compressed, tiled, BigTIFF, with overviews.
#
# Steps:
#   1. Recreate the DSM mask if it was deleted. Tawny needs it:
#      PIMs-ORTHO/MTDMaskOrtho.xml points to ../PIMs-TmpBasc/PIMs-Merged_Masq.tif + .xml.
#      Rebuilt from results/DSM.tif (valid where DSM != -9999).
#   2. Run Tawny  -> PIMs-ORTHO/Orthophotomosaic.tif
#      Porto (called by Tawny) writes it as a MicMac split TIFF when it is bigger than
#      20000 px (SzTileResult in include/XML_MicMac/Param-Tawny.xml): a small header plus
#      Orthophotomosaic_Tile_<x>_<y>.tif files. GDAL can't read the header.
#   3. Give each tile its own .tfw (offset from Orthophotomosaic.tfw) and merge the tiles
#      with GDAL into results/Ortho.tif. If there are no tiles, convert the single file.
#
# After checking results/Ortho.tif in QGIS you can run
#   ./pims_finish_dsm.sh <project_dir> --delete-ortho
# to delete PIMs-ORTHO/ (88 GB) and the recreated PIMs-TmpBasc/.

set -euo pipefail

export PATH="$HOME/.pixi/bin:$PATH"   # GDAL from pixi global
CRS="EPSG:2154"
NODATA=-9999                          # nodata value used in results/DSM.tif

[[ $# -eq 1 ]] || { sed -n '4,6p' "$0"; exit 1; }
PROJ=$(realpath "$1")
cd "$PROJ"

for t in mm3d gdal_calc gdal_edit gdal python3; do
  command -v "$t" >/dev/null || { echo "Missing tool: $t" >&2; exit 1; }
done
[[ -d PIMs-ORTHO ]]      || { echo "No PIMs-ORTHO/ in $PROJ" >&2; exit 1; }
[[ -f results/DSM.tif ]] || { echo "No results/DSM.tif - run pims_finish_dsm.sh first" >&2; exit 1; }

OUT=results/Ortho.tif
[[ ! -e $OUT ]] || { echo "$OUT already exists - delete it first to rebuild" >&2; exit 1; }

# Print one value from `gdal raster info --format json <file>`; $2 is a Python expression on d
json_get() {
  gdal raster info --format json "$1" | python3 -c "import json,sys; d=json.load(sys.stdin); print($2)"
}

# ---- 1. DSM mask for Tawny -------------------------------------------------
MASQ=PIMs-TmpBasc/PIMs-Merged_Masq.tif
MASQ_XML=PIMs-TmpBasc/PIMs-Merged_Masq.xml
if [[ -f $MASQ && -f $MASQ_XML ]]; then
  echo "== $MASQ exists, keeping it"
else
  echo "== Recreating $MASQ from results/DSM.tif"
  mkdir -p PIMs-TmpBasc
  rm -f "$MASQ"
  # 1-bit, uncompressed, no nodata: same format as the mask PIMs2Mnt wrote
  gdal_calc -A results/DSM.tif --calc="A != $NODATA" \
    --type=Byte --hideNoData --NoDataValue=none --co NBITS=1 \
    --outfile="$MASQ"

  # Grid description, same fields PIMs2Mnt writes (ToFOM in src/geom3d/cElNuage3DMaille.cpp).
  # GDAL's geotransform is the pixel *corner*; MicMac's origin is what it wrote in the .tfw,
  # which GDAL reads as the pixel *centre*. So MicMac origin = corner + half a pixel.
  read -r W H X0 Y0 RX RY < <(json_get results/DSM.tif \
    "' '.join(map(str, [*d['size'], d['geoTransform'][0]+d['geoTransform'][1]/2, d['geoTransform'][3]+d['geoTransform'][5]/2, d['geoTransform'][1], d['geoTransform'][5]]))")
  cat > "$MASQ_XML" <<EOF
<?xml version="1.0" ?>
<FileOriMnt>
     <NameFileMnt>PIMs-Merged_Prof.tif</NameFileMnt>
     <NameFileMasque>PIMs-Merged_Masq.tif</NameFileMasque>
     <NombrePixels>$W $H</NombrePixels>
     <OriginePlani>$X0 $Y0</OriginePlani>
     <ResolutionPlani>$RX $RY</ResolutionPlani>
     <OrigineAlti>0</OrigineAlti>
     <ResolutionAlti>1</ResolutionAlti>
     <Geometrie>eGeomMNTEuclid</Geometrie>
</FileOriMnt>
EOF
  echo "   grid: ${W}x${H} px, origin $X0 $Y0, pixel $RX $RY"
fi

# ---- 2. Tawny --------------------------------------------------------------
MOSAIC=PIMs-ORTHO/Orthophotomosaic.tif
if [[ -f $MOSAIC ]]; then
  echo "== $MOSAIC exists, skipping Tawny"
else
  echo "== Running Tawny (Porto)"
  mm3d Tawny PIMs-ORTHO/
fi
[[ -f $MOSAIC ]] || { echo "Tawny did not create $MOSAIC" >&2; exit 1; }
[[ -f PIMs-ORTHO/Orthophotomosaic.tfw ]] || { echo "Missing PIMs-ORTHO/Orthophotomosaic.tfw" >&2; exit 1; }

# ---- 3. Merge into one GeoTIFF ---------------------------------------------
mkdir -p results
TMP=results/Ortho.tmp.tif
rm -f "$TMP"
CO=(--co COMPRESS=DEFLATE --co PREDICTOR=2 --co TILED=YES --co BIGTIFF=YES)

shopt -s nullglob
TILES=(PIMs-ORTHO/Orthophotomosaic_Tile_*_*.tif)
shopt -u nullglob

if [[ ${#TILES[@]} -eq 0 ]]; then
  echo "== Mosaic is a single file, converting"
  gdal raster convert "${CO[@]}" "$MOSAIC" "$TMP"
else
  echo "== Mosaic is split into ${#TILES[@]} tiles, georeferencing each tile"
  # World file of the whole mosaic: line 1 = pixel width, 4 = pixel height (negative),
  # 5/6 = X/Y of the top-left pixel. Tile <x>_<y> starts x*tile_width, y*tile_height pixels in.
  mapfile -t TFW < <(tr -d '\r' < PIMs-ORTHO/Orthophotomosaic.tfw)
  T00=PIMs-ORTHO/Orthophotomosaic_Tile_0_0.tif
  [[ -f $T00 ]] || { echo "Missing $T00" >&2; exit 1; }
  read -r TW TH < <(json_get "$T00" "' '.join(map(str, d['size']))")
  echo "   tile size ${TW}x${TH} px"

  for t in "${TILES[@]}"; do
    [[ $t =~ _Tile_([0-9]+)_([0-9]+)\.tif$ ]] || { echo "Bad tile name $t" >&2; exit 1; }
    tx=${BASH_REMATCH[1]}; ty=${BASH_REMATCH[2]}
    python3 - "${TFW[@]}" "$tx" "$ty" "$TW" "$TH" > "${t%.tif}.tfw" <<'PY'
import sys
a, b, c, d, x0, y0 = map(float, sys.argv[1:7])
tx, ty, tw, th = map(int, sys.argv[7:11])
for v in (a, b, c, d, x0 + tx * tw * a, y0 + ty * th * d):
    print(repr(v))
PY
  done

  echo "== Merging tiles into $TMP"
  gdal raster mosaic "${CO[@]}" "${TILES[@]}" "$TMP"
fi

echo "== Setting CRS $CRS"
gdal_edit -a_srs "$CRS" "$TMP"

echo "== Building overviews"
gdal raster overview add -r average --levels 2,4,8,16,32,64 "$TMP"

mv "$TMP" "$OUT"

echo "== Done: $OUT"
gdal raster info "$OUT" | grep -E -i 'size is|origin|pixel size|ID\["EPSG"' || true
