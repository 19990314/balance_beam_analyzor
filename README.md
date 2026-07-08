# Balance Beam Analyzer

MATLAB pipeline for analyzing mouse balance beam videos. Tracks movement, classifies behavior (crossing, crawling, pausing), and exports summary metrics including speed in cm/s.

---

## Quick Start

Run the full pipeline with a single script:

```matlab
run_pipeline
```

Select your project folder once — Steps 1, 2, and 3 run in sequence. Already-processed videos are skipped automatically.

---

## Pipeline Overview

```
Step 1 → calibrate px/cm              → pixels_per_cm_output.xlsx
Step 2 → define ROI & track videos    → per-video *_tracking_results.mat
Step 3 → aggregate master statistics  → beamwalking_time_and_speed_{XX}.csv
```

Steps can also be run individually (each script accepts an optional folder argument or prompts via file browser).

---

## Steps

### Step 1 — `step1_pixel_per_cm_calculator.m`
Calibrates the pixel-to-centimeter ratio for each video.

- Select the folder containing `*beam_h.mp4` videos
- For each **new** video (not yet in the output file), displays a mid-video frame — draw a line spanning **100 cm** on the beam
- Already-calibrated videos are skipped; new rows are appended
- Saves `pixels_per_cm_output.xlsx` to `<project>/stats_and_analysis/balancebeam/`

**Output columns:** `VideoName`, `PixelsPerCm`

---

### Step 2 — `step2_setup_ROI_beamregioncalculate_time_statistics.m`
Batch-tracks mouse position within a user-defined ROI across all videos.

- Select folder containing `*beam_h.mp4` videos
- Videos with an existing `*_tracking_results.mat` are **skipped** and loaded into the master summary automatically
- For each new video: set start/stop frames, draw the beam ROI polygon, draw the crawl boundary polyline
- Uses background subtraction (threshold = 50) at 30 fps
- Classifies each frame (categories can overlap):
  - **Pause** — speed < 0.3 px/frame
  - **Crawling** — blob boundary crosses the user-drawn polyline (independent of pause)
  - **Crossing** — frames that are neither pausing nor crawling
- Saves a `*_tracking_results.mat` and `*_tracked.mp4` per video
- Saves master summary MAT + CSV

**Per-video MAT variables:** `centers`, `speed_px_per_frame`, `isPause`, `isCrawling`, `isCrossing`, time totals, percentages, ROI info, crawl polyline

**Master summary files:**
- `crossing_pausing_crawling_timein_seconds+percentage.mat`
- `crossing_pausing_crawling_timein_seconds+percentage.csv`

---

### Step 3 — `step3_routeanalysis.m`
Aggregates all per-video MAT files into one master CSV with timing, percentages, and speeds.

- Select the folder containing `*_tracking_results.mat` files
- Reads `pixels_per_cm_output.xlsx` to convert speeds to cm/s (matched by first 7 characters of filename)
- Output filename includes a 2-character cohort tag extracted from the **first 2 characters of the selected folder name** (e.g. `B4` from `B4_cohort_2_post_injection_behavior`)

**Output:** `beamwalking_time_and_speed_{XX}.csv` in `<project>/stats_and_analysis/balancebeam/`

| Column | Description |
|---|---|
| `Video` | Filename (no extension) |
| `ID` | First 4 characters of filename, uppercased (e.g. `SC04`) |
| `Day` | Day number extracted from `_d<N>_` in filename (integer; NaN if not found) |
| `Group` | `SNr-DTA` or `Ctrl` based on ID lookup; empty if unknown |
| `PauseTime_sec` | Time spent pausing (s) |
| `CrawlingTime_sec` | Time spent crawling (s) |
| `CrossingTime_sec` | Time spent crossing (s) |
| `PausePct` | % of trial time pausing |
| `CrawlingPct` | % of trial time crawling |
| `CrossingPct` | % of trial time crossing |
| `PixelsPerCm` | Calibration value from Step 1 |
| `MedianSpeed_px_per_frame_pauseIncluded` | Median speed over all frames in trial window (px/frame) |
| `MeanSpeed_px_per_frame_pauseIncluded` | Mean speed over all frames in trial window (px/frame) |
| `MedianSpeed_cm_s_pauseIncluded` | Median speed over all frames in trial window (cm/s) |
| `MeanSpeed_cm_s_pauseIncluded` | Mean speed over all frames in trial window (cm/s) |
| `MedianSpeed_px_s_pauseExcluded` | Median speed excluding pause frames (px/s) |
| `MeanSpeed_px_s_pauseExcluded` | Mean speed excluding pause frames (px/s) |
| `MedianSpeed_cm_s_pauseExcluded` | Median speed excluding pause frames (cm/s) |
| `MeanSpeed_cm_s_pauseExcluded` | Mean speed excluding pause frames (cm/s) |

#### Speed calculation formulas

All speed is derived from `speed_px_per_frame`, which is the Euclidean distance (pixels) between consecutive blob centroids. The trial window is `[startIdx, stopIdx]` as set during Step 2.

**Pause-included** (all frames in trial window, NaN frames omitted):

```
speed_px_per_frame  =  dist(centroid[t], centroid[t-1])          [px/frame]
median_px_per_frame =  median(speed_px_per_frame)                 [px/frame]
median_cm_per_s     =  median_px_per_frame × fps ÷ PixelsPerCm   [cm/s]
```

**Pause-excluded** (frames where `isPause == false`):

```
active_speeds_px_s  =  speed_px_per_frame(~isPause) × fps        [px/s]
median_px_per_s     =  median(active_speeds_px_s)                 [px/s]
median_cm_per_s     =  median_px_per_s ÷ PixelsPerCm             [cm/s]
```

> Note: `fps = 30`. `PixelsPerCm` is matched from `pixels_per_cm_output.xlsx` by the first 7 characters of the filename. The first frame of every video gets speed = 0 by definition (no prior frame).

---

### Step 5 — `step5_bar_plot_caseANDcontrol.m`
Plots grouped bar charts comparing baseline vs. post-injection sessions per mouse.

- Edit the file paths at the top (`baselineFile`, `postFile`) to point to your two output CSVs
- Produces bar plots for crossing time, crawling time, pausing time, and speed metrics

---

### Utility — `stepn_merge.m`
Merges summary tables from multiple sessions or cohorts into a single file.

---

## Folder Structure

```
project_folder/
├── *beam_h.mp4                             # Raw videos (can be in subfolders)
└── stats_and_analysis/
    └── balancebeam/
        ├── pixels_per_cm_output.xlsx           # Step 1 output
        ├── *_tracking_results.mat              # Step 2 output (one per video)
        ├── *_tracked.mp4                       # Step 2 annotated video
        ├── crossing_pausing_crawling_timein_seconds+percentage.mat  # Step 2 master
        ├── crossing_pausing_crawling_timein_seconds+percentage.csv  # Step 2 master
        └── beamwalking_time_and_speed_{XX}.csv # Step 3 master output
```

---

## Requirements

- MATLAB R2020b or later
- Image Processing Toolbox
- Video files named with the pattern `*beam_h.mp4`
