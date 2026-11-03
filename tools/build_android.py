#!/usr/bin/env python3
"""Android build for Last Handoff (Phase 6).

Builds the APK from a scratch copy of the project with phone-sized textures, so the
desktop project and its imports are never touched:
  * every VRAM-compressed texture is capped at 512 px (characters at 1024 px, the v1.1 room AO atlas at 2048)
  * re-import (ETC2), export the "Android" preset, verify with apksigner + aapt

Usage:  python3 tools/build_android.py OUT.apk
Signing: GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD in the environment
(see lasthandoff_keystore/keystore.properties; never commit the password).
Needs GODOT (path to the editor binary), Android SDK build-tools, JDK 17 in the
editor settings.
"""
import os, re, shutil, subprocess, sys

PROJ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GODOT = os.environ.get("GODOT", "godot")
WORK = os.environ.get("LH_ANDROID_WORK", "/tmp/lh_android_build")


def cap_textures(root):
    n = 0
    for d, _, files in os.walk(root):
        if "/.godot" in d or "/src_assets" in d:
            continue
        for f in files:
            if not f.endswith(".import"):
                continue
            p = os.path.join(d, f)
            s = open(p, encoding="utf-8").read()
            if 'importer="texture"' not in s or "compress/mode=2" not in s:
                continue
            cap = 1024 if "/characters/" in p else 512
            if p.endswith("level_ao.png.import"):
                cap = 2048    # v1.1 room AO atlas: ~23 texels per metre on phones
            m = re.search(r"process/size_limit=(\d+)", s)
            cur = int(m.group(1)) if m else 0
            new = cap if cur == 0 or cur > cap else cur
            if m:
                s = s.replace(m.group(0), "process/size_limit=%d" % new)
            else:
                s = s.replace("[params]\n", "[params]\n\nprocess/size_limit=%d\n" % new)
            open(p, "w", encoding="utf-8").write(s)
            n += 1
    return n


def main():
    out = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "LastHandoff.apk")
    if os.path.exists(WORK):
        shutil.rmtree(WORK)
    shutil.copytree(PROJ, WORK, ignore=shutil.ignore_patterns("src_assets", ".git", "export"))
    print("capped", cap_textures(WORK), "textures")
    subprocess.run(["timeout", "-k", "5", "1200", GODOT, "--headless", "--path", WORK, "--import"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    r = subprocess.run(["timeout", "-k", "5", "1200", GODOT, "--headless", "--path", WORK, "--export-release", "Android", out],
                       capture_output=True, text=True)
    tail = "\n".join(l for l in (r.stdout + r.stderr).splitlines() if "Storing File" not in l and "ADDING" not in l)[-3000:]
    print(tail)
    if not os.path.exists(out):
        sys.exit("export failed")
    print("APK", out, os.path.getsize(out) // 1024 // 1024, "MB")


if __name__ == "__main__":
    main()
