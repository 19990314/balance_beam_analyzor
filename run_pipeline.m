%% run_pipeline
% Full balance beam analysis pipeline.
% Select your project folder once — steps 1, 2, and 3 run in sequence.
%
%   Step 1 — step1_pixel_per_cm_calculator   : calibrate px/cm (skips done)
%   Step 2 — step2_setup_ROI_...             : track & classify (skips done)
%   Step 3 — step3_routeanalysis             : aggregate master CSV

    project_folder = uigetdir(pwd, 'Select Project Folder Containing Videos');
    if isequal(project_folder, 0), error('No folder selected.'); end

    fprintf('\n========== STEP 1: Pixel/cm Calibration ==========\n');
    step1_pixel_per_cm_calculator(project_folder);

    fprintf('\n========== STEP 2: Tracking & Behavior Classification ==========\n');
    step2_setup_ROI_beamregioncalculate_time_statistics(project_folder);

    fprintf('\n========== STEP 3: Aggregate Master Statistics ==========\n');
    step3_routeanalysis(project_folder);

    fprintf('\nPipeline complete.\n');
