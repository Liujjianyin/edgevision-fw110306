# Model data layout

Training photos and labels are intentionally omitted from this repository. The model was trained on a private beverage dataset and the current board model excludes 水溶 C.

For a local retraining workspace, prepare files under:

```text
Model/data/
  images/all/
  labels/all/
  background/
  demo_retake_20261103/
```

Set `EDGEVISION_BACKGROUND_DIR` to the local empty-cloth background folder before running either training script. Set `EDGEVISION_RETAKE_DIR` when using the retake script. Do not commit private photos or manifests containing local absolute paths.
