#!/bin/bash
# Validate this lab repo before handing it to Systems.
# Usage: tools/check.sh        (run from anywhere inside the repo)
# Needs: bash, python3 >= 3.11 (for tomllib). Exits non-zero if anything is wrong.
#
# Problems are reported as ERROR (the check fails) or WARN (it still passes).
# What is checked:
#
# Module code
#   - MODULE_CODE in module.env looks like scc_253 or sccm_5550 (lower case).
#   - Once MODULE_CODE is no longer sccm_0000, no file name or contents still
#     contains sccm_0000 / SCCM_0000 (a half-finished rename). The READMEs,
#     tools/, .github/ and images/ are skipped as they mention it on purpose.
#
# Scripts in bin/
#   - Every name is <module>_launch_<vm> or <module>_spice_<vm>, with no file
#     extension, and is executable.
#   - There is at least one <module>_launch_<vm> script.
#
# Launch scripts (bin/<module>_launch_<vm>)
#   - The filename is the VM name: bin/<module>_launch_<vm>, where <vm> uses
#     only lower-case letters, digits and underscores. The script reads VM_NAME from
#     its own filename, so it is not filled in by hand.
#   - The FILL IN block sets IMAGE, CPUS, MEMORY, MAC, QMP_PORT and SPICE_PORT,
#     none of them empty.
#   - The script contains LAB_DIR="${LAB_DIR:-$HOME/.<module>}" so that, once
#     deployed, it finds the student's own copy of the images.
#   - IMAGE is a bare filename ending in .qcow2 (warning if it is not prefixed
#     <module>_<vm>.qcow2, matching the script name).
#   - MAC looks like 52:54:00:xx:xx:xx, and ports are numbers in 1025-65535.
#
# Uniqueness across all VMs
#   - No image filename is used by more than one VM.
#   - No MAC address is used more than once.
#   - No port is used more than once (QMP and SPICE ports together).
#
# SPICE scripts (bin/<module>_spice_<vm>)
#   - Each has a matching bin/<module>_launch_<vm>, and its SPICE_PORT is the
#     same as that launch script's.
#
# sccvm configuration (sccvm/<module>.toml)
#   - It is the only file in sccvm/ and parses as TOML.
#   - Every launch script has an entry [vms.<module>_<vm>], and every entry
#     has a launch script.
#   - Each entry's script is $HOME/.<module>/bin/<module>_launch_<vm>, and its
#     spice_script, if set, is $HOME/.<module>/bin/<module>_spice_<vm>.
#   - For each entry:
#       name matches the table key;
#       module, if set, is the module code in upper case (sccvm takes the
#       module from the upper-cased filename);
#       script is present;
#       script and spice_script start with $HOME/.<module>/bin/ and point at a
#       file that exists in bin/.
#   - access_control windows have start and end as full timestamps with a
#     timezone (2026-02-16T09:00:00+00:00), with start before end. Windows
#     using override, force_unlock or force_lock are not checked.
#   - Warning if an access_control offset isn't UK time on that date
#     (+00:00 in GMT, +01:00 in BST), e.g. +00:00 for a date in July.
#   - module.actions use a valid mode (vm, spice, both, vm_with_kali_spice)
#     and only name VMs that exist.
#   - module.section_actions name a category that some VM actually uses, and
#     use a valid mode.
#   - Warning for any script in bin/ that the TOML never refers to, as
#     students would not see it.
#
# Images kept out of git
#   - No tracked file has an image or archive extension (.qcow2, .iso, .ova,
#     .vmdk, .xz, .zip, ...), which catches anything added with git add -f.
#
# Hand-off summary
#   - Lists every image filename the launch scripts refer to, i.e. exactly what
#     must be uploaded to LUNA, and whether each is present in images/ (with
#     its size).
#
# Not checked: whether QEMU actually boots the image, whether the copy on LUNA
# matches the one in images/, or whether the QEMU hardware options are sensible.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! python3 -c 'import sys, tomllib; sys.exit(sys.version_info < (3, 11))' 2>/dev/null; then
	echo "tools/check.sh needs python3 3.11 or newer (for tomllib)." >&2
	exit 2
fi

# module.env is plain shell assignments
# shellcheck source=/dev/null
source "$ROOT/module.env"

TRACKED_FILES=""
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	TRACKED_FILES="$(git -C "$ROOT" ls-files)"
fi

export ROOT MODULE_CODE TRACKED_FILES
exec python3 -I - <<'PY'
import os
import re
import sys
import tomllib
from datetime import datetime
try:
    from zoneinfo import ZoneInfo
    UK = ZoneInfo("Europe/London")
except Exception:  # no tz database: skip the UK offset warning
    UK = None
from pathlib import Path

ROOT = Path(os.environ["ROOT"])
CODE = os.environ.get("MODULE_CODE", "")
TRACKED = [f for f in os.environ.get("TRACKED_FILES", "").splitlines() if f]
TEMPLATE_CODE = "sccm_0000"
IMAGE_EXTS = (".qcow2", ".img", ".raw", ".iso", ".vmdk", ".vdi", ".vhd", ".vhdx", ".ova", ".ovf",
              ".xz", ".gz", ".zst", ".zip", ".7z", ".tar", ".bz2")
MODES = {"vm", "spice", "both", "vm_with_kali_spice"}

tty = sys.stdout.isatty()
def c(code, s): return f"\033[{code}m{s}\033[0m" if tty else s

errors, warnings = [], []
def err(msg): errors.append(msg)
def warn(msg): warnings.append(msg)

# 1. Module code ------------------------------------------------------------
if not re.fullmatch(r"scc(m)?_[0-9]+", CODE):
    err(f"module.env: MODULE_CODE={CODE!r} must look like scc_253 or sccm_5550 (lower case)")

if CODE != TEMPLATE_CODE:
    skip = {"README.md", "MAINTAINERS.md", "CLAUDE.md", "AGENTS.md"}
    for p in sorted(ROOT.rglob("*")):
        rel = p.relative_to(ROOT).as_posix()
        if p.is_dir() or rel in skip or rel.startswith((".git/", ".github/", "tools/", "images/")):
            continue
        if TEMPLATE_CODE in rel:
            err(f"{rel}: filename still contains '{TEMPLATE_CODE}' - rename it to use '{CODE}'")
        try:
            text = p.read_text()
        except (UnicodeDecodeError, OSError):
            continue
        for n, line in enumerate(text.splitlines(), 1):
            if TEMPLATE_CODE in line or TEMPLATE_CODE.upper() in line:
                err(f"{rel}:{n}: still contains '{TEMPLATE_CODE}' - replace with '{CODE}'")

# 2. bin/ files ------------------------------------------------------------
bin_dir = ROOT / "bin"
bin_files = sorted(p for p in bin_dir.iterdir() if p.is_file()) if bin_dir.is_dir() else []
for p in bin_files:
    if not p.name.startswith(f"{CODE}_"):
        err(f"bin/{p.name}: script names must start with '{CODE}_'")
    if not os.access(p, os.X_OK):
        err(f"bin/{p.name}: not executable - run: chmod +x bin/{p.name}")
    if p.suffix:
        err(f"bin/{p.name}: no file extension please (e.g. {CODE}_launch_kali, not .sh)")

def fill_in(path):
    """Return the KEY=value assignments from a script's FILL IN block."""
    out = {}
    for line in path.read_text().splitlines():
        m = re.match(r'^([A-Z_]+)=("?)([^"#]*?)\2\s*(#.*)?$', line)
        if m:
            out.setdefault(m.group(1), m.group(3).strip())
    return out

launch = {p.name[len(f"{CODE}_launch_"):]: p for p in bin_files if p.name.startswith(f"{CODE}_launch_")}
spice = {p.name[len(f"{CODE}_spice_"):]: p for p in bin_files if p.name.startswith(f"{CODE}_spice_")}
for p in bin_files:
    if p.name.startswith(f"{CODE}_") and not p.name.startswith((f"{CODE}_launch_", f"{CODE}_spice_")):
        err(f"bin/{p.name}: should be {CODE}_launch_<vm> or {CODE}_spice_<vm>")

if not launch:
    err(f"bin/: no launch scripts found (expected bin/{CODE}_launch_<vm>)")

# The launch script filename is the source of truth for VM names:
# bin/<module>_launch_<vm> is VM <vm>; its sccvm entry is [vms.<module>_<vm>]
# and its suggested image is <module>_<vm>.qcow2.
VM_RE = re.compile(r"[a-z0-9]+(_[a-z0-9]+)*")
def toml_key(vm): return f"{CODE}_{vm}"
for vm, p in launch.items():
    if not VM_RE.fullmatch(vm):
        err(f"bin/{p.name}: VM name {vm!r} must use only lower-case letters, digits and underscores")
    elif {"launch", "spice"} & set(vm.split("_")):
        err(f"bin/{p.name}: VM name {vm!r} can't contain 'launch' or 'spice' as a word")

# 3. Launch scripts: unique image / MAC / ports --------------------------------
images, macs, ports = {}, {}, {}
for vm, p in launch.items():
    v = fill_in(p)
    rel = f"bin/{p.name}"
    for key in ("IMAGE", "CPUS", "MEMORY", "MAC", "QMP_PORT", "SPICE_PORT"):
        if not v.get(key):
            err(f"{rel}: FILL IN value {key}= is missing or empty")
    lab_line = f'LAB_DIR="${{LAB_DIR:-$HOME/.{CODE}}}"'
    if lab_line not in p.read_text():
        err(f"{rel}: must contain the line {lab_line}")

    img = v.get("IMAGE", "")
    if img:
        if "/" in img:
            err(f"{rel}: IMAGE={img!r} must be a bare filename (no folders) - all images live in images/")
        if not img.endswith(".qcow2"):
            err(f"{rel}: IMAGE={img!r} must be an uncompressed .qcow2")
        elif img != f"{CODE}_{vm}.qcow2":
            warn(f"{rel}: IMAGE={img!r} - suggest {CODE}_{vm}.qcow2 to match the script name")
        images.setdefault(img, []).append(rel)

    mac = v.get("MAC", "")
    if mac:
        if not re.fullmatch(r"52:54:00(:[0-9a-fA-F]{2}){3}", mac):
            err(f"{rel}: MAC={mac!r} should look like 52:54:00:xx:xx:xx")
        macs.setdefault(mac.lower(), []).append(rel)

    for key in ("QMP_PORT", "SPICE_PORT"):
        port = v.get(key, "")
        if port:
            if not port.isdigit() or not 1024 < int(port) < 65536:
                err(f"{rel}: {key}={port!r} is not a valid port")
            ports.setdefault(port, []).append(f"{rel} ({key})")

    if vm in spice:
        sp = fill_in(spice[vm]).get("SPICE_PORT")
        if sp != v.get("SPICE_PORT"):
            err(f"bin/{spice[vm].name}: SPICE_PORT={sp} does not match {rel} SPICE_PORT={v.get('SPICE_PORT')}")

for img, where in images.items():
    if len(where) > 1:
        err(f"image filename {img!r} is used by more than one VM: {', '.join(where)} - every VM needs its own uniquely named image")
for mac, where in macs.items():
    if len(where) > 1:
        err(f"MAC {mac} is used more than once: {', '.join(where)}")
for port, where in ports.items():
    if len(where) > 1:
        err(f"port {port} is used more than once: {', '.join(where)}")

for vm, p in spice.items():
    if vm not in launch:
        err(f"bin/{p.name}: no matching bin/{CODE}_launch_{vm}")

# 4. sccvm TOML ---------------------------------------------------------------
tomls = sorted((ROOT / "sccvm").glob("*.toml"))
expected_toml = ROOT / "sccvm" / f"{CODE}.toml"
if tomls != [expected_toml]:
    err(f"sccvm/: expected exactly one file, sccvm/{CODE}.toml (found: {', '.join(t.name for t in tomls) or 'none'})")

referenced = set()
if expected_toml.exists():
    try:
        cfg = tomllib.loads(expected_toml.read_text())
    except tomllib.TOMLDecodeError as e:
        err(f"sccvm/{CODE}.toml: not valid TOML - {e}")
        cfg = {}

    vms = cfg.get("vms", {})
    if not vms and cfg:
        err(f"sccvm/{CODE}.toml: no [vms.*] entries")
    prefix = f"$HOME/.{CODE}/bin/"
    categories = set()
    by_key = {toml_key(vm): vm for vm in launch}
    for vm in launch:
        if toml_key(vm) not in vms:
            err(f"bin/{CODE}_launch_{vm}: needs an entry [vms.{toml_key(vm)}] in sccvm/{CODE}.toml")
    for key, vm in vms.items():
        where = f"sccvm/{CODE}.toml [vms.{key}]"
        if key not in by_key:
            err(f"{where}: no matching launch script - [vms.{CODE}_<vm>] needs bin/{CODE}_launch_<vm>")
        else:
            expected = {"script": f"{prefix}{CODE}_launch_{by_key[key]}",
                        "spice_script": f"{prefix}{CODE}_spice_{by_key[key]}"}
            for field, want in expected.items():
                if vm.get(field) and vm[field] != want:
                    err(f"{where}: {field} must be {want!r}")
        if vm.get("name") != key:
            err(f"{where}: name = {vm.get('name')!r} must equal the table key {key!r}")
        if vm.get("module") and vm["module"] != CODE.upper():
            err(f"{where}: module = {vm['module']!r} must be {CODE.upper()!r} (or removed)")
        if vm.get("category"):
            categories.add(vm["category"])
        if not vm.get("script"):
            err(f"{where}: script is required")
        for field in ("script", "spice_script"):
            path = vm.get(field)
            if not path:
                continue
            if not path.startswith(prefix):
                err(f"{where}: {field} must start with {prefix}")
                continue
            name = path[len(prefix):]
            referenced.add(name)
            if not (bin_dir / name).is_file():
                err(f"{where}: {field} points at bin/{name}, which does not exist")
        for period, ac in vm.get("access_control", {}).items():
            aw = f"{where} access_control.{period}"
            if ac.get("override") or ac.get("force_unlock") or ac.get("force_lock"):
                continue
            times = {}
            for f in ("start", "end"):
                try:
                    t = datetime.fromisoformat(str(ac.get(f, "")))
                    if t.tzinfo is None:
                        raise ValueError
                    times[f] = t
                except ValueError:
                    err(f"{aw}: {f} = {ac.get(f)!r} must be like 2026-02-16T09:00:00+00:00")
            if len(times) == 2 and times["start"] >= times["end"]:
                err(f"{aw}: start must be before end")
            for f, t in times.items():
                if UK and t.utcoffset() != t.replace(tzinfo=UK).utcoffset():
                    uk = t.replace(tzinfo=UK).strftime("%z")
                    warn(f"{aw}: {f} = {ac.get(f)!r} - UK time on that date is {uk[:3]}:{uk[3:]}, not {t.strftime('%z')[:3]}:{t.strftime('%z')[3:]}")

    module = cfg.get("module", {})
    for i, action in enumerate(module.get("actions", []), 1):
        aw = f"sccvm/{CODE}.toml module.actions #{i} ({action.get('name', '?')})"
        if action.get("mode", "vm") not in MODES:
            err(f"{aw}: mode must be one of {sorted(MODES)}")
        for n in action.get("vm_names", []):
            if n not in vms:
                err(f"{aw}: vm_names entry {n!r} is not a [vms.*] entry")
    for cat, sa in module.get("section_actions", {}).items():
        aw = f"sccvm/{CODE}.toml module.section_actions.{cat!r}"
        if cat not in categories:
            err(f"{aw}: no VM has category = {cat!r}")
        if sa.get("mode", "vm") not in MODES:
            err(f"{aw}: mode must be one of {sorted(MODES)}")

for p in bin_files:
    if p.name not in referenced:
        warn(f"bin/{p.name}: not referenced from sccvm/{CODE}.toml - students won't see it")

# 5. Nothing image-like committed --------------------------------------------
for f in TRACKED:
    if f.lower().endswith(IMAGE_EXTS):
        err(f"{f}: VM images/archives must not be committed - run: git rm --cached '{f}'")

# Report ---------------------------------------------------------------------
for w in warnings:
    print(c("1;33", "WARN  ") + w)
for e in errors:
    print(c("1;31", "ERROR ") + e)

print()
print(c("1", "VM images to upload to LUNA (uncompressed .qcow2, exact filenames):"))
img_dir = ROOT / "images"
for img in sorted(images):
    p = img_dir / img
    if p.is_file():
        status = c("32", f"found in images/ ({p.stat().st_size / 1024**3:.1f} GB)")
    else:
        status = c("33", "not in images/ (fine if already uploaded)")
    print(f"  - {img}  {status}")

print()
if errors:
    print(c("1;31", f"{len(errors)} error(s) - fix these before handing over."))
    sys.exit(1)
print(c("1;32", "All checks passed.") + (f" ({len(warnings)} warning(s))" if warnings else ""))
PY
