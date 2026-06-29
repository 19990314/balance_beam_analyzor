# Balance Beam Analyzer

MATLAB pipeline for analyzing mouse balance beam videos. Tracks movement, classifies behavior (crossing, crawling, pausing), and exports summary metrics including speed in cm/s.

---

## Pipeline Overview

Run the steps in order. Each step builds on outputs from the previous one.

```
Step 1 → calibrate px/cm
Step 2 → define ROI & track videos   → per-video .mat files
Step 3 → route analysis              → updates .mat files
Step 4 → extract metadata            → summary_behavior_metrics.xlsx
Step 5 → plot baseline vs post
```

---

## Steps

### Step 1 — `step1_pixel_per_cm_calculator.m`
Calibrates the pixel-to-centimeter ratio for each video.

- Opens a file browser — select the folder containing your `*beam_h.mp4` videos
- For each video, displays a mid-video frame; draw a line spanning **100 cm** on the beam
- Saves `pixels_per_cm_output.xlsx` to `<project>/stats_and_analysis/balancebeam/`

**Output columns:** `VideoName`, `PixelsPerCm`

---

### Step 2 — `step2_setup_ROI.m`
Batch-tracks mouse position within a user-defined ROI across all videos.

- Select folder containing `*beam_h.mp4` videos
- For each video: draw the beam ROI, mark start/stop positions, and draw the crawl polyline
- Uses background subtraction (threshold = 50) at 30 fps
- Classifies each frame as **Pause** (speed < 0.3 px/frame), **Crawling** (blob touches polyline), or **Crossing**
- Saves a `*_tracking_results.mat` per video and a master `tracking_master_summary` MAT + CSV

**Per-video MAT variables:** `centers`, `speed_px_per_frame`, `isPause`, `isCrawling`, `isCrossing`, time totals, ROI info

---

### Step 3 — `step3_routeanalysis.m`
Additional route-level analysis on the tracked data. Updates the per-video MAT files.

---

### Step 4 — `step4_extract_metadata.m`
Aggregates all per-video MAT files into a single Excel summary.

- Select the folder containing `*_tracking_results.mat` files
- Reads `pixels_per_cm_output.xlsx` to convert speeds from px/frame to cm/s
- Matches each file to its calibration via the filename prefix (first 7 characters)

**Output:** `summary_behavior_metrics.xlsx` in `<project>/stats_and_analysis/balancebeam/`

| Column | Description |
|---|---|
| `FilePrefix` | First 7 characters of the video filename |
| `CrossingTime_sec` | Time spent crossing (s) |
| `PauseTime_sec` | Time spent pausing (s) |
| `CrawlingTime_sec` | Time spent crawling (s) |
| `MedianSpeed_px_per_frame` | Median speed in pixels/frame |
| `MeanSpeed_px_per_frame` | Mean speed in pixels/frame |
| `PixelsPerCm` | Calibration value from Step 1 |
| `MedianSpeed_cm_per_s` | Median speed in cm/s |
| `MeanSpeed_cm_per_s` | Mean speed in cm/s |

---

### Step 5 — `step5_bar_plot_caseANDcontrol.m`
Plots grouped bar charts comparing baseline vs. post-injection sessions per mouse.

- Edit the file paths at the top (`baselineFile`, `postFile`) to point to your two `summary_behavior_metrics.xlsx` files
- Produces bar plots for crossing time, crawling time, pausing time, and optional slip counts

---

### Utility — `stepn_merge.m`
Merges summary tables from multiple sessions or cohorts into a single file.

---

## Folder Structure

```
project_folder/
├── videos/                          # Raw *beam_h.mp4 videos
├── stats_and_analysis/
│   └── balancebeam/
│       ├── pixels_per_cm_output.xlsx    # Step 1 output
│       ├── *_tracking_results.mat       # Step 2 output (one per video)
│       ├── tracking_master_summary.csv  # Step 2 master summary
│       └── summary_behavior_metrics.xlsx # Step 4 output
```

---

## Requirements

- MATLAB R2020b or later
- Image Processing Toolbox
- Video files named with the pattern `*beam_h.mp4`
