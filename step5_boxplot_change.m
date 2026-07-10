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
    {'/path/to/B4/beamwalking_time_and_speed_B4_baseline.csv', ...
     '/path/to/B4/beamwalking_time_and_speed_B4_post.csv'}, ...
    {'/path/to/B5/beamwalking_time_and_speed_B5_baseline.csv', ...
     '/path/to/B5/beamwalking_time_and_speed_B5_post.csv'}, ...
};

%% ==================== SETTINGS ====================

% Metric column name (must match step3 CSV column headers exactly)
% Examples:
%   'CrossingTime_sec'              'CrawlingTime_sec'    'PauseTime_sec'
%   'MedianSpeed_cm_s_pauseExcluded'  'MeanSpeed_cm_s_pauseExcluded'
%   'MedianSpeed_cm_s_pauseIncluded'  'CrossingPct'
metric = 'MedianSpeed_cm_s_pauseExcluded';

% Day windows (Day column in step3 CSV, extracted from filename _d<N>_)
%   window1: days in the BASELINE CSV to average
%   window2: days in the POST CSV to average
% Change = mean(window2) - mean(window1)
% Use [] to include all days in that session
window1Days = [1, 2];
window2Days = [3, 4];

% Mice to exclude globally (leave empty [] to keep all)
% These IDs are removed from ALL cohorts before any computation.
miceToExclude = [];   % e.g. ["SC01", "LM45", "SC04"]

% Where to save figures (defaults to folder of first baseline CSV)
outputDir = fileparts(cohortFiles{1}{1});

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
% Tables from different cohorts or sessions may have different column sets
% (e.g. one CSV has PixelsPerCm, another doesn't). Missing columns are
% filled with NaN so vertcat succeeds.
allCols = {};
for k = 1:numel(allTables)
    allCols = union(allCols, allTables{k}.Properties.VariableNames, 'stable');
end
for k = 1:numel(allTables)
    missingCols = setdiff(allCols, allTables{k}.Properties.VariableNames);
    for c = 1:numel(missingCols)
        allTables{k}.(missingCols{c}) = NaN(height(allTables{k}), 1);
    end
    % Reorder to match allCols
    allTables{k} = allTables{k}(:, allCols);
end

allData       = vertcat(allTables{:});
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

    % Window 1: baseline session
    w1 = mData(mData.Session == "baseline", :);
    if ~isempty(window1Days)
        w1 = w1(ismember(w1.Day, window1Days), :);
    end

    % Window 2: post session
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

snrColors  = makeShades(dot_snr_color,  max(nSNR, 1));
ctrlColors = makeShades(dot_ctrl_color, max(nCtrl, 1));

%% ==================== FIGURE ====================

fig = figure('Color', 'w', 'Units', 'inches', 'Position', [1 1 3.5 4]);
hold on;

boxWidth = 0.35;
xSNR = 1; xCtrl = 2;

% Helper: draw Mean±SEM box with 2×SEM whiskers
function drawBox(xPos, vals, boxW, fillColor)
    if isempty(vals); return; end
    n   = sum(~isnan(vals));
    mV  = mean(vals, 'omitnan');
    sV  = std(vals, 'omitnan') / sqrt(n);
    rectangle('Position', [xPos-boxW/2, mV-sV, boxW, 2*sV], ...
        'FaceColor', fillColor, 'EdgeColor', 'k', 'LineWidth', 1.5);
    plot([xPos-boxW/2, xPos+boxW/2], [mV mV], 'k-', 'LineWidth', 2);
    plot([xPos, xPos], [mV-2*sV, mV-sV], 'k-', 'LineWidth', 1.5);
    plot([xPos, xPos], [mV+sV,   mV+2*sV], 'k-', 'LineWidth', 1.5);
end

drawBox(xSNR,  snrVals,  boxWidth, snr_color);
drawBox(xCtrl, ctrlVals, boxWidth, ctrl_color);

% Individual dots
for i = 1:nSNR
    scatter(xSNR  + (rand-0.5)*0.2, snrVals(i),  60, snrColors(i,:),  'filled', ...
        'MarkerEdgeColor', 'k', 'LineWidth', 0.8);
end
for i = 1:nCtrl
    scatter(xCtrl + (rand-0.5)*0.2, ctrlVals(i), 60, ctrlColors(i,:), 'filled', ...
        'MarkerEdgeColor', 'k', 'LineWidth', 0.8);
end

% Zero reference line
yL = ylim; ylim([min(yL(1), 0), yL(2)]);
plot([0.5, 2.5], [0, 0], 'k--', 'LineWidth', 1, 'HandleVisibility', 'off');

% Significance bracket
yL2 = ylim; ylim([yL2(1), yL2(2) * 1.15]);
if nSNR >= 2 && nCtrl >= 2
    [p, ~] = ranksum(snrVals, ctrlVals);
    addSigBracket(gca, xSNR, xCtrl, p);
    fprintf('\nMann-Whitney U: p = %.4g\n', p);
    if nSNR > 0
        fprintf('SNr-DTA: %.3f ± %.3f (mean ± SEM)\n', ...
            mean(snrVals,'omitnan'), std(snrVals,'omitnan')/sqrt(nSNR));
    end
    if nCtrl > 0
        fprintf('Control:  %.3f ± %.3f (mean ± SEM)\n', ...
            mean(ctrlVals,'omitnan'), std(ctrlVals,'omitnan')/sqrt(nCtrl));
    end
else
    fprintf('Not enough animals for statistics (need ≥2 per group).\n');
end

% Axis labels
xlim([0.5, 2.5]);
xticks([xSNR, xCtrl]);
xticklabels({'SNr-DTA', 'Control'});

w1Str = strjoin(string(window1Days), '&');
w2Str = strjoin(string(window2Days), '&');
yLabel = sprintf('\\Delta%s\n(Day %s minus Day %s)', ...
    strrep(metric, '_', ' '), w2Str, w1Str);
ylabel(yLabel, 'FontSize', 10, 'FontWeight', 'bold');

if title_flag
    title(strrep(metric, '_', ' '), 'FontSize', 11, 'FontWeight', 'bold');
end

set(gca, 'FontSize', 12, 'LineWidth', 1.2, 'Box', 'off', ...
    'TickDir', 'out', 'FontName', 'Helvetica');

% Legend
if legend_flag
    dB1 = patch(NaN, NaN, snr_color,  'EdgeColor', 'k', 'LineWidth', 1.5);
    dB2 = patch(NaN, NaN, ctrl_color, 'EdgeColor', 'k', 'LineWidth', 1.5);
    legend([dB1, dB2], {'SNr-DTA', 'Control'}, 'Location', 'best', ...
        'FontSize', 10, 'Box', 'on');
end

%% ==================== EXPORT ====================

metricShort = strrep(metric, '_', '-');
baseName = fullfile(outputDir, sprintf('%s_%s_change_Day%s-vs-Day%s', ...
    version, metricShort, w1Str, w2Str));

exportgraphics(fig, [baseName '.pdf'], 'ContentType', 'vector');
fprintf('\nSaved: %s.pdf\n', baseName);

if png_flag
    exportgraphics(fig, [baseName '.png'], 'Resolution', 300);
    fprintf('Saved: %s.png\n', baseName);
end
if ai_flag
    set(fig, 'Renderer', 'painters');
    set(findall(fig, '-property', 'FontName'), 'FontName', 'Helvetica');
    print(fig, [baseName '.eps'], '-depsc', '-painters');
    fprintf('Saved (EPS/AI): %s.eps\n', baseName);
end

%% ==================== HELPER ====================

function addSigBracket(ax, x1, x2, p)
    yl   = ylim(ax);
    span = yl(2) - yl(1);
    topY = yl(2) - span * 0.12;
    barH = span * 0.02;
    line(ax, [x1, x1, x2, x2], [topY-barH, topY, topY, topY-barH], ...
        'Color', 'k', 'LineWidth', 1.2, 'HandleVisibility', 'off');
    if     p < 0.001; starStr = '***';
    elseif p < 0.01;  starStr = '**';
    elseif p < 0.05;  starStr = '*';
    else;             starStr = 'ns';
    end
    text(ax, (x1+x2)/2, topY + span*0.02, sprintf('%s\np = %.3g', starStr, p), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
        'FontSize', 10, 'FontWeight', 'bold', 'FontName', 'Helvetica');
end
