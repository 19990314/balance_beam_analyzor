%% Simple Weight Change Plot
% Y-axis = Weight (g)
% X-axis = Days (from row 1 of CSV)

clear; clc; close all;

%% ==================== LOAD DATA ====================

% Load CSV file
[filename, filepath] = uigetfile('*.csv', 'Select weight data CSV file');
if filename == 0
    error('No file selected');
end

fullPath = fullfile(filepath, filename);

% Read CSV - first row as variable names (days)
data = readtable(fullPath, 'ReadVariableNames', true);

fprintf('Loaded: %s\n', filename);
fprintf('Data size: %d rows × %d columns\n', height(data), width(data));

% DEBUG: Show what we loaded
disp('First few rows:');
disp(data(1:min(3, height(data)), :));

%% ==================== EXTRACT DATA ====================

% Extract days from column headers (skip first column which is mouse IDs)
colNames = data.Properties.VariableNames(2:end);

% Try to convert column names to numbers (days)
days = zeros(1, length(colNames));
for i = 1:length(colNames)
    % Remove any 'x' prefix that MATLAB adds (e.g., 'x12' -> '12')
    colName = colNames{i};
    colName = strrep(colName, 'x', '');
    colName = strrep(colName, 'Var', '');
    
    % Try to convert to number
    dayNum = str2double(colName);
    if ~isnan(dayNum)
        days(i) = dayNum;
    else
        % If not a number, just use sequential
        days(i) = i;
    end
end

fprintf('Days: %s\n', mat2str(days));

% Extract mouse IDs from first column
mouseIDs = string(data{:, 1});

% Extract weights (all columns except first)
weights = table2array(data(:, 2:end));

% Convert to numeric if needed
if ~isnumeric(weights)
    weights_numeric = zeros(size(weights));
    for i = 1:numel(weights)
        if isnumeric(weights(i))
            weights_numeric(i) = weights(i);
        else
            weights_numeric(i) = str2double(string(weights(i)));
        end
    end
    weights = weights_numeric;
end

% Replace 0 and NaN with NaN
weights(weights == 0) = NaN;

nMice = size(weights, 1);
nDays = size(weights, 2);

fprintf('Processed: %d mice, %d days\n', nMice, nDays);

% DEBUG: Check each mouse's data
fprintf('\n=== DATA CHECK ===\n');
for i = 1:nMice
    validPoints = sum(~isnan(weights(i, :)));
    if validPoints > 0
        fprintf('%s: %d valid points (%.1f - %.1f g)\n', ...
            mouseIDs(i), validPoints, ...
            min(weights(i, :), [], 'omitnan'), ...
            max(weights(i, :), [], 'omitnan'));
    else
        fprintf('%s: NO DATA\n', mouseIDs(i));
    end
end

%% ==================== DEFINE GROUPS ====================

% Define groups (case-insensitive)
snrDTA_list = ["SC29", "SC30", "SC31", "SC32", "SC04", "SC05", "SC06", ...
               "SC09", "SC10", "SC11", "SC12"];
control_list = ["SC33", "SC34", "SC08", "SC13", "SC14"];

% Assign groups
groups = strings(nMice, 1);
for i = 1:nMice
    mouseID_clean = upper(strtrim(string(mouseIDs(i))));
    
    if ismember(mouseID_clean, upper(snrDTA_list))
        groups(i) = "SNr-DTA";
    elseif ismember(mouseID_clean, upper(control_list))
        groups(i) = "Control";
    else
        groups(i) = "Unknown";
    end
end

% Print assignments
fprintf('\n=== GROUP ASSIGNMENTS ===\n');
for i = 1:nMice
    fprintf('%s -> %s\n', mouseIDs(i), groups(i));
end

%% ==================== COLORS ====================

% Base colors
snr_color = [0.80, 0.20, 0.20];  % Red
ctrl_color = [0.20, 0.35, 0.75]; % Blue
unknown_color = [0.5, 0.5, 0.5]; % Gray

% Assign color to each mouse
colors = zeros(nMice, 3);
for i = 1:nMice
    if groups(i) == "SNr-DTA"
        colors(i, :) = snr_color;
    elseif groups(i) == "Control"
        colors(i, :) = ctrl_color;
    else
        colors(i, :) = unknown_color;
    end
end

%% ==================== PLOT ====================

figure('Color', 'w', 'Position', [100, 100, 1000, 600]);
hold on;

% Counter for mice with data
nPlotted = 0;

% Plot each mouse
for i = 1:nMice
    w = weights(i, :);
    
    % Skip if no data
    if all(isnan(w))
        fprintf('Skipping %s (no data)\n', mouseIDs(i));
        continue;
    end
    
    % Plot smooth curve
    plot(days, w, '-o', ...
        'Color', colors(i, :), ...
        'LineWidth', 2, ...
        'MarkerSize', 6, ...
        'MarkerFaceColor', colors(i, :), ...
        'MarkerEdgeColor', 'k', ...
        'DisplayName', sprintf('%s (%s)', mouseIDs(i), groups(i)));
    
    nPlotted = nPlotted + 1;
end

fprintf('\nPlotted %d/%d mice\n', nPlotted, nMice);

if nPlotted == 0
    error('No mice had valid data to plot. Check CSV format.');
end

% Labels
xlabel('Days', 'FontSize', 13, 'FontWeight', 'bold');
ylabel('Weight (g)', 'FontSize', 13, 'FontWeight', 'bold');
title('Body Weight Changes Over Time', 'FontSize', 14, 'FontWeight', 'bold');

% Grid
grid on;
set(gca, 'GridAlpha', 0.2);

% Legend
legend('Location', 'best', 'FontSize', 10);

% Axes
set(gca, 'FontSize', 11, 'LineWidth', 1.2, 'Box', 'off');

%% ==================== SAVE ====================

exportgraphics(gcf, fullfile(filepath, 'weight_plot.png'), 'Resolution', 300);
exportgraphics(gcf, fullfile(filepath, 'weight_plot.pdf'), 'ContentType', 'vector');

fprintf('\nSaved: weight_plot.png and .pdf\n');