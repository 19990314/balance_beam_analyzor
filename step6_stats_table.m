%% step6_stats_table.m
% Appends new cohort data to an existing stats meta file.
%
% Workflow:
%   1. Select the existing meta CSV (e.g. beamwalking_time.csv).
%      Its column names define the output schema — baseline_* columns are
%      filled from the baseline session CSV, all other metric columns from
%      the post session CSV.
%   2. Select baseline session CSV (e.g. beamwalking_time_and_speed_B2.csv).
%   3. Select post session CSV     (e.g. beamwalking_time_and_speed_B4.csv).
%   4. Repeat steps 2-3 for every additional cohort; cancel baseline picker
%      to stop.
%   5. New rows are appended to the meta table and saved with a timestamp.
%
% Column mapping from source CSVs:
%   meta column "baseline_X"      → look for column "X" in baseline CSV
%   meta column "postinjection_X" → look for "postinjection_X" first,
%                                   then fall back to "X" in post CSV
%   meta column "X" (other)       → look for "X" in post CSV
%
% Rows whose Note column is non-empty have their metrics set to NaN.

clear; clc;

%% ==================== BOOKKEEPING COLUMNS (never treated as metrics) ====================
bookkeepCols = {'ID','Days','Group','Day','Note','Video', ...
                'ValueToPlot','Slips'};

%% ==================== SELECT META FILE ====================

[mFile, mDir] = uigetfile('*.csv', 'Select existing meta CSV (e.g. beamwalking_time.csv)');
if isequal(mFile, 0)
    error('No meta file selected. Exiting.');
end
metaPath = fullfile(mDir, mFile);
fprintf('Meta file: %s\n', metaPath);

tMeta = readtable(metaPath);

% Normalize ID / Group to string in meta
for col = {'ID','Group'}
    if ismember(col{1}, tMeta.Properties.VariableNames)
        v = tMeta.(col{1});
        if iscell(v);       tMeta.(col{1}) = string(v);
        elseif isnumeric(v); tMeta.(col{1}) = string(v); end
    end
end

metaCols = tMeta.Properties.VariableNames;

% Separate meta columns into baseline-mapped and post-mapped
baselineMeta = {};   % meta column names starting with "baseline_"
postMeta     = {};   % all other non-bookkeeping meta columns

for i = 1:numel(metaCols)
    col = metaCols{i};
    if ismember(col, bookkeepCols); continue; end
    if startsWith(col, 'baseline_')
        baselineMeta{end+1} = col; %#ok<AGROW>
    else
        postMeta{end+1} = col; %#ok<AGROW>
    end
end

fprintf('Meta schema:\n');
fprintf('  Baseline-mapped columns (%d): %s\n', numel(baselineMeta), strjoin(baselineMeta,', '));
fprintf('  Post-mapped columns    (%d): %s\n', numel(postMeta),     strjoin(postMeta,', '));

%% ==================== SELECT OUTPUT FOLDER ====================

outputDir = uigetdir(mDir, 'Select output folder for updated stats CSV');
if isequal(outputDir, 0)
    error('No output folder selected. Exiting.');
end

%% ==================== COLLECT & PROCESS COHORT PAIRS ====================

newRows   = {};
cohortNum = 0;

while true
    %% Pick baseline file
    [bFile, bDir] = uigetfile('*.csv', ...
        sprintf('Select BASELINE CSV (cohort %d) — cancel to finish', cohortNum+1));
    if isequal(bFile, 0); break; end

    %% Pick post file
    [pFile, pDir] = uigetfile('*.csv', ...
        sprintf('Select POST CSV (cohort %d)', cohortNum+1), bDir);
    if isequal(pFile, 0)
        fprintf('No post file for cohort %d — skipping.\n', cohortNum+1);
        continue;
    end

    cohortNum = cohortNum + 1;
    baselinePath = fullfile(bDir, bFile);
    postPath     = fullfile(pDir, pFile);

    fprintf('\n--- Cohort %d ---\n  Baseline: %s\n  Post: %s\n', ...
        cohortNum, baselinePath, postPath);

    tBase = readtable(baselinePath);
    tPost = readtable(postPath);

    %% Normalize ID / Group / Note to string
    for tbl = {'tBase','tPost'}
        t = eval(tbl{1});
        for col = {'ID','Group','Note'}
            if ismember(col{1}, t.Properties.VariableNames)
                v = t.(col{1});
                if iscell(v);        t.(col{1}) = string(v);
                elseif isnumeric(v); t.(col{1}) = repmat("", height(t), 1); end
            end
        end
        eval([tbl{1} ' = t;']);
    end

    %% Apply Note masking in each source table
    for tbl = {'tBase','tPost'}
        t = eval(tbl{1});
        if ismember('Note', t.Properties.VariableNames)
            flagged = strtrim(t.Note) ~= "";
            if any(flagged)
                fprintf('  Nulling %d flagged rows in %s\n', sum(flagged), tbl{1});
                numVars = t.Properties.VariableNames( ...
                    varfun(@isnumeric, t, 'OutputFormat', 'uniform'));
                for c = 1:numel(numVars)
                    t.(numVars{c})(flagged) = NaN;
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

        % Days = total number of post-injection days for this animal
        totalDays = nPost;

        for dIdx = 1:nPost
            row = struct();
            row.ID    = mID;
            % Days = actual Day value from source post CSV
            % Day  = Days - 1 (sequential 1-based index)
            row.Days  = postRows.Day(dIdx);
            row.Group = grp;
            row.Day   = row.Days - 1;

            % --- Baseline component columns ---
            % Mirror each post component column → look up in baseline CSV
            for c = 1:numel(postMeta)
                metaCol = postMeta{c};
                if endsWith(metaCol, '_total_time'); continue; end
                stripped = metaCol(numel('postinjection_')+1:end);  % e.g. CrossingTime_sec
                baseCol  = ['baseline_' stripped];                   % e.g. baseline_CrossingTime_sec
                if dIdx <= nBase
                    if ismember(stripped, baseRows.Properties.VariableNames)
                        v = baseRows.(stripped)(dIdx);
                    elseif ismember(baseCol, baseRows.Properties.VariableNames)
                        v = baseRows.(baseCol)(dIdx);
                    else
                        v = NaN;
                    end
                else
                    v = NaN;
                end
                row.(baseCol) = v;
            end
            % baseline_total_time = CrossingTime + PauseTime + CrawlingTime
            bVals = [row.baseline_CrossingTime_sec, row.baseline_PauseTime_sec, row.baseline_CrawlingTime_sec];
            if dIdx <= nBase && any(~isnan(bVals))
                row.baseline_total_time = sum(bVals(~isnan(bVals)));
            else
                row.baseline_total_time = NaN;
            end

            % --- Post-mapped meta columns ---
            for c = 1:numel(postMeta)
                metaCol = postMeta{c};
                if endsWith(metaCol, '_total_time'); continue; end
                if ismember(metaCol, postRows.Properties.VariableNames)
                    v = postRows.(metaCol)(dIdx);
                else
                    stripped = metaCol(numel('postinjection_')+1:end);
                    if ismember(stripped, postRows.Properties.VariableNames)
                        v = postRows.(stripped)(dIdx);
                    else
                        v = NaN;
                    end
                end
                row.(metaCol) = v;
            end
            % postinjection_total_time = CrossingTime + PauseTime + CrawlingTime
            pVals = [row.postinjection_CrossingTime_sec, row.postinjection_PauseTime_sec, row.postinjection_CrawlingTime_sec];
            if any(~isnan(pVals))
                row.postinjection_total_time = sum(pVals(~isnan(pVals)));
            else
                row.postinjection_total_time = NaN;
            end

            % --- Speed columns (MedianSpeed_cm_s_pauseIncluded/Excluded) ---
            for pfxPair = {{'baseline_', baseRows, dIdx <= nBase}, ...
                           {'postinjection_', postRows, true}}
                pfx    = pfxPair{1}{1};
                srcTbl = pfxPair{1}{2};
                hasRow = pfxPair{1}{3};
                for spd = {'MedianSpeed_cm_s_pauseIncluded', 'MedianSpeed_cm_s_pauseExcluded'}
                    outCol = [pfx spd{1}];
                    if hasRow
                        if ismember(spd{1}, srcTbl.Properties.VariableNames)
                            row.(outCol) = srcTbl.(spd{1})(dIdx);
                        elseif ismember([pfx spd{1}], srcTbl.Properties.VariableNames)
                            row.(outCol) = srcTbl.([pfx spd{1}])(dIdx);
                        else
                            row.(outCol) = NaN;
                        end
                    else
                        row.(outCol) = NaN;
                    end
                end
            end

            % ValueToPlot = postinjection_total_time
            row.ValueToPlot = row.postinjection_total_time;

            newRows{end+1} = row; %#ok<AGROW>
        end
    end
end

%% ==================== APPEND & SAVE ====================

if isempty(newRows)
    error('No new rows generated. No cohort pairs were processed.');
end

tNew = struct2table(vertcat(newRows{:}));

% New speed columns to add to the output schema
speedCols = {'baseline_MedianSpeed_cm_s_pauseIncluded', ...
             'baseline_MedianSpeed_cm_s_pauseExcluded', ...
             'postinjection_MedianSpeed_cm_s_pauseIncluded', ...
             'postinjection_MedianSpeed_cm_s_pauseExcluded'};

% Add any missing meta columns to tNew (NaN for unmatched)
for c = 1:numel(metaCols)
    if ~ismember(metaCols{c}, tNew.Properties.VariableNames)
        tNew.(metaCols{c}) = NaN(height(tNew), 1);
    end
end

% Add speed columns to tMeta (blank for existing rows) and tNew (if missing)
for c = 1:numel(speedCols)
    col = speedCols{c};
    if ~ismember(col, tMeta.Properties.VariableNames)
        tMeta.(col) = NaN(height(tMeta), 1);
    end
    if ~ismember(col, tNew.Properties.VariableNames)
        tNew.(col) = NaN(height(tNew), 1);
    end
end

% Build unified column order: meta cols + speed cols (deduplicated)
allOutCols = [metaCols, speedCols(~ismember(speedCols, metaCols))];

% Rename Days → Experiment_Day in both tables
for tbl = {'tMeta', 'tNew'}
    t = eval(tbl{1});
    if ismember('Days', t.Properties.VariableNames)
        t.Properties.VariableNames{'Days'} = 'Experiment_Day';
    end
    eval([tbl{1} ' = t;']);
end
allOutCols = strrep(allOutCols, 'Days', 'Experiment_Day');

% Align both tables to allOutCols before vertcat
for tbl = {'tMeta', 'tNew'}
    t = eval(tbl{1});
    t = t(:, allOutCols(ismember(allOutCols, t.Properties.VariableNames)));
    eval([tbl{1} ' = t;']);
end

% Append to meta table
tOut = vertcat(tMeta, tNew);

% Save with timestamp
ts = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
[~, baseName, ext] = fileparts(mFile);
outputFileName = [baseName '_' ts ext];
outPath = fullfile(outputDir, outputFileName);

% Write CSV with blank cells instead of "NaN"
fid = fopen(outPath, 'w');
% Header row
fprintf(fid, '%s\n', strjoin(tOut.Properties.VariableNames, ','));
% Data rows
for r = 1:height(tOut)
    parts = cell(1, width(tOut));
    for ci = 1:width(tOut)
        val = tOut{r, ci};
        if iscell(val); val = val{1}; end
        if isstring(val) || ischar(val)
            parts{ci} = char(val);
        elseif isnumeric(val) && isnan(val)
            parts{ci} = '';
        else
            parts{ci} = num2str(val, '%.10g');
        end
    end
    fprintf(fid, '%s\n', strjoin(parts, ','));
end
fclose(fid);

fprintf('\nAppended %d new rows to meta table (%d total rows).\nSaved to:\n  %s\n', ...
    height(tNew), height(tOut), outPath);
