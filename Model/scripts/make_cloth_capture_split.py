#!/usr/bin/env python
"""Create a leakage-resistant split by photo batch for the cloth-background demo."""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[1]
DATA = PROJECT / "data"


def read_label(path: Path, nclasses: int) -> set[int]:
    if not path.is_file():
        raise SystemExit(f"Missing label: {path}")
    seen: set[int] = set()
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        fields = line.split()
        if len(fields) != 5:
            raise SystemExit(f"Bad YOLO label {path}:{line_no}")
        cls, *coords = map(float, fields)
        if cls != int(cls) or not 0 <= int(cls) < nclasses:
            raise SystemExit(f"Bad class id in {path}:{line_no}")
        if any(not 0 <= value <= 1 for value in coords) or coords[2] <= 0 or coords[3] <= 0:
            raise SystemExit(f"Out-of-range box in {path}:{line_no}")
        seen.add(int(cls))
    return seen


def main() -> None:
    catalog = json.loads((PROJECT / "catalog.json").read_text(encoding="utf-8"))["classes"]
    class_count = len(catalog)
    images = sorted((DATA / "images" / "all").glob("*.jpg"))
    train = [path for path in images if "_supp_" in path.stem]
    val = [path for path in images if "_supp_" not in path.stem]
    if not train or not val:
        raise SystemExit("Expected separate supplementary and original capture batches")

    counts = {"train": Counter(), "val": Counter()}
    for split, items in (("train", train), ("val", val)):
        for image in items:
            expected = int(image.name.split("_", 1)[0].removeprefix("class"))
            classes = read_label(DATA / "labels" / "all" / f"{image.stem}.txt", class_count)
            if classes != {expected}:
                raise SystemExit(f"{image.name}: expected class {expected}, found {sorted(classes)}")
            counts[split][expected] += 1

    split_dir = DATA / "cloth_capture_split"
    split_dir.mkdir(parents=True, exist_ok=True)
    for name, items in (("train", train), ("val", val)):
        (split_dir / f"{name}.txt").write_text(
            "\n".join(path.resolve().as_posix() for path in items) + "\n", encoding="utf-8"
        )
    names = [f"  {item['id']}: {json.dumps(item['name'], ensure_ascii=False)}" for item in catalog]
    data_path = DATA.resolve().as_posix()
    yaml_text = (
        f"path: {json.dumps(data_path, ensure_ascii=False)}\n"
        "train: cloth_capture_split/train.txt\n"
        "val: cloth_capture_split/val.txt\n"
        "names:\n"
        + "\n".join(names)
        + "\n"
    )
    dataset_yaml = DATA / "dataset_cloth_capture.yaml"
    dataset_yaml.write_text(yaml_text, encoding="utf-8")
    summary = {
        "purpose": "single-product demo against the supplied cloth backdrop",
        "train_capture_batch": "all 5 supplementary folders (371 unique images)",
        "validation_capture_batch": "original 5 folders (210 images; held out by capture batch)",
        "labels": "GrabCut-assisted and still pending full human review",
        "counts": {
            split: {catalog[class_id]["name"]: count for class_id, count in sorted(counter.items())}
            for split, counter in counts.items()
        },
        "dataset_yaml": str(dataset_yaml),
    }
    (split_dir / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
