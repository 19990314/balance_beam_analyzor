%% summarize_beamwalking_master
% Reads all *_tracking_results.mat files and writes one master CSV with:
%
%   Per-video timing & percentages (pause / crawling / crossing)
%   Speed with pausing INCLUDED (raw median/mean over all frames)
%   Speed with pausing EXCLUDED (median/mean over ~isPause frames only)
%   All speeds in both px/frame and cm/s (via pixels_per_cm_output.xlsx)
%
% Output: beamwalking_time_and_speed_{XX}.csv
%   where XX = first 2 characters of the selected folder name.

    fps = 30;

    folder = uigetdir(pwd, 'Select folder containing *_tracking_results.mat files');
    if isequal(folder, 0), error('No folder selected.'); end

    % Extract 2-char label from folder basename (e.g. "B4" from "B4_cohort_2_...")
    [~, folderName] = fileparts(folder);
    cohortTag = folderName(1:min(2, numel(folderName)));

    files = dir(fullfile(folder, '**', '*results.mat'));
    if isempty(files), error('No *_tracking_results.mat files found in %s', folder); end

    % Load pixels-per-cm lookup
    ppcFile = fullfile(folder, 'stats_and_analysis/balancebeam/pixels_per_cm_output.xlsx');
    if exist(ppcFile, 'file')
        ppcTable = readtable(ppcFile);
    else
        ppcTable = [];
        warning('pixels_per_cm_output.xlsx not found; cm/s columns will be NaN.');
    end

    % --- Output accumulator ---
    Video                        = {};
    PauseTime_sec                = [];
    CrawlingTime_sec             = [];
    CrossingTime_sec             = [];
    PausePct                     = [];
    CrawlingPct                  = [];
    CrossingPct                  = [];
    PixelsPerCm                  = [];
    MedianSpeed_px_frame_pauseIncluded = [];
    MeanSpeed_px_frame_pauseIncluded   = [];
    MedianSpeed_cm_s_pauseIncluded     = [];
    MeanSpeed_cm_s_pauseIncluded       = [];
    MedianSpeed_px_s_pauseExcluded     = [];
    MeanSpeed_px_s_pauseExcluded       = [];
    MedianSpeed_cm_s_pauseExcluded     = [];
    MeanSpeed_cm_s_pauseExcluded       = [];

    for k = 1:numel(files)
        fpath = fullfile(files(k).folder, files(k).name);
        [~, base] = fileparts(files(k).name);
        d = load(fpath);

        if ~isfield(d,'speed_px_per_frame') || ~isfield(d,'pause_time_sec') || ...
           ~isfield(d,'crawling_time_sec')  || ~isfield(d,'crossing_time_sec')
            warning('Missing required fields in %s — skipping.', files(k).name);
            continue;
        end

        spd_pf = d.speed_px_per_frame(:);

        % --- Crop to trial window if valid ---
        if isfield(d,'startIdx') && isfield(d,'stopIdx') && ...
           ~isempty(d.startIdx) && ~isempty(d.stopIdx)
            a = double(d.startIdx(1)); b = double(d.stopIdx(1));
            if isfinite(a) && isfinite(b) && a>=1 && b>=a && b<=numel(spd_pf)
                spd_pf = spd_pf(a:b);
            end
        end

        % --- Timing (taken directly from MAT) ---
        N   = numel(d.isPause);
        tot = N / fps;
        p_pct  = 100 * d.pause_time_sec    / tot;
        cr_pct = 100 * d.crawling_time_sec / tot;
        cx_pct = 100 * d.crossing_time_sec / tot;

        % --- PixelsPerCm lookup (7-char prefix) ---
        ppc = NaN;
        if ~isempty(ppcTable)
            prefix = files(k).name(1:min(7, numel(files(k).name)));
            matchIdx = find(strncmp(ppcTable.VideoName, prefix, numel(prefix)), 1);
            if ~isempty(matchIdx)
                ppc = ppcTable.PixelsPerCm(matchIdx);
            else
                warning('No PixelsPerCm match for prefix: %s', prefix);
            end
        end

        % --- Speed: pausing INCLUDED (raw, all frames, px/frame → cm/s) ---
        medPxPf_inc = median(spd_pf, 'omitnan');
        mnPxPf_inc  = mean(spd_pf,   'omitnan');
        % px/frame * fps = px/s;  px/s / px_per_cm = cm/s
        medCm_inc = medPxPf_inc * fps / ppc;
        mnCm_inc  = mnPxPf_inc  * fps / ppc;

        % --- Speed: pausing EXCLUDED (~isPause mask) ---
        if isfield(d,'isPause') && ~isempty(d.isPause)
            isP = d.isPause(:);
            % align crop if needed
            if numel(spd_pf) == numel(isP)
                % already same length (cropped together or both full)
            elseif isfield(d,'startIdx') && isfield(d,'stopIdx')
                a2 = double(d.startIdx(1)); b2 = double(d.stopIdx(1));
                if isfinite(a2) && isfinite(b2) && a2>=1 && b2>=a2 && b2<=numel(isP)
                    isP = isP(a2:b2);
                end
            end
            activeMask = ~isP(1:numel(spd_pf));
        else
            activeMask = true(numel(spd_pf), 1);
        end

        spd_ps_exc = spd_pf(activeMask) * fps;  % px/s, pauses removed
        if isempty(spd_ps_exc) || all(isnan(spd_ps_exc))
            medPxS_exc = NaN; mnPxS_exc = NaN;
            warning('No active (non-pause) frames in %s.', files(k).name);
        else
            medPxS_exc = median(spd_ps_exc, 'omitnan');
            mnPxS_exc  = mean(spd_ps_exc,   'omitnan');
        end
        medCm_exc = medPxS_exc / ppc;
        mnCm_exc  = mnPxS_exc  / ppc;

        % --- Accumulate ---
        Video{end+1}                              = base; %#ok<AGROW>
        PauseTime_sec(end+1)                      = d.pause_time_sec;
        CrawlingTime_sec(end+1)                   = d.crawling_time_sec;
        CrossingTime_sec(end+1)                   = d.crossing_time_sec;
        PausePct(end+1)                           = p_pct;
        CrawlingPct(end+1)                        = cr_pct;
        CrossingPct(end+1)                        = cx_pct;
        PixelsPerCm(end+1)                        = ppc;
        MedianSpeed_px_frame_pauseIncluded(end+1) = medPxPf_inc;
        MeanSpeed_px_frame_pauseIncluded(end+1)   = mnPxPf_inc;
        MedianSpeed_cm_s_pauseIncluded(end+1)     = medCm_inc;
        MeanSpeed_cm_s_pauseIncluded(end+1)        = mnCm_inc;
        MedianSpeed_px_s_pauseExcluded(end+1)     = medPxS_exc;
        MeanSpeed_px_s_pauseExcluded(end+1)       = mnPxS_exc;
        MedianSpeed_cm_s_pauseExcluded(end+1)     = medCm_exc;
        MeanSpeed_cm_s_pauseExcluded(end+1)       = mnCm_exc;
    end

    T = table(Video', PauseTime_sec', CrawlingTime_sec', CrossingTime_sec', ...
              PausePct', CrawlingPct', CrossingPct', PixelsPerCm', ...
              MedianSpeed_px_frame_pauseIncluded', MeanSpeed_px_frame_pauseIncluded', ...
              MedianSpeed_cm_s_pauseIncluded',     MeanSpeed_cm_s_pauseIncluded', ...
              MedianSpeed_px_s_pauseExcluded',     MeanSpeed_px_s_pauseExcluded', ...
              MedianSpeed_cm_s_pauseExcluded',     MeanSpeed_cm_s_pauseExcluded', ...
        'VariableNames', { ...
            'Video', ...
            'PauseTime_sec', 'CrawlingTime_sec', 'CrossingTime_sec', ...
            'PausePct', 'CrawlingPct', 'CrossingPct', ...
            'PixelsPerCm', ...
            'MedianSpeed_px_per_frame_pauseIncluded', 'MeanSpeed_px_per_frame_pauseIncluded', ...
            'MedianSpeed_cm_s_pauseIncluded',         'MeanSpeed_cm_s_pauseIncluded', ...
            'MedianSpeed_px_s_pauseExcluded',         'MeanSpeed_px_s_pauseExcluded', ...
            'MedianSpeed_cm_s_pauseExcluded',         'MeanSpeed_cm_s_pauseExcluded' ...
        });

    if ~exist(fullfile(folder, 'stats_and_analysis/balancebeam'), 'dir')
        mkdir(fullfile(folder, 'stats_and_analysis/balancebeam'));
    end
    outName = sprintf('beamwalking_time_and_speed_%s.csv', cohortTag);
    out = fullfile(folder, 'stats_and_analysis/balancebeam', outName);
    writetable(T, out);
    fprintf('Wrote %s with %d rows.\n', out, height(T));
    disp(T);
