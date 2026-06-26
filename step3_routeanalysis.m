%% function summarize_crossing_speeds_simple
% Writes one CSV with per-file:
%   file, cross_mean_speed_px_s, cross_median_speed_px_s
%
% Crossing frames = isCrossing==1 (crawling included); pauses excluded if available.
% Robust to bad startIdx/stopIdx (will skip cropping if indices exceed vector length).

    folder = uigetdir(pwd,'Select folder with trial MAT files');
    if isequal(folder,0), error('No folder selected.'); end

    files = dir(fullfile(folder,"**", '*results.mat'));
    if isempty(files), error('No .mat files found in %s',folder); end

    rows = struct('file',{},'cross_mean_speed_px_s',{},'cross_median_speed_px_s',{});

    for k = 1:numel(files)
        fpath = fullfile(files(k).folder, files(k).name);
        d = load(fpath);

        % Pull & cast
        v = @(nm) d.(nm)(:);
        spd_pf = d.speed_px_per_frame;
        isX    = d.isCrossing;
        fps    = d.fps_used;

        % --- Optional crop: ONLY if indices make sense for these vectors
        if isfield(d,'startIdx') && isfield(d,'stopIdx') && ~isempty(d.startIdx) && ~isempty(d.stopIdx)
            a = double(d.startIdx(1));
            b = double(d.stopIdx(1));
            if isfinite(a) && isfinite(b) && a>=1 && b>=a && b<=numel(spd_pf)
                spd_pf = spd_pf(a:b);
                isX    = isX(a:b);
            else
                % indices refer to the full video, not the trimmed trial → skip cropping
                % fprintf('Skipping crop for %s (start/stop out of bounds: %g..%g > %d).\n', ...
                %     files(k).name, a, b, numel(spd_pf));
            end
        end

        % Exclude pauses if present; INCLUDE crawling by design
        if isfield(d,'isPause') && ~isempty(d.isPause)
            isP = d.isPause(:);
            if exist('a','var') && exist('b','var') && b<=numel(d.isPause)
                isP = isP(a:b);
            end
            mask = isX & ~isP;
        else
            mask = isX;
        end

        % Convert to px/s
        spd_ps = spd_pf * fps;

        % Guard 1: if mask ended empty (e.g., all frames were labeled Pause), fall back to raw isCrossing
        if nnz(mask)==0
            mask = isX;
        end
        % Guard 2: if still empty or all NaN speeds, write NaN but warn
        if nnz(mask)==0 || all(isnan(spd_ps(mask)))
            mMean = NaN; mMed = NaN;
            warning('No valid crossing frames in %s (after guards). Writing NaN.', files(k).name);
        else
            mMean = mean(spd_ps(mask), 'omitnan');   % mean across ALL crossing frames
            mMed  = median(spd_ps(mask), 'omitnan'); % median across ALL crossing frames
        end

        rows(end+1) = struct( ... %#ok<AGROW>
            'file', files(k).name, ...
            'cross_mean_speed_px_s',   mMean, ...
            'cross_median_speed_px_s', mMed);
    end

    T = struct2table(rows);

    if ~exist(fullfile(folder, "stats_and_analysis/balancebeam"), 'dir')
        mkdir(fullfile(dataDir, "stats_and_analysis/balancebeam"));
    end
    out = fullfile(folder, "stats_and_analysis/balancebeam",'crossing_speed_summary.csv');
    writetable(T, out);
    fprintf('Wrote %s with %d rows.\n', out, height(T));
  

