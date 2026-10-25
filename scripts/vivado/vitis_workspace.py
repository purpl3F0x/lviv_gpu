"""Vitis workspace of a block design under bd/<name>/: a platform made from the design's XSA
(standalone on one processor) and an application whose sources stay where they are in the repo,
so what is edited in the IDE is edited in git. Used by bd.mk.

Usage: vitis -s vitis_workspace.py <args.json> <stage>
  workspace  create the platform and the application if they are missing, otherwise give the
             platform the XSA again (bd.mk runs it when the XSA is newer); build the platform, and
             give the application's launch configurations its bitstream and psu_init.tcl
  sources    list in the application every .c and .h of the app_src directories and every .h of
             app_includes, so the IDE shows them all, and make both its include path (bd.mk runs it
             when a file is added or removed there)
  build      build the application
args.json (written by bd.mk): workspace, xsa, platform, cpu, domain, app, app_src, app_includes,
and the files that say a stage succeeded: stamp (workspace), sources_stamp (sources), built (build)
"""

import glob
import json
import os
import shutil
import sys
import time

import vitis

with open(sys.argv[1]) as f:
    args = json.load(f)
stage = sys.argv[2]

workspace = args["workspace"]
domain = args["domain"]
export = os.path.join(workspace, args["platform"], "export", args["platform"])
xpfm = os.path.join(export, args["platform"] + ".xpfm")
bsp_lib = os.path.join(export, "sw", domain, "lib", "libxil.a")

# vitis -s drops the script's exit code on Windows, so bd.mk checks for this file instead: removed
# first, written once the stage has succeeded.
done_file = {"workspace": args["stamp"], "sources": args["sources_stamp"], "build": args["built"]}[stage]


def open_workspace(client):
    # The server of a vitis run that has just ended holds the workspace for a few more seconds.
    for attempt in range(30):
        try:
            client.set_workspace(path=workspace)
            return
        except Exception as e:
            if "already in use" not in str(e) or attempt == 29:
                raise
            time.sleep(2)


def exists(component):
    return os.path.isfile(os.path.join(workspace, component, "vitis-comp.json"))


def make_workspace(client):
    if exists(args["platform"]):
        platform = client.get_component(name=args["platform"])
        platform.update_hw(hw_design=args["xsa"])
    else:
        platform = client.create_platform_component(
            name=args["platform"], hw_design=args["xsa"], os="standalone", cpu=args["cpu"],
            domain_name=domain)
    # build() does not report a failed BSP build: the BSP's library must be back in the export.
    if os.path.exists(bsp_lib):
        os.remove(bsp_lib)
    platform.build()
    if not os.path.isfile(bsp_lib) or not os.path.isfile(xpfm):
        raise RuntimeError(f"{args['platform']} did not build")

    if not exists(args["app"]):
        client.create_app_component(name=args["app"], platform=xpfm, domain=domain)
    refresh_launch_files()


def refresh_launch_files():
    # The IDE's launch configurations program copies of the platform's bitstream and psu_init.tcl,
    # made in <app>/_ide/ with them, and do not refresh them when the platform takes a new XSA: the
    # board would run the new software on the old hardware. The platform keeps them below hw/
    # (hw/sdt/ in 2025.2); the newest, should there be more than one.
    hw = os.path.join(export, "hw")
    ide = os.path.join(workspace, args["app"], "_ide")
    for directory, pattern in (("bitstream", "*.bit"), ("psinit", "psu_init.tcl")):
        if not os.path.isdir(os.path.join(ide, directory)):
            continue  # no launch configuration yet: the IDE copies the platform's when it makes one
        found = glob.glob(os.path.join(hw, "**", pattern), recursive=True)
        if not found:
            raise RuntimeError(f"no {pattern} below {hw} for {args['app']}'s launch configuration")
        f = max(found, key=os.path.getmtime)
        shutil.copy2(f, os.path.join(ide, directory))
        print(f"Launch file: {os.path.join(args['app'], '_ide', directory, os.path.basename(f))}")


def files(directory, patterns):
    return [f for p in patterns for f in glob.glob(os.path.join(directory, "**", p), recursive=True)]


def sources(client):
    # Relative to the application's src/, as the IDE writes them. The headers are listed only to be
    # shown: the build compiles the .c files.
    src = os.path.join(workspace, args["app"], "src")

    def relative(paths):
        return [os.path.relpath(f, src).replace("\\", "/") for f in paths]

    listed = []
    for directory in args["app_src"]:
        listed += files(directory, ["*.c", "*.h"])
    for directory in args["app_includes"]:
        listed += files(directory, ["*.h"])
    listed = sorted(set(relative(listed)))
    includes = relative(args["app_src"] + args["app_includes"])
    app = client.get_component(name=args["app"])
    app.set_app_config(key="USER_COMPILE_SOURCES", values=listed)
    app.set_app_config(key="USER_INCLUDE_DIRECTORIES", values=includes)
    print("Sources: " + " ".join(listed))
    print("Include directories: " + " ".join(includes))


def build(client):
    # build() reports a failed build only in its log, so the ELF is removed first and must be back.
    elf = os.path.join(workspace, args["app"], "build", args["app"] + ".elf")
    if os.path.exists(elf):
        os.remove(elf)
    client.get_component(name=args["app"]).build()
    if not os.path.isfile(elf):
        raise RuntimeError(f"{args['app']} did not build")
    print(f"Built {elf}")


if os.path.exists(done_file):
    os.remove(done_file)
client = vitis.create_client()
try:
    open_workspace(client)
    {"workspace": make_workspace, "sources": sources, "build": build}[stage](client)
    with open(done_file, "w") as f:
        f.write(args["xsa"] + "\n")
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
finally:
    vitis.dispose()
