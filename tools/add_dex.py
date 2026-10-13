"""Insert classes.dex into an APK produced by `aapt2 link`.

Kept as a tiny script so the Android build does not need Gradle: aapt2 + javac +
d8 + zipalign + apksigner are all it takes.
"""

import sys
import zipfile

src_apk, dex_path, dst_apk = sys.argv[1], sys.argv[2], sys.argv[3]

with zipfile.ZipFile(src_apk, "r") as zin, zipfile.ZipFile(dst_apk, "w", zipfile.ZIP_DEFLATED) as zout:
    for item in zin.infolist():
        if item.filename == "classes.dex":
            continue
        zout.writestr(item, zin.read(item.filename))

    with open(dex_path, "rb") as fh:
        dex = fh.read()
    info = zipfile.ZipInfo("classes.dex")
    info.compress_type = zipfile.ZIP_STORED  # uncompressed dex, like AGP does
    zout.writestr(info, dex)

print(f"added {len(dex)} bytes of classes.dex -> {dst_apk}")
