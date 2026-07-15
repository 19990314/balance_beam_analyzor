%% step6_stats_table.m
% Builds a paired baseline/post statistics CSV from step3 output files.
%
% For each cohort pair the user supplies:
%   - Baseline CSV  (e.g. beamwalking_time_and_speed_B2.csv)
%   - Post CSV      (e.g. beamwalking_time_and_speed_B4.csv)
%
% Matching rule: animals are matched by ID; days are paired by sequential
% index (baseline day 1 ↔ post day 1, baseline day 2 ↔ post day 2, …).
% Rows whose Note column is non-empty have their metrics set to NaN.
%
% Output: one row per animal × post day, with baseline_<metric> and
%         post_<metric> columns for every numeric metric in the CSVs.

clear; clc;

%% ==================== COHORT FILE MAP ====================
% Each row: {baselineCSV, postCSV}
% You can add more cohort pairs here.
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

% Mice to exclude globally (applied across all cohorts)
miceToExclude = [];   % e.g. ["SC01", "LM45"]

% Output file name
outputFileName = 'beamwalking_stats_table.csv';

% Columns that are bookkeeping, not metrics
excludeCols = {'Video', 'ID', 'Day', 'Days', 'Group', 'Note', ...
               'Slips', 'ValueToPlot', 'baseline_total_time', ...
               'postinjection_total_time'};

%% ==================== SELECT OUTPUT FOLDER ====================

defaultOut = '\\moorelaboratory.dts.usc.edu\Shared\Shuting\P1-SNr\Figures-P1-SNr\Data\Balance Beam';
outputDir = uigetdir(defaultOut, 'Select output folder for stats CSV');
if isequal(outputDir, 0)
    error('No output folder selected. Exiting.');
end

%% ==================== PROCESS COHORTS ====================

outRows = {};

for iCohort = 1:numel(cohortFiles)
    baselinePath = cohortFiles{iCohort}{1};
    postPath     = cohortFiles{iCohort}{2};

    fprintf('\n--- Cohort %d ---\n', iCohort);
    fprintf('  Baseline: %s\n', baselinePath);
    fprintf('  Post:     %s\n', postPath);

    tBase = readtable(baselinePath);
    tPost = readtable(postPath);

    % Normalize ID, Group, Note to string in both tables
    for tbl = {'tBase', 'tPost'}
        t = eval(tbl{1});
        for col = {'ID', 'Group', 'Note'}
            if ismember(col{1}, t.Properties.VariableNames)
                v = t.(col{1});
                if iscell(v)
                    t.(col{1}) = string(v);
                elseif isnumeric(v)
                    t.(col{1}) = repmat("", height(t), 1);
                end
            end
        end
        eval([tbl{1} ' = t;']);
    end

    % Determine metric columns from the POST file
    % (post is the primary data; baseline is matched to it)
    postVars = tPost.Properties.VariableNames;
    postVars = postVars(~ismember(postVars, excludeCols));
    isNum    = varfun(@isnumeric, tPost(:, postVars), 'OutputFormat', 'uniform');
    metricCols = unique(postVars(isNum), 'stable');

    fprintf('  Metrics (%d): %s\n', numel(metricCols), strjoin(metricCols, ', '));

    % Apply Note masking: set metric values to NaN for flagged rows
    for tbl = {'tBase', 'tPost'}
        t = eval(tbl{1});
        if ismember('Note', t.Properties.VariableNames)
            flagged = strtrim(t.Note) ~= "";
            if any(flagged)
                fprintf('  Nulling %d flagged rows in %s\n', sum(flagged), tbl{1});
                for c = 1:numel(metricCols)
                    col = metricCols{c};
                    if ismember(col, t.Properties.VariableNames)
                        t.(col)(flagged) = NaN;
                    end
                end
            end
        end
        eval([tbl{1} ' = t;']);
    end

    % Per-animal pairing
    mouseIDs = unique(tPost.ID, 'stable');

    for iMouse = 1:numel(mouseIDs)
        mID = mouseIDs(iMouse);

        % Skip excluded mice
        if ~isempty(miceToExclude) && any(string(miceToExclude) == mID)
            fprintf('  Skipping excluded mouse: %s\n', mID);
            continue;
        end

        postRows = tPost(tPost.ID == mID, :);
        baseRows = tBase(tBase.ID == mID, :);

        % Sort both by Day number ascending
        postRows = sortrows(postRows, 'Day');
        baseRows = sortrows(baseRows, 'Day');

        nPost = height(postRows);
        nBase = height(baseRows);
        grp   = postRows.Group(1);

        for dIdx = 1:nPost
            row = struct();
            row.ID                  = mID;
            row.Group               = grp;
            row.Day                 = dIdx;
            row.ActualExperimentDay = postRows.Day(dIdx);

            for c = 1:numel(metricCols)
                col = metricCols{c};

                % Post value: this day's row
                if ismember(col, postRows.Properties.VariableNames)
                    postVal = postRows.(col)(dIdx);
                else
                    postVal = NaN;
                end

                % Baseline value: same sequential index (NaN if no baseline row)
                if dIdx <= nBase && ismember(col, baseRows.Properties.VariableNames)
                    baseVal = baseRows.(col)(dIdx);
                else
                    baseVal = NaN;
                end

                row.(['baseline_' col]) = baseVal;
                row.(['post_'     col]) = postVal;
            end

            outRows{end+1} = row; %#ok<AGROW>
        end
    end
end

%% ==================== WRITE CSV ====================

if isempty(outRows)
    error('No output rows generated. Check file paths and column names.');
end

outTable = struct2table(vertcat(outRows{:}));
outPath  = fullfile(outputDir, outputFileName);
writetable(outTable, outPath);

fprintf('\nSaved %d rows (%d animals) to:\n  %s\n', ...
    height(outTable), numel(unique(outTable.ID)), outPath);
