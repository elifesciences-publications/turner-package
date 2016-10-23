classdef TextureCSAdditiviy < edu.washington.riekelab.protocols.RiekeLabStageProtocol

    properties
        preTime = 200 % ms
        stimTime = 200 % ms
        tailTime = 200 % ms
        centerSigmas = [4 6 8 10 12 16 20];
        surroundSigmas = [4 6 8 10 12 16 20];

        centerDiameter = 200 % um
        annulusInnerDiameter = 300 % um
        annulusOuterDiameter = 600 % um
        centerOffset = [0, 0] % [x,y] (um)
        backgroundIntensity = 0.5       % Background light intensity (0-0.5)
        onlineAnalysis = 'none'
        numberOfAverages = uint16(147) % number of epochs to queue
        amp % Output amplifier
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        centerOffsetType = symphonyui.core.PropertyType('denserealdouble', 'matrix')
        
        centerTexture
        surroundTexture
        sigmaPairsList
        
        %saved out to each epoch...
        currentCenterSeed
        currentCenterSigma
        currentSurroundSeed
        currentSurroundSigma
        currentStimulus
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
                'groupBy',{'currentStimulus'});
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            
            %get a list of all center, surround sigma pairs and randomize
            %its order
            [cc, ss] = meshgrid(obj.centerSigmas, obj.surroundSigmas);
            pairs = [cc(:) ss(:)];
            obj.sigmaPairsList = pairs(randperm(size(pairs,1)),:);
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);

            % get stim type:
            stimInd = mod(obj.numEpochsCompleted,3);
            if stimInd == 0
                obj.currentStimulus = 'Center';
                %start of a new triplet. Get new textures...
                % sigmas:
                sigmaInd = mod(floor(obj.numEpochsCompleted/3), size(obj.sigmaPairsList,1)) + 1;
                obj.currentCenterSigma = obj.sigmaPairsList(sigmaInd,1);
                obj.currentSurroundSigma = obj.sigmaPairsList(sigmaInd,2);
                
                % seeds:
                obj.currentCenterSeed = RandStream.shuffleSeed;
                obj.currentSurroundSeed = RandStream.shuffleSeed;

                obj.centerTexture = makeTextureMatrix(textureSize,...
                    obj.currentCenterSigma, obj.currentCenterSeed, obj.backgroundIntensity);
                obj.surroundTexture = makeTextureMatrix(textureSize,...
                    obj.currentSurroundSigma, obj.currentSurroundSeed, obj.backgroundIntensity);

            elseif stimInd == 1
                obj.currentStimulus = 'Surround';
            elseif stimInd == 2
                obj.currentStimulus = 'Center-Surround';
            end

            epoch.addParameter('currentCenterSigma', obj.currentCenterSigma);
            epoch.addParameter('currentCenterSeed', obj.currentCenterSeed);
            epoch.addParameter('currentSurroundSigma', obj.currentSurroundSigma);
            epoch.addParameter('currentSurroundSeed', obj.currentSurroundSeed);
            epoch.addParameter('currentStimulus', obj.currentStimulus);
        end
        
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            centerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.centerDiameter);
            annulusInnerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.annulusInnerDiameter);
            annulusOuterDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.annulusOuterDiameter);
            centerOffsetPix = obj.rig.getDevice('Stage').um2pix(obj.centerOffset);
            
            %make image patch:
            scene = stage.builtin.stimuli.Image(obj.imagePatchMatrix);
            scene.size = canvasSize; %scale up to canvas size
            scene.position = canvasSize/2 + centerOffsetPix;
            % Use linear interpolation when scaling the image.
            scene.setMinFunction(GL.LINEAR);
            scene.setMagFunction(GL.LINEAR);
            p.addStimulus(scene);
            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(sceneVisible);
            
            if strcmp(obj.currentStimulus,'Center') %aperture around center
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = canvasSize/2 + centerOffsetPix;
                aperture.color = obj.backgroundIntensity;
                aperture.size = [max(canvasSize) max(canvasSize)];
                mask = stage.core.Mask.createCircularAperture(centerDiameterPix/max(canvasSize), 1024);
                aperture.setMask(mask);
                p.addStimulus(aperture);
            elseif strcmp(obj.currentStimulus,'Surround') %aperture in far surround + mask in center
                % big aperture:
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = canvasSize/2 + centerOffsetPix;
                aperture.color = obj.backgroundIntensity;
                aperture.size = [max(canvasSize) max(canvasSize)];
                mask = stage.core.Mask.createCircularAperture(annulusOuterDiameterPix/max(canvasSize), 1024);
                aperture.setMask(mask);
                p.addStimulus(aperture);
                % center mask:
                maskSpot = stage.builtin.stimuli.Ellipse();
                maskSpot.radiusX = annulusInnerDiameterPix/2;
                maskSpot.radiusY = annulusInnerDiameterPix/2;
                maskSpot.position = canvasSize/2 + centerOffsetPix;
                maskSpot.color = obj.backgroundIntensity;
                p.addStimulus(maskSpot);
            elseif strcmp(obj.currentStimulus,'Center-Surround') %annulus between center & surround
                % big aperture:
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = canvasSize/2 + centerOffsetPix;
                aperture.color = obj.backgroundIntensity;
                aperture.size = [max(canvasSize) max(canvasSize)];
                mask = stage.core.Mask.createCircularAperture(annulusOuterDiameterPix/max(canvasSize), 1024);
                aperture.setMask(mask);
                p.addStimulus(aperture);
                
                %annulus between center & surround:
                annulus = stage.builtin.stimuli.Rectangle();
                annulus.position = canvasSize/2 + centerOffsetPix;
                annulus.color = obj.backgroundIntensity;
                annulus.size = [max(canvasSize) max(canvasSize)];
                mask = stage.core.Mask.createAnnulus(centerDiameterPix/max(canvasSize),...
                    annulusInnerDiameterPix/max(canvasSize),1024);
                annulus.setMask(mask);
                p.addStimulus(annulus);
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