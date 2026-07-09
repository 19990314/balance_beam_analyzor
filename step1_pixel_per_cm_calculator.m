function step1_pixel_per_cm_calculator(project_folder)
%% step1_pixel_per_cm_calculator
% Calibrate pixels/cm for each *beam_h.mp4 video.
% Skips videos already present in pixels_per_cm_output.xlsx.
% Can be called standalone (no args) or from run_pipeline.m.

    if nargin < 1 || isempty(project_folder)
        project_folder = uigetdir([], 'Select Folder Containing Videos');
        if isequal(project_folder, 0), error('No folder selected.'); end
    end

    videoFiles = dir(fullfile(project_folder, '**', '*beam_h.mp4'));
    if isempty(videoFiles), error('No *beam_h.mp4 files found.'); end

    outputDir = fullfile(project_folder, 'stats_and_analysis', 'balancebeam');
    if ~exist(outputDir, 'dir'), mkdir(outputDir); end
    outXlsx = fullfile(outputDir, 'pixels_per_cm_output.xlsx');

    if exist(outXlsx, 'file')
        existingT     = readtable(outXlsx);
        existingNames = existingT.VideoName;
    else
        existingT     = table('Size',[0 2], 'VariableTypes',{'cellstr','double'}, ...
                              'VariableNames',{'VideoName','PixelsPerCm'});
        existingNames = {};
    end

    realLength_cm = 100;
    newNames = {}; newPpc = [];

    for i = 1:numel(videoFiles)
        fname = videoFiles(i).name;
        if any(strcmp(existingNames, fname))
            fprintf('  Skipping %s (already calibrated)\n', fname);
            continue;
        end

        v = VideoReader(fullfile(videoFiles(i).folder, fname));
        v.CurrentTime = v.Duration / 2;
        frame = readFrame(v);

        figure(1); clf;
        imshow(frame);
        title(['Draw line spanning 100 cm: ', fname], 'Interpreter', 'none');
        h = drawline('Color','r');
        wait(h);

        ppc = norm(h.Position(1,:) - h.Position(2,:)) / realLength_cm;
        hold on;
        midPt = mean(h.Position);
        text(midPt(1), midPt(2), sprintf('%.2f px/cm', ppc), ...
            'Color','y','FontSize',12,'FontWeight','bold');
        pause(1);

        newNames{end+1} = fname; %#ok<AGROW>
        newPpc(end+1)   = ppc;   %#ok<AGROW>
    end

    if ~isempty(newNames)
        newT = table(newNames', newPpc', 'VariableNames', {'VideoName','PixelsPerCm'});
        writetable([existingT; newT], outXlsx);
        fprintf('  Saved %d new calibration(s) to %s\n', numel(newNames), outXlsx);
    else
        fprintf('  All videos already calibrated.\n');
    end
end
