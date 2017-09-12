classdef FlashedGratingCorrelatedSurround < edu.washington.riekelab.protocols.RiekeLabStageProtocol

    properties
        preTime = 200 % ms
        stimTime = 200 % ms
        tailTime = 200 % ms
        
        apertureDiameter = 200 % um
        annulusInnerDiameter = 300; %  um
        annulusOuterDiameter = 600; % um

        gratingContrast = 0.5;
        gratingMean = 0.5;
        backgroundIntensity = 0.5; %0-1
        
        onlineAnalysis = 'none'
        amp % Output amplifier
        numberOfAverages = uint16(90) % number of epochs to queue
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        surroundIntensityValues
        surroundContrastSequence
        
        %saved out to each epoch...
        centerTag
        surroundTag
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
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'groupBy',{'centerTag','surroundTag'});
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            
            maxInt = obj.gratingMean + obj.gratingMean * obj.gratingContrast;
            minInt = obj.gratingMean - obj.gratingMean * obj.gratingContrast;
            if maxInt > 1
               error('Pixel value greater than 255'); 
            elseif minInt < 0
                error('Pixel value less than 0');
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);

            
            centerInd = mod(obj.numEpochsCompleted,2);
            if centerInd == 1 %even, show null
                obj.centerTag = 'intensity';
            elseif centerInd == 0 %odd, show grating
                obj.centerTag = 'image';
            end
            
            surroundInd = floor(mod(obj.numEpochsCompleted/2, 3) + 1);
            if surroundInd == 1
                obj.surroundTag = 'none';
            elseif surroundInd == 2
                obj.surroundTag = 'corr';
            elseif surroundInd == 3
                obj.surroundTag = 'acorr';
            end

            epoch.addParameter('centerTag', obj.centerTag);
            epoch.addParameter('surroundTag', obj.surroundTag);
        end
        
        function p = createPresentation(obj)            
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            annulusInnerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.annulusInnerDiameter);
            annulusOuterDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.annulusOuterDiameter);

            if strcmp(obj.centerTag,'image')
                % Create grating stimulus.            
                grate = edu.washington.riekelab.turner.stimuli.GratingWithOffset('square'); %square wave grating
                grate.orientation = 0;
                grate.size = [apertureDiameterPix, apertureDiameterPix];
                grate.position = canvasSize/2;
                grate.spatialFreq = 1/(2*apertureDiameterPix);
                grate.meanLuminance = obj.gratingMean;
                grate.contrast = obj.gratingContrast; %multiplier on square wave
                grate.phase = 90; %split field
                p.addStimulus(grate); %add grating to the presentation
                
                %hide during pre & post
                grateVisible = stage.builtin.controllers.PropertyController(grate, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(grateVisible);
                
            elseif strcmp(obj.centerTag,'intensity')
                % Create spot stimulus.            
                spot = stage.builtin.stimuli.Ellipse();
                spot.color = obj.gratingMean;
                spot.radiusX = apertureDiameterPix/2;
                spot.radiusY = apertureDiameterPix/2;
                spot.position = canvasSize/2;
                p.addStimulus(spot);

                % hide during pre & post
                spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(spotVisible);
            end
            
            if (obj.apertureDiameter > 0) %% Create aperture
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = canvasSize/2;
                aperture.color = obj.backgroundIntensity;
                aperture.size = [max(canvasSize) max(canvasSize)];
                mask = stage.core.Mask.createCircularAperture(apertureDiameterPix/max(canvasSize), 1024); %circular aperture
                aperture.setMask(mask);
                p.addStimulus(aperture); %add aperture
            end
            
            
            if strcmp(obj.surroundTag,'none')
                
            else
                %make annulus in surround
                rect = stage.builtin.stimuli.Rectangle();
                rect.position = canvasSize/2;
                rect.size = [max(canvasSize) max(canvasSize)];
                if strcmp(obj.surroundTag,'corr')
                    rect.color = obj.gratingMean;
                    
                elseif strcmp(obj.surroundTag,'acorr')
                    rect.color = obj.backgroundIntensity - ...
                        (obj.gratingMean - obj.backgroundIntensity);
                end
                
                distanceMatrix = createDistanceMatrix(1024);
                annulus = uint8((distanceMatrix < annulusOuterDiameterPix/max(canvasSize) & ...
                    distanceMatrix > annulusInnerDiameterPix/max(canvasSize)) * 255);
                mask = stage.core.Mask(annulus);
                
                rect.setMask(mask);
                p.addStimulus(rect);
                rectVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(rectVisible);
            end

            function m = createDistanceMatrix(size)
                step = 2 / (size - 1);
                [xx, yy] = meshgrid(-1:step:1, -1:step:1);
                m = sqrt(xx.^2 + yy.^2);
            end
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end

    end
    
end