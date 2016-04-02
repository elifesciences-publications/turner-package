classdef MeanResponseFigure < symphonyui.core.FigureHandler
    
    properties (SetAccess = private)
        device
        groupBy
        sweepColor
        recordingType
    end
    
    properties (Access = private)
        axesHandle
        sweeps
    end
    
    methods
        
        function obj = MeanResponseFigure(device, varargin)
            co = get(groot, 'defaultAxesColorOrder');
            
            ip = inputParser();
            ip.addParameter('groupBy', [], @(x)iscellstr(x));
            ip.addParameter('sweepColor', co(1,:), @(x)ischar(x) || isvector(x));
            ip.addParameter('recordingType', [], @(x)ischar(x));
            ip.parse(varargin{:});
            
            obj.device = device;
            obj.groupBy = ip.Results.groupBy;
            obj.sweepColor = ip.Results.sweepColor;
            obj.recordingType = ip.Results.recordingType;
            
            obj.createUi();
        end
        
        function createUi(obj)
            obj.axesHandle = axes( ...
                'Parent', obj.figureHandle, ...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'), ...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            xlabel(obj.axesHandle, 'sec');
            obj.sweeps = {};
            
            obj.setTitle([obj.device.name ' Mean Response']);
        end
        
        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t);
            title(obj.axesHandle, t);
        end
        
        function clear(obj)
            cla(obj.axesHandle);
            obj.sweeps = {};
        end
        
        function handleEpoch(obj, epoch)
            if ~epoch.hasResponse(obj.device)
                error(['Epoch does not contain a response for ' obj.device.name]);
            end
            
            response = epoch.getResponse(obj.device);
            [quantities, units] = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            if numel(quantities) > 0
                x = (1:numel(quantities)) / sampleRate;
                y = quantities;
                
                if strcmp(obj.recordingType,'extracellular')
                    filterSigma = (15/1000)*sampleRate; %15 msec -> dataPts
                    newFilt = normpdf(1:10*filterSigma,10*filterSigma/2,filterSigma);
                    res = spikeDetectorOnline(y,[],sampleRate);
                    y = zeros(size(y));
                    y(res.sp) = 1; %spike binary
                    y = sampleRate*conv(y,newFilt,'same'); %inst firing rate, Hz
                end
                
            else
                x = [];
                y = [];
            end
            
            p = epoch.parameters;
            if isempty(obj.groupBy) && isnumeric(obj.groupBy)
                parameters = p;
            else
                parameters = containers.Map();
                for i = 1:length(obj.groupBy)
                    key = obj.groupBy{i};
                    parameters(key) = p(key);
                end
            end
            
            if isempty(parameters)
                t = 'All epochs grouped together';
            else
                t = ['Grouped by ' strjoin(parameters.keys, ', ')];
            end
            obj.setTitle([obj.device.name ' Mean Response (' t ')']);
            
            sweepIndex = [];
            for i = 1:numel(obj.sweeps)
                if isequal(obj.sweeps{i}.parameters, parameters)
                    sweepIndex = i;
                    break;
                end
            end
            
            if isempty(sweepIndex)
                sweep.line = line(x, y, 'Parent', obj.axesHandle, 'Color', obj.sweepColor);
                sweep.parameters = parameters;
                sweep.count = 1;
                obj.sweeps{end + 1} = sweep;
            else
                sweep = obj.sweeps{sweepIndex};
                cy = get(sweep.line, 'YData');
                set(sweep.line, 'YData', (cy * sweep.count + y) / (sweep.count + 1));
                sweep.count = sweep.count + 1;
                obj.sweeps{sweepIndex} = sweep;
            end
            
            ylabel(obj.axesHandle, units, 'Interpreter', 'none');
        end
        
    end
        
end

