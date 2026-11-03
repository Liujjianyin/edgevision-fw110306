#!/usr/bin/env python
"""Add the five product-specific supplemental photo sets to the isolated dataset."""

from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageOps


PROJECT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT / "data" / "supplementary"
IMAGES = PROJECT / "data" / "images" / "all"
LABELS = {
    "water": (0, "水溶c", 5.5),
    "wusu": (1, "乌苏啤酒", 8.0),
    "coke": (2, "小可口可乐", 2.5),
    "lime": (3, "小青柠", 5.0),
    "pepsi": (4, "百事可乐", 3.0),
}
SUFFIXES = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def main() -> None:
    IMAGES.mkdir(parents=True, exist_ok=True)
    labels = PROJECT / "data" / "labels" / "all"
    seen = set()
    for path in IMAGES.glob("*.jpg"):
        try:
            seen.add(hashlib.sha256(path.read_bytes()).hexdigest())
        except OSError:
            pass

    rows = []
    skipped = 0
    errors = []
    for slug, (class_id, name, price) in LABELS.items():
        files = sorted(p for p in (SOURCE / slug).rglob("*") if p.is_file() and p.suffix.lower() in SUFFIXES)
        serial = 0
        for source in files:
            try:
                digest = hashlib.sha256(source.read_bytes()).hexdigest()
                if digest in seen:
                    skipped += 1
                    continue
                with Image.open(source) as raw:
                    image = ImageOps.exif_transpose(raw).convert("RGB")
                    original_size = f"{image.width}x{image.height}"
                    if max(image.size) > 1280:
                        scale = 1280 / max(image.size)
                        image = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
                    serial += 1
                    target_name = f"class{class_id}_supp_{serial:04d}.jpg"
                    image.save(IMAGES / target_name, "JPEG", quality=92, optimize=True)
                seen.add(digest)
                rows.append({
                    "image": target_name,
                    "class_id": class_id,
                    "class_name": name,
                    "price_cny": price,
                    "source_file": str(source),
                    "source_size": original_size,
                    "annotation": "pending_grabcut_review",
                    "sha256": digest,
                })
            except Exception as exc:
                errors.append(f"{source}: {exc}")

    out = PROJECT / "data" / "supplementary_manifest.csv"
    with out.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]) if rows else ["image", "class_id", "class_name", "price_cny", "source_file", "source_size", "annotation", "sha256"])
        writer.writeheader()
        writer.writerows(rows)
    counts = {name: sum(row["class_name"] == name for row in rows) for _, name, _ in LABELS.values()}
    print(json.dumps({"added": len(rows), "skipped_duplicate": skipped, "per_class": counts, "manifest": str(out), "labels_dir_ready": labels.exists()}, ensure_ascii=False))
    for error in errors:
        print("WARNING " + error)


if __name__ == "__main__":
    main()
