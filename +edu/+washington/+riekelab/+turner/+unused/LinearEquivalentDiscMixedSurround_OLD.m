classdef LinearEquivalentDiscMixedSurround_OLD < edu.washington.riekelab.turner.protocols.SinglePatchFlashProtocol

    properties
        preTime = 200 % ms
        stimTime = 200 % ms
        tailTime = 200 % ms

        apertureDiameter = 250 % um
        annulusInnerDiameter = 250; %  um
        annulusOuterDiameter = 600; % um
        
        patchContrast = 'negative' %of center
        patchLinearity = 'biasedNonlinear' %of center
        linearIntegrationFunction = 'gaussian'
        rfSigmaCenter = 50 % (um) Enter from fit RF
        
        noMixedSurrounds = 8;
        surroundContrast = 'all' %surround

        
        numberOfAverages = uint16(180) % number of epochs to queue
    end
    
    properties (Hidden)
        linearIntegrationFunctionType = symphonyui.core.PropertyType('char', 'row', {'gaussian','uniform'})
        
        patchContrastType = symphonyui.core.PropertyType('char', 'row', {'all','negative','positive'})
        surroundContrastType = symphonyui.core.PropertyType('char', 'row', {'all','negative','positive'})
        patchLinearityType = symphonyui.core.PropertyType('char', 'row', {'biasedNonlinear','biasedLinear','random'})
       
        surroundPatchLocations
        centerPatchMatrix
        surroundPatchMatrix
        
        %saved out to each epoch...
        centerPatchLocation
        equivalentIntensity
        stimulusTag
        currentSurroundLocation
        surroundIndex
    end

    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.turner.protocols.SinglePatchFlashProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.turner.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'groupBy',{'stimulusTag'});
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            
            %Center image location:
            obj.centerPatchLocation = ...
                edu.washington.riekelab.turner.protocols.SinglePatchFlashProtocol.getPatchLocations(...
                obj,1,obj.patchContrast,obj.patchLinearity);
            %Center disc intensity:
            obj.equivalentIntensity = ...
                edu.washington.riekelab.turner.protocols.SinglePatchFlashProtocol.getEquivalentIntensityValue(...
                obj, 0, obj.apertureDiameter, obj.rfSigmaCenter, obj.centerPatchLocation);
            
            %Center image patch:
            obj.centerPatchMatrix = ...
                edu.washington.riekelab.turner.protocols.SinglePatchFlashProtocol.getImagePatchMatrix(...
                obj, obj.centerPatchLocation);
            
            %shuffled surround image locations:
            obj.surroundPatchLocations = ...
                edu.washington.riekelab.turner.protocols.SinglePatchFlashProtocol.getPatchLocations(...
                obj,obj.noMixedSurrounds,obj.surroundContrast,'random');
            
            %first location is real "matched" surround:
            obj.surroundPatchLocations = cat(2,obj.centerPatchLocation,obj.surroundPatchLocations);

            if ~strcmp(obj.onlineAnalysis,'none')
                responseDimensions = [2, length(obj.surroundPatchLocations) + 1, 1]; %image/equiv by surround contrast by image patch
                obj.showFigure('edu.washington.riekelab.turner.figures.ModImageVsIntensityFigure',...
                obj.rig.getDevice(obj.amp),responseDimensions,...
                'recordingType',obj.onlineAnalysis,...
                'stimType','SinglePatchMixedSurround',...
                'preTime',obj.preTime,'stimTime',obj.stimTime);
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.turner.protocols.SinglePatchFlashProtocol(obj, epoch);
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);

            evenInd = mod(obj.numEpochsCompleted,2);
            if evenInd == 1 %even, show uniform linear equivalent intensity
                obj.stimulusTag = 'intensity';
            elseif evenInd == 0 %odd, show image
                obj.stimulusTag = 'image';
            end

            %get current surround location
            totalSurrounds = length(obj.surroundPatchLocations) + 1; %mixed surrounds plus real surround plus no surround
            obj.surroundIndex = floor(mod(obj.numEpochsCompleted/2,totalSurrounds)) + 1;
            if (obj.surroundIndex == 1) %no surround
                obj.currentSurroundLocation = [0,0]; %placeholder
            else
                obj.currentSurroundLocation = obj.surroundPatchLocations(:,obj.surroundIndex-1);
                %Surround image patch:
                obj.surroundPatchMatrix = ...
                    edu.washington.riekelab.turner.protocols.SinglePatchFlashProtocol.getImagePatchMatrix(...
                    obj, obj.currentSurroundLocation);
            end

            epoch.addParameter('centerPatchLocation', obj.centerPatchLocation);
            epoch.addParameter('equivalentIntensity', obj.equivalentIntensity);
            epoch.addParameter('stimulusTag', obj.stimulusTag);
            
            epoch.addParameter('currentSurroundLocation', obj.currentSurroundLocation);
            
            epoch.addParameter('imagePatchIndex', obj.surroundIndex); %for analysis fig mostly
        end
        
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            annulusInnerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.annulusInnerDiameter);
            annulusOuterDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.annulusOuterDiameter);

            % Add surround image
            if (obj.surroundIndex == 1) %no surround
                
            else
                scene = stage.builtin.stimuli.Image(obj.surroundPatchMatrix);
                scene.size = canvasSize; %scale up to canvas size
                scene.position = canvasSize/2;
                % Use linear interpolation when scaling the image.
                scene.setMinFunction(GL.LINEAR);
                scene.setMagFunction(GL.LINEAR);

                % Add mask to make image appear only in annulus
                distanceMatrix = createDistanceMatrix(canvasSize(1),canvasSize(2));
                annulus = uint8((distanceMatrix < annulusOuterDiameterPix/2 & ...
                    distanceMatrix >= annulusInnerDiameterPix/2) * 255);
                surroundMask = stage.core.Mask(annulus);
                scene.setMask(surroundMask);
                
                p.addStimulus(scene);
                sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(sceneVisible);
            end

            %add center image
            if strcmp(obj.stimulusTag,'image') %image in center
                scene = stage.builtin.stimuli.Image(obj.centerPatchMatrix);
                scene.size = canvasSize; %scale up to canvas size
                scene.position = canvasSize/2;
                % Use linear interpolation when scaling the image.
                scene.setMinFunction(GL.LINEAR);
                scene.setMagFunction(GL.LINEAR);
                
                % Add mask to make image appear only in center
                distanceMatrix = createDistanceMatrix(canvasSize(1),canvasSize(2));
                annulus = uint8((distanceMatrix < apertureDiameterPix/2) * 255);
                centerMask = stage.core.Mask(annulus);
                scene.setMask(centerMask);
                
                p.addStimulus(scene);
                sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(sceneVisible);
            elseif strcmp(obj.stimulusTag,'intensity') %uniform disc in center
                disc = stage.builtin.stimuli.Ellipse();
                disc.radiusX = apertureDiameterPix/2;
                disc.radiusY = apertureDiameterPix/2;
                disc.color = obj.equivalentIntensity;
                disc.position = canvasSize/2;
                p.addStimulus(disc);
                sceneVisible = stage.builtin.controllers.PropertyController(disc, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(sceneVisible);
            end

            function m = createDistanceMatrix(sizeX,sizeY)
                [xx, yy] = meshgrid(1:sizeX,1:sizeY);
                m = sqrt((xx-(sizeX/2)).^2+(yy-(sizeY/2)).^2);
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