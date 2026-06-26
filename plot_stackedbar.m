% Read the Excel table
T = readtable('/Volumes/Shared/Shuting/P1-SNr/B4_cohort_2_post_injection_bahavior/stats_and_analysis/balancebeam/summary_behavior_metrics.xlsx');

% Extract mouse labels
mice = string(T.ANIMALID);  % Ensure it's a string array for x-tick labels

% Extract data columns and make sure they are numeric
[G, ANIMALID] = findgroups(T.ANIMALID);
crossing = splitapply(@mean, T.CrossingTime_sec, G);
crawling = splitapply(@mean, T.CrawlingTime_sec, G);
pause    = splitapply(@mean, T.PauseTime_sec, G);


% Combine into numeric matrix for stacked bar
data = [crossing, crawling, pause];
avgSlips = [2, 4.5, 1.25,3,4];

% Create stacked bar plot
figure;
hBar = bar(data, 'stacked', 'BarWidth', 0.7);

% Better color scheme for publication-style
colors = [ ...
    0.2, 0.4, 0.6;   % Crossing - dark teal
    0.4, 0.6, 0.8;   % Crawling - steel blue
    0.7, 0.7, 0.7];  % Pause    - neutral gray

for i = 1:numel(hBar)
    hBar(i).FaceColor = colors(i,:);
end

hold on;
dotOffset = 2;   % Higher offset for dots
labelOffset =5.5; % Higher offset for text

% Compute x-coordinates for placing dots (middle of each bar group)
x = 1:length(avgSlips);

% Compute the top of each stacked bar to place slip dots above them
topOfBars = sum(data, 2);

% Plot slips as black dots
hDot = plot(x, topOfBars + dotOffset, 'kx', 'MarkerFaceColor', 'k', 'LineWidth', 1.5, 'MarkerSize', 12);

% Add slip value annotations
for i = 1:length(avgSlips)
    text(x(i), topOfBars(i) + labelOffset, sprintf('%.1f', avgSlips(i)), ...
        'HorizontalAlignment', 'center', 'FontSize', 12, 'Color', 'k');
end

hSlipLegend = plot(nan, nan, 'kx', 'MarkerSize', 12, 'LineWidth', 1.5);

% Axis and labels
set(gca, 'XTickLabel', ANIMALID, 'FontSize', 12, 'FontName','Arial');
ylabel('Time Spent Traversing Beam (sec)', 'FontSize', 12);
ylim([0, max(topOfBars + labelOffset + 3)]);
title('Balance Beam Performance', 'FontSize', 14);


% Legend
lgd = legend([hBar, hSlipLegend], {'Crossing', 'Crawling', 'Pausing', "Slip counts"}, ...
             'Location', 'northeast', ...
             'FontSize', 13, ...
             'Box', 'off');
lgd.Box = 'on'; 
lgd.EdgeColor = [0 0 0]; 

% Add title to legend — this works across more MATLAB versions
lgd.Title.String = 'States on Beam';

% Add annotation text below the plot
annotation('textbox', [0.15, 0.01, 0.7, 0.05], ...
    'String', '*Time metrics and slip counts represent averages across a 4-day testing period.', ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'left', 'FontSize', 10);

grid on;
print(gcf, 'balance_beam_performance.png', '-dpng', '-r300');