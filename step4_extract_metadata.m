correctFPS = 30;


% Get all *_results.mat files in the current folder
folder = uigetdir(pwd,'Select folder with trial MAT files');
files = dir(fullfile(folder,"**", '*results.mat'));

% Load pixels-per-cm lookup table
ppcFile = fullfile(folder, 'stats_and_analysis/balancebeam/pixels_per_cm_output.xlsx');
ppcTable = readtable(ppcFile);

% Initialize results
FilePrefix = {};
CrossingTime = [];
PauseTime = [];
CrawlingTime = [];
MedianSpeed = [];
MeanSpeed = [];
PixelsPerCm = [];
MedianSpeed_cm = [];
MeanSpeed_cm = [];

% Loop through each file
for k = 1:length(files)
    fileName = fullfile(files(k).folder, files(k).name);
    data = load(fileName);

    % Extract the first 7 characters of the file name
    prefix = files(k).name(1:7);

    % Check required variables exist
    if isfield(data, 'crossing_time_sec') && isfield(data, 'pause_time_sec') && ...
       isfield(data, 'crawling_time_sec') && isfield(data, 'speed_px_per_frame')

        FilePrefix{end+1} = prefix;

        % Apply correction to times
        CrossingTime(end+1) = data.crossing_time_sec;
        PauseTime(end+1)    = data.pause_time_sec;
        CrawlingTime(end+1) = data.crawling_time_sec;

        % Speed in pixels per frame
        medSpeedPx = median(data.speed_px_per_frame);
        meanSpeedPx = mean(data.speed_px_per_frame);
        MedianSpeed(end+1) = medSpeedPx;
        MeanSpeed(end+1) = meanSpeedPx;

        % Look up PixelsPerCm: VideoName column must start with prefix
        matchIdx = find(strncmp(ppcTable.VideoName, prefix, length(prefix)), 1);
        if ~isempty(matchIdx)
            ppc = ppcTable.PixelsPerCm(matchIdx);
        else
            warning('No PixelsPerCm match for prefix: %s', prefix);
            ppc = NaN;
        end
        PixelsPerCm(end+1) = ppc;

        % Convert speed: px/frame * fps / px_per_cm = cm/s
        MedianSpeed_cm(end+1) = medSpeedPx * correctFPS / ppc;
        MeanSpeed_cm(end+1)   = meanSpeedPx * correctFPS / ppc;
    else
        warning('Missing variable in file: %s', fileName);
    end
end

% Combine into a table
T = table(FilePrefix', CrossingTime', PauseTime', CrawlingTime', ...
    MedianSpeed', MeanSpeed', PixelsPerCm', MedianSpeed_cm', MeanSpeed_cm', ...
    'VariableNames', {'FilePrefix', 'CrossingTime_sec', 'PauseTime_sec', 'CrawlingTime_sec', ...
    'MedianSpeed_px_per_frame', 'MeanSpeed_px_per_frame', 'PixelsPerCm', ...
    'MedianSpeed_cm_per_s', 'MeanSpeed_cm_per_s'});

% Save to Excel
writetable(T, fullfile(folder,"stats_and_analysis/balancebeam/summary_behavior_metrics.xlsx"));
disp('Corrected summary saved to summary_behavior_metrics.xlsx');