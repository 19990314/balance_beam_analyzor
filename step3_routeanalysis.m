%% summarize_beamwalking_speeds
% Writes one CSV with per-file:
%   file, mean_speed_px_s, median_speed_px_s, mean_speed_cm_s, median_speed_cm_s
%
% Active (locomotion) frames = crossing + crawling; pauses excluded.
% Robust to bad startIdx/stopIdx (will skip cropping if indices exceed vector length).

    folder = uigetdir(pwd,'Select folder with trial MAT files');
    if isequal(folder,0), error('No folder selected.'); end

    files = dir(fullfile(folder,"**", '*results.mat'));
    if isempty(files), error('No .mat files found in %s',folder); end

    % Load pixels-per-cm lookup
    ppcFile = fullfile(folder, 'stats_and_analysis/balancebeam/pixels_per_cm_output.xlsx');
    if exist(ppcFile,'file')
        ppcTable = readtable(ppcFile);
    else
        ppcTable = [];
        warning('pixels_per_cm_output.xlsx not found; cm/s columns will be NaN.');
    end

    rows = struct('file',{}, ...
        'mean_speed_px_s',{}, 'median_speed_px_s',{}, ...
        'mean_speed_cm_s',{}, 'median_speed_cm_s',{});

    for k = 1:numel(files)
        fpath = fullfile(files(k).folder, files(k).name);
        d = load(fpath);

        spd_pf = d.speed_px_per_frame(:);
        fps    = d.fps_used;

        % --- Optional crop
        a = []; b = [];
        if isfield(d,'startIdx') && isfield(d,'stopIdx') && ~isempty(d.startIdx) && ~isempty(d.stopIdx)
            a = double(d.startIdx(1));
            b = double(d.stopIdx(1));
            if isfinite(a) && isfinite(b) && a>=1 && b>=a && b<=numel(spd_pf)
                spd_pf = spd_pf(a:b);
            else
                a = []; b = [];
            end
        end

        % Build mask: active = ~pause (includes both crossing AND crawling)
        if isfield(d,'isPause') && ~isempty(d.isPause)
            isP = d.isPause(:);
            if ~isempty(a) && b<=numel(d.isPause)
                isP = isP(a:b);
            end
            mask = ~isP;
        else
            % No pause info — fall back to isCrossing | isCrawling if available
            if isfield(d,'isCrossing') && isfield(d,'isCrawling')
                isX = d.isCrossing(:); isCr = d.isCrawling(:);
                if ~isempty(a) && b<=numel(isX), isX = isX(a:b); isCr = isCr(a:b); end
                mask = isX | isCr;
            elseif isfield(d,'isCrossing')
                isX = d.isCrossing(:);
                if ~isempty(a) && b<=numel(isX), isX = isX(a:b); end
                mask = isX;
            else
                mask = true(numel(spd_pf),1);
            end
        end

        % Convert to px/s
        spd_ps = spd_pf * fps;

        % Guard: if mask empty, warn and write NaN
        if nnz(mask)==0 || all(isnan(spd_ps(mask)))
            mMean = NaN; mMed = NaN;
            warning('No valid active frames in %s. Writing NaN.', files(k).name);
        else
            mMean = mean(spd_ps(mask),   'omitnan');
            mMed  = median(spd_ps(mask), 'omitnan');
        end

        % Look up px/cm for this file (match on 7-char prefix)
        ppc = NaN;
        if ~isempty(ppcTable)
            prefix = files(k).name(1:min(7,end));
            matchIdx = find(strncmp(ppcTable.VideoName, prefix, length(prefix)), 1);
            if ~isempty(matchIdx)
                ppc = ppcTable.PixelsPerCm(matchIdx);
            else
                warning('No PixelsPerCm match for prefix: %s', prefix);
            end
        end

        % cm/s = px/s / px_per_cm
        mMean_cm = mMean / ppc;
        mMed_cm  = mMed  / ppc;

        rows(end+1) = struct( ... %#ok<AGROW>
            'file',             files(k).name, ...
            'mean_speed_px_s',  mMean, ...
            'median_speed_px_s',mMed, ...
            'mean_speed_cm_s',  mMean_cm, ...
            'median_speed_cm_s',mMed_cm);
    end

    T = struct2table(rows);

    if ~exist(fullfile(folder, "stats_and_analysis/balancebeam"), 'dir')
        mkdir(fullfile(folder, "stats_and_analysis/balancebeam"));
    end
    out = fullfile(folder, "stats_and_analysis/balancebeam", 'beamwalking_speed_pausing_excluded.csv');
    writetable(T, out);
    fprintf('Wrote %s with %d rows.\n', out, height(T));
