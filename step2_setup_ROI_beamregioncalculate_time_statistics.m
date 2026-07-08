function step2_setup_ROI_beamregioncalculate_time_statistics(dataDir)
%% step2_setup_ROI_beamregioncalculate_time_statistics
% Batch ROI tracking with start/stop selection and OPEN-CURVE-based crawling.
% Skips videos that already have a *_tracking_results.mat — loads saved data
% and re-applies the current crawling classification logic before adding to
% the master summary.
%
% Can be called standalone (no args) or from run_pipeline.m.
%
% Per-video MAT: centers, roiMask, crawlPolylinePts, boundingBox, threshold,
%   startIdx, stopIdx, dt, speed_px_per_frame,
%   isPause, pause_time_sec, isCrawling, crawling_time_sec,
%   isCrossing, crossing_time_sec,
%   pause_pct, crawling_pct, crossing_pct

    if nargin < 1 || isempty(dataDir)
        dataDir = uigetdir(pwd, 'Select folder containing videos');
        if isequal(dataDir, 0), error('No folder selected.'); end
    end

    files = dir(fullfile(dataDir, '**', '*beam_h.mp4'));
    if isempty(files), error('No *beam_h.mp4 files found in %s', dataDir); end

    outDir2 = fullfile(dataDir, 'stats_and_analysis/balancebeam');
    if ~exist(outDir2,'dir'), mkdir(outDir2); end

    pause_thr        = 0.3;   % px/frame threshold for pause
    side_tolerance_px = 5;
    masterRows = {};

    for i = 1:numel(files)
        fname = files(i).name;
        fpath = fullfile(files(i).folder, fname);
        [~, base0] = fileparts(fname);
        outMatCheck = fullfile(dataDir, 'stats_and_analysis/balancebeam', ...
                               sprintf('%s_tracking_results.mat', base0));

            % Skip if already processed — but recompute crawling with current logic
            if exist(outMatCheck, 'file')
                fprintf('\n=== Skipping %s (already processed) ===\n', fname);
                d = load(outMatCheck);
                if isfield(d,'isPause') && isfield(d,'isCrawling') && isfield(d,'dt')
                    % Re-apply current classification logic (crawling independent of pause)
                    isP  = d.isPause(:);
                    isCr = logical(d.isCrawling(:));
                    isCx = ~(isP | isCr);
                    N    = numel(isP);
                    dt_v = d.dt;

                    pause_time_sec_r    = sum(isP)  * dt_v;
                    crawling_time_sec_r = sum(isCr) * dt_v;
                    crossing_time_sec_r = sum(isCx) * dt_v;
                    tot = N * dt_v;

                    % Overwrite fields and re-save if crawling_time changed
                    if abs(crawling_time_sec_r - d.crawling_time_sec) > 1e-9
                        fprintf('    Updating crawling_time_sec: %.2f -> %.2f s\n', ...
                            d.crawling_time_sec, crawling_time_sec_r);
                        d.isCrawling       = isCr;
                        d.isCrossing       = isCx;
                        d.pause_time_sec   = pause_time_sec_r;
                        d.crawling_time_sec= crawling_time_sec_r;
                        d.crossing_time_sec= crossing_time_sec_r;
                        d.pause_pct        = 100*pause_time_sec_r/tot;
                        d.crawling_pct     = 100*crawling_time_sec_r/tot;
                        d.crossing_pct     = 100*crossing_time_sec_r/tot;
                        save(outMatCheck, '-struct', 'd');
                    end

                    masterRows(end+1,:) = {base0, d.pause_time_sec, d.crawling_time_sec, d.crossing_time_sec, ...
                        100*d.pause_time_sec/tot, 100*d.crawling_time_sec/tot, 100*d.crossing_time_sec/tot}; %#ok<AGROW>
                end
                continue;
            end

        fprintf('\n=== Processing %s ===\n', fname);
        vMeta = VideoReader(fpath);
        totalFrames = floor(vMeta.Duration * vMeta.FrameRate);
        fps_vid     = vMeta.FrameRate;
        dt          = 1 / fps_vid;

        % 1) Frame range
        [startIdx, stopIdx, canceled] = selectFrameRangeUI(fpath, totalFrames);
        if canceled, fprintf('  Skipped by user: %s\n', fname); continue; end

        % 2) ROI polygon
        midFrame = readFrameAtIndex(fpath, floor(totalFrames/2));
        figure(1); clf; imshow(midFrame);
        title(['Draw beam ROI polygon: ' fname], 'Interpreter','none');
        roiPoly = drawpolygon('Color','g');
        wait(roiPoly);
        pts = roiPoly.Position;
        if size(pts,1) < 3
            fprintf('  Empty ROI; skipping %s\n', fname); continue;
        end
        roiMask = poly2mask(pts(:,1), pts(:,2), size(midFrame,1), size(midFrame,2));
        boundingBox = regionprops(roiMask,'BoundingBox').BoundingBox;

        % 3) Draw crawl boundary (open polyline)
        figure(1); clf; imshow(midFrame); hold on;
        title('Draw OPEN polyline for crawl boundary (double-click to finish)');
        crawlPolylinePts = [];
        try
            h = drawpolyline('Color','r');
            wait(h); crawlPolylinePts = h.Position;
        catch
            [xv,yv] = getline(gca); crawlPolylinePts = [xv(:),yv(:)];
        end
        if size(crawlPolylinePts,1) < 2
            fprintf('  Need >=2 crawl points; skipping %s\n', fname); continue;
        end

        segs     = polylineToSegments(crawlPolylinePts);
        threshold = 50;

        % 4) Background model from first frames in ROI
        vr = VideoReader(fpath);
        bgFrames = min(30, totalFrames);
        bgStack  = zeros([size(roiMask) bgFrames], 'uint8');
        for fi = 1:bgFrames
            fr = readFrame(vr);
            gr = rgb2gray(fr);
            gr(~roiMask) = 0;
            bgStack(:,:,fi) = gr;
        end
        bgModel = uint8(median(double(bgStack),3));

        % 5) Track
        vr = VideoReader(fpath);
        centers = []; isCrawling = []; refSide = NaN;
        frameIdx = 0;
        while hasFrame(vr)
            fr = readFrame(vr);
            frameIdx = frameIdx + 1;
            if frameIdx < startIdx || frameIdx > stopIdx
                centers(end+1,:)   = [NaN NaN]; %#ok<AGROW>
                isCrawling(end+1)  = false;      %#ok<AGROW>
                continue;
            end
            gr = rgb2gray(fr);
            gr(~roiMask) = 0;
            fg = abs(double(gr) - double(bgModel)) > threshold;
            fg = fg & roiMask;
            fg = imclose(fg, strel('disk',3));
            CC = bwconncomp(fg);
            if CC.NumObjects == 0
                centers(end+1,:)  = [NaN NaN]; %#ok<AGROW>
                isCrawling(end+1) = false;      %#ok<AGROW>
                continue;
            end
            stats = regionprops(CC,'Area','Centroid','BoundingBox');
            [~,mi] = max([stats.Area]);
            cx = stats(mi).Centroid(1); cy = stats(mi).Centroid(2);
            centers(end+1,:) = [cx cy]; %#ok<AGROW>

            bb   = stats(mi).BoundingBox;
            bPts = [bb(1) bb(2); bb(1)+bb(3) bb(2); bb(1)+bb(3) bb(2)+bb(4); bb(1) bb(2)+bb(4)];
            crawlingNow = false;
            for si = 1:size(segs,1)
                [sides, dists] = signedSideAndDistance(bPts, segs(si,:));
                if isnan(refSide)
                    refSide = sign(median(sides,'omitnan'));
                    if refSide == 0, refSide = 1; end
                end
                crawlingNow = any(sides==-refSide | dists<=side_tolerance_px);
                if crawlingNow, break; end
            end
            isCrawling(end+1) = crawlingNow; %#ok<AGROW>
        end

        % 6) Speed
        N = numel(centers(:,1));
        step = sqrt(diff(centers(:,1)).^2 + diff(centers(:,2)).^2);
        if numel(step) == N-1
            speed_px_per_frame = [0; step];
            speed_px_per_frame([false; isnan(step)]) = NaN;
        end

        isPause    = speed_px_per_frame < pause_thr;
        isPause(~isfinite(speed_px_per_frame)) = false;
        isCrawling = logical(isCrawling(:));
        isCrossing = ~(isPause | isCrawling);

        pause_time_sec    = sum(isPause)    * dt;
        crawling_time_sec = sum(isCrawling) * dt;
        crossing_time_sec = sum(isCrossing) * dt;
        total_time_sec    = N * dt;

        pause_pct    = 100 * (pause_time_sec    / (N*dt));
        crawling_pct = 100 * (crawling_time_sec / (N*dt));
        crossing_pct = 100 * (crossing_time_sec / (N*dt));

        outDir = fullfile(dataDir, 'stats_and_analysis/balancebeam');
        if ~exist(outDir,'dir'), mkdir(outDir); end
        base   = base0;
        outMat = fullfile(outDir, sprintf('%s_tracking_results.mat', base));
        save(outMat, 'centers','roiMask','crawlPolylinePts','boundingBox', ...
            'threshold','startIdx','stopIdx','dt', ...
            'speed_px_per_frame', ...
            'isPause','pause_time_sec','isCrawling','crawling_time_sec', ...
            'isCrossing','crossing_time_sec','total_time_sec', ...
            'refSide','side_tolerance_px','pause_pct','crawling_pct','crossing_pct');

        fprintf('  Saved: %s\n', outMat);
        masterRows(end+1,:) = {base, pause_time_sec, crawling_time_sec, crossing_time_sec, ...
            pause_pct, crawling_pct, crossing_pct}; %#ok<AGROW>
    end

    if ~isempty(masterRows)
        masterSummary = cell2table(masterRows,'VariableNames', ...
            {'VideoName','PauseTime_sec','CrawlingTime_sec','CrossingTime_sec', ...
             'PausePct','CrawlingPct','CrossingPct'});
        save(fullfile(outDir2,'crossing_pausing_crawling_timein_seconds+percentage.mat'),'masterSummary');
        writetable(masterSummary, fullfile(outDir2,'crossing_pausing_crawling_timein_seconds+percentage.csv'));
        fprintf('\nMaster summary saved to %s\n', outDir2);
        disp(masterSummary);
    else
        fprintf('No videos processed.\n');
    end
end

%% ── local helpers ──────────────────────────────────────────────────────────

function [startIdx, stopIdx, canceled] = selectFrameRangeUI(fpath, totalFrames)
    canceled = false;
    vr = VideoReader(fpath);
    fig = figure('Name','Set Start Frame','NumberTitle','off');
    sl  = uicontrol('Style','slider','Min',1,'Max',totalFrames,'Value',1, ...
                    'Units','normalized','Position',[0.05 0.05 0.75 0.08], ...
                    'SliderStep',[1/(totalFrames-1) 10/(totalFrames-1)]);
    btn = uicontrol('Style','pushbutton','String','Confirm Start', ...
                    'Units','normalized','Position',[0.82 0.05 0.15 0.08]);
    ax  = axes('Parent',fig,'Position',[0.05 0.15 0.90 0.80]);
    addlistener(sl,'Value','PostSet',@(~,~) showFrame(vr,round(sl.Value),ax,totalFrames));
    showFrame(vr,1,ax,totalFrames);
    btn.Callback = @(~,~) uiresume(fig);
    uiwait(fig);
    if ~isvalid(fig), canceled=true; startIdx=1; stopIdx=totalFrames; return; end
    startIdx = round(sl.Value);
    close(fig);

    fig2 = figure('Name','Set Stop Frame','NumberTitle','off');
    sl2  = uicontrol('Style','slider','Min',startIdx,'Max',totalFrames,'Value',totalFrames, ...
                     'Units','normalized','Position',[0.05 0.05 0.75 0.08], ...
                     'SliderStep',[1/(totalFrames-startIdx+1) 10/(totalFrames-startIdx+1)]);
    btn2 = uicontrol('Style','pushbutton','String','Confirm Stop', ...
                     'Units','normalized','Position',[0.82 0.05 0.15 0.08]);
    ax2  = axes('Parent',fig2,'Position',[0.05 0.15 0.90 0.80]);
    addlistener(sl2,'Value','PostSet',@(~,~) showFrame(vr,round(sl2.Value),ax2,totalFrames));
    showFrame(vr,totalFrames,ax2,totalFrames);
    btn2.Callback = @(~,~) uiresume(fig2);
    uiwait(fig2);
    if ~isvalid(fig2), canceled=true; stopIdx=totalFrames; return; end
    stopIdx = round(sl2.Value);
    close(fig2);
end

function showFrame(vr, idx, ax, totalFrames)
    idx = max(1, min(totalFrames, idx));
    vr.CurrentTime = (idx-1)/vr.FrameRate;
    if hasFrame(vr)
        fr = readFrame(vr);
        imshow(fr,'Parent',ax);
        title(ax, sprintf('Frame %d / %d', idx, totalFrames));
    end
end

function frame = readFrameAtIndex(fpath, idx)
    vr = VideoReader(fpath);
    vr.CurrentTime = max(0, (idx-1)/vr.FrameRate);
    frame = readFrame(vr);
end

function verts = findPolygonVertices(mask)
    B = bwboundaries(mask, 'noholes');
    if isempty(B), verts = zeros(0,2); return; end
    b = B{1};
    verts = [b(:,2) b(:,1)];
end

function segs = polylineToSegments(pts)
    segs = [pts(1:end-1,:) pts(2:end,:)];
end

function [side, dist] = signedSideAndDistance(points, seg)
    x1=seg(1); y1=seg(2); x2=seg(3); y2=seg(4);
    dx=x2-x1; dy=y2-y1;
    L = sqrt(dx^2+dy^2);
    if L < 1e-9, side=zeros(size(points,1),1); dist=zeros(size(points,1),1); return; end
    nx=-dy/L; ny=dx/L;
    v = [points(:,1)-x1, points(:,2)-y1];
    side = v(:,1)*nx + v(:,2)*ny;
    dist = abs(side);
    side = sign(side);
end
