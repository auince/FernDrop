#!/usr/bin/env python3
"""Package the approved PNG as a multi-resolution Windows ICO on macOS."""
from pathlib import Path
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
source = root / "ui/assets/app-icon/ferndrop.png"
destination = root / "ui/assets/app-icon/ferndrop.ico"
sizes = (16, 24, 32, 48, 64, 128, 256)
images = []
with tempfile.TemporaryDirectory(prefix="ferndrop-icon-") as directory:
    for size in sizes:
        path = Path(directory) / f"{size}.png"
        subprocess.run(
            ["sips", "-z", str(size), str(size), str(source), "--out", str(path)],
            check=True, stdout=subprocess.DEVNULL,
        )
        images.append(path.read_bytes())

offset = 6 + 16 * len(images)
entries = []
for size, data in zip(sizes, images):
    entries.append(struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0,
                               1, 32, len(data), offset))
    offset += len(data)
destination.write_bytes(struct.pack("<HHH", 0, 1, len(images))
                        + b"".join(entries) + b"".join(images))
print(f"Created {destination.relative_to(root)} ({len(images)} resolutions)")
