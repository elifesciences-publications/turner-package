classdef AreaSummationFigure < symphonyui.core.FigureHandler
    
    properties (SetAccess = private)
        ampDevice
        recordingType
        preTime
        stimTime
    end
    
    properties (Access = private)
        axesHandle
        lineHandle
        fitLineHandle
        allEpochResponses
        allSpotSizes
        summaryData
        
    end
    
    methods
        
        function obj = AreaSummationFigure(ampDevice, varargin)
            obj.ampDevice = ampDevice;            
            ip = inputParser();
            ip.addParameter('recordingType', [], @(x)ischar(x));
            ip.addParameter('preTime', [], @(x)isvector(x));
            ip.addParameter('stimTime', [], @(x)isvector(x));
            ip.parse(varargin{:});
            obj.recordingType = ip.Results.recordingType;
            obj.preTime = ip.Results.preTime;
            obj.stimTime = ip.Results.stimTime;
            
            
            obj.createUi();
        end
        
        function createUi(obj)
            import appbox.*;
            iconDir = 'C:\Users\Max Turner\Documents\GitHub\turner-package\resources\icons\';
            toolbar = findall(obj.figureHandle, 'Type', 'uitoolbar');
            fitGaussianButton = uipushtool( ...
                'Parent', toolbar, ...
                'TooltipString', 'Fit Gaussian', ...
                'Separator', 'on', ...
                'ClickedCallback', @obj.onSelectedFitGaussian);
            setIconImage(fitGaussianButton, [iconDir, 'Gaussian.png']);
            
            fitDoGButton = uipushtool( ...
                'Parent', toolbar, ...
                'TooltipString', 'Fit DoG', ...
                'Separator', 'on', ...
                'ClickedCallback', @obj.onSelectedFitDoG);
            setIconImage(fitDoGButton, [iconDir, 'DoG.png']);
            
            
            obj.axesHandle = axes( ...
                'Parent', obj.figureHandle, ...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            xlabel(obj.axesHandle, 'Spot Diameter (um)');
            ylabel(obj.axesHandle, 'Response');
            title(obj.axesHandle,'Area summation curve');
            
        end

        
        function handleEpoch(obj, epoch)
            %load amp data
            response = epoch.getResponse(obj.ampDevice);
            epochResponseTrace = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            currentSpotSize = epoch.parameters('currentSpotSize');
            
            if strcmp(obj.recordingType,'extracellular') %spike recording
                %take (prePts+1:prePts+stimPts)
                epochResponseTrace = epochResponseTrace((sampleRate*obj.preTime/1000)+1:(sampleRate*(obj.preTime + obj.stimTime)/1000));
                %count spikes
                S = spikeDetectorOnline(epochResponseTrace);
                newEpochResponse = length(S.sp); %spike count
            else %intracellular - Vclamp
                epochResponseTrace = epochResponseTrace-mean(epochResponseTrace(1:sampleRate*obj.preTime/1000)); %baseline
                %take (prePts+1:prePts+stimPts)
                epochResponseTrace = epochResponseTrace((sampleRate*obj.preTime/1000)+1:(sampleRate*(obj.preTime + obj.stimTime)/1000));
                %charge transfer
                if strcmp(obj.recordingType,'exc') %measuring exc
                    chargeMult = -1;
                elseif strcmp(obj.recordingType,'inh') %measuring inh
                    chargeMult = 1;
                end
                newEpochResponse = chargeMult*trapz(epochResponseTrace(1:sampleRate*obj.stimTime/1000)); %pA*datapoint
                newEpochResponse = newEpochResponse/sampleRate; %pA*sec = pC
            end
            obj.allSpotSizes = cat(1,obj.allSpotSizes,currentSpotSize);
            obj.allEpochResponses = cat(1,obj.allEpochResponses,newEpochResponse);
            
            obj.summaryData.spotSizes = unique(obj.allSpotSizes);
            obj.summaryData.meanResponses = zeros(size(obj.summaryData.spotSizes));
            for SpotSizeIndex = 1:length(obj.summaryData.spotSizes)
                pullIndices = (obj.summaryData.spotSizes(SpotSizeIndex) == obj.allSpotSizes);
                obj.summaryData.meanResponses(SpotSizeIndex) = mean(obj.allEpochResponses(pullIndices));
            end
            
            if isempty(obj.lineHandle)
                obj.lineHandle = line(obj.summaryData.spotSizes, obj.summaryData.meanResponses,...
                    'Parent', obj.axesHandle,'Color','k','Marker','o');
            else
                set(obj.lineHandle, 'XData', obj.summaryData.spotSizes,...
                    'YData', obj.summaryData.meanResponses);
            end
        end
        
    end
    
    methods (Access = private)
        
        function onSelectedFitGaussian(obj, ~, ~)
            if strcmp(obj.recordingType,'extracellular')
                R0upperBound = Inf;
            else
                R0upperBound = 1e-6; %analog signals already baseline subtracted. Curve goes through [0,0]
            end
            params0 = [0.35,100,0]; % [kC, sigmaC, R0]
            fitRes = fitGaussianRFAreaSummation(obj.summaryData.spotSizes,obj.summaryData.meanResponses,params0,R0upperBound);
            fitX = 0:(1.1*max(obj.summaryData.spotSizes));
            fitY = GaussianRFAreaSummation(fitX,fitRes.Kc,fitRes.sigmaC,fitRes.R0);
            if isempty(obj.fitLineHandle)
                obj.fitLineHandle = line(fitX, fitY, 'Parent', obj.axesHandle);
            else
                set(obj.fitLineHandle, 'XData', fitX,...
                    'YData', fitY);
            end
            set(obj.fitLineHandle,'Color',[1 0 0],'LineWidth',2,'Marker','none');
            str = {['SigmaC = ',num2str(fitRes.sigmaC)]};
            title(obj.axesHandle,str);
            
        end
        
        function onSelectedFitDoG(obj, ~, ~)
             if strcmp(obj.recordingType,'extracellular')
                R0upperBound = Inf;
            else
                R0upperBound = 1e-6; %analog signals already baseline subtracted. Curve goes through [0,0]
            end
            params0 = [0.35,35,0.08,300,0];
            fitRes = fitDoGAreaSummation(obj.summaryData.spotSizes,obj.summaryData.meanResponses,params0,R0upperBound);
            fitX = 0:(1.1*max(obj.summaryData.spotSizes));
            fitY = DoGAreaSummation(fitX,fitRes.Kc,fitRes.sigmaC,fitRes.Ks,fitRes.sigmaS,fitRes.R0);
            if isempty(obj.fitLineHandle)
                obj.fitLineHandle = line(fitX, fitY, 'Parent', obj.axesHandle);
            else
                set(obj.fitLineHandle, 'XData', fitX,...
                    'YData', fitY);
            end
            set(obj.fitLineHandle,'Color',[1 0 0],'LineWidth',2,'Marker','none');
            tempKc = fitRes.Kc / (fitRes.Kc + fitRes.Ks);
            str = {['SigmaC = ',num2str(fitRes.sigmaC)],['sigmaS = ',num2str(fitRes.sigmaS)],...
            ['Kc = ',num2str(tempKc)]};
            title(obj.axesHandle,str);
        end

    end
    
end

