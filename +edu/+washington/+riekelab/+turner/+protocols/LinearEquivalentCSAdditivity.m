classdef LinearEquivalentCSAdditivity < edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol

    properties
        preTime = 150 % ms
        stimTime = 200 % ms
        tailTime = 150 % ms

        centerDiameter = 200 % um
        annulusInnerDiameter = 300 % um
        annulusOuterDiameter = 600 % um
        linearIntegrationFunction = 'gaussian' %applies to both center & surround
        rfSigmaCenter = 50 % (um) Enter from fit RF
        rfSigmaSurround = 180 % (um) Enter from fit RF
        
        numberOfAverages = uint16(1200) % number of epochs to queue
    end
    
    properties (Hidden)
        linearIntegrationFunctionType = symphonyui.core.PropertyType('char', 'row', {'gaussian','uniform'})
        
        centerEquivalentIntensityValues
        surroundEquivalentIntensityValues
        
        %saved out to each epoch...
        imagePatchIndex
        currentPatchLocation
        equivalentCenterIntensity
        equivalentSurroundIntensity
        currentCenter
        currentSurround
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
                'groupBy',{'currentCenter','currentSurround'});
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));

            obj.centerEquivalentIntensityValues =  ...
                edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol.getEquivalentIntensityValues(...
                obj, 0, obj.centerDiameter, obj.rfSigmaCenter);
            
            obj.surroundEquivalentIntensityValues =  ...
                edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol.getEquivalentIntensityValues(...
                obj, obj.annulusInnerDiameter, obj.annulusOuterDiameter, obj.rfSigmaSurround);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol(obj, epoch);
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
            
            %eight different stim types
            centerStims = {'Image','none','Image','Equiv','none','Equiv','Image','Equiv'};
            surroundStims = {'none','Image','Image','none','Equiv','Equiv','Equiv','Image'};
            
            %pull patch location, equivalent intensities, and stim type tags:
            obj.imagePatchIndex = floor(mod(obj.numEpochsCompleted/8,obj.noPatches) + 1);
            stimInd = mod(obj.numEpochsCompleted,8);
            obj.currentCenter = centerStims{stimInd + 1};
            obj.currentSurround = surroundStims{stimInd + 1};
            
            obj.currentPatchLocation(1) = obj.patchLocations(1,obj.imagePatchIndex); %in VH pixels
            obj.currentPatchLocation(2) = obj.patchLocations(2,obj.imagePatchIndex);
            obj.equivalentCenterIntensity = obj.centerEquivalentIntensityValues(obj.imagePatchIndex);
            obj.equivalentSurroundIntensity = obj.surroundEquivalentIntensityValues(obj.imagePatchIndex);
            
            obj.imagePatchMatrix = ...
                edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol.getImagePatchMatrix(...
                obj, obj.currentPatchLocation);

            epoch.addParameter('imagePatchIndex', obj.imagePatchIndex);
            epoch.addParameter('currentPatchLocation', obj.currentPatchLocation);
            epoch.addParameter('equivalentCenterIntensity', obj.equivalentCenterIntensity);
            epoch.addParameter('equivalentSurroundIntensity', obj.equivalentSurroundIntensity);
            epoch.addParameter('currentCenter', obj.currentCenter);
            epoch.addParameter('currentSurround', obj.currentSurround);
        end
        
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            %convert stuff to pixels:
            centerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.centerDiameter);
            annulusInnerDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.annulusInnerDiameter);
            annulusOuterDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.annulusOuterDiameter);
            centerOffsetPix = obj.rig.getDevice('Stage').um2pix(obj.centerOffset);

            
            if strcmp(obj.currentCenter,'Image')
                makeScene(obj);
                if  strcmp(obj.currentSurround,'Image')
                    makeAnnulusMask(obj);
                    makeAperture(obj,annulusOuterDiameterPix);
                elseif strcmp(obj.currentSurround,'Equiv')
                    makeAperture(obj,centerDiameterPix);
                    makeAnnulus(obj,obj.equivalentSurroundIntensity);
                elseif strcmp(obj.currentSurround,'none')
                    makeAperture(obj,centerDiameterPix);
                end
            elseif strcmp(obj.currentCenter,'Equiv')
                if  strcmp(obj.currentSurround,'Image')
                    makeScene(obj);
                    makeMediumMask(obj);
                    makeAperture(obj,annulusOuterDiameterPix);
                    makeSpot(obj,centerDiameterPix,obj.equivalentCenterIntensity);
                elseif strcmp(obj.currentSurround,'Equiv')
                    makeSpot(obj,annulusOuterDiameterPix,obj.equivalentSurroundIntensity);
                    makeMediumMask(obj);
                    makeSpot(obj,centerDiameterPix,obj.equivalentCenterIntensity);
                elseif strcmp(obj.currentSurround,'none')
                    makeSpot(obj,centerDiameterPix,obj.equivalentCenterIntensity);
                end
            elseif strcmp(obj.currentCenter,'none')
                if  strcmp(obj.currentSurround,'Image')
                    makeScene(obj);
                    makeMediumMask(obj);
                    makeAperture(obj,annulusOuterDiameterPix);
                elseif strcmp(obj.currentSurround,'Equiv')
                    makeSpot(obj,annulusOuterDiameterPix,obj.equivalentSurroundIntensity);
                    makeMediumMask(obj);
                end
            end
            
            function makeScene(obj)
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
            end
            function makeAnnulusMask(obj)
                annulus = stage.builtin.stimuli.Rectangle();
                annulus.position = canvasSize/2 + centerOffsetPix;
                annulus.color = obj.backgroundIntensity;
                annulus.size = [max(canvasSize) max(canvasSize)];
                mask = stage.core.Mask.createAnnulus(centerDiameterPix/max(canvasSize),...
                    annulusInnerDiameterPix/max(canvasSize),1024);
                annulus.setMask(mask);
                p.addStimulus(annulus);
            end
            function makeAnnulus(~,intensity)
                rect = stage.builtin.stimuli.Rectangle();
                rect.position = canvasSize/2 + centerOffsetPix;
                rect.color = intensity;
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
            end
            function makeAperture(obj, apertureDiameter)
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = canvasSize/2 + centerOffsetPix;
                aperture.color = obj.backgroundIntensity;
                aperture.size = [max(canvasSize) max(canvasSize)];
                mask = stage.core.Mask.createCircularAperture(apertureDiameter/max(canvasSize), 1024);
                aperture.setMask(mask);
                p.addStimulus(aperture);
            end
            function makeMediumMask(obj)
                maskSpot = stage.builtin.stimuli.Ellipse();
                maskSpot.radiusX = annulusInnerDiameterPix/2;
                maskSpot.radiusY = annulusInnerDiameterPix/2;
                maskSpot.position = canvasSize/2 + centerOffsetPix;
                maskSpot.color = obj.backgroundIntensity;
                p.addStimulus(maskSpot);
                maskSpotVisible = stage.builtin.controllers.PropertyController(maskSpot, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(maskSpotVisible);
            end
            function makeSpot(~,spotDiameter,spotColor)
                spot = stage.builtin.stimuli.Ellipse();
                spot.radiusX = spotDiameter/2;
                spot.radiusY = spotDiameter/2;
                spot.position = canvasSize/2 + centerOffsetPix;
                spot.color = spotColor;
                p.addStimulus(spot);
                spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(spotVisible);
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