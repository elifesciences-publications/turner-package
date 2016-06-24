classdef AnnulusWeightTest < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    
    properties
        preTime = 200                   % (ms)
        stimTime = 200                 % (ms)
        tailTime = 200                  % (ms)
        centerIntensity = 0.75;
        centerDiameter = 150 % (um)
        referenceInnerDiameter = 250 % (um)
        referenceOuterDiameter = 300 % (um)
        rfSigmaSurround = 180 % (um)
        annulusIntensity = 1.0             % (0-1)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0, 0]           % center offset (um)
        onlineAnalysis = 'none'
        numberOfAverages = uint16(15)    % Number of epochs
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
            colors = edu.washington.riekelab.turner.utils.pmkmp(3,'CubicYF');
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.turner.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'groupBy',{'currentStimulusType'},'sweepColor',colors);
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            if (obj.centerDiameter > obj.referenceInnerDiameter)
                warndlg('Center spot occludes reference annulus (centerDiameter > referenceInnerDiameter)')
            end
            %use the input RF to calculate the size of the
            %annulus that should drive an equal response to the reference
            %stimulus
            sigmaS = obj.rfSigmaSurround;
            %activation of the surround from the reference stimulus:
            targetActivation = edu.washington.riekelab.turner.utils.GaussianRFAreaSummation([1 sigmaS],...
                obj.referenceOuterDiameter) - ...
                edu.washington.riekelab.turner.utils.GaussianRFAreaSummation([1 sigmaS],...
                obj.referenceInnerDiameter);
            
            startPoint = obj.referenceOuterDiameter; %start at the edge of the reference stim
            micronsPerPixel = obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
            endOfSearch = round(min(obj.rig.getDevice('Stage').getCanvasSize()).*micronsPerPixel); %um
            obj.testInnerDiameter = startPoint;
            obj.testOuterDiameter = [];
            testVector = startPoint:endOfSearch;
            for ii = 1:length(testVector)
                testActivation = edu.washington.riekelab.turner.utils.GaussianRFAreaSummation([1 sigmaS],...
                testVector(ii)) - ...
                edu.washington.riekelab.turner.utils.GaussianRFAreaSummation([1 sigmaS],...
                startPoint);
                if testActivation > targetActivation
                   obj.testOuterDiameter = testVector(ii);
                   break 
                end
            end
            if isempty(obj.testOuterDiameter)
                error('Cannot find equivalent annulus, make reference stimulus smaller')
            end

            figure(30); clf;
            refYY = edu.washington.riekelab.turner.utils.GaussianRFAreaSummation([1 sigmaS],...
                obj.referenceInnerDiameter:obj.referenceOuterDiameter) - ...
                edu.washington.riekelab.turner.utils.GaussianRFAreaSummation([1 sigmaS],obj.referenceInnerDiameter);
            testYY = edu.washington.riekelab.turner.utils.GaussianRFAreaSummation([1 sigmaS],...
                obj.referenceOuterDiameter:obj.testOuterDiameter) - ...
                edu.washington.riekelab.turner.utils.GaussianRFAreaSummation([1 sigmaS],obj.referenceOuterDiameter);
            hold on;
            plot(refYY,'g')
            plot(testYY,'r')
            legend('Reference','Test')
            xlabel('Annulus width (microns)'); ylabel('RF activation')
            grid on
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
            
            tempInd = mod(obj.numEpochsCompleted, 3);
            if (tempInd == 0)
                obj.currentStimulusType = 'Center';
            elseif (tempInd == 1)
                obj.currentStimulusType = 'Reference';
            elseif (tempInd == 2)
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
            
            if ~strcmp(obj.currentStimulusType,'Center')
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
            else
                %No annulus, just spot
            end

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

