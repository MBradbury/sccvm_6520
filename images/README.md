# images/

Put your VM images here for local testing. Apart from this README, nothing in this folder is committed; `.gitignore` excludes it.

- Images live in one flat folder, so every filename must be unique. We suggest naming each one after its launch script, `<module>_<vm>.qcow2`, for example `sccm_5550_kali.qcow2`.
- The filename must match the `IMAGE=` line in the corresponding `bin/<module>_launch_<vm>` script.
- Use plain qcow2, and upload it to LUNA uncompressed.

`tools/check.sh` lists the images it expects and whether each one is present here.
