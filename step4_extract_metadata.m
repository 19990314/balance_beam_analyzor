correctFPS = 30;


% Get all *_results.mat files in the current folder
folder = uigetdir(pwd,'Select folder with trial MAT files');
files = dir(fullfile(folder,"**", '*results.mat'));

% Initialize results
FilePrefix = {};
CrossingTime = [];
PauseTime = [];
CrawlingTime = [];
MedianSpeed = [];

% Loop through each file
for k = 1:length(files)
    fileName = fullfile(files(k).folder, files(k).name);
    data = load(fileName);
    
    % Extract the first 5 characters of the file name
    prefix = files(k).name(1:7);
    
    % Check required variables exist
    if isfield(data, 'crossing_time_sec') && isfield(data, 'pause_time_sec') && ...
       isfield(data, 'crawling_time_sec') && isfield(data, 'speed_px_per_frame')

        FilePrefix{end+1} = prefix;

        % Apply correction to times
        CrossingTime(end+1) = data.crossing_time_sec;
        PauseTime(end+1)    = data.pause_time_sec;
        CrawlingTime(end+1) = data.crawling_time_sec;

        % Speed is independent of time, no need to adjust
        MedianSpeed(end+1) = median(data.speed_px_per_frame);
        MeanSpeed(end+1) = mean(data.speed_px_per_frame);
    else
        warning('Missing variable in file: %s', fileName);
    end
end

% Combine into a table
T = table(FilePrefix', CrossingTime', PauseTime', CrawlingTime', MedianSpeed, MeanSpeed', ...
    'VariableNames', {'FilePrefix', 'CrossingTime_sec', 'PauseTime_sec', 'CrawlingTime_sec', 'MedianSpeed_px_per_frame', 'MeanSpeed_px_per_frame'});

% Save to Excel
writetable(T, fullfile(folder,"stats_and_analysis/balancebeam/summary_behavior_metrics.xlsx"));
disp('Corrected summary saved to summary_behavior_metrics.xlsx');