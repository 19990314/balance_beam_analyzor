function batch_track_roi_tracking()
% Batch ROI tracking with start/stop selection and OPEN-CURVE-based crawling.
% Adds pause/crawl/cross PERCENT columns to master summary.
%
% Categories:
%   • Pause     : speed < 0.3 px/frame
%   • Crawling  : any blob boundary pixel crosses/touches the user-drawn open polyline
%   • Crossing  : ~(Pause | Crawling)
%
% Per-video MAT saves:
%   centers, roiMask, crawlPolylinePts, boundingBox, threshold, fps_used, dt,
%   startIdx, stopIdx, speed_px_per_frame, pause_thr,
%   isPause, pause_time_sec, isCrawling, crawling_time_sec,
%   isCrossing, crossing_time_sec, total_time_sec,
%   refSide, side_tolerance_px
%
% Master MAT saves table 'masterSummary' with columns:
%   Video | PauseTime_sec | CrawlingTime_sec | CrossingTime_sec | PausePct | CrawlingPct | CrossingPct

    %-------------------------------%
    % Select folder and enumerate
    %-------------------------------%
    dataDir = uigetdir(pwd, 'Select folder containing videos');
    files = dir(fullfile(dataDir, '**', '*beam_h.mp4'));  % Change to *.avi if needed

    %-------------------------------%
    % Parameters
    %-------------------------------%
    threshold   = 50;     % 0..255; tweak if needed
    fps_used    = 30;     % analysis/output fps
    dt          = 1 / fps_used;
    pause_thr   = 0.3;    % px/frame
    curve_width = 3;      % px thickness for overlay
    side_tolerance_px = 1.5; % <= this distance to curve counts as "touch"

    %-------------------------------%
    % Master accumulator
    %-------------------------------%
    % Each row: {videoName, pause_sec, crawl_sec, cross_sec, pause_pct, crawl_pct, cross_pct}
    masterRows = {};

    %-------------------------------%
    % Loop videos
    %-------------------------------%
    for i = 1:numel(files)
        try
            fname = files(i).name;
            fpath = fullfile(files(i).folder, fname);
            fprintf('\n=== Processing %s ===\n', fname);

            vMeta = VideoReader(fpath);
            totalFrames = max(1, floor(vMeta.FrameRate * vMeta.Duration));

            % 1) Select start/stop
            [startIdx, stopIdx, canceled] = selectFrameRangeUI(fpath);
            if canceled, fprintf('  Skipped: %s\n', fname); continue; end
            if startIdx >= stopIdx, startIdx = 1; stopIdx = totalFrames; end
            fprintf('  Range: %d -> %d (of %d)\n', startIdx, stopIdx, totalFrames);

            % Get START frame
            vp = VideoReader(fpath);
            firstFrame = readFrameAtIndex(vp, startIdx);
            [H, W, ~] = size(firstFrame);

            % 2) Draw tracking ROI (closed polygon)
            hFig = figure('Name','Draw TRACKING ROI (double-click to finish)','NumberTitle','off');
            imshow(firstFrame, 'Border','tight');
            title('Draw polygon ROI (double-click to finish)');
            roiMask = roipoly();
            close(hFig);
            if isempty(roiMask) || ~any(roiMask(:))
                fprintf('  Empty ROI; skipping %s\n', fname); continue;
            end
            propsROI    = regionprops(roiMask, 'BoundingBox');
            boundingBox = round(propsROI.BoundingBox); % [x y w h]

            % 3) Draw CRAWL BOUNDARY (OPEN polyline)
            hFig = figure('Name','Draw CRAWL BOUNDARY (open polyline)','NumberTitle','off');
            imshow(firstFrame, 'Border','tight');
            title('Draw OPEN polyline for crawl boundary (double-click to finish)');
            crawlPolylinePts = [];
            try
                h = drawpolyline('Color','m','InteractionsAllowed','all');
                wait(h);
                crawlPolylinePts = h.Position;  % [n×2] [x y]
            catch
                [xv, yv] = getline(gca);
                crawlPolylinePts = [xv(:), yv(:)];
            end
            close(hFig);
            if size(crawlPolylinePts,1) < 2
                fprintf('  Need at least 2 points for an open polyline. Skipping %s\n', fname);
                continue;
            end

            % Precompute segments for the polyline
            segs = polylineToSegments(crawlPolylinePts);  % [M×4] [x1 y1 x2 y2]
            segVecs = [segs(:,3)-segs(:,1), segs(:,4)-segs(:,2)]; % [M×2]
            segLens2 = sum(segVecs.^2,2) + eps;

            % Prepare output video
            [~, base, ~] = fileparts(fname);

            if ~exist(fullfile(dataDir, "stats_and_analysis/balancebeam"), 'dir')
                mkdir(fullfile(dataDir, "stats_and_analysis/balancebeam"));
            end
            outVideoPath = fullfile(dataDir, "stats_and_analysis",sprintf('%s_tracked.mp4', base));
            outputVideo  = VideoWriter(outVideoPath);
            outputVideo.FrameRate = fps_used;
            open(outputVideo);

            % Re-open for pass
            v = VideoReader(fpath);
            v.CurrentTime = (startIdx-1)/v.FrameRate;

            % Process
            centers     = [];
            isCrawling  = [];
            refSide     = NaN;   % reference side (+1 or -1) from first detection

            % Visualization
            trackingFig = figure('Name', sprintf('Tracking: %s', fname), 'NumberTitle','off');
            subplot(1,2,1); h1 = imshow(firstFrame); title('Annotated Frame');
            subplot(1,2,2); h2 = imshow(zeros(size(roiMask))); title('Binary ROI');

            roiPolyVerts   = findPolygonVertices(roiMask);
            lineSegmentsForDraw = segs; % [M×4] for insertShape

            frameIdx = startIdx;
            while hasFrame(v) && frameIdx <= stopIdx
                frame = readFrame(v); frameIdx = frameIdx + 1;
                grayFrame = rgb2gray(frame);

                % Mask outside ROI and crop
                maskedFrame = grayFrame; maskedFrame(~roiMask) = 255;
                roiFrame = imcrop(maskedFrame, boundingBox);

                % Threshold + largest blob
                bw = roiFrame < threshold;
                bw = bwareafilt(bw, 1);

                % Centroid
                props = regionprops(bw, 'Centroid');
                if ~isempty(props)
                    localCenter  = props(1).Centroid;
                    globalCenter = [localCenter(1) + boundingBox(1), ...
                                    localCenter(2) + boundingBox(2)];
                else
                    globalCenter = [NaN, NaN];
                end
                centers = [centers; globalCenter]; %#ok<AGROW>

                % Build blob mask in full frame
                blobMaskFull = false(H,W);
                [x1,y1,w,h] = deal(boundingBox(1), boundingBox(2), boundingBox(3), boundingBox(4));
                x2 = min(W, x1 + w - 1); y2 = min(H, y1 + h - 1);
                if x2 >= x1 && y2 >= y1 && any(bw(:))
                    subW = x2 - x1 + 1; subH = y2 - y1 + 1;
                    bwCrop = bw(1:min(subH, size(bw,1)), 1:min(subW, size(bw,2)));
                    blobMaskFull(y1:y1+size(bwCrop,1)-1, x1:x1+size(bwCrop,2)-1) = bwCrop;
                end

                % Crawling by side-of-polyline test on boundary points
                crawlingNow = false;
                if any(blobMaskFull(:))
                    perim = bwperim(blobMaskFull);
                    [py, px] = find(perim);
                    if numel(px) > 400
                        idx = round(linspace(1, numel(px), 400));
                        px = px(idx); py = py(idx);
                    end
                    pts = [px, py]; % [N×2]

                    [sides, dists] = signedSideAndDistance(pts, segs, segVecs, segLens2);

                    if isnan(refSide) && isfinite(globalCenter(1))
                        [s0, d0] = signedSideAndDistance(globalCenter, segs, segVecs, segLens2); %#ok<ASGLU>
                        if s0 == 0, s0 = +1; end   % bias if exactly on the curve
                        refSide = s0;
                    end

                    if ~isnan(refSide)
                        opp   = (sides == -refSide);
                        touch = (dists <= side_tolerance_px);
                        crawlingNow = any(opp | touch);
                    end
                end
                isCrawling = [isCrawling; crawlingNow]; %#ok<AGROW>

                % Annotate
                annotated = frame;
                if ~isempty(roiPolyVerts)
                    annotated = insertShape(annotated, 'Polygon', roiPolyVerts, 'Color', 'green', 'LineWidth', 2);
                end
                annotated = insertShape(annotated, 'Line', lineSegmentsForDraw, 'Color', 'magenta', 'LineWidth', curve_width);
                if ~isnan(globalCenter(1))
                    annotated = insertMarker(annotated, globalCenter, 'o', 'Color', 'blue', 'Size', 5);
                end

                writeVideo(outputVideo, annotated);

                if ishandle(trackingFig)
                    subplot(1,2,1); set(h1, 'CData', annotated); title('Annotated Frame');
                    subplot(1,2,2); set(h2, 'CData', bw); title('Binary ROI (Mouse Tracking)');
                    drawnow;
                end
            end

            close(outputVideo);
            if ishandle(trackingFig), close(trackingFig); end

            % 6) Kinematics & time categories
            N = size(centers,1);
            speed_px_per_frame = zeros(N,1);
            if N >= 2
                dx = diff(centers(:,1)); dy = diff(centers(:,2));
                step = sqrt(dx.^2 + dy.^2);            % N-1
                speed_px_per_frame = [0; step];
                bad = isnan(step);
                speed_px_per_frame([false; bad]) = NaN;
            end

            isPause    = speed_px_per_frame < pause_thr;
            isPause(~isfinite(speed_px_per_frame)) = false;
            isCrawling = logical(isCrawling(:));
            isCrossing = ~(isPause | isCrawling);

            pause_time_sec    = sum(isPause)    * dt;
            crawling_time_sec = sum(isCrawling) * dt;
            crossing_time_sec = sum(isCrossing) * dt;
            total_time_sec    = N * dt; %#ok<NASGU>

            % Percentages of overall analyzed time (start..stop)
            if N > 0
                pause_pct    = 100 * (pause_time_sec    / (N*dt));
                crawling_pct = 100 * (crawling_time_sec / (N*dt));
                crossing_pct = 100 * (crossing_time_sec / (N*dt));
            else
                pause_pct = 0; crawling_pct = 0; crossing_pct = 0;
            end

            % 7) Save per-video MAT
            outMat = fullfile(dataDir, "stats_and_analysis/balancebeam", sprintf('%s_tracking_results.mat', base));
            save(outMat, ...
                'centers', 'roiMask', 'crawlPolylinePts', 'boundingBox', ...
                'threshold', 'fps_used', 'dt', 'startIdx', 'stopIdx', ...
                'speed_px_per_frame', 'pause_thr', ...
                'isPause', 'pause_time_sec', ...
                'isCrawling', 'crawling_time_sec', ...
                'isCrossing', 'crossing_time_sec', ...
                'total_time_sec', 'refSide', 'side_tolerance_px', ...
                'pause_pct', 'crawling_pct', 'crossing_pct');

            fprintf('  ✅ Saved: %s\n', outVideoPath);
            fprintf('  ✅ Saved: %s\n', outMat);

            % 8) Master row (now with percentages)
            masterRows(end+1, :) = { ...
                base, ...
                pause_time_sec, crawling_time_sec, crossing_time_sec, ...
                pause_pct,      crawling_pct,      crossing_pct ...
            }; %#ok<AGROW>

        catch ME
            warning('  ⚠️ Error processing %s: %s', files(i).name, ME.message);
        end
    end

    % 9) Save master summary (7 columns)
    if ~isempty(masterRows)
        masterSummary = cell2table(masterRows, ...
            'VariableNames', {'Video','PauseTime_sec','CrawlingTime_sec','CrossingTime_sec','PausePct','CrawlingPct','CrossingPct'});
        masterMatPath = fullfile(dataDir, 'tracking_master_summary.mat');
        save(masterMatPath, 'masterSummary');
        
        % Also write CSV next to the MAT
masterCsvPath = fullfile(dataDir, 'tracking_master_summary.csv');
try
    writetable(masterSummary, masterCsvPath);  % includes headers
    fprintf('\n🧾 Master CSV saved: %s\n', masterCsvPath);
catch ME
    warning('Could not write master CSV: %s', ME.message);
end

        fprintf('\n📦 Master summary saved: %s\n', masterMatPath);
        disp(masterSummary);
    else
        fprintf('\n(No videos processed; master summary not created.)\n');
    end

    disp('Done.');
end

%% --------- Helpers --------- %%
function [startIdx, stopIdx, canceled] = selectFrameRangeUI(videoPath)
    canceled = false;
    v = VideoReader(videoPath);
    totalFrames = max(1, floor(v.FrameRate * v.Duration));
    firstFrame = readFrameAtIndex(v, 1);

    f = figure('Name','Select Start/Stop Frames','NumberTitle','off',...
               'MenuBar','none','ToolBar','none','Units','normalized',...
               'Position',[0.2 0.15 0.6 0.7],'Color','w','KeyPressFcn',@onKey,...
               'CloseRequestFcn',@onClose);
    ax = axes('Parent',f,'Position',[0.05 0.12 0.9 0.78]);
    hImg = imshow(firstFrame,'Parent',ax);
    title(ax,'Use slider. Set Start (S), Set Stop (E), then Done.');

    sldr = uicontrol('Parent',f,'Style','slider','Units','normalized',...
                     'Position',[0.05 0.03 0.9 0.04],'Min',1,'Max',totalFrames,'Value',1,...
                     'SliderStep',[1/(totalFrames-1), 10/(totalFrames-1)],'Callback',@onSlide);
    uicontrol('Parent',f,'Style','pushbutton','String','Set Start (S)',...
              'Units','normalized','Position',[0.05 0.92 0.18 0.06],'Callback',@onSetS);
    uicontrol('Parent',f,'Style','pushbutton','String','Set Stop (E)',...
              'Units','normalized','Position',[0.25 0.92 0.18 0.06],'Callback',@onSetE);
    uicontrol('Parent',f,'Style','pushbutton','String','Done',...
              'Units','normalized','Position',[0.77 0.92 0.18 0.06],'Callback',@onDone);
    txt = uicontrol('Parent',f,'Style','text','Units','normalized',...
                    'Position',[0.47 0.92 0.28 0.06],'BackgroundColor','w','HorizontalAlignment','left',...
                    'String',sprintf('Frame: 1 / %d | Time: %.3f s', totalFrames, 0));

    startIdx=1; startSet=false; stopIdx=totalFrames; stopSet=false;
    uiwait(f);
    if ~ishandle(f), canceled = ~(startSet && stopSet); return; end
    ud = getappdata(f,'ssr_state');
    if isempty(ud), canceled = true;
    else
        startIdx = ud.startIdx; stopIdx = ud.stopIdx;
        startSet = ud.startSet; stopSet = ud.stopSet;
        canceled = ~(startSet && stopSet);
    end
    delete(f);

    function onSlide(~,~)
        idx = round(get(sldr,'Value')); idx = max(1,min(totalFrames,idx)); set(sldr,'Value',idx);
        try, v.CurrentTime = (idx-1)/v.FrameRate; frm = readFrame(v);
        catch, frm = readFrameAtIndex(v, idx); end
        if ishandle(hImg), set(hImg,'CData',frm); title(ax,sprintf('Frame %d / %d',idx,totalFrames)); end
        set(txt,'String',sprintf('Frame: %d / %d | Time: %.3f s',idx,totalFrames,(idx-1)/v.FrameRate)); drawnow;
    end
    function onSetS(~,~), startIdx = round(get(sldr,'Value')); startSet=true; if stopSet && stopIdx<startIdx, stopIdx=startIdx; end, upd(); end
    function onSetE(~,~), stopIdx  = round(get(sldr,'Value'));  stopSet =true; if startSet && startIdx>stopIdx, startIdx=stopIdx; end, upd(); end
    function onDone(~,~), if ~(startSet&&stopSet), warndlg('Set BOTH Start and Stop.'); return; end, upd(); uiresume(f); end
    function onKey(~,ev), switch lower(ev.Key), case 's', onSetS(); case 'e', onSetE(); case 'return', onDone(); case 'escape', setappdata(f,'ssr_state',[]); uiresume(f); end, end
    function onClose(~,~), if ~(startSet&&stopSet), setappdata(f,'ssr_state',[]); else, upd(); end, uiresume(f); end
    function upd(), setappdata(f,'ssr_state',struct('startIdx',startIdx,'stopIdx',stopIdx,'startSet',startSet,'stopSet',stopSet)); end
end

function frame = readFrameAtIndex(v, idx)
    idx = max(1, round(idx));
    v.CurrentTime = (idx-1)/v.FrameRate;
    frame = readFrame(v);
end

function poly = findPolygonVertices(mask)
    B = bwboundaries(mask);
    if ~isempty(B)
        boundary = B{1}; x = boundary(:,2); y = boundary(:,1);
        poly = reshape([x y].', 1, []);
    else
        poly = [];
    end
end

function segs = polylineToSegments(P)
% P: [n×2] [x y] vertices; returns [ (n-1)×4 ] [x1 y1 x2 y2]
    if size(P,1) < 2, segs = zeros(0,4); return; end
    segs = [P(1:end-1,1), P(1:end-1,2), P(2:end,1), P(2:end,2)];
end

function [sides, dists] = signedSideAndDistance(pts, segs, segVecs, segLens2)
% pts: [N×2]; segs: [M×4]; segVecs: [M×2]; segLens2: [M×1]
% For each point, find nearest segment and:
%   sides ∈ {-1,0,+1} by sign of cross( segVec, (pt - segStart) )
%   dists = Euclidean distance to that segment
    N = size(pts,1); M = size(segs,1);
    sides = zeros(N,1); dists = inf(N,1);
    for j = 1:M
        a = segs(j,1:2); v = segVecs(j,:); vv = segLens2(j);
        ap = bsxfun(@minus, pts, a);           % [N×2]
        t  = (ap(:,1).*v(1) + ap(:,2).*v(2)) ./ vv;
        t  = max(0, min(1, t));                % clamp to segment
        proj = a + [t.*v(1), t.*v(2)];         % closest points on segment
        d   = hypot(pts(:,1)-proj(:,1), pts(:,2)-proj(:,2));
        better = d < dists;                    % nearest seg so far?
        if any(better)
            dists(better) = d(better);
            crossz = v(1).*ap(:,2) - v(2).*ap(:,1);
            s = sign(crossz); s(s==0) = 0;
            sides(better) = s(better);
        end
    end
    epsz = 1e-6;
    sides(abs(sides) < epsz) = 0;
end
