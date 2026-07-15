%% step6_stats_table.m
% Builds a paired baseline/post statistics CSV from step3 output files.
%
% You will be prompted to select baseline and post CSV files (one pair at
% a time). Keep selecting pairs; cancel the baseline picker to stop.
%
% Matching rule: animals matched by ID; days paired by sequential index
% (baseline day 1 ↔ post day 1, baseline day 2 ↔ post day 2, …).
% Rows whose Note column is non-empty have their metrics set to NaN.
%
% Output columns:
%   ID, Group, Day (1-based sequential), ActualExperimentDay,
%   baseline_<col>  — every numeric column from the baseline CSV
%   post_<col>      — every numeric column from the post CSV

clear; clc;

%% ==================== SETTINGS ====================

% Columns to skip when extracting metrics (bookkeeping only)
skipCols = {'ID','Day','Days','Group','Note','Video', ...
            'Slips','ValueToPlot'};

outputFileName = 'beamwalking_stats_table.csv';

%% ==================== SELECT OUTPUT FOLDER ====================

defaultOut = '\\moorelaboratory.dts.usc.edu\Shared\Shuting\P1-SNr\Figures-P1-SNr\Data\Balance Beam';
outputDir = uigetdir(defaultOut, 'Select output folder for stats CSV');
if isequal(outputDir, 0)
    error('No output folder selected. Exiting.');
end

%% ==================== COLLECT FILE PAIRS ====================

outRows = {};
cohortNum = 0;

while true
    % Pick baseline file
    [bFile, bDir] = uigetfile('*.csv', ...
        sprintf('Select BASELINE CSV (cohort %d) — cancel to finish', cohortNum+1));
    if isequal(bFile, 0)
        break;   % user cancelled — done collecting
    end

    % Pick post file
    [pFile, pDir] = uigetfile('*.csv', ...
        sprintf('Select POST CSV (cohort %d)', cohortNum+1), bDir);
    if isequal(pFile, 0)
        fprintf('No post file selected for cohort %d — skipping.\n', cohortNum+1);
        continue;
    end

    cohortNum = cohortNum + 1;
    baselinePath = fullfile(bDir, bFile);
    postPath     = fullfile(pDir, pFile);

    fprintf('\n--- Cohort %d ---\n', cohortNum);
    fprintf('  Baseline: %s\n', baselinePath);
    fprintf('  Post:     %s\n', postPath);

    %% Load tables
    tBase = readtable(baselinePath);
    tPost = readtable(postPath);

    %% Normalize ID / Group / Note to string in both tables
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

    %% Identify numeric metric columns in each file separately
    baseVars = tBase.Properties.VariableNames;
    baseVars = baseVars(~ismember(baseVars, skipCols));
    isNumB   = varfun(@isnumeric, tBase(:, baseVars), 'OutputFormat', 'uniform');
    baseMetrics = baseVars(isNumB);

    postVars = tPost.Properties.VariableNames;
    postVars = postVars(~ismember(postVars, skipCols));
    isNumP   = varfun(@isnumeric, tPost(:, postVars), 'OutputFormat', 'uniform');
    postMetrics = postVars(isNumP);

    fprintf('  Baseline metrics (%d): %s\n', numel(baseMetrics), strjoin(baseMetrics, ', '));
    fprintf('  Post metrics     (%d): %s\n', numel(postMetrics), strjoin(postMetrics, ', '));

    %% Apply Note masking (set metric values to NaN for flagged rows)
    for tbl = {'tBase', 'tPost'}
        t = eval(tbl{1});
        if ismember('Note', t.Properties.VariableNames)
            flagged = strtrim(t.Note) ~= "";
            if any(flagged)
                fprintf('  Nulling %d flagged rows in %s\n', sum(flagged), tbl{1});
                if strcmp(tbl{1}, 'tBase')
                    mCols = baseMetrics;
                else
                    mCols = postMetrics;
                end
                for c = 1:numel(mCols)
                    if ismember(mCols{c}, t.Properties.VariableNames)
                        t.(mCols{c})(flagged) = NaN;
                    end
                end
            end
        end
        eval([tbl{1} ' = t;']);
    end

    %% Per-animal pairing by sequential day index
    mouseIDs = unique(tPost.ID, 'stable');

    for iMouse = 1:numel(mouseIDs)
        mID = mouseIDs(iMouse);

        postRows = sortrows(tPost(tPost.ID == mID, :), 'Day');
        baseRows = sortrows(tBase(tBase.ID == mID, :), 'Day');

        nPost = height(postRows);
        nBase = height(baseRows);
        grp   = postRows.Group(1);

        for dIdx = 1:nPost
            row = struct();
            row.ID                  = mID;
            row.Group               = grp;
            row.Day                 = dIdx;
            row.ActualExperimentDay = postRows.Day(dIdx);

            % Baseline columns
            for c = 1:numel(baseMetrics)
                col = baseMetrics{c};
                if dIdx <= nBase
                    row.(['baseline_' col]) = baseRows.(col)(dIdx);
                else
                    row.(['baseline_' col]) = NaN;
                end
            end

            % Post columns
            for c = 1:numel(postMetrics)
                col = postMetrics{c};
                row.(['post_' col]) = postRows.(col)(dIdx);
            end

            outRows{end+1} = row; %#ok<AGROW>
        end
    end
end

%% ==================== WRITE CSV ====================

if isempty(outRows)
    error('No output rows generated. No cohort pairs were processed.');
end

outTable = struct2table(vertcat(outRows{:}));
outPath  = fullfile(outputDir, outputFileName);
writetable(outTable, outPath);

fprintf('\nSaved %d rows (%d cohorts) to:\n  %s\n', ...
    height(outTable), cohortNum, outPath);
