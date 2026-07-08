%% run_pipeline
% Full balance beam analysis pipeline.
% Select your project folder once — steps 1, 2, and 3 run in sequence.
%
%   Step 1 — Calibrate px/cm for each video (skips already-calibrated)
%   Step 2 — Track and classify behavior per video (skips already-processed)
%   Step 3 — Aggregate master CSV with timing + speeds (pause-included & excluded)

    project_folder = uigetdir(pwd, 'Select Project Folder Containing Videos');
    if isequal(project_folder, 0), error('No folder selected.'); end

    fprintf('\n========== STEP 1: Pixel/cm Calibration ==========\n');
    run_step1(project_folder);

    fprintf('\n========== STEP 2: Tracking & Behavior Classification ==========\n');
    run_step2(project_folder);

    fprintf('\n========== STEP 3: Aggregate Master Statistics ==========\n');
    run_step3(project_folder);

    fprintf('\nPipeline complete.\n');
end


%% ===================== STEP 1 =====================
function run_step1(project_folder)
    videoFiles = dir(fullfile(project_folder, '**', '*beam_h.mp4'));
    if isempty(videoFiles), error('No *beam_h.mp4 files found.'); end

    outputDir = fullfile(project_folder, 'stats_and_analysis', 'balancebeam');
    if ~exist(outputDir, 'dir'), mkdir(outputDir); end
    outXlsx = fullfile(outputDir, 'pixels_per_cm_output.xlsx');

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
        if any(strcmp(existingNames, fname))
            fprintf('  Skipping %s (already calibrated)\n', fname);
            continue;
        end

        videoPath = fullfile(videoFiles(i).folder, fname);
        v = VideoReader(videoPath);
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
        fprintf('  Saved %d new calibration(s).\n', numel(newNames));
    else
        fprintf('  All videos already calibrated.\n');
    end
end


%% ===================== STEP 2 =====================
function run_step2(dataDir)
    files = dir(fullfile(dataDir, '**', '*beam_h.mp4'));
    if isempty(files), error('No *beam_h.mp4 files found in %s', dataDir); end

    threshold         = 50;
    fps_used          = 30;
    dt                = 1 / fps_used;
    pause_thr         = 0.3;
    curve_width       = 3;
    side_tolerance_px = 1.5;

    masterRows = {};

    for i = 1:numel(files)
        try
            fname = files(i).name;
            fpath = fullfile(files(i).folder, fname);
            [~, base0] = fileparts(fname);
            outMatCheck = fullfile(dataDir, 'stats_and_analysis/balancebeam', ...
                                   sprintf('%s_tracking_results.mat', base0));

            if exist(outMatCheck, 'file')
                fprintf('  Skipping %s (already processed)\n', fname);
                d = load(outMatCheck);
                if isfield(d,'pause_time_sec') && isfield(d,'crawling_time_sec') && isfield(d,'crossing_time_sec')
                    N   = numel(d.isPause);
                    tot = N * d.dt;
                    masterRows(end+1,:) = {base0, d.pause_time_sec, d.crawling_time_sec, d.crossing_time_sec, ...
                        100*d.pause_time_sec/tot, 100*d.crawling_time_sec/tot, 100*d.crossing_time_sec/tot}; %#ok<AGROW>
                end
                continue;
            end

            fprintf('  Processing %s\n', fname);
            vMeta = VideoReader(fpath);
            totalFrames = max(1, floor(vMeta.FrameRate * vMeta.Duration));

            [startIdx, stopIdx, canceled] = selectFrameRangeUI(fpath);
            if canceled, fprintf('  Skipped by user: %s\n', fname); continue; end
            if startIdx >= stopIdx, startIdx = 1; stopIdx = totalFrames; end

            vp = VideoReader(fpath);
            firstFrame = readFrameAtIndex(vp, startIdx);
            [H, W, ~] = size(firstFrame);

            hFig = figure('Name','Draw TRACKING ROI','NumberTitle','off');
            imshow(firstFrame,'Border','tight');
            title('Draw polygon ROI (double-click to finish)');
            roiMask = roipoly(); close(hFig);
            if isempty(roiMask) || ~any(roiMask(:)), fprintf('  Empty ROI; skipping\n'); continue; end
            propsROI    = regionprops(roiMask,'BoundingBox');
            boundingBox = round(propsROI.BoundingBox);

            hFig = figure('Name','Draw CRAWL BOUNDARY','NumberTitle','off');
            imshow(firstFrame,'Border','tight');
            title('Draw open polyline for crawl boundary (double-click to finish)');
            crawlPolylinePts = [];
            try
                h = drawpolyline('Color','m','InteractionsAllowed','all');
                wait(h); crawlPolylinePts = h.Position;
            catch
                [xv,yv] = getline(gca); crawlPolylinePts = [xv(:),yv(:)];
            end
            close(hFig);
            if size(crawlPolylinePts,1) < 2, fprintf('  Need >=2 crawl points; skipping\n'); continue; end

            segs     = polylineToSegments(crawlPolylinePts);
            segVecs  = [segs(:,3)-segs(:,1), segs(:,4)-segs(:,2)];
            segLens2 = sum(segVecs.^2,2) + eps;

            [~, base] = fileparts(fname);
            outDir = fullfile(dataDir,'stats_and_analysis/balancebeam');
            if ~exist(outDir,'dir'), mkdir(outDir); end
            outVideoPath = fullfile(outDir, sprintf('%s_tracked.mp4', base));
            outputVideo  = VideoWriter(outVideoPath); outputVideo.FrameRate = fps_used; open(outputVideo);

            v = VideoReader(fpath); v.CurrentTime = (startIdx-1)/v.FrameRate;
            centers = []; isCrawling = []; refSide = NaN;

            trackingFig = figure('Name',sprintf('Tracking: %s',fname),'NumberTitle','off');
            subplot(1,2,1); h1 = imshow(firstFrame); title('Annotated');
            subplot(1,2,2); h2 = imshow(zeros(size(roiMask))); title('Binary ROI');
            roiPolyVerts = findPolygonVertices(roiMask);

            frameIdx = startIdx;
            while hasFrame(v) && frameIdx <= stopIdx
                frame = readFrame(v); frameIdx = frameIdx+1;
                grayFrame = rgb2gray(frame);
                maskedFrame = grayFrame; maskedFrame(~roiMask) = 255;
                roiFrame = imcrop(maskedFrame, boundingBox);
                bw = bwareafilt(roiFrame < threshold, 1);

                props = regionprops(bw,'Centroid');
                if ~isempty(props)
                    lc = props(1).Centroid;
                    globalCenter = [lc(1)+boundingBox(1), lc(2)+boundingBox(2)];
                else
                    globalCenter = [NaN,NaN];
                end
                centers = [centers; globalCenter]; %#ok<AGROW>

                blobMaskFull = false(H,W);
                [x1,y1,w,h_] = deal(boundingBox(1),boundingBox(2),boundingBox(3),boundingBox(4));
                x2 = min(W,x1+w-1); y2 = min(H,y1+h_-1);
                if x2>=x1 && y2>=y1 && any(bw(:))
                    bwCrop = bw(1:min(y2-y1+1,size(bw,1)), 1:min(x2-x1+1,size(bw,2)));
                    blobMaskFull(y1:y1+size(bwCrop,1)-1, x1:x1+size(bwCrop,2)-1) = bwCrop;
                end

                crawlingNow = false;
                if any(blobMaskFull(:))
                    perim = bwperim(blobMaskFull); [py,px] = find(perim);
                    if numel(px)>400, idx=round(linspace(1,numel(px),400)); px=px(idx); py=py(idx); end
                    pts = [px,py];
                    [sides,dists] = signedSideAndDistance(pts,segs,segVecs,segLens2);
                    if isnan(refSide) && isfinite(globalCenter(1))
                        [s0,~] = signedSideAndDistance(globalCenter,segs,segVecs,segLens2);
                        if s0==0, s0=+1; end; refSide = s0;
                    end
                    if ~isnan(refSide)
                        crawlingNow = any(sides==-refSide | dists<=side_tolerance_px);
                    end
                end
                isCrawling = [isCrawling; crawlingNow]; %#ok<AGROW>

                annotated = frame;
                if ~isempty(roiPolyVerts)
                    annotated = insertShape(annotated,'Polygon',roiPolyVerts,'Color','green','LineWidth',2);
                end
                annotated = insertShape(annotated,'Line',segs,'Color','magenta','LineWidth',curve_width);
                if ~isnan(globalCenter(1))
                    annotated = insertMarker(annotated,globalCenter,'o','Color','blue','Size',5);
                end
                writeVideo(outputVideo,annotated);
                if ishandle(trackingFig)
                    subplot(1,2,1); set(h1,'CData',annotated);
                    subplot(1,2,2); set(h2,'CData',bw); drawnow;
                end
            end
            close(outputVideo);
            if ishandle(trackingFig), close(trackingFig); end

            N = size(centers,1);
            speed_px_per_frame = zeros(N,1);
            if N>=2
                step = sqrt(sum(diff(centers).^2,2));
                speed_px_per_frame = [0; step];
                speed_px_per_frame([false; isnan(step)]) = NaN;
            end

            isPause    = speed_px_per_frame < pause_thr;
            isPause(~isfinite(speed_px_per_frame)) = false;
            isCrawling = logical(isCrawling(:)) & ~isPause;
            isCrossing = ~(isPause | isCrawling);

            pause_time_sec    = sum(isPause)    * dt;
            crawling_time_sec = sum(isCrawling) * dt;
            crossing_time_sec = sum(isCrossing) * dt;
            total_time_sec    = N * dt; %#ok<NASGU>

            pause_pct    = 100*(pause_time_sec    /(N*dt));
            crawling_pct = 100*(crawling_time_sec /(N*dt));
            crossing_pct = 100*(crossing_time_sec /(N*dt));

            outMat = fullfile(outDir, sprintf('%s_tracking_results.mat', base));
            save(outMat, 'centers','roiMask','crawlPolylinePts','boundingBox', ...
                'threshold','fps_used','dt','startIdx','stopIdx', ...
                'speed_px_per_frame','pause_thr', ...
                'isPause','pause_time_sec','isCrawling','crawling_time_sec', ...
                'isCrossing','crossing_time_sec','total_time_sec', ...
                'refSide','side_tolerance_px','pause_pct','crawling_pct','crossing_pct');

            masterRows(end+1,:) = {base, pause_time_sec, crawling_time_sec, crossing_time_sec, ...
                pause_pct, crawling_pct, crossing_pct}; %#ok<AGROW>

        catch ME
            warning('Error processing %s: %s', files(i).name, ME.message);
        end
    end

    if ~isempty(masterRows)
        masterSummary = cell2table(masterRows,'VariableNames', ...
            {'Video','PauseTime_sec','CrawlingTime_sec','CrossingTime_sec','PausePct','CrawlingPct','CrossingPct'});
        outDir2 = fullfile(dataDir,'stats_and_analysis/balancebeam');
        save(fullfile(outDir2,'crossing_pausing_crawling_timein_seconds+percentage.mat'),'masterSummary');
        writetable(masterSummary, fullfile(outDir2,'crossing_pausing_crawling_timein_seconds+percentage.csv'));
        fprintf('  Master summary saved (%d videos).\n', height(masterSummary));
    end
end


%% ===================== STEP 3 =====================
function run_step3(folder)
    fps = 30;
    [~, folderName] = fileparts(folder);
    cohortTag = folderName(1:min(2,numel(folderName)));

    files = dir(fullfile(folder,'**','*results.mat'));
    if isempty(files), error('No *_tracking_results.mat files found.'); end

    ppcFile = fullfile(folder,'stats_and_analysis/balancebeam/pixels_per_cm_output.xlsx');
    if exist(ppcFile,'file')
        ppcTable = readtable(ppcFile);
    else
        ppcTable = []; warning('pixels_per_cm_output.xlsx not found; cm/s columns will be NaN.');
    end

    Video={}; PauseTime_sec=[]; CrawlingTime_sec=[]; CrossingTime_sec=[];
    PausePct=[]; CrawlingPct=[]; CrossingPct=[]; PixelsPerCm=[];
    MedianSpeed_px_frame_pauseIncluded=[]; MeanSpeed_px_frame_pauseIncluded=[];
    MedianSpeed_cm_s_pauseIncluded=[];     MeanSpeed_cm_s_pauseIncluded=[];
    MedianSpeed_px_s_pauseExcluded=[];     MeanSpeed_px_s_pauseExcluded=[];
    MedianSpeed_cm_s_pauseExcluded=[];     MeanSpeed_cm_s_pauseExcluded=[];

    for k = 1:numel(files)
        [~,base] = fileparts(files(k).name);
        d = load(fullfile(files(k).folder, files(k).name));
        if ~isfield(d,'speed_px_per_frame')||~isfield(d,'pause_time_sec')||...
           ~isfield(d,'crawling_time_sec') ||~isfield(d,'crossing_time_sec')
            warning('Missing fields in %s — skipping.', files(k).name); continue;
        end

        spd_pf = d.speed_px_per_frame(:);
        if isfield(d,'startIdx')&&isfield(d,'stopIdx')&&~isempty(d.startIdx)&&~isempty(d.stopIdx)
            a=double(d.startIdx(1)); b=double(d.stopIdx(1));
            if isfinite(a)&&isfinite(b)&&a>=1&&b>=a&&b<=numel(spd_pf), spd_pf=spd_pf(a:b); end
        end

        N=numel(d.isPause); tot=N/fps;
        p_pct=100*d.pause_time_sec/tot; cr_pct=100*d.crawling_time_sec/tot; cx_pct=100*d.crossing_time_sec/tot;

        ppc=NaN;
        if ~isempty(ppcTable)
            prefix=files(k).name(1:min(7,numel(files(k).name)));
            idx=find(strncmp(ppcTable.VideoName,prefix,numel(prefix)),1);
            if ~isempty(idx), ppc=ppcTable.PixelsPerCm(idx);
            else, warning('No PixelsPerCm match for: %s',prefix); end
        end

        medPxPf_inc=median(spd_pf,'omitnan'); mnPxPf_inc=mean(spd_pf,'omitnan');
        medCm_inc=medPxPf_inc*fps/ppc;        mnCm_inc=mnPxPf_inc*fps/ppc;

        if isfield(d,'isPause')&&~isempty(d.isPause)
            isP=d.isPause(:);
            if numel(spd_pf)~=numel(isP)&&isfield(d,'startIdx')&&isfield(d,'stopIdx')
                a2=double(d.startIdx(1)); b2=double(d.stopIdx(1));
                if isfinite(a2)&&isfinite(b2)&&a2>=1&&b2>=a2&&b2<=numel(isP), isP=isP(a2:b2); end
            end
            activeMask=~isP(1:numel(spd_pf));
        else
            activeMask=true(numel(spd_pf),1);
        end

        spd_ps_exc=spd_pf(activeMask)*fps;
        if isempty(spd_ps_exc)||all(isnan(spd_ps_exc))
            medPxS_exc=NaN; mnPxS_exc=NaN;
        else
            medPxS_exc=median(spd_ps_exc,'omitnan'); mnPxS_exc=mean(spd_ps_exc,'omitnan');
        end
        medCm_exc=medPxS_exc/ppc; mnCm_exc=mnPxS_exc/ppc;

        Video{end+1}=base; %#ok<AGROW>
        PauseTime_sec(end+1)=d.pause_time_sec; CrawlingTime_sec(end+1)=d.crawling_time_sec; CrossingTime_sec(end+1)=d.crossing_time_sec;
        PausePct(end+1)=p_pct; CrawlingPct(end+1)=cr_pct; CrossingPct(end+1)=cx_pct;
        PixelsPerCm(end+1)=ppc;
        MedianSpeed_px_frame_pauseIncluded(end+1)=medPxPf_inc; MeanSpeed_px_frame_pauseIncluded(end+1)=mnPxPf_inc;
        MedianSpeed_cm_s_pauseIncluded(end+1)=medCm_inc;       MeanSpeed_cm_s_pauseIncluded(end+1)=mnCm_inc;
        MedianSpeed_px_s_pauseExcluded(end+1)=medPxS_exc;      MeanSpeed_px_s_pauseExcluded(end+1)=mnPxS_exc;
        MedianSpeed_cm_s_pauseExcluded(end+1)=medCm_exc;       MeanSpeed_cm_s_pauseExcluded(end+1)=mnCm_exc;
    end

    T = table(Video',PauseTime_sec',CrawlingTime_sec',CrossingTime_sec', ...
              PausePct',CrawlingPct',CrossingPct',PixelsPerCm', ...
              MedianSpeed_px_frame_pauseIncluded',MeanSpeed_px_frame_pauseIncluded', ...
              MedianSpeed_cm_s_pauseIncluded',    MeanSpeed_cm_s_pauseIncluded', ...
              MedianSpeed_px_s_pauseExcluded',    MeanSpeed_px_s_pauseExcluded', ...
              MedianSpeed_cm_s_pauseExcluded',    MeanSpeed_cm_s_pauseExcluded', ...
        'VariableNames',{'Video', ...
            'PauseTime_sec','CrawlingTime_sec','CrossingTime_sec', ...
            'PausePct','CrawlingPct','CrossingPct','PixelsPerCm', ...
            'MedianSpeed_px_per_frame_pauseIncluded','MeanSpeed_px_per_frame_pauseIncluded', ...
            'MedianSpeed_cm_s_pauseIncluded','MeanSpeed_cm_s_pauseIncluded', ...
            'MedianSpeed_px_s_pauseExcluded','MeanSpeed_px_s_pauseExcluded', ...
            'MedianSpeed_cm_s_pauseExcluded','MeanSpeed_cm_s_pauseExcluded'});

    outDir = fullfile(folder,'stats_and_analysis/balancebeam');
    if ~exist(outDir,'dir'), mkdir(outDir); end
    out = fullfile(outDir, sprintf('beamwalking_time_and_speed_%s.csv', cohortTag));
    writetable(T, out);
    fprintf('  Wrote %s with %d rows.\n', out, height(T));
    disp(T);
end


%% ===================== HELPERS =====================
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
    uicontrol('Parent',f,'Style','pushbutton','String','Set Start (S)','Units','normalized','Position',[0.05 0.92 0.18 0.06],'Callback',@onSetS);
    uicontrol('Parent',f,'Style','pushbutton','String','Set Stop (E)','Units','normalized','Position',[0.25 0.92 0.18 0.06],'Callback',@onSetE);
    uicontrol('Parent',f,'Style','pushbutton','String','Done','Units','normalized','Position',[0.77 0.92 0.18 0.06],'Callback',@onDone);
    txt = uicontrol('Parent',f,'Style','text','Units','normalized','Position',[0.47 0.92 0.28 0.06],...
                    'BackgroundColor','w','HorizontalAlignment','left',...
                    'String',sprintf('Frame: 1 / %d | Time: %.3f s',totalFrames,0));
    startIdx=1; startSet=false; stopIdx=totalFrames; stopSet=false;
    uiwait(f);
    if ~ishandle(f), canceled=~(startSet&&stopSet); return; end
    ud = getappdata(f,'ssr_state');
    if isempty(ud), canceled=true;
    else
        startIdx=ud.startIdx; stopIdx=ud.stopIdx;
        startSet=ud.startSet; stopSet=ud.stopSet;
        canceled=~(startSet&&stopSet);
    end
    delete(f);
    function onSlide(~,~)
        idx=round(get(sldr,'Value')); idx=max(1,min(totalFrames,idx)); set(sldr,'Value',idx);
        try, v.CurrentTime=(idx-1)/v.FrameRate; frm=readFrame(v); catch, frm=readFrameAtIndex(v,idx); end
        if ishandle(hImg), set(hImg,'CData',frm); title(ax,sprintf('Frame %d/%d',idx,totalFrames)); end
        set(txt,'String',sprintf('Frame: %d / %d | Time: %.3f s',idx,totalFrames,(idx-1)/v.FrameRate)); drawnow;
    end
    function onSetS(~,~), startIdx=round(get(sldr,'Value')); startSet=true; upd(); end
    function onSetE(~,~), stopIdx=round(get(sldr,'Value'));  stopSet=true;  upd(); end
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
        boundary=B{1}; poly=reshape([boundary(:,2) boundary(:,1)].',1,[]);
    else, poly=[]; end
end

function segs = polylineToSegments(P)
    if size(P,1)<2, segs=zeros(0,4); return; end
    segs=[P(1:end-1,1),P(1:end-1,2),P(2:end,1),P(2:end,2)];
end

function [sides,dists] = signedSideAndDistance(pts,segs,segVecs,segLens2)
    N=size(pts,1); M=size(segs,1);
    sides=zeros(N,1); dists=inf(N,1);
    for j=1:M
        a=segs(j,1:2); v=segVecs(j,:); vv=segLens2(j);
        ap=bsxfun(@minus,pts,a);
        t=max(0,min(1,(ap(:,1)*v(1)+ap(:,2)*v(2))./vv));
        proj=a+[t*v(1),t*v(2)];
        d=hypot(pts(:,1)-proj(:,1),pts(:,2)-proj(:,2));
        better=d<dists;
        if any(better)
            dists(better)=d(better);
            s=sign(v(1)*ap(:,2)-v(2)*ap(:,1)); s(s==0)=0;
            sides(better)=s(better);
        end
    end
    sides(abs(sides)<1e-6)=0;
end
