# my-micmac
Customized MicMac scripts for English speakers like myself

`micmac/` is my fork of [micmacIGN/micmac](https://github.com/micmacIGN/micmac), built in a pixi environment.

## Build

```bash
pixi install
pixi run build          # configure + compile + install into micmac/bin
pixi run mm3d -help     # micmac/bin is on PATH inside pixi
```

## Run

```bash
# Full pipeline, each step timed -> <project>/timings.txt
pixi run ./run_pipeline.sh ~/Documents/projects/Toulouse_EO

# DSM -> results/DSM.tif, then delete MicMac's temp folders (asks before deleting)
./run_cleanup.sh ~/Documents/projects/Toulouse_EO [--delete-ortho] [--delete-pims]
```

`run_pipeline.sh` steps: GrapheHom → Tapioca → C3DC → PIMs2Mnt (DSM) → PIMs2Mnt (Ortho) → Tawny.
Image pattern, orientation and ply offset are set at the top of the script.

## Fork changes

- `PIMs2Mnt Purge=0` skips deleting `PIMs-TmpMnt/` and `PIMs-TmpBasc/` at start, so orthos
  can be made from an existing DSM in a separate run:
  ```bash
  mm3d PIMs2Mnt MicMac                              # DSM only
  mm3d PIMs2Mnt MicMac DoMnt=0 DoOrtho=1 Purge=0    # Ortho only, reuses the DSM
  ```
