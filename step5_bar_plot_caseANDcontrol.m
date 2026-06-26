%% Balance beam: Baseline vs Post (two bars per mouse)
clearvars; clc;clearvars; clc;
% ---- INPUTS ----
baselineFile = '/Volumes/Shared/Shuting/P1-SNr/B2_cohort_2_baseline_bahavior/stats_and_analysis/balancebeam/summary_behavior_metrics.xlsx';
postFile     = '/Volumes/Shared/Shuting/P1-SNr/B4_cohort_2_post_injection_bahavior/stats_and_analysis/balancebeam/summary_behavior_metrics_post.xlsx';

% Optional: slips (must align with ANIMALID order after grouping)
% If you have slips per mouse per condition, use two vectors:
avgSlips_baseline = [];   % e.g., [2, 4.5, 1.25, 3, 4];
avgSlips_post     = [];   % e.g., [3, 6, 2, 4, 5];

% ---- READ ----
Tb = readtable(baselineFile);
Tp = readtable(postFile);

% Ensure consistent ID type
Tb.ANIMALID = string(Tb.ANIMALID);
Tp.ANIMALID = string(Tp.ANIMALID);

% ---- BUILD A COMMON MOUSE ORDER (union, stable) ----
allIDs = unique([Tb.ANIMALID; Tp.ANIMALID], 'stable');
nMice  = numel(allIDs);

% ---- Helper: compute mean per mouse (returns nMice x 1 in allIDs order) ----
meanByMouse = @(T, varName) arrayfun(@(k) ...
    mean(T.(varName)(T.ANIMALID == allIDs(k)), 'omitnan'), (1:nMice)');

% Baseline means
cross_b = meanByMouse(Tb, 'CrossingTime_sec');
crawl_b = meanByMouse(Tb, 'CrawlingTime_sec');
pause_b = meanByMouse(Tb, 'PauseTime_sec');

% Post means
cross_p = meanByMouse(Tp, 'CrossingTime_sec');
crawl_p = meanByMouse(Tp, 'CrawlingTime_sec');
pause_p = meanByMouse(Tp, 'PauseTime_sec');

% Stacked data matrices (nMice x 3)
data_b = [cross_b, crawl_b, pause_b];
data_p = [cross_p, crawl_p, pause_p];

% ---- PLOT SETTINGS ----
figure('Color','w'); hold on;

colors = [ ...
    0.2, 0.4, 0.6;   % Crossing
    0.4, 0.6, 0.8;   % Crawling
    0.7, 0.7, 0.7];  % Pause

barWidth = 0.35;         % each bar
groupGap = 1.0;          % spacing between mice groups

xCenter  = (1:nMice) * groupGap;           % center per mouse
xBase    = xCenter - barWidth/2;           % baseline bar x
xPost    = xCenter + barWidth/2;           % post bar x

% ---- Stacked bars: Baseline ----
hBarB = bar(xBase, data_b, 'stacked', 'BarWidth', barWidth);
for i = 1:numel(hBarB)
    hBarB(i).FaceColor = colors(i,:);
end

% ---- Stacked bars: Post ----
hBarP = bar(xPost, data_p, 'stacked', 'BarWidth', barWidth);
for i = 1:numel(hBarP)
    hBarP(i).FaceColor = colors(i,:);
end

% ---- Slip dots + labels (optional) ----
dotOffset   = 2;
labelOffset = 5.5;

topB = sum(data_b, 2);
topP = sum(data_p, 2);

% If slips not provided, skip plotting slips
plotSlips = ~isempty(avgSlips_baseline) && ~isempty(avgSlips_post);

if plotSlips
    % Force to column vectors
    avgSlips_baseline = avgSlips_baseline(:);
    avgSlips_post     = avgSlips_post(:);

    if numel(avgSlips_baseline) ~= nMice || numel(avgSlips_post) ~= nMice
        warning('Slip vectors do not match number of mice (%d). Slips will not be plotted.', nMice);
        plotSlips = false;
    end
end

if plotSlips
    % Dots
    plot(xBase, topB + dotOffset, 'kx', 'LineWidth', 1.5, 'MarkerSize', 12);
    plot(xPost, topP + dotOffset, 'kx', 'LineWidth', 1.5, 'MarkerSize', 12);

    % Labels
    for i = 1:nMice
        text(xBase(i), topB(i) + labelOffset, sprintf('%.1f', avgSlips_baseline(i)), ...
            'HorizontalAlignment','center', 'FontSize',12, 'Color','k');
        text(xPost(i), topP(i) + labelOffset, sprintf('%.1f', avgSlips_post(i)), ...
            'HorizontalAlignment','center', 'FontSize',12, 'Color','k');
    end
end

% Dummy handle for slip legend entry (optional)
hSlipLegend = plot(nan, nan, 'kx', 'MarkerSize', 12, 'LineWidth', 1.5);

% ---- Axes formatting ----

ax = gca;
ax.XTick = double(xCenter);              % ensure numeric
ax.XTickLabel = cellstr(string(["SNr-DTA","SNr-DTA","SNr-DTA","Ctrl","Ctrl"])); % safe across MATLAB versions
ax.FontSize = 11;
ax.FontName = 'Arial';
ax.XAxis.TickLabelGapOffset = 13;   % moves them down

xtickangle(0);
ylabel('Time Spent Traversing Beam (sec)', 'FontSize', 12);
title('Balance Beam Performance (Baseline vs Post-Injection)', 'FontSize', 14);

% Condition labels under each mouse group (small, clean)
for i = 1:nMice
    text(xBase(i), -0.02*max([topB; topP]+labelOffset+3), 'Base', ...
        'HorizontalAlignment','center', 'FontSize',10);
    text(xPost(i), -0.02*max([topB; topP]+labelOffset+3), 'Post', ...
        'HorizontalAlignment','center', 'FontSize',10);
end

ylim([0, max([topB; topP]) + labelOffset + 3]);

grid on;

% ---- Legend ----
% Use one set of bar handles (baseline) to represent state colors
%lgd = legend([hBarB, hSlipLegend], {'Crossing', 'Crawling', 'Pausing', 'Slip counts'}, ...
%    'Location', 'northeast', 'FontSize', 13, 'Box', 'off');
lgd = legend([hBarB, hSlipLegend], {'Crossing', 'Crawling', 'Pausing'}, ...
    'Location', 'northeast', 'FontSize', 13, 'Box', 'off');
lgd.Box = 'on';
lgd.EdgeColor = [0 0 0];

% Legend title (version-robust)
if isprop(lgd, 'Title')
    lgd.Title.String = 'States on Beam';
end

% Annotation
annotation('textbox', [0.15, 0.001, 0.7, 0.05], ...
    'String', '*Time metrics and slip counts represent medians across a 4-day testing period.', ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'left', 'FontSize', 10);

print(gcf, 'balance_beam_performance_baseline_vs_postinjection.png', '-dpng', '-r300');