classdef ReceptiveFieldWeightTest < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    
    properties
        preTime = 200                   % (ms)
        stimTime = 200                 % (ms)
        tailTime = 200                  % (ms)
        referenceInnerDiameter = 0 % (um); 0 for spot in the center, >0 for annulus
        referenceOuterDiameter = 40 % (um)
        
        rfSigmaCenter = 40 % (um) Enter from fit RF
        rfWeightCenter = 0.85 % 1 for center only. Wc + Ws = 1
        rfSigmaSurround = 180 % (um)
        
        intensity = 1.0             % (0-1)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0, 0]           % center offset (um)
        onlineAnalysis = 'none'
        numberOfAverages = uint16(1)    % Number of epochs
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
            sigmaC = obj.rfSigmaCenter;
            sigmaS = obj.rfSigmaSurround;
            weightC = obj.rfWeightCenter;
            weightS = 1 - weightC;
            startPoint = obj.referenceOuterDiameter / 2; %start at the edge of the reference stim

            if (obj.referenceInnerDiameter == 0) %reference is a spot
                targetStartPoint = 0;
                targetEndPoint = round(obj.referenceOuterDiameter / 2);
            elseif (obj.referenceInnerDiameter > 0) %reference is an annulus
                targetStartPoint = round(obj.referenceInnerDiameter / 2);
                targetEndPoint = round(obj.referenceOuterDiameter / 2);
            end
            
            if weightC == 1 %just the center
                targetWts = exp(-((targetStartPoint:targetEndPoint)./(2*sigmaC)).^2);
                testWts = exp(-((startPoint:8*sigmaC)./(2*sigmaC)).^2); %search out to 8 sigma
                dispWts = exp(-((0:4*sigmaC)./(2*sigmaC)).^2);
            else % difference of gaussians, use center and surround
                targetWts = (weightC.*exp(-((targetStartPoint:targetEndPoint)./(2*sigmaC)).^2) - ...
                    weightS.*exp(-((targetStartPoint:targetEndPoint)./(2*sigmaS)).^2));
                testWts = (weightC.*exp(-((startPoint:8*sigmaS)./(2*sigmaC)).^2) - ...
                    weightS.*exp(-((startPoint:8*sigmaS)./(2*sigmaS)).^2));
                dispWts = (weightC.*exp(-((0:4*sigmaS)./(2*sigmaC)).^2) - ...
                    weightS.*exp(-((0:4*sigmaS)./(2*sigmaS)).^2));
            end
            testActivations = cumsum(testWts);
            targetActivation = sum(targetWts);
            if targetActivation < 0 %mostly surround
                distanceInMicrons = getThresCross(testActivations,targetActivation,-1);
            elseif targetActivation >= 0
                distanceInMicrons = getThresCross(testActivations,targetActivation,1);
            end
            
            if isempty(distanceInMicrons)
                error('Cannot find equivalent annulus, make reference stimulus smaller')
            else
                obj.testInnerDiameter = 2*startPoint;
                obj.testOuterDiameter = 2*(startPoint + distanceInMicrons);
            end
            figure(30); clf; plot(dispWts,'k');
            hold on;
            if (targetStartPoint == 0)
                targetStartPoint = 1;
            end
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
            
            if strcmp(obj.currentStimulusType,'Reference')
                if (obj.referenceInnerDiameter == 0) %reference is a spot
                    %convert from microns to pixels...
                    spotDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.referenceOuterDiameter);
                    % Create spot stimulus.            
                    spot = stage.builtin.stimuli.Ellipse();
                    spot.color = obj.intensity;
                    spot.radiusX = spotDiameterPix/2;
                    spot.radiusY = spotDiameterPix/2;
                    spot.position = canvasSize/2 + centerOffsetPix;
                    p.addStimulus(spot);
                else %reference is an annulus
                    innerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.referenceInnerDiameter);
                    outerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.referenceOuterDiameter);
                    spot = stage.builtin.stimuli.Ellipse();
                    spot.color = obj.intensity;
                    spot.radiusX = outerDiameterPix/2;
                    spot.radiusY = outerDiameterPix/2;
                    spot.position = canvasSize/2 + centerOffsetPix;
                    p.addStimulus(spot);
                    
                    maskSpot = stage.builtin.stimuli.Ellipse();
                    maskSpot.color = obj.backgroundIntensity;
                    maskSpot.radiusX = innerDiameterPix/2;
                    maskSpot.radiusY = innerDiameterPix/2;
                    maskSpot.position = canvasSize/2 + centerOffsetPix;
                    p.addStimulus(maskSpot);
                    % hide during pre & post
                    maskSpotVisible = stage.builtin.controllers.PropertyController(maskSpot, 'visible', ...
                        @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                    p.addController(maskSpotVisible);
                end

            elseif strcmp(obj.currentStimulusType,'Test')
                innerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.testInnerDiameter);
                outerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.testOuterDiameter);
                spot = stage.builtin.stimuli.Ellipse();
                spot.color = obj.intensity;
                spot.radiusX = outerDiameterPix/2;
                spot.radiusY = outerDiameterPix/2;
                spot.position = canvasSize/2 + centerOffsetPix;
                p.addStimulus(spot);

                maskSpot = stage.builtin.stimuli.Ellipse();
                maskSpot.color = obj.backgroundIntensity;
                maskSpot.radiusX = innerDiameterPix/2;
                maskSpot.radiusY = innerDiameterPix/2;
                maskSpot.position = canvasSize/2 + centerOffsetPix;
                p.addStimulus(maskSpot);
                % hide during pre & post
                maskSpotVisible = stage.builtin.controllers.PropertyController(maskSpot, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(maskSpotVisible);
            else
                error('Not a recognized stimulus type')
            end
            % hide spot during pre & post
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

