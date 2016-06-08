classdef LinearFilterFigure < symphonyui.core.FigureHandler
    
    properties (SetAccess = private)
        ampDevice
        recordingType
        preTime
        stimTime
        frameDwell
    end
    
    properties (Access = private)
        axesHandle
        lineHandle
        lnDataHandle
        noiseStream
        allStimuli
        allResponses
        newFilter
    end
    
    methods
        
        function obj = LinearFilterFigure(ampDevice, varargin)
            obj.ampDevice = ampDevice;            
            ip = inputParser();
            ip.addParameter('recordingType', [], @(x)ischar(x));
            ip.addParameter('preTime', [], @(x)isvector(x));
            ip.addParameter('stimTime', [], @(x)isvector(x));
            ip.addParameter('frameDwell', [], @(x)isvector(x));
            ip.parse(varargin{:});
            
            obj.recordingType = ip.Results.recordingType;
            obj.preTime = ip.Results.preTime;
            obj.stimTime = ip.Results.stimTime;
            obj.frameDwell = ip.Results.frameDwell;
            
            obj.allStimuli = [];
            obj.allResponses = [];
            obj.createUi();
        end
        
        function createUi(obj)
            import appbox.*;
            iconDir = [fileparts(fileparts(mfilename('fullpath'))), '\+utils\+icons\'];
            toolbar = findall(obj.figureHandle, 'Type', 'uitoolbar');
            fitGaussianButton = uipushtool( ...
                'Parent', toolbar, ...
                'TooltipString', 'Fit nonlinearity', ...
                'Separator', 'on', ...
                'ClickedCallback', @obj.onSelectedFitLN);
            setIconImage(fitGaussianButton, [iconDir, 'Gaussian.png']);

            obj.axesHandle(1) = subplot(2,1,1,...
                'Parent',obj.figureHandle,...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'),...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            xlabel(obj.axesHandle(1), 'Time (ms)');
            ylabel(obj.axesHandle(1), 'Amp.');
            title(obj.axesHandle(1),'Linear filter');
            
            obj.axesHandle(2) = subplot(2,1,2,...
                'Parent',obj.figureHandle,...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'),...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            xlabel(obj.axesHandle(2), 'Linear prediction');
            ylabel(obj.axesHandle(2), 'Measured');
            title(obj.axesHandle(2),'Nonlinearity');
        end

        
        function handleEpoch(obj, epoch)
            %load amp data
            response = epoch.getResponse(obj.ampDevice);
            epochResponseTrace = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            prePts = sampleRate*obj.preTime/1000;
            stimPts = sampleRate*obj.stimTime/1000;
            if strcmp(obj.recordingType,'extracellular') %spike recording
                %take (prePts+1:prePts+stimPts)
                epochResponseTrace = epochResponseTrace((prePts + 1):(prePts+stimPts));
                newResponse = zeros(size(epochResponseTrace));
                %count spikes
                S = edu.washington.riekelab.turner.utils.spikeDetectorOnline(epochResponseTrace);
                newResponse(S.sp) = 1;
            else %intracellular - Vclamp
                epochResponseTrace = epochResponseTrace-mean(epochResponseTrace(1:prePts)); %baseline
                %take (prePts+1:prePts+stimPts)
                epochResponseTrace = epochResponseTrace((prePts + 1):(prePts+stimPts));
                if strcmp(obj.recordingType,'exc') %measuring exc
                    polarity = -1;
                elseif strcmp(obj.recordingType,'inh') %measuring inh
                    polarity = 1;
                end
                newResponse = polarity * epochResponseTrace;
            end
            
            %reconstruct noise stimulus
            filterLen = 800; %msec, length of linear filter to compute
            %fraction of noise update rate at which to cut off filter spectrum
            freqCutoffFraction = 1;
            frameRate = 60;
            
            currentNoiseSeed = epoch.parameters('noiseSeed');
            %reconstruct stimulus trajectories...
            stimFrames = round(frameRate * (obj.stimTime/1e3));
            noise = zeros(1,floor(stimFrames/obj.frameDwell));
            response = zeros(1, floor(stimFrames/obj.frameDwell));
            %reset random stream to recover stim trajectories
            obj.noiseStream = RandStream('mt19937ar', 'Seed', currentNoiseSeed);
            % stim trajectories in frame updates
            chunkLen = length(newResponse) / floor(stimFrames/obj.frameDwell);
            for ii = 1:floor(stimFrames/obj.frameDwell)
                noise(ii) = obj.noiseStream.randn;
                response(ii) = mean(newResponse(round((ii-1)*chunkLen + 1) : round(ii*chunkLen)));
            end
            obj.allStimuli = cat(1,obj.allStimuli,noise);
            obj.allResponses = cat(1,obj.allResponses,response);
            
            updateRate = (frameRate/obj.frameDwell); %hz
            obj.newFilter = edu.washington.riekelab.turner.utils.getLinearFilterOnline(obj.allStimuli,obj.allResponses,...
                updateRate, freqCutoffFraction*updateRate);

            filterPts = (filterLen/1000)*updateRate;
            filterTimes = linspace(0,filterLen,filterPts); %msec
            
            obj.newFilter = obj.newFilter(1:filterPts);
            if isempty(obj.lineHandle)
                obj.lineHandle = line(filterTimes, obj.newFilter,...
                    'Parent', obj.axesHandle(1),'LineWidth',2);
                ht = line([filterTimes(1) filterTimes(end)],[0 0],...
                    'Parent', obj.axesHandle(1),'Color','k',...
                    'Marker','none','LineStyle','--');
            else
                set(obj.lineHandle, 'YData', obj.newFilter);
            end
        end
        
    end
    
    methods (Access = private)
        
        function onSelectedFitLN(obj, ~, ~)
            measuredResponse = reshape(obj.allResponses,1,numel(obj.allResponses));
            stimulusArray = reshape(obj.allStimuli,1,numel(obj.allStimuli));
            linearPrediction = conv(stimulusArray,obj.newFilter);
            linearPrediction = linearPrediction(1:length(stimulusArray));
            if isempty(obj.lnDataHandle)
                obj.lnDataHandle = line(linearPrediction, measuredResponse,...
                    'Parent', obj.axesHandle(2),'LineStyle','none','Marker','.');
                limDown = min([linearPrediction measuredResponse]);
                limUp = max([linearPrediction measuredResponse]);
                
                ht = line([limDown limUp],[limDown limUp],...
                    'Parent', obj.axesHandle(2),'Color','k',...
                    'Marker','none','LineStyle','--');
            else
                set(obj.lnDataHandle, 'YData', measuredResponse,...
                    'XData', linearPrediction);
            end
            
        end
    end

end

