# Instructions for AI assistants

This repository describes the virtual machines for one university module, so that SCC Systems can deploy them to the teaching labs. Students launch them with sccvm (https://github.com/scc-systems/tool_sccvm), a terminal UI that reads `sccvm/<module>.toml` and runs the scripts in `bin/`. The person you're helping is an academic, not necessarily a Linux or QEMU specialist. Read `README.md` for the full picture.

## Your job

Help them fill in the template so that `tools/check.sh` passes and the VMs boot. Run `tools/check.sh` after every change and keep going until it reports "All checks passed". Treat its errors as authoritative; don't work around them. The untouched template, with module `sccm_0000` and its example VMs, is a working example module and already passes, so a pass means nothing until the user's own module is in place.

CI on GitHub also runs `shellcheck bin/* tools/*.sh`. If you change a script beyond its `FILL IN` block, run shellcheck too when it's available.

Ask the user rather than guessing for anything you can't know: module code, VM names, CPUs and memory, which VMs need a desktop (SPICE), categories, and assessment dates and times. Ask too for the details in `module.env` (module title, convenor and email, `TERM`, `START_DATE`, `DEPLOY_TO`). `tools/check.sh` only validates `MODULE_CODE`, so placeholder values elsewhere in that file still pass.

## Rules

- The placeholder module code is `sccm_0000`. Replace it with `tools/rename.sh <module_code>` (e.g. `scc_253`), not by hand.
- Launch script filenames are the source of truth. `bin/<module>_launch_<vm>` defines VM `<vm>`. Everything else follows from it:
  - SPICE script: `bin/<module>_spice_<vm>`
  - sccvm entry: `[vms.<module>_<vm>]`, with `name = "<module>_<vm>"`
  - script paths: `$HOME/.<module>/bin/<module>_launch_<vm>` and `$HOME/.<module>/bin/<module>_spice_<vm>`
  - image: `<module>_<vm>.qcow2`
- `<vm>` is lower-case letters, digits and underscores only, and must not contain the words `launch` or `spice`.
- Scripts in `bin/` have no extension and must be executable.
- In each launch script, edit only the `FILL IN` block unless the user needs different virtual hardware. Keep the `LAB_DIR="${LAB_DIR:-$HOME/.<module>}"` line exactly as it is. `VM_NAME` comes from the filename; don't add it back.
- Every VM needs its own image filename, MAC address, QMP port and SPICE port. Continue the existing sequences (MAC `52:54:00:00:00:0N`, QMP `900N`, SPICE `800N`).
- A SPICE script's `SPICE_PORT` must match its launch script's.
- `sccvm/<module>.toml` is edited directly; there is no generator. Valid action modes are `vm`, `spice`, `both` and `vm_with_kali_spice`. `section_actions` names must match a `category` used by a VM. Access-control times are RFC3339 with a timezone, e.g. `2026-02-16T09:00:00+00:00` (`+01:00` during BST, which runs from the last Sunday in March to the last Sunday in October).
- Fill in `module.env`. Put anything unusual (extra disks, UEFI, networking between VMs, internet access) in `NOTES` so Systems know about it.

## Never

- Never commit VM images or archives (`.qcow2`, `.iso`, `.ova`, `.vmdk`, `.xz`, `.zip`...), and never use `git add -f` on them. They go on the LUNA share, uncompressed.
- Never edit `tools/`, `.github/` or `.gitignore`, and never weaken or bypass `tools/check.sh`.
- Never give two VMs the same image filename.

## Done means

- `tools/check.sh` passes.
- The user has booted each VM locally with `LAB_DIR="$PWD" NET_MODE=user bin/<module>_launch_<vm>` (Linux with KVM). You can't confirm this for them, so ask.
- The images listed at the end of `tools/check.sh` have been uploaded to LUNA (see README step 7).
