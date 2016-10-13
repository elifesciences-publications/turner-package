classdef LinearEquivalentCSAdditivity < edu.washington.riekelab.protocols.RiekeLabStageProtocol

    properties
        preTime = 150 % ms
        stimTime = 200 % ms
        tailTime = 150 % ms
        imageName = '00152' %van hateren image names
        
        noPatches = 50 %number of different image patches (fixations) to show
        centerDiameter = 200 % um
        annulusInnerDiameter = 300 % um
        annulusOuterDiameter = 600 % um
        
        linearIntegrationFunction = 'gaussian' %applies to both center & surround
        rfSigmaCenter = 50 % (um) Enter from fit RF
        rfSigmaSurround = 180 % (um) Enter from fit RF
        
        patchSampling = 'random'
        patchContrast = 'all'
        seed = 1 % rand seed for picking image patches
        centerOffset = [0, 0] % [x,y] (um)
        onlineAnalysis = 'none'
        numberOfAverages = uint16(1200) % number of epochs to queue
        amp % Output amplifier
    end
    
    properties (Hidden)
        ampType
        imageNameType = symphonyui.core.PropertyType('char', 'row', {'00152','00377','00405','00459','00657','01151','01154',...
            '01192','01769','01829','02265','02281','02733','02999','03093',...
            '03347','03447','03584','03758','03760'})
        linearIntegrationFunctionType = symphonyui.core.PropertyType('char', 'row', {'gaussian','uniform'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        patchSamplingType = symphonyui.core.PropertyType('char', 'row', {'random','ranked'})
        patchContrastType = symphonyui.core.PropertyType('char', 'row', {'all','negative','positive'})
        centerOffsetType = symphonyui.core.PropertyType('denserealdouble', 'matrix')
        
        wholeImageMatrix
        imagePatchMatrix
        patchLocations
        centerEquivalentIntensityValues
        surroundEquivalentIntensityValues
        
        %saved out to each epoch...
        currentStimSet
        backgroundIntensity
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
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.turner.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'groupBy',{'currentCenter','currentSurround'});
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            
            %load appropriate image...
            resourcesDir = 'C:\Users\Public\Documents\turner-package\resources\';
            obj.currentStimSet = '/VHsubsample_20160105';
            fileId=fopen([resourcesDir, obj.currentStimSet, '/imk', obj.imageName,'.iml'],'rb','ieee-be');
            img = fread(fileId, [1536,1024], 'uint16');
           
            img = double(img);
            img = (img./max(img(:))); %rescale s.t. brightest point is maximum monitor level
            obj.backgroundIntensity = mean(img(:));%set the mean to the mean over the image
            contrastImage = (img - obj.backgroundIntensity) ./ obj.backgroundIntensity;
            img = img.*255; %rescale s.t. brightest point is maximum monitor level
            obj.wholeImageMatrix = uint8(img);
            rng(obj.seed); %set random seed for fixation draw
            
            %get patch locations:
            load([resourcesDir,'NaturalImageFlashLibrary_072216.mat']);
            fieldName = ['imk', obj.imageName];
            %1) restrict to desired patch contrast:
            LnResp = imageData.(fieldName).LnModelResponse;
            if strcmp(obj.patchContrast,'all')
                inds = 1:length(LnResp);
            elseif strcmp(obj.patchContrast,'positive')
                inds = find(LnResp > 0);
            elseif strcmp(obj.patchContrast,'negative')
                inds = find(LnResp <= 0);
            end
            xLoc = imageData.(fieldName).location(inds,1);
            yLoc = imageData.(fieldName).location(inds,2);
            subunitResp = imageData.(fieldName).SubunitModelResponse(inds);
            LnResp = imageData.(fieldName).LnModelResponse(inds);
            
            %2) do patch sampling:
            responseDifferences = subunitResp - LnResp;
            if strcmp(obj.patchSampling,'random')
                %get patch indices:
                pullInds = randsample(1:length(xLoc),obj.noPatches);
            else strcmp(obj.patchSampling,'ranked')
                %pull more than needed to account for empty bins at tail
                [~, ~, bin] = histcounts(responseDifferences,1.5*obj.noPatches);
                populatedBins = unique(bin);
                %pluck one patch from each bin
                pullInds = arrayfun(@(b) find(b == bin,1),populatedBins);
                %get patch indices:
                pullInds = randsample(pullInds,obj.noPatches);
            end
            obj.patchLocations(1,1:obj.noPatches) = xLoc(pullInds); %in VH pixels
            obj.patchLocations(2,1:obj.noPatches) = yLoc(pullInds);
            
            
            %GET EQUIVALENT INTENSITY VALUES...
            %size of the stimulus on the prep:
            stimSize = obj.rig.getDevice('Stage').getCanvasSize() .* ...
                obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel'); %um
            stimSize_VHpix = stimSize ./ (3.3); %um / (um/pixel) -> pixel
            radX = round(stimSize_VHpix(1) / 2); %boundaries for fixation draws depend on stimulus size
            radY = round(stimSize_VHpix(2) / 2);

            % % % % % First the RF center % % % % % % % % % % % % % % % % % % % % % % % % 
            sigmaC = obj.rfSigmaCenter ./ 3.3; %microns -> VH pixels
            RFcenter = fspecial('gaussian',2.*[radX radY] + 1,sigmaC);

            %   get the aperture to apply to the image...
            %   set to 1 = values to be included (i.e. image is shown there)
            [rr, cc] = meshgrid(1:(2*radX+1),1:(2*radY+1));
            if obj.centerDiameter > 0
                apertureMatrix = sqrt((rr-radX).^2 + ...
                    (cc-radY).^2) < ((obj.centerDiameter/2) ./ 3.3);
                apertureMatrix = apertureMatrix';
            else
                apertureMatrix = ones(2.*[radX radY] + 1);
            end
            if strcmp(obj.linearIntegrationFunction,'gaussian')
                centerWeightingFxn = apertureMatrix .* RFcenter; %set to zero mean gray pixels
            elseif strcmp(obj.linearIntegrationFunction,'uniform')
                centerWeightingFxn = apertureMatrix;
            end
            centerWeightingFxn = centerWeightingFxn ./ sum(centerWeightingFxn(:)); %sum to one
            
            % % % %  Now the RF surround % % % % % % % % % % % % % % % % % % % % % % % % 
            sigmaS = obj.rfSigmaSurround ./ 3.3; %microns -> VH pixels
            RFsurround = fspecial('gaussian',2.*[radX radY] + 1,sigmaS);

            %   get the mask \ aperture to apply to the image...
            %   set to 1 = values to be included (i.e. image is shown there)
            maskMatrix = sqrt((rr-radX).^2 + ...
                (cc-radY).^2) > (obj.annulusInnerDiameter/2) ./ 3.3;
            maskMatrix = maskMatrix';
            
            if obj.annulusOuterDiameter > 0
                apertureMatrix = sqrt((rr-radX).^2 + ...
                    (cc-radY).^2) < (obj.annulusOuterDiameter/2) ./ 3.3;
                apertureMatrix = apertureMatrix';
            else
                apertureMatrix = ones(2.*[radX radY] + 1);
            end
            
            annulusMatrix = min(maskMatrix,apertureMatrix);  %#ok<UDIM>
            if strcmp(obj.linearIntegrationFunction,'gaussian')
                surroundWeightingFxn = annulusMatrix .* RFsurround; %set to zero mean gray pixels
            elseif strcmp(obj.linearIntegrationFunction,'uniform')
                surroundWeightingFxn = annulusMatrix;
            end
            surroundWeightingFxn = surroundWeightingFxn ./ sum(surroundWeightingFxn(:)); %sum to one
            
            obj.centerEquivalentIntensityValues = zeros(1,obj.noPatches);
            obj.surroundEquivalentIntensityValues = zeros(1,obj.noPatches);
            for ff = 1:obj.noPatches
                tempPatch = contrastImage(round(obj.patchLocations(1,ff)-radX):round(obj.patchLocations(1,ff)+radX),...
                    round(obj.patchLocations(2,ff)-radY):round(obj.patchLocations(2,ff)+radY));
                centerEquivalentContrast = sum(sum(centerWeightingFxn .* tempPatch));
                surroundEquivalentContrast = sum(sum(surroundWeightingFxn .* tempPatch));
                
                obj.centerEquivalentIntensityValues(ff) = obj.backgroundIntensity + ...
                    centerEquivalentContrast * obj.backgroundIntensity;
                obj.surroundEquivalentIntensityValues(ff) = obj.backgroundIntensity + ...
                    surroundEquivalentContrast * obj.backgroundIntensity;
            end
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
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
            
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
            
            %imagePatchMatrix is in VH pixels
            %size of the stimulus on the prep:
            stimSize = obj.rig.getDevice('Stage').getCanvasSize() .* ...
                obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel'); %um
            stimSize_VHpix = stimSize ./ (3.3); %um / (um/pixel) -> pixel
            radX = stimSize_VHpix(1) / 2; %boundaries for fixation draws depend on stimulus size
            radY = stimSize_VHpix(2) / 2;
            obj.imagePatchMatrix = obj.wholeImageMatrix(round(obj.currentPatchLocation(1)-radX):round(obj.currentPatchLocation(1)+radX),...
                round(obj.currentPatchLocation(2)-radY):round(obj.currentPatchLocation(2)+radY));
            obj.imagePatchMatrix = obj.imagePatchMatrix';

            epoch.addParameter('currentStimSet', obj.currentStimSet);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
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