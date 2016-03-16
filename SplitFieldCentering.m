classdef SplitFieldCentering < edu.washington.rieke.protocols.RiekeStageProtocol
    
    properties
        preTime = 250 %(ms)
        stimTime = 2000 %(ms)
        tailTime = 250 %(ms)
        contrast = 0.9 %relative to mean (0-1)
        cycleFrequency = 4; %(Hz)
        spotDiameter = 300; %(um)
        splitField = false; 
        rotation = 0; %(deg)
        backgroundIntensity = 0.5 %(0-1)
        centerOffset = [0, 0] %([x,y] um)
        onlineAnalysis = {'none','extracellular','exc','inh'}
        numberOfAverages = uint16(1) %number of epochs to queue
        amp % Output amplifier
    end
    
    properties (Hidden)
        ampType
        runningPSTH
        runningTrace
    end

    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.rieke.protocols.RiekeStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function p = getPreview(obj, panel)
            if isempty(obj.rig.getDevices('Stage'))
                p = [];
                return;
            end
            p = io.github.stage_vss.previews.StagePreview(panel, @()obj.createPresentation(), ...
                'windowSize', obj.rig.getDevice('Stage').getCanvasSize());
        end

        function prepareRun(obj)
            prepareRun@edu.washington.rieke.protocols.RiekeStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('symphonyui.builtin.figures.MeanResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('io.github.stage_vss.figures.FrameTimingFigure', obj.rig.getDevice('Stage'));
            
            if ~strcmp(obj.onlineAnalysis,'none')
                % custom figure handler
                obj.openFigure('Custom', 'UpdateCallback', @F1F2_PSTH);
            end
            
            
            obj.stage.setCanvasClearColor(obj.backgroundIntensity);
        end
        
        function F1F2_PSTH(obj,epoch,axesHandle) %online analysis function
            cla(axesHandle)
            set(axesHandle, 'XTick', [], 'YTick', []);
            set(axesHandle,'FontSize',14)
            [response, sampleRate] = epoch.response(obj.amp);
            

            if strcmp(obj.onlineAnalysis,'extracellular') %spike recording
                binSize = 100; %dataPts
                noCycles = floor(obj.cycleFrequency*obj.stimTime/1000);
                period = (1/obj.cycleFrequency)*sampleRate; %data points
                
                response(1:(sampleRate*obj.preTime/1000)) = []; %cut out prePts
                cycleAvgBinCts = 0;
                for c = 1:noCycles
                    cyclePSTH = getPSTHOnline(response((c-1)*period+1:c*period),binSize,0);
                    cycleAvgBinCts = cycleAvgBinCts + cyclePSTH.spikeCounts;
                end
                cycleAvgBinCts = cycleAvgBinCts./noCycles;
                trialPSTH.spikeCounts = cycleAvgBinCts;
                trialPSTH.binCenters = cyclePSTH.binCenters;
                
                if (obj.numEpochsCompleted == 1)
                    obj.runningPSTH = trialPSTH;
                else %add spike counts...
                    obj.runningPSTH.spikeCounts = obj.runningPSTH.spikeCounts + trialPSTH.spikeCounts;
                end
                h = bar(obj.runningPSTH.binCenters./sampleRate,(obj.runningPSTH.spikeCounts./obj.numEpochsCompleted)/(binSize/sampleRate),...
                    'hist');
                set(h,'FaceColor',[0 0 0],'EdgeColor',[1 1 1]);
                xlabel('Time (s)')
                ylabel('Spike rate (Hz)')
                title('Running cycle average...')
                
            else %intracellular - Vclamp
                response = response-mean(response(1:sampleRate*obj.preTime/1000)); %baseline
                if strcmp(obj.onlineAnalysis,'exc') %measuring exc
                    response = response./(-60-0); %conductance (nS), ballpark
                elseif strcmp(obj.onlineAnalysis,'inh') %measuring inh
                    response = response./(0-(-60)); %conductance (nS), ballpark
                end
                noCycles = floor(obj.cycleFrequency*obj.stimTime/1000);
                period = (1/obj.cycleFrequency)*sampleRate; %data points
                response(1:(sampleRate*obj.preTime/1000)) = []; %cut out prePts
                cycleAvgResp = 0;
                for c = 1:noCycles
                    cycleAvgResp = cycleAvgResp + response((c-1)*period+1:c*period);
                end
                cycleAvgResp = cycleAvgResp./noCycles;
                timeVector = (1:length(cycleAvgResp))./sampleRate; %sec
                if (obj.numEpochsCompleted == 1)
                    obj.runningTrace = cycleAvgResp;
                else %add resp...
                    obj.runningTrace = obj.runningTrace + cycleAvgResp;
                end
                
                plot(timeVector,obj.runningTrace./obj.numEpochsCompleted,'k','LineWidth',2)
                xlabel('Time (s)')
                ylabel('Resp (nS)')
                title('Running cycle average...')
            end
        end
        
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            
            %convert from microns to pixels...
            spotDiameterPix = obj.um2pix(obj.spotDiameter);
            centerOffsetPix = obj.um2pix(obj.centerOffset);
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            % Create grating stimulus.            
            grate = stage.builtin.stimuli.Grating('square'); %square wave grating
            grate.orientation = obj.rotation;
            grate.size = [spotDiameterPix, spotDiameterPix];
            grate.position = canvasSize/2 + centerOffsetPix;
            grate.spatialFreq = 1/(2*spotDiameterPix);
            grate.color = 2*obj.backgroundIntensity; %amplitude of square wave
            grate.contrast = obj.contrast; %multiplier on square wave
            if (obj.splitField)
                grate.phase = 90;
            else %full-field
                grate.phase = 0;
            end
            p.addStimulus(grate); %add grating to the presentation
            
            %make it contrast-reversing
            if (obj.cycleFrequency>0) 
                grateContrast = stage.builtin.controllers.PropertyController(grate, 'contrast',...
                    @(state)getGrateContrast(obj, state.time - obj.preTime/1e3));
                p.addController(grateContrast); %add the controller
            end
            function c = getGrateContrast(obj, time)
                c = obj.contrast.*sin(2 * pi * obj.cycleFrequency * time);
            end
            
            % Create aperture
            aperture = stage.builtin.stimuli.Rectangle();
            aperture.position = canvasSize/2 + centerOffsetPix;
            aperture.color = obj.backgroundIntensity;
            aperture.size = [2*max(canvasSize), 2*max(canvasSize)];
            mask = Mask.createCircularAperture(spotDiameterPix/(2*max(canvasSize)), 1024); %circular aperture
            aperture.setMask(mask);
            p.addStimulus(aperture); %add aperture

        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.rieke.protocols.RiekeStageProtocol(obj, epoch);
            
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
        end
        
        function prepareInterval(obj, interval)
            prepareInterval@edu.washington.rieke.protocols.RiekeStageProtocol(obj, interval);
            
            device = obj.rig.getDevice(obj.amp);
            interval.addDirectCurrentStimulus(device, device.background, obj.interpulseInterval, obj.sampleRate);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
    end
    
end