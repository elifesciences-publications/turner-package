classdef AnnulusWeightTest < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    
    properties
        preTime = 200                   % (ms)
        stimTime = 200                 % (ms)
        tailTime = 200                  % (ms)
        referenceInnerDiameter = 250 % (um)
        referenceOuterDiameter = 300 % (um)
        rfSigmaSurround = 180 % (um)
        
        annulusIntensity = 1.0             % (0-1)
        centerIntensity = 0.75;
        centerDiameter = 150 % (um)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0, 0]           % center offset (um)
        onlineAnalysis = 'none'
        numberOfAverages = uint16(10)    % Number of epochs
        amp                             % Output amplifier
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        testInnerDiameter
        testOuterDiameter
        currentStimulusType
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.turner.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,'groupBy',{'currentStimulusType'});
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            
            %use the input RF to calculate the size of the
            %annulus that should drive an equal response to the reference
            %stimulus
            sigmaS = obj.rfSigmaSurround;
            startPoint = obj.referenceOuterDiameter / 2; %start at the edge of the reference stim
            micronsPerPixel = obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
            endOfSearch = round(0.5 * min(obj.rig.getDevice('Stage').getCanvasSize()).*micronsPerPixel); %um
            targetStartPoint = round(obj.referenceInnerDiameter / 2);
            targetEndPoint = round(obj.referenceOuterDiameter / 2);

            targetWts = exp(-((targetStartPoint:targetEndPoint)./(2*sigmaS)).^2);
            testWts = exp(-((startPoint:endOfSearch)./(2*sigmaS)).^2);
            dispWts = exp(-((0:4*sigmaS)./(2*sigmaS)).^2);
            
            testActivations = cumsum(testWts);
            targetActivation = sum(targetWts);
            distanceInMicrons = edu.washington.riekelab.turner.utils.getThresCross(testActivations,targetActivation,1);

            if isempty(distanceInMicrons)
                error('Cannot find equivalent annulus, make reference stimulus smaller')
            else
                obj.testInnerDiameter = 2*startPoint;
                obj.testOuterDiameter = 2*(startPoint + distanceInMicrons);
            end
            figure(30); clf; plot(dispWts,'k');
            hold on;
            area(targetStartPoint:targetEndPoint,dispWts(targetStartPoint:targetEndPoint),'FaceColor','g')
            startPoint = round(startPoint); endPoint = round(startPoint + distanceInMicrons);
            area(startPoint:endPoint,dispWts(startPoint:endPoint),'FaceColor','r')
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
            
            isOdd = mod(obj.numEpochsCompleted, 2);
            if (isOdd == 0)
                obj.currentStimulusType = 'Reference';
            elseif (isOdd == 1)
                obj.currentStimulusType = 'Test';
            end
            epoch.addParameter('currentStimulusType', obj.currentStimulusType);
            epoch.addParameter('testInnerDiameter', obj.testInnerDiameter);
            epoch.addParameter('testOuterDiameter', obj.testOuterDiameter);
        end
        
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            centerOffsetPix = obj.rig.getDevice('Stage').um2pix(obj.centerOffset);
            centerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.centerDiameter);
            
            %Make the annulus
            if strcmp(obj.currentStimulusType,'Reference')
                innerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.referenceInnerDiameter);
                outerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.referenceOuterDiameter);
            elseif strcmp(obj.currentStimulusType,'Test')
                innerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.testInnerDiameter);
                outerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.testOuterDiameter);
            end
            annulus = stage.builtin.stimuli.Ellipse();
            annulus.color = obj.annulusIntensity;
            annulus.radiusX = outerDiameterPix/2;
            annulus.radiusY = outerDiameterPix/2;
            annulus.position = canvasSize/2 + centerOffsetPix;
            p.addStimulus(annulus);
            annulusVisible = stage.builtin.controllers.PropertyController(annulus, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(annulusVisible);
            
            maskSpot = stage.builtin.stimuli.Ellipse();
            maskSpot.color = obj.backgroundIntensity;
            maskSpot.radiusX = innerDiameterPix/2;
            maskSpot.radiusY = innerDiameterPix/2;
            maskSpot.position = canvasSize/2 + centerOffsetPix;
            p.addStimulus(maskSpot);
            maskSpotVisible = stage.builtin.controllers.PropertyController(maskSpot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(maskSpotVisible);

            %make the spot in the center
            spot = stage.builtin.stimuli.Ellipse();
            spot.color = obj.centerIntensity;
            spot.radiusX = centerDiameterPix/2;
            spot.radiusY = centerDiameterPix/2;
            spot.position = canvasSize/2 + centerOffsetPix;
            p.addStimulus(spot);
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
    end
    
end

