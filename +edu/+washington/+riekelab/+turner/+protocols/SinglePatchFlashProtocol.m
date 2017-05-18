classdef (Abstract) SinglePatchFlashProtocol < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    properties
        imageName = '00152' %van hateren image names
        seed = 1 % rand seed for picking image patch
        
        
        onlineAnalysis = 'none'
        amp % Output amplifier
    end
    
    properties (Hidden)
        ampType
        imageNameType = symphonyui.core.PropertyType('char', 'row', {'00152','00377','00405','00459','00657','01151','01154',...
            '01192','01769','01829','02265','02281','02733','02999','03093',...
            '03347','03447','03584','03758','03760'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        
        
        screenSize
        wholeImageMatrix
        contrastImage
        
        %saved out to each epoch...
        currentImageSet
        currentStimSet
        backgroundIntensity
    end
    
    methods
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            % get current image and stim (library) set:
            resourcesDir = 'C:\Users\Public\Documents\turner-package\resources\';
            obj.currentImageSet = '/VHsubsample_20160105';
            obj.screenSize = obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel') .* ...
                obj.rig.getDevice('Stage').getCanvasSize(); %microns
            obj.currentStimSet = 'NaturalImageFlashLibrary_110316'; %OLED on rigs F,E,B

            
            % get the image and scale it:
            fileId=fopen([resourcesDir, obj.currentImageSet, '/imk', obj.imageName,'.iml'],'rb','ieee-be');
            img = fread(fileId, [1536,1024], 'uint16');
            img = double(img);
            img = (img./max(img(:))); %rescale s.t. brightest point is maximum monitor level
            obj.backgroundIntensity = mean(img(:));%set the mean to the mean over the image
            obj.contrastImage = (img - obj.backgroundIntensity) ./ obj.backgroundIntensity;
            img = img.*255; %rescale s.t. brightest point is maximum monitor level
            obj.wholeImageMatrix = uint8(img);
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            
            epoch.addParameter('currentImageSet', obj.currentImageSet);
            epoch.addParameter('currentStimSet', obj.currentStimSet);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
        end
    end
    methods (Static)
        function patchLocations =  getPatchLocations(obj,noPatches,patchContrast,patchLinearity)
            % GET PATCH LOCATIONS:
            resourcesDir = 'C:\Users\Public\Documents\turner-package\resources\';
            rng(obj.seed); %set random seed for fixation draw
            load([resourcesDir,obj.currentStimSet,'.mat']);
            fieldName = ['imk', obj.imageName];
            
            %1) restrict to desired patch contrast:
            LnResp = imageData.(fieldName).LnModelResponse;
            if strcmp(patchContrast,'all')
                inds = 1:length(LnResp);
            elseif strcmp(patchContrast,'positive')
                inds = find(LnResp > 0);
            elseif strcmp(patchContrast,'negative')
                inds = find(LnResp <= 0);
            end
            xLoc = imageData.(fieldName).location(inds,1);
            yLoc = imageData.(fieldName).location(inds,2);
            subunitResp = imageData.(fieldName).SubunitModelResponse(inds);
            LnResp = imageData.(fieldName).LnModelResponse(inds);
            
            %2) do patch sampling:
            responseDifferences = subunitResp - LnResp;
            if strcmp(patchLinearity,'random')
                %get patch index:
                pullInds = randsample(1:length(xLoc),noPatches);
            elseif strcmp(patchLinearity,'biasedNonlinear')
                %select patches more nonlinear than average
                biggerInds = find(responseDifferences > mean(responseDifferences));
                %randomly sample from this subset:
                pullInds = randsample(biggerInds,noPatches);
            elseif strcmp(patchLinearity,'biasedLinear')
                %select patches less nonlinear than average
                smallerInds = find(responseDifferences < mean(responseDifferences));
                %randomly sample from this subset:
                pullInds = randsample(smallerInds,noPatches);
            end
            patchLocations(1,1:noPatches) = xLoc(pullInds); %in VH pixels
            patchLocations(2,1:noPatches) = yLoc(pullInds);
        end
               
        function EquivalentIntensityValue =  getEquivalentIntensityValue(obj,innerDiameter,outerDiameter,RFsigma,patchLocation)
            %outerDiameter is circle in which to integrate. innerDiameter
            %is the size of a circle to mask off before integration.
            %e.g. center RF (Linear equivalent disc): innerDiameter = 0
            %   surround RF (Linear equivalent annulus): innerDiameter > 0
            stimSize_VHpix = obj.screenSize ./ (6.6); %um / (um/pixel) -> pixel
            radX = floor(stimSize_VHpix(1) / 2); %boundaries for fixation draws depend on stimulus size
            radY = floor(stimSize_VHpix(2) / 2);
            
            % Get the model RF:
            RFsigma = RFsigma ./ 6.6; %microns -> VH pixels
            RF = fspecial('gaussian',2.*[radX radY],RFsigma);

            % Get the aperture to apply to the image...
            %   set to 1 = values to be included (i.e. image is shown there)
            [rr, cc] = meshgrid(1:(2*radX),1:(2*radY));
            apertureMatrix = sqrt((rr-radX).^2 + ...
                (cc-radY).^2) < (outerDiameter/2) ./ 6.6;
            apertureMatrix = apertureMatrix';
            
            if innerDiameter > 0
                maskMatrix = sqrt((rr-radX).^2 + ...
                    (cc-radY).^2) > (innerDiameter/2) ./ 6.6;
                maskMatrix = maskMatrix';
                apertureMatrix = min(maskMatrix,apertureMatrix); 
            end

            if strcmp(obj.linearIntegrationFunction,'gaussian')
                weightingFxn = apertureMatrix .* RF; %set to zero mean gray pixels
            elseif strcmp(obj.linearIntegrationFunction,'uniform')
                weightingFxn = apertureMatrix;
            end
            weightingFxn = weightingFxn ./ sum(weightingFxn(:)); %sum to one
            
            tempPatch = obj.contrastImage(round(patchLocation(1,1)-radX)+1:round(patchLocation(1,1)+radX),...
                round(patchLocation(2,1)-radY)+1:round(patchLocation(2,1)+radY));
            equivalentContrast = sum(sum(weightingFxn .* tempPatch));
            EquivalentIntensityValue = obj.backgroundIntensity + ...
                equivalentContrast * obj.backgroundIntensity;
            
        end
        function imagePatchMatrix =  getImagePatchMatrix(obj,currentPatchLocation)
            %imagePatchMatrix is in VH pixels
            stimSize_VHpix = obj.screenSize ./ (6.6); %um / (um/pixel) -> pixel
            radX = floor(stimSize_VHpix(1) / 2);
            radY = floor(stimSize_VHpix(2) / 2);
            imagePatchMatrix = obj.wholeImageMatrix(round(currentPatchLocation(1)-radX)+1:round(currentPatchLocation(1)+radX),...
                round(currentPatchLocation(2)-radY)+1:round(currentPatchLocation(2)+radY));
            imagePatchMatrix = imagePatchMatrix';

        end
 
    end
    
end

