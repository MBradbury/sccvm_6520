# sccvm lab template

This repository is a template for describing the virtual machines a module needs in the SCC teaching labs. You fill it in and test it, then pass it to Systems. We then deploy it so that students can start your VMs from `sccvm` on any lab machine.

> Using an AI assistant (Claude, Copilot, ChatGPT and so on) to fill this in is perfectly fine. `CLAUDE.md`, also available as `AGENTS.md`, sets out the rules for the assistant: point it at that file first, and let `tools/check.sh` be the judge of whether the result is right. You're still the one who knows what the lab needs, so check what it writes, and make sure each VM actually boots before handing over.

You'll need a Linux machine with KVM (see step 5), a GitHub account, and `python3` 3.11 or newer to run `tools/check.sh`.

## What is sccvm?

[sccvm](https://github.com/scc-systems/tool_sccvm) is a small terminal application, built with Go and Bubble Tea, that students use to launch the VMs for their modules. Each module has its own tab, VMs are grouped into categories (for example "Main Lab" or "Week 14 Assessment"), and a few keystrokes start a VM or open its graphical console. It can also restrict a VM to a time window, which is how assessment VMs are kept locked until the assessment begins.

sccvm doesn't run VMs itself. It reads a configuration file for each module and calls the launch scripts that file points to. This repository holds those scripts and that configuration file.

## How it fits together

```
  YOU                                SYSTEMS                     LAB MACHINE
  ---                                -------                     -----------

  this repository  ---------------> Ansible role  -----------> /etc/sccvm/conf.d/<module>.toml
    module.env                       for <module>                /opt/<module>/bin/...
    bin/<module>_launch_<vm>              |                       /opt/<module>/images/...
    bin/<module>_spice_<vm>               |                              |
    sccvm/<module>.toml                   |                              | reflink copy (btrfs) to
                                          |                              | the student's home on
                                          |                              | first login
  VM images (.qcow2)                      |                              v
    uploaded to LUNA  -------------------'                       ~/.<module>/bin/...
                                                                 ~/.<module>/images/...
                                                                         |
                                                                         |
                    student runs `sccvm`, picks your module tab ---------'
                                          |
                          +---------------+----------------+
                          |                                |
                  launch script                      SPICE script
                  starts QEMU with the               opens remote-viewer on
                  student's copy of the image        the VM's console
```

Each student gets a private copy of the images in their home directory, so nothing they do inside a VM affects anyone else, and a VM can be reset by deleting that copy. The lab machines use btrfs, and the copy is made with `cp --reflink`, so it is close to instant and shares its blocks with the original. A student's copy only takes up extra disk space as the VM changes it, which is why large images are not a problem.

## What you provide

| Where | What |
|---|---|
| `module.env` | Module code, title, convenor, term dates and notes for Systems |
| `bin/` | A launch script for each VM, and a SPICE script for each VM with a desktop |
| `sccvm/<module>.toml` | How the VMs appear in sccvm: names, categories, quick actions and any assessment windows |
| LUNA share | The VM images themselves |

VM images are never committed to git. The `.gitignore` already excludes `.qcow2`, `.iso`, `.ova`, compressed archives and the whole of `images/`.

### A note on names

The launch script filenames are the source of truth. `bin/<module>_launch_<vm>` defines a VM called `<vm>`, and everything else about that VM is named after it: its SPICE script, its entry in `sccvm/<module>.toml` and, by convention, its image.

`sccvm/<module>.toml` is edited directly, by you or your assistant, rather than generated. Labs vary a good deal (shared VMs, assessments with time windows, groups of VMs launched together), and a generator would either get in the way or need as many options as the file itself. Whoever edits it, `tools/check.sh` makes sure it agrees with the scripts in `bin/`.

## Steps

### 1. Make your own copy

Use the "Use this template" button on GitHub to create a new repository. If you can't see the button, ask Systems and we'll create one for you.

### 2. Set your module code

Fill in `module.env`, then replace the `sccm_0000` placeholder throughout the repository:

```bash
tools/rename.sh scc_253        # your module code in lower case, e.g. scc_253 or sccm_5550
```

### 3. Write a launch script for each VM

Each VM is defined by its launch script, `bin/<module>_launch_<vm>`. The `<vm>` part of the filename is the VM's name everywhere else, so choose it with care and use only lower-case letters, digits and underscores, for example `scc_253_launch_kali` or `scc_253_launch_assessment_kali`.

Copy one of the examples, rename it, and change only the `FILL IN` block at the top:

```bash
VM_DISPLAY_NAME="Kali Linux"
IMAGE="scc_253_kali.qcow2"   # must be unique within this repository
CPUS=2
MEMORY="4096M"
MAC="52:54:00:00:00:03"      # unique per VM
QMP_PORT=9003                # unique per VM
SPICE_PORT=8003              # unique per VM
BRIDGE="br1"
```

A few rules apply:

- Every image needs a filename that is unique within the repository. All images end up in one folder, so two VMs can't both use `kali.qcow2`, even if one is for the main lab and the other for an assessment. We suggest naming it after the launch script, `<module>_<vm>.qcow2`, for example `scc_253_kali.qcow2` and `scc_253_assessment_kali.qcow2`.
- Images should be uncompressed qcow2, and self-contained. Run `qemu-img info <image>.qcow2` and make sure there is no `backing file` line. An image that depends on a backing file boots on your machine but not in the lab. `qemu-img convert -O qcow2 <image> <new>.qcow2` gives you a standalone copy, and it also converts VirtualBox and VMware disks (`.vdi`, `.vmdk`). For an `.ova`, extract it first (it is a tar archive) and convert the `.vmdk` inside.
- MAC addresses, QMP ports and SPICE ports must each be unique across your VMs. Counting up from the examples is fine.
- Script names have no `.sh` extension and must be executable (`chmod +x`).
- If you need different virtual hardware (extra disks, UEFI, more network cards), edit the `qemu-system-x86_64` command and mention it under `NOTES` in `module.env`.

For each VM with a desktop, copy one of the `bin/<module>_spice_<vm>` scripts and set its `SPICE_PORT` to match the launch script.

Delete any example scripts you don't use.

### 4. Describe the VMs for sccvm

Edit `sccvm/<module>.toml`. Each launch script needs a matching `[vms.<module>_<vm>]` entry. For `bin/scc_253_launch_assessment_kali` that is `[vms.scc_253_assessment_kali]`, with `script` pointing at `bin/scc_253_launch_assessment_kali` and `spice_script` (if it has a desktop) at `bin/scc_253_spice_assessment_kali`. The `category` field groups VMs under headings, and `module.actions` adds buttons that start several VMs together.

For assessments, add an `access_control` window; there's a commented example at the end of the file. Students can only start those VMs between `start` and `end`.

### 5. Test on your own machine

This step assumes you're testing on your own Linux machine, where you have root (or `sudo`) to install packages and, if you want it, set up a network bridge. The lab machines aren't suitable, since you won't have root there. The machine needs hardware virtualisation enabled (KVM, so `/dev/kvm` exists and your user can use it), and enough memory and disk for the VMs you're running at once. macOS and Windows won't work, as the launch scripts rely on KVM.

You'll also need QEMU, `remote-viewer` and `nc`. On Debian or Ubuntu these are `qemu-system-x86`, `virt-viewer` and `netcat-openbsd`; on Fedora, `qemu-kvm`, `virt-viewer` and `nmap-ncat`.

Put your images in `images/` (git ignores them), then:

```bash
LAB_DIR="$PWD" NET_MODE=user bin/scc_253_launch_kali     # start the VM; it keeps this terminal
bin/scc_253_spice_kali                                   # in a second terminal: open its console
```

Testing boots the image itself, so whatever you do in the VM (logs, shell history, files) is in the copy students get. If you'd rather keep the image as it was, test on a copy and upload the original. Either way, shut the VM down from inside the guest rather than terminating with Ctrl+C.

The two variables in front of the launch script are environment variables that override its defaults for that one command only. Nothing in the script needs editing, and on the lab machines neither is set, so the defaults apply.

- `LAB_DIR="$PWD"` makes the script look for images in this repository's `images/` folder. By default it uses `$HOME/.<module>/images/`, the student's own copy on a lab machine.
- `NET_MODE=user` gives the VM QEMU's simple NAT networking instead of the default, which attaches it to the `br1` bridge used in the labs. You don't need to create a bridge, but your VMs can't see each other in this mode.

If you need to test VMs talking to each other, you can create `br1` locally and leave out `NET_MODE`:

```bash
sudo ip link add br1 type bridge
sudo ip link set br1 up
echo "allow br1" | sudo tee -a /etc/qemu/bridge.conf    # lets QEMU attach VMs to br1

LAB_DIR="$PWD" bin/scc_253_launch_kali
LAB_DIR="$PWD" bin/scc_253_launch_linux
```

The bridge has no DHCP or internet access unless you add them, so give the VMs whatever addresses they would use in the lab. It disappears on reboot; `sudo ip link del br1` removes it sooner.

### 6. Check and push

```bash
tools/check.sh
```

Fix anything reported as an error and read any warnings. Its output ends with the list of image files Systems will expect to find on LUNA. The same check runs on GitHub each time you push, along with [shellcheck](https://www.shellcheck.net/) on the scripts. If you've changed a script beyond its `FILL IN` block, run `shellcheck bin/*` too when you have it installed.

In brief, it checks that:

- the module code is set and the `sccm_0000` placeholder has been replaced everywhere
- every script in `bin/` is named after the module, has no extension and is executable
- each launch script fills in all the required values and uses an uncompressed `.qcow2` image
- image filenames, MAC addresses and ports are not shared between VMs
- each SPICE script uses the same port as its VM's launch script
- every launch script has a matching entry in `sccvm/<module>.toml`, named after its filename
- `sccvm/<module>.toml` is valid, every VM in it points at a script that exists, and assessment dates are well formed
- no VM image or archive has been committed to git

The full list, and what it does not check, is in the comment at the top of `tools/check.sh`.

### 7. Upload the images to LUNA

Shut each VM down cleanly, then copy every image listed by `tools/check.sh` to `<LUNA_SHARE_PATH>/<module>/`. Upload the plain `.qcow2` files rather than zipped or compressed versions, and keep the filenames exactly as they appear in your launch scripts.

### 8. Let Systems know

Email Systems with the URL of your repository, confirmation that the images are on LUNA, and the date students will first need the VMs.

## Repository layout

```
module.env                    module details
bin/<module>_launch_<vm>      QEMU launch script, one per VM
bin/<module>_spice_<vm>       SPICE console script, one per VM with a desktop
sccvm/<module>.toml           sccvm configuration for the module
images/                       local test images, ignored by git
tools/check.sh                validation, run before handing over
tools/rename.sh               one-off rename of the sccm_0000 placeholder
CLAUDE.md, AGENTS.md          instructions for AI assistants
```
