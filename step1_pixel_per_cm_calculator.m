%% step1_pixel_per_cm_calculator
% For each *beam_h.mp4 video, show a mid-video frame and let the user draw
% a line spanning 100 cm on the beam to calibrate pixels/cm.
% Skips any video already present in pixels_per_cm_output.xlsx.

    project_folder = uigetdir([], 'Select Folder Containing Videos');
    if isequal(project_folder, 0), error('No folder selected.'); end

    videoFiles = dir(fullfile(project_folder, '**', '*beam_h.mp4'));
    if isempty(videoFiles), error('No *beam_h.mp4 files found.'); end

    outputDir = fullfile(project_folder, 'stats_and_analysis', 'balancebeam');
    if ~exist(outputDir, 'dir'), mkdir(outputDir); end
    outXlsx = fullfile(outputDir, 'pixels_per_cm_output.xlsx');

    % Load existing results so we can skip already-calibrated videos
    if exist(outXlsx, 'file')
        existingT = readtable(outXlsx);
        existingNames = existingT.VideoName;
    else
        existingT = table('Size',[0 2], 'VariableTypes',{'cellstr','double'}, ...
                          'VariableNames',{'VideoName','PixelsPerCm'});
        existingNames = {};
    end

    realLength_cm = 100;
    newNames = {}; newPpc = [];

    for i = 1:numel(videoFiles)
        fname = videoFiles(i).name;

        % Skip if already calibrated
        if any(strcmp(existingNames, fname))
            fprintf('Skipping %s (already calibrated)\n', fname);
            continue;
        end

        videoPath = fullfile(videoFiles(i).folder, fname);
        v = VideoReader(videoPath);

        % Show mid-video frame
        v.CurrentTime = v.Duration / 2;
        frame = readFrame(v);

        figure(1); clf;
        imshow(frame);
        title(['Draw line spanning 100 cm: ', fname], 'Interpreter', 'none');
        h = drawline('Color','r');
        wait(h);

        pixelDistance = norm(h.Position(1,:) - h.Position(2,:));
        ppc = pixelDistance / realLength_cm;

        hold on;
        midPt = mean(h.Position);
        text(midPt(1), midPt(2), sprintf('%.2f px/cm', ppc), ...
            'Color', 'y', 'FontSize', 12, 'FontWeight', 'bold');
        pause(1);

        newNames{end+1} = fname; %#ok<AGROW>
        newPpc(end+1)   = ppc;   %#ok<AGROW>
    end

    % Append new rows and save
    if ~isempty(newNames)
        newT = table(newNames', newPpc', 'VariableNames', {'VideoName','PixelsPerCm'});
        T = [existingT; newT];
        writetable(T, outXlsx);
        fprintf('Saved %d new calibration(s) to %s\n', numel(newNames), outXlsx);
    else
        fprintf('No new videos to calibrate.\n');
    end
