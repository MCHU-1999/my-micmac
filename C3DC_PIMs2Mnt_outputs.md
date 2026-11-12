# C3DC / PIMs2Mnt outputs: what each file is and where it comes from

Traced from the source in this repo (commit `f8fe43210`) and checked against a real run in
`~/Documents/projects/Toulouse_EO` (27 UltraCam Eagle images, orientation `Ori-Compense-Figee5`).

## What you actually need

| Result | File | Format |
| --- | --- | --- |
| **DSM** | `PIMs-TmpBasc/PIMs-Merged_Prof.tif` + `PIMs-Merged_Prof.tfw` | float32, 1 band, Z in metres (`OrigineAlti=0`, `ResolutionAlti=1` in `PIMs-Merged.xml`). Toulouse run: 28300 × 23013 px, 0.10 m pixels, top-left corner X 573412.9, Y 6278154.8 (Lambert-93) |
| DSM validity mask | `PIMs-TmpBasc/PIMs-Merged_Masq.tif` | 1-bit, 1 = valid, 0 = no data. The DSM has **no nodata value set**: invalid pixels hold junk Z, so use this mask |
| **Point cloud** | `C3DC_MicMac.ply` | binary PLY, RGB + normals, coordinates minus `OffsetPly` |
| Ortho mosaic | `PIMs-ORTHO/Orthophotomosaic.tif` | only after you run `mm3d Tawny PIMs-ORTHO/` (see below) |

Everything else is an intermediate. The outputs look complicated because C3DC and PIMs2Mnt are wrappers: each runs
5–10 other MicMac programs, and every one of those writes its own working files into its own folder. None of them
cleans up after itself, and the final DSM ends up in a folder named `Tmp`.

## Glossary

Most of the cryptic names are French or jokes, because MicMac was written at IGN, the French mapping agency.

### Commands

| Name | Meaning |
| --- | --- |
| **mm3d** | The single MicMac program; every command is `mm3d <Command>` |
| **C3DC** | Named after the "Culture 3D Cloud" research project ([mm3d.cpp:628](src/CBinaires/mm3d.cpp#L628)); builds the point cloud |
| **PIMs** | **Per Image Matchings**: one depth map computed per image ([mm3d.cpp:629](src/CBinaires/mm3d.cpp#L629)) |
| **PIMs2Ply / PIMs2Mnt** | Turn the per-image matchings into a PLY point cloud / an MNT (height model) |
| **MMByP** | MicMac By Pair: the matching step inside C3DC |
| **MMEnvlop** | MicMac Envelope: min/max depth bounds per image |
| **SMDM** | Simplified Merging of Depth Maps: merges the per-image maps into the DSM |
| **Tapioca, Tapas, Apero, Pastis, Malt, Tawny, Porto** | Not abbreviations. They're named after food and drinks (an IGN joke). Tapioca/Pastis find tie points, Tapas/Apero compute orientations, Malt does matching, Tawny builds the ortho mosaic. |

### French words in file and folder names

| Name | French | Meaning |
| --- | --- | --- |
| **MNT** | Modèle Numérique de Terrain | Elevation model (DTM) |
| **MNE** (in `UrbanMNE`) | Modèle Numérique d'Élévation | Surface model incl. buildings = **DSM** |
| **MEC** (in `DoMEC`) | Mise En Correspondance | Matching |
| **Nuage** | nuage | Point cloud |
| **Prof** (`_Prof.tif`) | profondeur | Depth; in the DSM this is the height Z |
| **Masq** (`_Masq.tif`) | masque | Valid-pixel mask (1 = good) |
| **Correl** | corrélation | Matching quality score |
| **Cptr** | compteur | How many images saw each pixel |
| **Bascule / Basc** | basculer = to tilt | Reprojecting each image's depth map onto the ground grid |
| **Ori** | orientation | Camera positions/angles folder |
| **Compense-Figee** | compensé, figé | Bundle-adjusted, frozen (the name your orientation came with) |
| **Homol** | homologues | Tie points between image pairs |
| **ImSec** | images secondaires | Neighbour images each image is matched with |
| **Foc / AutoCal** | focale / auto-calibration | Focal length / camera calibration file |
| **Chantier** (`LocalChantierDescripteur`) | chantier = worksite | Project folder settings |
| **PC_** (in `PIMs-ORTHO`) | Parties Cachées | Hidden-part (occlusion) masks |
| **Incid_** | incidence | Viewing angle per ortho pixel |
| **Ort_** | ortho | Per-image orthophoto |
| **MTD** | métadonnées | Metadata XML |
| **ZNUM** | probably "Z numérique" | XML giving the DSM grid: origin, pixel size, Z scale |

### General GIS and file terms

| Name | Meaning |
| --- | --- |
| **DSM / DTM** | Digital Surface Model (rooftops, trees) / Digital Terrain Model (bare ground) |
| **Ortho / orthophoto** | Image corrected so it lines up with a map |
| **.tfw** | TIFF World File: 6 numbers giving pixel size and top-left corner |
| **GeoTIFF** | TIFF with georeferencing and the CRS stored inside |
| **CRS / EPSG:2154** | Coordinate Reference System; 2154 is the code for Lambert-93, France's standard projection |
| **nodata** | Pixel value meaning "no measurement" (-9999 in `pims_finish_dsm.sh`) |
| **PLY** | Polygon File Format, the point-cloud file |
| **GDAL** | Geospatial Data Abstraction Library, the raster tools used by `pims_finish_dsm.sh` |
| **DEFLATE / tiled / overviews** | Lossless compression / stored in blocks / built-in low-resolution copies for fast zooming |
| **EO** (`Toulouse_EO`) | Exterior Orientation, i.e. camera positions and angles |
| **UCE** | UltraCam Eagle, the camera name used in the calibration file |

### Command options

| Name | Meaning |
| --- | --- |
| **ZoomF** | Final zoom: 2 = depth computed at half image resolution |
| **DS** (`PIMs-DS2_…`) | DownScale |
| **SH** | Suffix for the Homol folder (e.g. `HomolMasq`) |
| **NKS** (`NKS-Assoc-STD-FOC`) | MicMac's file-naming key system. These two keys tell it the focal length (FOC) and camera (CAM). |
| **Tmp** | Temporary (but `PIMs-TmpBasc` holds your DSM) |

## Which program writes which folder

```
Images (20FE*.tif) + Ori-Compense-Figee5/ + MicMac-LocalChantierDescripteur.xml
 │
 ├─ GrapheHom ............................. overlap.xml                (image pairs)
 ├─ Tapioca File ........................... Homol/, Pastis/            (tie points)
 │
 ├─ C3DC MicMac
 │   ├─ MMByP
 │   │   ├─ AperoChImSecMM (Apero) ......... Ori-Compense-Figee5/ImSec-*, Pt3dIm-*, Pts3d.dat, FileImSel.xml
 │   │   │                                   SauvApero.xml, WarnApero.txt
 │   │   ├─ MMPyram ........................ Pyram/, Tmp-MM-Dir/
 │   │   └─ MICMAC (1 per image) ........... PIMs-MicMac/Nuage-Depth-*
 │   ├─ MMEnvlop ........................... PIMs-MicMac/Nuage-Min-*, Nuage-Max-*
 │   ├─ MergeCloud (+ Nuage2Ply) ........... PIMs-MicMac/Nuage-Merge-*
 │   └─ MergePly ........................... C3DC_MicMac.ply
 │
 └─ PIMs2Mnt MicMac DoOrtho=1
     ├─ Malt UrbanMNE DoMEC=0 .............. PIMs-TmpMnt/               (defines the ground grid only)
     ├─ NuageBascule (1 per image) ......... PIMs-TmpBasc/Bascule*
     ├─ SMDM -> MergeDepthMap .............. PIMs-TmpBasc/PIMs-Merged*  (THE DSM)
     ├─ PIMs2Mnt itself .................... PIMs-TmpBasc/PIMs-ZNUM-Merged.xml, PIMs-Merged_Masq.xml
     └─ MICMAC MM-PIMs2Ortho.xml ........... PIMs-TmpMntOrtho/, PIMs-ORTHO/
```

Each command is also logged with its exact arguments in `mm3d-LogFile.txt`.

## Every file, folder by folder

Sizes are from the Toulouse run. "Delete" means safe to delete once you have copied the results out; MicMac
recreates them if you re-run.

### Project root

| File | Written by | What it is | Keep? |
| --- | --- | --- | --- |
| `C3DC_MicMac.ply` (2.4 GB) | `MergePly` ([CPP_C3DC.cpp:376](src/uti_phgrm/CPP_C3DC.cpp#L376)) | Final point cloud | **Keep** |
| `MicMac-LocalChantierDescripteur.xml` | you / me | Declares focal 123.9 mm + camera `UCE` (the TIFFs have no EXIF) | Keep |
| `overlap.xml` | `GrapheHom Out=overlap.xml` | Image pairs in Tapioca format | Keep (small) |
| `overlap.txt` | not MicMac | Your own image list | – |
| `mm3d-LogFile.txt` | every `mm3d` call | Log of each command, start/end time, success/failure | Keep |
| `MMByPairCAWSI.xml`, `MMByPairFiles.xml` | `MMByP` ([CPP_MMByPair.cpp:45](src/uti_phgrm/CPP_MMByPair.cpp#L45)) | Image list and pairs chosen for matching | Delete |
| `SauvApero.xml` | `Apero` ([CPP_Apero.cpp:77](src/uti_phgrm/CPP_Apero.cpp#L77)) | Copy of the last Apero parameter file | Delete |
| `WarnApero.txt` | `Apero` ([CPP_Apero.cpp:109](src/uti_phgrm/CPP_Apero.cpp#L109)) | Warnings. Yours says "Focal length specified both by xif and NKS-Assoc-STD-FOC": harmless, it means the focal from the descriptor file was used | Delete |
| `cAppliMMByPair_0` | `MMByP` (not traced further) | Empty file | Delete |

### `Homol/` (45 MB) — Tapioca

| File | What it is | Keep? |
| --- | --- | --- |
| `Homol/Pastis<img1>/<img2>.dat` | Binary tie points between img1 and img2 | **Keep** (needed to re-run C3DC) |

### `Pastis/` (321 MB) — Tapioca

| File | What it is | Keep? |
| --- | --- | --- |
| `Resol132_Teta0_<img>`, `LBPpResol132_Teta0_<img>.dat` | Down-sampled images and their key points | Delete |
| `LBPp-Match-*/` | Per-pair raw matches | Delete |

### `Ori-Compense-Figee5/` (19 MB) — your orientation + C3DC additions

| File | Written by | What it is | Keep? |
| --- | --- | --- | --- |
| `Orientation-<img>.xml`, `AutoCal_Foc-123900_Cam-UCE.xml`, `Densite_*.tiff` | your earlier processing | Camera poses and calibration | **Keep** |
| `ImSec-<img>.xml` | `AperoChImSecMM` (key `NKS-Assoc-ImSec`, [DefautChantierDescripteur.xml:507](include/XML_GEN/DefautChantierDescripteur.xml#L507)) | For each image, which images it is matched against | Keep (small) |
| `Pt3dIm-<img>.dat`, `Pts3d.dat` | `AperoChImSecMM` (key `NKS-Assoc-Pts3dIm`) | 3D tie points used to choose those images | Keep (small) |
| `FileImSel.xml` | `AperoChImSecMM` ([Apero-Choix-ImSec.xml:156](include/XML_MicMac/Apero-Choix-ImSec.xml#L156)) | Images kept for matching | Keep (small) |

### `Tmp-MM-Dir/` (12 GB) — MicMac image cache

| File | Written by | What it is | Keep? |
| --- | --- | --- | --- |
| `<img>_Ch1.tif` (463 MB each) | TIFF conversion ([tiff_header.cpp:2554](src/tiff/tiff_header.cpp#L2554)) | Full-resolution 1-channel (grey) copy of each image | Delete (slow to rebuild) |
| `<img>-MDT-4227.xml/.dmp` | metadata reader ([dates.cpp:58](src/util/dates.cpp#L58)) | Cached focal/camera/size per image | Delete |
| `MM-Error-*.txt`, `TestOpenMM*` | failed earlier runs | Error logs | Delete |
| `MkStdMM*` | parallel runner | Generated Makefile | Delete |

### `Pyram/` (18 GB) — MMByP / MICMAC image pyramids

| File | What it is | Keep? |
| --- | --- | --- |
| `<img>DeZoom{2,4,…,128}.tif` | Down-sampled copies used for coarse-to-fine matching ([phgr_epip_cam.cpp:886](src/photogram/phgr_epip_cam.cpp#L886)) | Delete (slow to rebuild) |
| `ImSzW_Dz{4,8,16}<img>.tif` | Pre-computed correlation-window data ([cAppliMICMAC.cpp:995](src/uti_phgrm/MICMAC/cAppliMICMAC.cpp#L995)) | Delete |
| `MasqIm_Dz*_M26460x17004.tif` | Image-extent masks (one per zoom, shared by all images of that size) | Delete |

### `PIMs-MicMac/` (14 GB) — C3DC per-image results

File names come from `cMMByImNM` ([CPP_MMModelInitial.cpp](src/uti_phgrm/CPP_MMModelInitial.cpp)):
`Nuage-<Type>-<img>` + `.xml` / `_Prof.tif` / `_Masq.tif` / `_Label.tif`.

| File | Written by | What it is | Keep? |
| --- | --- | --- | --- |
| `PimsFile.xml`, `PimsEtat.xml` | C3DC | Image list + orientation name. PIMs2Mnt needs both | Keep while you may re-run PIMs2Mnt |
| `Nuage-Depth-<img>.xml` + `_Prof.tif` + `_Masq.tif` (27×) | `MMByP` matching | Depth map per image, 1/4 resolution (6615 × 4251 px, float32). **This is what PIMs2Mnt reads** | Keep while you may re-run PIMs2Mnt |
| `Nuage-Min-*`, `Nuage-Max-*` (27× each) | `MMEnvlop` | Lower/upper depth envelopes, used to filter outliers | Delete |
| `Nuage-Merge-<img>.xml/.ply` + `_Masq.tif` + `_Label.tif` (17×) | `MergeCloud` ([cASAMG.cpp:376](src/uti_phgrm/MergeCloud/cASAMG.cpp#L376)) | Each image's share of the final cloud, after removing points other images see better | Delete (already concatenated into `C3DC_MicMac.ply`) |

Only 17 of 27 images have a `Nuage-Merge-*`. MergeCloud keeps each point from the image that sees it best. My reading
of the code is that the other 10 had nothing unique to contribute, so no file was written for them. That is
expected with heavy overlap and is not an error.

### `PIMs-TmpMnt/` (109 MB) — Malt, ground grid only

| File | What it is | Keep? |
| --- | --- | --- |
| `MMLastNuage.xml` | Ground-grid geometry; the target every depth map is projected onto ([CPP_C3DC.cpp:928](src/uti_phgrm/CPP_C3DC.cpp#L928)) | Delete |
| `Z_Num*_DeZoom*_STD-MALT.xml/.tfw`, `NuageImProf_*`, `Anam_*`, `MM_Avancement_*`, `MemPart.xml` | Malt set-up files. `DoMEC=0` means no matching, so no Z images | Delete |

### `PIMs-TmpBasc/` (26 GB) — the DSM

| File | Written by | What it is | Keep? |
| --- | --- | --- | --- |
| `PIMs-Merged_Prof.tif` + `.tfw` | `SMDM` → `MergeDepthMap` ([FusionCarteProf.cpp:875](src/uti_phgrm/MICMAC/FusionCarteProf.cpp#L875)) | **The DSM** | **Copy out** |
| `PIMs-Merged_Masq.tif` | same | Valid-pixel mask | **Copy out** |
| `PIMs-Merged.xml` | same | DSM descriptor (grid, Z scale) | Copy out |
| `PIMs-Merged_Correl.tif`, `_Cptr.tif` | same | Quality map and number of depth maps per pixel | Copy out if useful |
| `PIMs-ZNUM-Merged.xml`, `PIMs-Merged_Masq.xml` | PIMs2Mnt itself ([CPP_C3DC.cpp:704-713](src/uti_phgrm/CPP_C3DC.cpp#L704-L713)) | Grid descriptors used by the ortho step | Copy out |
| `Bascule<img>.xml` + `_Prof.tif/.tfw` + `_Masq.tif` (27×) | `NuageBascule` | Each depth map re-projected onto the ground grid, before fusion | Delete |

**Re-running PIMs2Mnt deletes this whole folder first** ([CPP_C3DC.cpp:907-911](src/uti_phgrm/CPP_C3DC.cpp#L907-L911)). Copy the
`PIMs-Merged*` files out before you do.

### `PIMs-TmpMntOrtho/` (12 GB) — ortho working folder

| File | What it is | Keep? |
| --- | --- | --- |
| `Z_Num1_DeZoom2_LeChantier.tif` (+ tiles), `Z_000_*` | DSM resampled at ortho resolution | Delete |
| `MasqPC_LeChantier_Num1_<img>*` | Hidden-part masks per image | Delete |
| `Masq_LeChantier_DeZoom*.tif`, `TA_LeChantier.tif` | Area masks | Delete |
| `param_LeChantier_*.xml`, `MakefileParallelisation*`, `MM_Avancement_*`, `MemPart.xml`, `MMLastNuage.xml`, `NuageImProf_*` | Run parameters and progress | Delete |

### `PIMs-ORTHO/` (88 GB) — per-image orthos

| File | Written by | What it is | Keep? |
| --- | --- | --- | --- |
| `Ort_<img>.tif` (282 bytes!) + `Ort_<img>_Tile_<i>_<j>.tif` (9–12 per image, 10240 × 10240 RGB) | MICMAC ortho step | One ortho per image, stored as MicMac **split TIFF**: the small file is a header, the pixels are in the tiles ([tiff_header.cpp:1172](src/tiff/tiff_header.cpp#L1172)). QGIS/GDAL cannot open the header file | Keep until Tawny is done |
| `Ort_<img>.tfw` | same | World file for the whole (un-split) ortho | Keep until Tawny |
| `PC_<img>.tif` + tiles, `PC_<img>.xml` | same | Hidden parts ("parties cachées") per image | Keep until Tawny |
| `Incid_<img>.tif` | same | Viewing-incidence map (low-res, float). Tawny uses it to pick the most vertical image per pixel | Keep until Tawny |
| `MTD-<img>.xml`, `MTDOrtho.xml`, `MTDMaskOrtho.xml` | same | Metadata Tawny reads. `MTDMaskOrtho.xml` points to `../PIMs-TmpBasc/PIMs-Merged_Masq.*`, so Tawny also needs that | Keep until Tawny |
| `Orthophotomosaic.tfw` | ortho step ([PartiesCachees.cpp:903](src/uti_phgrm/MICMAC/PartiesCachees.cpp#L903)) | Georeferencing written in advance for the mosaic Tawny will create | Keep |

## How to use the results

### DSM in QGIS

1. Copy it out: `mkdir -p results && cp PIMs-TmpBasc/PIMs-Merged* results/`
2. Open `results/PIMs-Merged_Prof.tif` in QGIS. The `.tfw` next to it gives position and pixel size.
3. Set the layer CRS to **EPSG:2154** (Lambert-93); the file has no CRS embedded.
4. Mask invalid pixels. With GDAL installed (`pixi add gdal`):
   ```bash
   gdal_calc.py -A results/PIMs-Merged_Prof.tif -B results/PIMs-Merged_Masq.tif \
     --calc="where(B>0, A, -9999)" --NoDataValue=-9999 --type=Float32 \
     --co COMPRESS=DEFLATE --co TILED=YES --outfile=results/DSM_tmp.tif
   gdal_translate -a_srs EPSG:2154 results/DSM_tmp.tif results/DSM_L93.tif
   ```
   Without GDAL, use QGIS Raster Calculator: `"PIMs-Merged_Prof@1" / ("PIMs-Merged_Masq@1" > 0)`.
   Division by zero gives no-data.

### Ortho mosaic

```bash
mm3d Tawny PIMs-ORTHO/        # -> PIMs-ORTHO/Orthophotomosaic.tif (+ the .tfw already there)
```

Two catches, both handled by `pims_ortho.sh` in this repo:

- **Tawny reads the DSM mask from outside `PIMs-ORTHO/`.** `PIMs-ORTHO/MTDMaskOrtho.xml` points to
  `../PIMs-TmpBasc/PIMs-Merged_Masq.tif` and `.xml`. If `PIMs-TmpBasc/` was deleted, Tawny (Porto) stops with
  "can't open file". The script rebuilds both from `results/DSM.tif`.
- **The mosaic is a split TIFF.** Porto sets the tile size to `SzTileResult` = 20000 px
  ([Param-Tawny.xml:136](include/XML_MicMac/Param-Tawny.xml#L136),
  [cAppli_Ortho.cpp:195](src/uti_phgrm/Porto/cAppli_Ortho.cpp#L195)). The Toulouse ortho is 56600 × 46026 px
  at 5 cm (`MTDOrtho.xml`), so you get a header plus `Orthophotomosaic_Tile_<x>_<y>.tif`. The script gives
  each tile a world file and merges them with GDAL into `results/Ortho.tif` (about 7.8 GB uncompressed, so
  BigTIFF).

`mm3d ConvertIm` can also merge a split TIFF (e.g. a single `Ort_<img>.tif`), but MicMac's TIFF writer has no
BigTIFF support, so it is not suitable for an output over 4 GB. Not yet run on this dataset.

### Point cloud in CloudCompare

Open `C3DC_MicMac.ply`. The coordinates are shifted by the `OffsetPly=[574000,6276000,0]` you passed. Add it
back with *Edit → Apply transformation* (translation 574000, 6276000, 0) when exporting. Let CloudCompare keep its
own "global shift" for display.

## Cleaning up (Toulouse run)

After copying `PIMs-TmpBasc/PIMs-Merged*` out and running Tawny:

| Delete | Frees | Cost of deleting |
| --- | --- | --- |
| `PIMs-ORTHO/Ort_*`, `PC_*`, `Incid_*`, `MTD-*` | ~88 GB | Orthos must be redone with PIMs2Mnt |
| `PIMs-TmpBasc/Bascule*` | most of 26 GB | none |
| `Pyram/` | 18 GB | slow rebuild on re-run |
| `Tmp-MM-Dir/` | 12 GB | slow rebuild on re-run |
| `PIMs-TmpMntOrtho/` | 12 GB | none |
| `PIMs-MicMac/Nuage-Min-*`, `Nuage-Max-*`, `Nuage-Merge-*` | several GB | none |
| `Pastis/` | 321 MB | none |
| `PIMs-TmpMnt/` | 109 MB | none |
| `PIMs-MicMac/` (whole) | 14 GB | cannot re-run PIMs2Mnt / PIMs2Ply without redoing C3DC |

Always keep: the images, `Ori-Compense-Figee5/`, `Homol/`, `MicMac-LocalChantierDescripteur.xml`, `overlap.xml`,
and your copied `results/`.
