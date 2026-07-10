%% step6_stats_table.m
% Exports a per-animal × per-post-day statistics CSV combining baseline
% and post-injection metrics from step3 output files.
%
% Output columns (one row per animal per post day):
%   ID, Group, Day (sequential 1,2,...), ActualDay,
%   baseline_<metric>  (mean over all valid baseline days),
%   post_<metric>      (per-day post value),
%   delta_<metric>     (post - baseline mean)
%
% Rows flagged in the Note column are excluded from metric values
% (their metric cells are set to NaN) but the row structure is kept.
% Mice in miceToExclude are dropped entirely.

clear; clc;

%% ==================== COHORT FILE MAP ====================
cohortFiles = {
    {'\\moorelaboratory.dts.usc.edu\Shared\Shuting\P1-SNr\B2_cohort_2_baseline_bahavior\stats_and_analysis\balancebeam\beamwalking_time_and_speed_B2.csv', ...
     '\\moorelaboratory.dts.usc.edu\Shared\Shuting\P1-SNr\B4_cohort_2_post_injection_bahavior\stats_and_analysis\balancebeam\beamwalking_time_and_speed_B4.csv'}, ...
    {'\\moorelaboratory.dts.usc.edu\Shared\Shuting\P1-SNr\B3_cohort_3_baseline_bahavior\stats_and_analysis\balancebeam\beamwalking_time_and_speed_B3.csv', ...
     '\\moorelaboratory.dts.usc.edu\Shared\Shuting\P1-SNr\B5_cohort_3_post_injection_bahavior\stats_and_analysis\balancebeam\beamwalking_time_and_speed_B5.csv'}, ...
    {'\\moorelaboratory.dts.usc.edu\Shared\Shuting\P1-SNr\B6_cohort_4_baseline_behavior\stats_and_analysis\balancebeam\beamwalking_time_and_speed_B6.csv', ...
     '\\moorelaboratory.dts.usc.edu\Shared\Shuting\P1-SNr\B7_cohort_4_post_injection_behavior\stats_and_analysis\balancebeam\beamwalking_time_and_speed_B7.csv'}, ...
    {'\\moorelaboratory.dts.usc.edu\Shared\Shuting\P1-SNr\B8_cohort_5_baseline_behavior\stats_and_analysis\balancebeam\beamwalking_time_and_speed_B8.csv', ...
     '\\moorelaboratory.dts.usc.edu\Shared\Shuting\P1-SNr\B9_cohort5_post_injection_behavior\stats_and_analysis\balancebeam\beamwalking_time_and_speed_B9.csv'}, ...
};

%% ==================== SETTINGS ====================

% Mice to exclude globally
miceToExclude = [];   % e.g. ["SC01", "LM45"]

% Output file name
outputFileName = 'beamwalking_stats_table.csv';

% Where to save (user selects via dialog)
default_output = '\\moorelaboratory.dts.usc.edu\Shared\Shuting\P1-SNr';
outputDir = uigetdir(default_output, 'Select output folder for stats CSV');
if isequal(outputDir, 0)
    error('No output folder selected. Exiting.');
end

%% ==================== LOAD & POOL ALL COHORTS ====================

allTables = {};

for iCohort = 1:numel(cohortFiles)
    basePath = cohortFiles{iCohort}{1};
    postPath = cohortFiles{iCohort}{2};

    tBase         = readtable(basePath);
    tBase.Session = repmat("baseline", height(tBase), 1);

    tPost         = readtable(postPath);
    tPost.Session = repmat("post", height(tPost), 1);

    allTables{end+1} = tBase; %#ok<AGROW>
    allTables{end+1} = tPost; %#ok<AGROW>
end

% Align columns across all tables before concatenating.
allCols = {};
for k = 1:numel(allTables)
    allCols = union(allCols, allTables{k}.Properties.VariableNames, 'stable');
end
for k = 1:numel(allTables)
    missingCols = setdiff(allCols, allTables{k}.Properties.VariableNames);
    for c = 1:numel(missingCols)
        if strcmp(missingCols{c}, 'Note')
            allTables{k}.Note = repmat({''}, height(allTables{k}), 1);
        else
            allTables{k}.(missingCols{c}) = NaN(height(allTables{k}), 1);
        end
    end
    % Normalize text columns to string so vertcat succeeds
    textCols = {'Note', 'Group', 'ID'};
    for tc = 1:numel(textCols)
        col = textCols{tc};
        if ismember(col, allTables{k}.Properties.VariableNames)
            v = allTables{k}.(col);
            if iscell(v)
                allTables{k}.(col) = string(v);
            elseif isnumeric(v)
                allTables{k}.(col) = repmat("", height(allTables{k}), 1);
            end
        end
    end
    allTables{k} = allTables{k}(:, allCols);
end

allData = vertcat(allTables{:});
allData.ID    = string(allData.ID);
allData.Group = string(allData.Group);

% Null out metrics for Note-flagged rows (keep row, exclude value)
metricCols = allData.Properties.VariableNames;
metricCols = metricCols(~ismember(metricCols, {'ID','Group','Day','Session','Note'}));
numericMetricCols = metricCols(varfun(@isnumeric, allData(:, metricCols), 'OutputFormat', 'uniform'));

if ismember('Note', allData.Properties.VariableNames)
    hasNote = strtrim(allData.Note) ~= "";
    nFlagged = sum(hasNote);
    if nFlagged > 0
        fprintf('Nulling metrics for %d flagged rows (Note non-empty).\n', nFlagged);
        for c = 1:numel(numericMetricCols)
            allData.(numericMetricCols{c})(hasNote) = NaN;
        end
    end
end

% Exclude specified mice
if ~isempty(miceToExclude)
    before = height(allData);
    for i = 1:numel(miceToExclude)
        allData(allData.ID == string(miceToExclude(i)), :) = [];
    end
    fprintf('Excluded %d rows for: %s\n', before - height(allData), ...
        strjoin(string(miceToExclude), ', '));
end

%% ==================== BUILD OUTPUT TABLE ====================

mouseIDs = unique(allData.ID, 'stable');
outRows  = {};

for iMouse = 1:numel(mouseIDs)
    mID   = mouseIDs(iMouse);
    mData = allData(allData.ID == mID, :);
    grp   = mData.Group(1);

    baseRows = mData(mData.Session == "baseline", :);
    postRows = mData(mData.Session == "post",     :);

    if isempty(postRows); continue; end

    % Baseline mean per metric (omitting NaN from flagged rows)
    baseMeans = struct();
    for c = 1:numel(numericMetricCols)
        col = numericMetricCols{c};
        if ismember(col, baseRows.Properties.VariableNames)
            baseMeans.(col) = mean(baseRows.(col), 'omitnan');
        else
            baseMeans.(col) = NaN;
        end
    end

    % One output row per post day
    postDays = sort(unique(postRows.Day));
    for dIdx = 1:numel(postDays)
        actualDay = postDays(dIdx);
        dayRow    = postRows(postRows.Day == actualDay, :);
        if isempty(dayRow); continue; end

        row.ID        = mID;
        row.Group     = grp;
        row.DayIndex  = dIdx;
        row.ActualDay = actualDay;

        for c = 1:numel(numericMetricCols)
            col = numericMetricCols{c};
            if ismember(col, dayRow.Properties.VariableNames)
                postVal = dayRow.(col)(1);
            else
                postVal = NaN;
            end
            baseVal = baseMeans.(col);

            row.(['baseline_' col]) = baseVal;
            row.(['post_'     col]) = postVal;
            row.(['delta_'    col]) = postVal - baseVal;
        end

        outRows{end+1} = row; %#ok<AGROW>
    end
end

%% ==================== WRITE CSV ====================

if isempty(outRows)
    error('No output rows generated. Check file paths and column names.');
end

% Convert struct array to table
outTable = struct2table(vertcat(outRows{:}));

outPath = fullfile(outputDir, outputFileName);
writetable(outTable, outPath);
fprintf('\nSaved stats table (%d rows, %d animals) to:\n  %s\n', ...
    height(outTable), numel(mouseIDs), outPath);
