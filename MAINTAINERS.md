# Maintainer notes (Systems)

How to get a filled-in lab repo into an Ansible module role. The reference implementation is `linux/roles/events/teaching/modules/scc_253/`.

## Giving an academic a repo

Most academics aren't in `scc-systems`, so create the repo for them:

```bash
gh repo create scc-systems/<module>_lab --private --template scc-systems/sccvm_lab_template
gh api -X PUT repos/scc-systems/<module>_lab/collaborators/<their-gh-user> -f permission=push
```

## Hand-off checklist

1. `tools/check.sh` passes on their default branch (CI badge / Actions tab).
2. Every image listed by `tools/check.sh` is on `<LUNA_SHARE_PATH>/<module>/`, with the exact filename, as uncompressed qcow2.
3. `module.env` is filled in: dates, `DEPLOY_TO`, `NOTES`.

## Mapping into the role

| Lab repo | Role (`linux/roles/events/teaching/modules/<module>/`) |
|---|---|
| `bin/*` | `files/bin/*`, deployed with `copy` to `<install_dir>/bin/` mode 0755. The scripts need no templating: they resolve `LAB_DIR` to `$HOME/.<module>` |
| `sccvm/<module>.toml` | `templates/sccvm_config.toml.j2`, deployed to `/etc/sccvm/conf.d/<module>.toml`. Turn the `access_control` dates into `defaults/main.yml` vars, as `scc_253_assessment_start/end` does |
| image filenames (`IMAGE=`) | a `defaults/main.yml` list, downloaded to `<install_dir>/images/` |
| LUNA images | asset server `teaching/{{ scc_academic_year }}/<module>/` |
| `module.env` | the `Module Details` debug task + metapackages in `tasks/<year>.yml` |

Directory layout on the host must match what the scripts expect:

```
/opt/<module>/              copied per user to ~/.<module>/ at login
├── bin/<module>_*          from bin/
└── images/<image>.qcow2    flat, unique names
```

Reuse from scc_253:
- `templates/scc253_setup.sh.j2` and the `/etc/skel/.profile` hook in `tasks/lab/2025_2026.yml` (per-user `cp -a --reflink=auto` copy, which is a cheap reflink on the btrfs lab machines but a full copy anywhere else, so check the filesystem on new targets)
- `tasks/lab/deploy_sccvm_config.yml` (installs sccvm and drops the TOML)
- the checksum task

For VDI (`DEPLOY_TO=vdi|both`), scc_253 uses `sccvm_config_vdi.toml.j2` with script paths under the install dir rather than `$HOME`. Do the same here: replace `$HOME/.<module>` with `{{ <module>_install_dir }}` in the VDI copy, and set `LAB_DIR` accordingly.

## sccvm behaviour worth knowing

- The module tab name is the TOML filename in upper case, so `scc_253.toml` becomes `SCC_253`. `module = "..."` in each VM must match it or be omitted.
- sccvm runs `script` / `spice_script` directly with no arguments, which is why every VM has its own self-contained SPICE script, as in scc_253.
- Action modes: `vm`, `spice`, `both`, `vm_with_kali_spice` (SPICE only for VMs whose name contains "kali").
