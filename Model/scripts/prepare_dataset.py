#!/usr/bin/env python
"""Copy the caller's beverage folders into a compact, EXIF-corrected dataset."""

from __future__ import annotations

import argparse
import csv
import json
from datetime import datetime
from pathlib import Path

from PIL import Image, ImageOps


CLASSES = [
    {"id": 0, "folder": "水溶c，5.5元", "name": "水溶c", "price_cny": 5.5},
    {"id": 1, "folder": "乌苏啤酒，8元", "name": "乌苏啤酒", "price_cny": 8.0},
    {"id": 2, "folder": "小可口可乐，2.5元", "name": "小可口可乐", "price_cny": 2.5},
    {"id": 3, "folder": "小青柠，5元", "name": "小青柠", "price_cny": 5.0},
    {"id": 4, "folder": "百事可乐，3元", "name": "百事可乐", "price_cny": 3.0},
]
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def capture_time(image: Image.Image) -> str:
    exif = image.getexif()
    value = exif.get(36867) or exif.get(306) or ""
    try:
        return datetime.strptime(str(value), "%Y:%m:%d %H:%M:%S").isoformat(sep=" ")
    except ValueError:
        return str(value)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=Path.home() / "Desktop")
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--max-edge", type=int, default=1280)
    args = parser.parse_args()

    image_root = args.project_root / "data" / "images" / "all"
    image_root.mkdir(parents=True, exist_ok=True)
    manifest_path = args.project_root / "data" / "manifest.csv"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, str | int | float]] = []
    errors: list[str] = []

    for cls in CLASSES:
        source_dir = args.source_root / cls["folder"]
        if not source_dir.is_dir():
            errors.append(f"Missing source folder: {source_dir}")
            continue
        files = sorted(p for p in source_dir.rglob("*") if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES)
        for index, source in enumerate(files, start=1):
            target_name = f"class{cls['id']}_{index:04d}_{source.stem}.jpg"
            target = image_root / target_name
            try:
                with Image.open(source) as raw:
                    taken = capture_time(raw)
                    image = ImageOps.exif_transpose(raw).convert("RGB")
                    original_size = f"{image.width}x{image.height}"
                    if max(image.size) > args.max_edge:
                        scale = args.max_edge / max(image.size)
                        size = (round(image.width * scale), round(image.height * scale))
                        image = image.resize(size, Image.Resampling.LANCZOS)
                    image.save(target, "JPEG", quality=92, optimize=True)
                rows.append(
                    {
                        "image": target_name,
                        "class_id": cls["id"],
                        "class_name": cls["name"],
                        "price_cny": cls["price_cny"],
                        "source_file": str(source),
                        "source_size": original_size,
                        "capture_time": taken,
                        "annotation": "pending",
                    }
                )
            except Exception as exc:  # keep a useful inventory even if one source is damaged
                errors.append(f"Failed {source}: {exc}")

    with manifest_path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]) if rows else ["image", "class_id", "class_name", "price_cny", "source_file", "source_size", "capture_time", "annotation"])
        writer.writeheader()
        writer.writerows(rows)

    catalog = {
        "version": 1,
        "classes": [
            {"id": c["id"], "name": c["name"], "display_name": c["name"], "price_cny": c["price_cny"]}
            for c in CLASSES
        ],
    }
    (args.project_root / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    counts = {str(c["name"]): sum(1 for r in rows if r["class_id"] == c["id"]) for c in CLASSES}
    print(f"Prepared {len(rows)} images under {image_root}")
    print(json.dumps(counts, ensure_ascii=False))
    print(f"Manifest: {manifest_path}")
    if errors:
        print("Warnings:")
        for message in errors:
            print(f"  {message}")


if __name__ == "__main__":
    main()
