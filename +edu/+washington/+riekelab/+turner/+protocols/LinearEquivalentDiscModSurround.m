classdef LinearEquivalentDiscModSurround < edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol

    properties
        preTime = 200 % ms
        stimTime = 200 % ms
        tailTime = 200 % ms

        apertureDiameter = 200 % um
        annulusInnerDiameter = 300; %  um
        annulusOuterDiameter = 600; % um
        surroundContrast = [-0.9 -0.75 -0.5 -0.25 0 0.25 0.5 0.75 0.9];
        includeImageSurroundContrast = true;
        linearIntegrationFunction = 'gaussian'
        rfSigmaCenter = 50 % (um) Enter from fit RF
        rfSigmaSurround = 180 % (um) Enter from fit RF
        
        numberOfAverages = uint16(180) % number of epochs to queue
    end
    
    properties (Hidden)
        linearIntegrationFunctionType = symphonyui.core.PropertyType('char', 'row', {'gaussian','uniform'})

        allEquivalentIntensityValues
        surroundIntensityValues
        surroundContrastSequence
        
        %saved out to each epoch...
        imagePatchIndex
        currentPatchLocation
        equivalentIntensity
        stimulusTag
        currentSurroundContrast
    end

    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.turner.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'groupBy',{'stimulusTag'});
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            
            obj.allEquivalentIntensityValues = ...
                edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol.getEquivalentIntensityValues(...
                obj, 0, obj.apertureDiameter, obj.rfSigmaCenter);
            
            if (obj.includeImageSurroundContrast)
                noColumns = length(obj.surroundContrast) + 1;
                obj.surroundIntensityValues = ...
                    edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol.getEquivalentIntensityValues(...
                    obj, obj.annulusInnerDiameter, obj.annulusOuterDiameter, obj.rfSigmaSurround);
                obj.surroundContrastSequence = [];
                for pp = 1:obj.noPatches
                    newContrast = (obj.surroundIntensityValues(pp) - obj.backgroundIntensity) / obj.backgroundIntensity;
                    newSeq = [obj.surroundContrast, newContrast];
                    newSeq = randsample(newSeq,length(newSeq));
                    obj.surroundContrastSequence = cat(2,obj.surroundContrastSequence,newSeq);
                end
                
            else
                noColumns = length(obj.surroundContrast);
                obj.surroundContrastSequence = [];
                for pp = 1:obj.noPatches
                    newSeq = randsample(obj.surroundContrast,length(obj.surroundContrast));
                    obj.surroundContrastSequence = cat(2,obj.surroundContrastSequence,newSeq);
                end
                
            end
            
            if ~strcmp(obj.onlineAnalysis,'none')
                responseDimensions = [2, noColumns, obj.noPatches]; %image/equiv by surround contrast by image patch
                obj.showFigure('edu.washington.riekelab.turner.figures.ModImageVsIntensityFigure',...
                obj.rig.getDevice(obj.amp),responseDimensions,...
                'recordingType',obj.onlineAnalysis,...
                'preTime',obj.preTime,'stimTime',obj.stimTime);
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol(obj, epoch);
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);

            %pull patch location and equivalent contrast:
            epochsPerImagePatch = 2 * length(obj.surroundContrastSequence) / obj.noPatches; %2 b/c image and equiv
            obj.imagePatchIndex = floor(mod(obj.numEpochsCompleted/epochsPerImagePatch,obj.noPatches) + 1);
            evenInd = mod(obj.numEpochsCompleted,2);
            if evenInd == 1 %even, show uniform linear equivalent intensity
                obj.stimulusTag = 'intensity';
            elseif evenInd == 0 %odd, show image
                obj.stimulusTag = 'image';
            end
            obj.currentPatchLocation(1) = obj.patchLocations(1,obj.imagePatchIndex); %in VH pixels
            obj.currentPatchLocation(2) = obj.patchLocations(2,obj.imagePatchIndex);
            obj.equivalentIntensity = obj.allEquivalentIntensityValues(obj.imagePatchIndex);
            
            %get current surround contrast
            surroundContrastIndex = floor(mod(obj.numEpochsCompleted/2, length(obj.surroundContrastSequence)) + 1);
            obj.currentSurroundContrast = obj.surroundContrastSequence(surroundContrastIndex);
            
            obj.imagePatchMatrix = ...
                edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol.getImagePatchMatrix(...
                obj, obj.currentPatchLocation);

            epoch.addParameter('imagePatchIndex', obj.imagePatchIndex);
            epoch.addParameter('currentPatchLocation', obj.currentPatchLocation);
            epoch.addParameter('equivalentIntensity', obj.equivalentIntensity);
            epoch.addParameter('stimulusTag', obj.stimulusTag);
            epoch.addParameter('currentSurroundContrast', obj.currentSurroundContrast);
        end
        
        function p = createPresentation(obj)            
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            annulusInnerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.annulusInnerDiameter);
            annulusOuterDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.annulusOuterDiameter);

            if strcmp(obj.stimulusTag,'image')
                scene = stage.builtin.stimuli.Image(obj.imagePatchMatrix);
                scene.size = canvasSize; %scale up to canvas size
                scene.position = canvasSize/2;
                % Use linear interpolation when scaling the image.
                scene.setMinFunction(GL.LINEAR);
                scene.setMagFunction(GL.LINEAR);
                p.addStimulus(scene);
                sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(sceneVisible);
            elseif strcmp(obj.stimulusTag,'intensity')
                scene = stage.builtin.stimuli.Rectangle();
                scene.size = canvasSize;
                scene.color = obj.equivalentIntensity;
                scene.position = canvasSize/2;
                p.addStimulus(scene);
                sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(sceneVisible);
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
            
            %make annulus in surround
            rect = stage.builtin.stimuli.Rectangle();
            rect.position = canvasSize/2;
            rect.color = obj.backgroundIntensity + ...
                obj.backgroundIntensity * obj.currentSurroundContrast;
            rect.size = [max(canvasSize) max(canvasSize)];

            distanceMatrix = createDistanceMatrix(1024);
            annulus = uint8((distanceMatrix < annulusOuterDiameterPix/max(canvasSize) & ...
                distanceMatrix > annulusInnerDiameterPix/max(canvasSize)) * 255);
            mask = stage.core.Mask(annulus);

            rect.setMask(mask);
            p.addStimulus(rect);
            rectVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(rectVisible);
            
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