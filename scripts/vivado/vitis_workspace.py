"""Vitis workspace of a block design under bd/<name>/: a platform made from the design's XSA
(standalone on one processor) and applications whose sources stay where they are in the repo, so
what is edited in the IDE is edited in git. Used by bd.mk.

Usage: vitis -s vitis_workspace.py <args.json> <stage> [<app>]
  workspace      create the platform if it is missing, otherwise give it the XSA again (bd.mk runs
                 it when the XSA is newer); build the platform, and give the applications' launch
                 configurations its bitstream and psu_init.tcl
  sources <app>  create the application if it is missing; list in it every .c, .cpp, .h and .hpp of
                 its src directories and every .h of its includes, so the IDE shows them all, make
                 those and its external_includes (libraries, not listed) its include path, link its
                 libs, and compile it with optimization and cflags, its C as C (bd.mk runs it when
                 a file is added or removed there, or the design's Makefile or this script changes)
  build <app>    build the application
args.json (written by bd.mk): workspace, xsa, platform, cpu, domain, stamp (the file that says the
workspace stage succeeded), the applications' optimization level and other compiler flags
(optimization, cflags), and apps, by name: src, includes, external_includes, libs, and the files
that say its stages succeeded, sources_stamp (sources) and built (build)
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
if stage == "workspace":
    done_file = args["stamp"]
else:
    name = sys.argv[3]  # the application
    app_args = args["apps"][name]
    done_file = app_args["sources_stamp" if stage == "sources" else "built"]


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

    for app in args["apps"]:
        if exists(app):
            refresh_launch_files(app)


def refresh_launch_files(app):
    # The IDE's launch configurations program copies of the platform's bitstream and psu_init.tcl,
    # made in <app>/_ide/ with them, and do not refresh them when the platform takes a new XSA: the
    # board would run the new software on the old hardware. The platform keeps them below hw/
    # (hw/sdt/ in 2025.2); the newest, should there be more than one.
    hw = os.path.join(export, "hw")
    ide = os.path.join(workspace, app, "_ide")
    for directory, pattern in (("bitstream", "*.bit"), ("psinit", "psu_init.tcl")):
        if not os.path.isdir(os.path.join(ide, directory)):
            continue  # no launch configuration yet: the IDE copies the platform's when it makes one
        found = glob.glob(os.path.join(hw, "**", pattern), recursive=True)
        if not found:
            raise RuntimeError(f"no {pattern} below {hw} for {app}'s launch configuration")
        f = max(found, key=os.path.getmtime)
        shutil.copy2(f, os.path.join(ide, directory))
        print(f"Launch file: {os.path.join(app, '_ide', directory, os.path.basename(f))}")


def files(directory, patterns):
    return [f for p in patterns for f in glob.glob(os.path.join(directory, "**", p), recursive=True)]


def c_project(app):
    # The application template's CMakeLists.txt compiles every file with g++ once one is C++ (its
    # "c++" project type): C as C++. Declared "c", each file compiles by its extension, .c with gcc
    # and .cpp with g++, and the link is still g++'s.
    path = os.path.join(workspace, app, "src", "CMakeLists.txt")
    with open(path, newline="") as f:
        text = f.read()
    line = 'set(PROJECT_TYPE "c")'
    if line in text:
        return
    anchor = "# Include any additional CMake files here"
    if anchor not in text or "if (NOT DEFINED PROJECT_TYPE)" not in text:
        raise RuntimeError(f"{path} is not the application template this script knows")
    eol = "\r\n" if "\r\n" in text else "\n"
    with open(path, "w", newline="") as f:
        f.write(text.replace(anchor, anchor + eol + line, 1))
    print(f"{app}: C compiled as C ({line} in its CMakeLists.txt)")


def sources(client):
    if not exists(name):
        client.create_app_component(name=name, platform=xpfm, domain=domain)
    c_project(name)
    # Relative to the application's src/, as the IDE writes them. The headers are listed only to be
    # shown: the build compiles the .c files.
    src = os.path.join(workspace, name, "src")

    def relative(paths):
        return [os.path.relpath(f, src).replace("\\", "/") for f in paths]

    listed = []
    for directory in app_args["src"]:
        listed += files(directory, ["*.c", "*.cpp", "*.h", "*.hpp"])
    for directory in app_args["includes"]:
        listed += files(directory, ["*.h"])
    listed = sorted(set(relative(listed)))
    includes = relative(app_args["src"] + app_args["includes"] + app_args["external_includes"])
    app = client.get_component(name=name)
    app.set_app_config(key="USER_COMPILE_SOURCES", values=listed)
    app.set_app_config(key="USER_INCLUDE_DIRECTORIES", values=includes)
    app.set_app_config(key="USER_LINK_LIBRARIES", values=app_args["libs"])
    # In the compiler's flags, which the IDE's build gives the link too
    app.set_app_config(key="USER_COMPILE_OPTIMIZATION_LEVEL", values=[args["optimization"]])
    app.set_app_config(key="USER_COMPILE_OTHER_FLAGS", values=[args["cflags"]])
    print("Sources: " + " ".join(listed))
    print("Include directories: " + " ".join(includes))
    print("Libraries: " + " ".join(app_args["libs"]))
    print("Compiler flags: " + " ".join(f for f in (args["optimization"], args["cflags"]) if f))


def build(client):
    # build() reports a failed build only in its log, so the ELF is removed first and must be back.
    elf = os.path.join(workspace, name, "build", name + ".elf")
    if os.path.exists(elf):
        os.remove(elf)
    client.get_component(name=name).build()
    if not os.path.isfile(elf):
        raise RuntimeError(f"{name} did not build")
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
