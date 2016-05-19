classdef ExpandingSpots < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    
    properties
        preTime = 250 % ms
        stimTime = 500 % ms
        tailTime = 250 % ms
        spotIntensity = 1.0 % (0-1)
        spotSizes = [40 80 120 160 180 200 220 240 280 320 460 600] % um
        randomizeOrder = false
        backgroundIntensity = 0.5 % (0-1)
        centerOffset = [0, 0] % [x,y] (um)
        onlineAnalysis = 'none'
        modelFit = 'none'
        numberOfAverages = uint16(100) % number of epochs to queue
        amp % Output amplifier
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        modelFitType = symphonyui.core.PropertyType('char', 'row', {'none','Gaussian', 'Difference of Gaussians'})
        
        spotSizeSequence
        currentSpotSize
        runCompletedFlag
    end
    
    properties (Hidden, Transient)
        analysisFigure
    end

    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            obj.runCompletedFlag = 0;
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.turner.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,'groupBy',{'currentSpotSize'});
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            if ~strcmp(obj.onlineAnalysis,'none')
                % custom figure handler
                if isempty(obj.analysisFigure) || ~isvalid(obj.analysisFigure)
                    obj.analysisFigure = obj.showFigure('symphonyui.builtin.figures.CustomFigure', @obj.expandingSpotAnalysis);
                    f = obj.analysisFigure.getFigureHandle();
                    set(f, 'Name', 'Area Summation');
                    obj.analysisFigure.userData.countBySize = zeros(size(obj.spotSizes));
                    obj.analysisFigure.userData.responseBySize = zeros(size(obj.spotSizes));
                    obj.analysisFigure.userData.axesHandle = axes('Parent', f);
                else
                    obj.analysisFigure.userData.countBySize = zeros(size(obj.spotSizes));
                    obj.analysisFigure.userData.responseBySize = zeros(size(obj.spotSizes));
                end
                
            end
            % Create spot size sequence.
            obj.spotSizeSequence = obj.spotSizes;
        end
        
        function expandingSpotAnalysis(obj, ~, epoch) %online analysis function
            response = epoch.getResponse(obj.rig.getDevice(obj.amp));
            epochResponseTrace = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            
            axesHandle = obj.analysisFigure.userData.axesHandle;
            countBySize = obj.analysisFigure.userData.countBySize;
            responseBySize = obj.analysisFigure.userData.responseBySize;
            
            if strcmp(obj.onlineAnalysis,'extracellular') %spike recording
                %take (prePts+1:prePts+stimPts)
                epochResponseTrace = epochResponseTrace((sampleRate*obj.preTime/1000)+1:(sampleRate*(obj.preTime + obj.stimTime)/1000));
                %count spikes
                S = spikeDetectorOnline(epochResponseTrace);
                newEpochResponse = length(S.sp); %spike count
            else %intracellular - Vclamp
                epochResponseTrace = epochResponseTrace-mean(epochResponseTrace(1:sampleRate*obj.preTime/1000)); %baseline
                %take (prePts+1:prePts+stimPts)
                epochResponseTrace = epochResponseTrace((sampleRate*obj.preTime/1000)+1:(sampleRate*(obj.preTime + obj.stimTime)/1000));
                %charge transfer
                if strcmp(obj.onlineAnalysis,'exc') %measuring exc
                    chargeMult = -1;
                elseif strcmp(obj.onlineAnalysis,'inh') %measuring inh
                    chargeMult = 1;
                end
                newEpochResponse = chargeMult*trapz(epochResponseTrace(1:sampleRate*obj.stimTime/1000)); %pA*datapoint
                newEpochResponse = newEpochResponse/sampleRate; %pA*sec = pC
            end
            spotInd = find(obj.currentSpotSize == obj.spotSizes);
            
            countBySize(spotInd) = countBySize(spotInd) + 1;
            responseBySize(spotInd) = responseBySize(spotInd) + newEpochResponse;
            
            cla(axesHandle);
            h = line(obj.spotSizes, responseBySize./countBySize, 'Parent', axesHandle);
            set(h,'Color',[0 0 0],'LineWidth',2,'Marker','o');
            xlabel(axesHandle,'Spot size (um)')
            if strcmp(obj.onlineAnalysis,'extracellular')
                ylabel(axesHandle,'Spike count')
            else
                ylabel(axesHandle,'Charge transfer (pC)')
            end
            obj.analysisFigure.userData.countBySize = countBySize;
            obj.analysisFigure.userData.responseBySize = responseBySize;
            
            
            if (obj.runCompletedFlag) %stopped or hit numberOfAverages
                if strcmp(obj.onlineAnalysis,'extracellular')
                    R0upperBound = Inf;
                else
                    R0upperBound = 1e-6; %analog signals already baseline subtracted. Curve goes through [0,0]
                end
                
                if strcmp(obj.modelFit,'Gaussian')
                    params0 = [0.35,100,0]; % [kC, sigmaC, R0]
                    fitRes = fitGaussianRFAreaSummation(obj.spotSizes,responseBySize./countBySize,params0,R0upperBound);
                    fitX = 0:(1.1*max(obj.spotSizes));
                    fitY = GaussianRFAreaSummation(fitX,fitRes.Kc,fitRes.sigmaC,fitRes.R0);
                    h = line(fitX, fitY, 'Parent', axesHandle);
                    set(h,'Color',[1 0 0],'LineWidth',2,'Marker','none');
                    str = {['SigmaC = ',num2str(fitRes.sigmaC)]};
                    dim = [0.2 0.5 0.3 0.3];
                    annotation('textbox',dim,'String',str,'FitBoxToText','on');
                    
                elseif strcmp(obj.modelFit,'Difference of Gaussians')
                    params0 = [0.35,35,0.08,300,0];
                    fitRes = fitDoGAreaSummation(obj.spotSizes,responseBySize./countBySize,params0,R0upperBound);
                    fitX = 0:(1.1*max(obj.spotSizes));
                    fitY = DoGAreaSummation(fitX,fitRes.Kc,fitRes.sigmaC,fitRes.Ks,fitRes.sigmaS,fitRes.R0);
                    h = line(fitX, fitY, 'Parent', axesHandle);
                    set(h,'Color',[1 0 0],'LineWidth',2,'Marker','none');
                    tempKc = fitRes.Kc / (fitRes.Kc + fitRes.Ks);
                    str = {['SigmaC = ',num2str(fitRes.sigmaC)],['sigmaS = ',num2str(fitRes.sigmaS)],...
                        ['Kc = ',num2str(tempKc)]};
                    dim = [0.2 0.5 0.3 0.3];
                    annotation('textbox',dim,'String',str,'FitBoxToText','on');
                    
                elseif strcmp(obj.modelFit,'none')

                end
            end
        end
        
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            
            %convert from microns to pixels...
            spotDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.currentSpotSize);
            centerOffsetPix = obj.rig.getDevice('Stage').um2pix(obj.centerOffset);
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            % Create spot stimulus.            
            spot = stage.builtin.stimuli.Ellipse();
            spot.color = obj.spotIntensity;
            spot.radiusX = spotDiameterPix/2;
            spot.radiusY = spotDiameterPix/2;
            spot.position = canvasSize/2 + centerOffsetPix;
            p.addStimulus(spot);
            
            % hide during pre & post
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);

        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
            
            index = mod(obj.numEpochsCompleted, length(obj.spotSizeSequence)) + 1;
            % Randomize the spot size sequence order at the beginning of each sequence.
            if index == 1 && obj.randomizeOrder
                obj.spotSizeSequence = randsample(obj.spotSizeSequence, length(obj.spotSizeSequence));
            end
            obj.currentSpotSize = obj.spotSizeSequence(index);
            epoch.addParameter('currentSpotSize', obj.currentSpotSize);
        end


        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
        function completeRun(obj)
            completeRun@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            obj.rig.getDevice('Stage').clearMemory();
            obj.runCompletedFlag = 1;
        end
        
    end
    
end