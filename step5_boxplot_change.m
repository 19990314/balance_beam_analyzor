%% step5_boxplot_change.m
% Plots the CHANGE in a beam-walking metric between two day windows,
% comparing SNr-DTA vs Control across multiple cohorts.
%
% For each animal:
%   value = mean(metric over window2Days in post CSV)
%         - mean(metric over window1Days in baseline CSV)
%
% Box style: Mean ± SEM rectangle + 2×SEM whiskers + individual dots
% Statistics: Mann-Whitney U with significance bracket
%
% INPUTS: cohortFiles map — one entry per cohort, each with a baseline
%         and a post-injection step3 output CSV.

clear; clc;

%% ==================== COHORT FILE MAP ====================
% Add one cell per cohort: {baselineCSV, postCSV}
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
default_output_figure = "\\moorelaboratory.dts.usc.edu\Shared\Shuting\P1-SNr\Figures-P1-SNr\G17_change_in_beam_time_and_speed";

%% ==================== SETTINGS ====================

% Metric column name (must match step3 CSV column headers exactly)
% Examples:
%   'CrossingTime_sec'              'CrawlingTime_sec'    'PauseTime_sec'
%   'MedianSpeed_cm_s_pauseExcluded'  'MeanSpeed_cm_s_pauseExcluded'
%   'MedianSpeed_cm_s_pauseIncluded'  'CrossingPct'
metric = 'CrossingTime_sec';

% Day windows (Day column in step3 CSV, extracted from filename _d<N>_)
%   window1: days in the BASELINE CSV to average
%   window2: days in the POST CSV to average
% Change = mean(window2) - mean(window1)
% Use [] to include all days in that session
window1Days = [2, 3];
window2Days = [4, 5];

% Mice to exclude globally (leave empty [] to keep all)
% These IDs are removed from ALL cohorts before any computation.
miceToExclude = [];   % e.g. ["SC01", "LM45", "SC04"]

% Where to save figures (user selects via dialog)
outputDir = uigetdir(default_output_figure, 'Select output folder for figures');
if isequal(outputDir, 0)
    error('No output folder selected. Exiting.');
end

% Output file prefix
version = 'v1';

% Export flags
ai_flag     = true;    % EPS for Illustrator
png_flag    = false;
title_flag  = true;
legend_flag = false;

%% ==================== COLOR SCHEME ====================
% Lab convention: green = SNr-DTA, grey = Control

snr_color      = [0.45 0.75 0.45];   % light green  — box fill
ctrl_color     = [0.55 0.55 0.55];   % light grey   — box fill
dot_snr_color  = [0.25 0.55 0.25];   % darker green — dots
dot_ctrl_color = [0.35 0.35 0.35];   % darker grey  — dots

makeShades = @(base, n) ...
    (1 - linspace(0.10, 0.45, n)') .* base + ...
     linspace(0.10, 0.45, n)'  .* [1 1 1];

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
    % Normalize text columns to string so vertcat succeeds regardless of
    % whether readtable produced cell-of-char or string array.
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
            % already string — leave as-is
        end
    end
    allTables{k} = allTables{k}(:, allCols);
end

allData       = vertcat(allTables{:});

% Null out the metric value for flagged rows so they are excluded from
% averaging via omitnan, but the mouse is kept if other valid rows exist.
if ismember('Note', allData.Properties.VariableNames) && ismember(metric, allData.Properties.VariableNames)
    hasNote = strtrim(allData.Note) ~= "";
    nFlagged = sum(hasNote);
    if nFlagged > 0
        fprintf('Nulling metric for %d flagged rows (Note column non-empty).\n', nFlagged);
        allData.(metric)(hasNote) = NaN;
    end
end
allData.ID    = string(allData.ID);
allData.Group = string(allData.Group);

% Exclude specified mice (global list)
if ~isempty(miceToExclude)
    before = height(allData);
    for i = 1:numel(miceToExclude)
        allData(allData.ID == string(miceToExclude(i)), :) = [];
    end
    fprintf('Excluded %d rows for: %s\n', before - height(allData), ...
        strjoin(string(miceToExclude), ', '));
end

%% ==================== COMPUTE CHANGE PER ANIMAL ====================

mouseIDs = unique(allData.ID, 'stable');
nMice    = numel(mouseIDs);

resultID    = strings(0,1);
resultGroup = strings(0,1);
resultDelta = zeros(0,1);

for iMouse = 1:nMice
    mID   = mouseIDs(iMouse);
    mData = allData(allData.ID == mID, :);

    w1 = mData(mData.Session == "baseline", :);
    if ~isempty(window1Days)
        w1 = w1(ismember(w1.Day, window1Days), :);
    end

    w2 = mData(mData.Session == "post", :);
    if ~isempty(window2Days)
        w2 = w2(ismember(w2.Day, window2Days), :);
    end

    if isempty(w1) || isempty(w2)
        fprintf('  Skipping %s — missing data in one or both windows\n', mID);
        continue;
    end

    avg1 = mean(w1.(metric), 'omitnan');
    avg2 = mean(w2.(metric), 'omitnan');
    if isnan(avg1) || isnan(avg2); continue; end

    resultID(end+1,1)    = mID;
    resultGroup(end+1,1) = mData.Group(1);
    resultDelta(end+1,1) = avg2 - avg1;
end

fprintf('\n');

%% ==================== SPLIT BY GROUP ====================

snrMask  = resultGroup == "SNr-DTA";
ctrlMask = resultGroup == "Ctrl";

snrVals  = resultDelta(snrMask);
ctrlVals = resultDelta(ctrlMask);
snrIDs   = resultID(snrMask);
ctrlIDs  = resultID(ctrlMask);

nSNR  = numel(snrVals);
nCtrl = numel(ctrlVals);

fprintf('SNr-DTA (%d): %s\n', nSNR, strjoin(snrIDs, ', '));
fprintf('Control  (%d): %s\n', nCtrl, strjoin(ctrlIDs, ', '));

if nSNR == 0 && nCtrl == 0
    error('No animals found. Check file paths and Day/Group columns in CSV.');
end

% ---- Group color lookup (add new groups here as needed) ----
groupDef = { ...
    'SNr-DTA',      [0.45 0.75 0.45], [0.25 0.55 0.25]; ...
    'Ctrl',         [0.55 0.55 0.55], [0.35 0.35 0.35]; ...
    'SNr-DTA miss', [0.70 0.55 0.80], [0.50 0.35 0.60]; ...
};  % {name, boxColor, dotColor}
fallbackBox = [0.70 0.70 0.85];
fallbackDot = [0.50 0.50 0.65];

% Preferred display order, then any unlisted groups alphabetically
preferredOrder = {'SNr-DTA', 'SNr-DTA miss', 'Ctrl'};
presentGroups  = unique(resultGroup, 'stable');
orderedGroups  = {};
for g = 1:numel(preferredOrder)
    if any(presentGroups == preferredOrder{g})
        orderedGroups{end+1} = preferredOrder{g}; %#ok<AGROW>
    end
end
for g = 1:numel(presentGroups)
    if ~any(strcmp(orderedGroups, char(presentGroups(g))))
        orderedGroups{end+1} = char(presentGroups(g)); %#ok<AGROW>
    end
end
nGroups   = numel(orderedGroups);
boxWidth  = 0.50;   % wider boxes (ref: 0.5)
groupGap  = 0.80;   % center-to-center spacing (ref: 0.8)

%% ==================== FIGURE ====================

figW = max(3.0, 1.2 + nGroups * 0.85);   % widen automatically for more groups
figure('Color', 'w', 'Units', 'inches', 'Position', [1 1 figW 4.5]);
hold on;

w1Str = strjoin(string(window1Days), '&');
w2Str = strjoin(string(window2Days), '&');

for iG = 1:nGroups
    gName = orderedGroups{iG};
    gVals = resultDelta(resultGroup == gName);
    xPos  = 1 + (iG-1) * groupGap;

    % Resolve colors
    rowIdx = find(strcmp(groupDef(:,1), gName), 1);
    if ~isempty(rowIdx)
        bColor = groupDef{rowIdx, 2};
        dColor = groupDef{rowIdx, 3};
    else
        bColor = fallbackBox;
        dColor = fallbackDot;
    end
    dotShades = makeShades(dColor, max(numel(gVals), 1));

    % Box
    if ~isempty(gVals)
        nB = sum(~isnan(gVals));
        mB = mean(gVals, 'omitnan');
        sB = std(gVals, 'omitnan') / sqrt(nB);
        rectangle('Position', [xPos-boxWidth/2, mB-sB, boxWidth, 2*sB], ...
            'FaceColor', bColor, 'EdgeColor', 'k', 'LineWidth', 1.5);
        plot([xPos-boxWidth/2, xPos+boxWidth/2], [mB mB], 'k-', 'LineWidth', 2);
        plot([xPos, xPos], [mB-2*sB, mB-sB], 'k-', 'LineWidth', 1.5);
        plot([xPos, xPos], [mB+sB,   mB+2*sB], 'k-', 'LineWidth', 1.5);
    end

    % Dots
    for i = 1:numel(gVals)
        scatter(xPos + (rand-0.5)*0.12, gVals(i), 60, dotShades(i,:), 'filled', ...
            'MarkerEdgeColor', 'k', 'LineWidth', 0.8);
    end

    fprintf('%s (%d): %s\n', gName, numel(gVals), ...
        strjoin(resultID(resultGroup == gName), ', '));
end

% X positions for all groups
xPositions = 1 + (0:nGroups-1) * groupGap;
xLeft  = xPositions(1);
xRight = xPositions(end);

% Ensure y-axis includes 0
yL = ylim; ylim([min(yL(1), 0), yL(2)]);

% Significance bracket (pairwise: first two groups only, if both have ≥2)
yL2 = ylim; ylim([yL2(1), yL2(2) * 1.15]);
if nGroups >= 2
    g1Vals = resultDelta(resultGroup == orderedGroups{1});
    g2Vals = resultDelta(resultGroup == orderedGroups{2});
    if numel(g1Vals) >= 2 && numel(g2Vals) >= 2
        [p, ~] = ranksum(g1Vals, g2Vals);

        ax   = gca;
        yl   = ylim(ax);
        span = yl(2) - yl(1);
        topY = yl(2) - span * 0.12;
        barH = span * 0.02;
        bracketMid = (xPositions(1) + xPositions(2)) / 2;
        line(ax, [xPositions(1), xPositions(1), xPositions(2), xPositions(2)], ...
            [topY-barH, topY, topY, topY-barH], ...
            'Color', 'k', 'LineWidth', 1.2, 'HandleVisibility', 'off');
        if     p < 0.001; starStr = '***';
        elseif p < 0.01;  starStr = '**';
        elseif p < 0.05;  starStr = '*';
        else;             starStr = 'ns';
        end
        text(ax, bracketMid, topY + span*0.02, sprintf('%s\np = %.3g', starStr, p), ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
            'FontSize', 12, 'FontWeight', 'bold', 'FontName', 'Helvetica');

        fprintf('\nMann-Whitney U (%s vs %s): p = %.4g\n', ...
            orderedGroups{1}, orderedGroups{2}, p);
    end
end

% Axes
xlim([xLeft - 0.55, xRight + 0.55]);
xticks(xPositions);
xticklabels(orderedGroups);
ylabel('\Delta Crossing Time', 'FontSize', 13, 'FontWeight', 'bold');

set(gca, 'FontSize', 13, 'LineWidth', 1.2, 'Box', 'off', ...
    'TickDir', 'out', 'FontName', 'Helvetica');

% Halve left and right margins
ax = gca;
pos = ax.Position;                         % [left bottom width height]
leftMargin  = pos(1);
rightMargin = 1 - pos(1) - pos(3);
pos(1) = leftMargin  / 2;
pos(3) = 1 - pos(1) - rightMargin / 2;
ax.Position = pos;

% Subtitle: metric + window info as small text under the figure
subtitleStr = sprintf('\\Delta Crossing Time (s) |  Day %s - Day %s', ...
    w2Str, w1Str);
annotation('textbox', [0.05, 0.001, 0.90, 0.045], 'String', subtitleStr, ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
    'FontSize', 7, 'FontAngle', 'italic', 'FontName', 'Helvetica');

if legend_flag
    hPatches = gobjects(nGroups, 1);
    for iG = 1:nGroups
        rowIdx = find(strcmp(groupDef(:,1), orderedGroups{iG}), 1);
        bColor = fallbackBox;
        if ~isempty(rowIdx); bColor = groupDef{rowIdx, 2}; end
        hPatches(iG) = patch(NaN, NaN, bColor, 'EdgeColor', 'k', 'LineWidth', 1.5);
    end
    legend(hPatches, orderedGroups, 'Location', 'best', 'FontSize', 10, 'Box', 'on');
end

%% ==================== EXPORT ====================

metricShort = strrep(metric, '_', '-');
baseName = fullfile(outputDir, sprintf('%s_%s_change_Day%s-minus-Day%s', ...
    version, metricShort, w1Str, w2Str));

set(gcf, 'Renderer', 'painters');
set(findall(gcf, '-property', 'FontName'), 'FontName', 'Helvetica');

print(gcf, [baseName '.pdf'], '-dpdf', '-painters');
fprintf('\nSaved: %s.pdf\n', baseName);

if png_flag
    print(gcf, [baseName '.png'], '-dpng', '-r300');
    fprintf('Saved: %s.png\n', baseName);
end
if ai_flag
    print(gcf, [baseName '.eps'], '-depsc', '-painters');
    fprintf('Saved (EPS/AI): %s.eps\n', baseName);
end
