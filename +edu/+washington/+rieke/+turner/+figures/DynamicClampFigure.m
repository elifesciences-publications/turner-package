classdef DynamicClampFigure < symphonyui.core.FigureHandler
    
    properties (SetAccess = private)
        ampDevice
        injectedCurrentDevice
        Gexc
        Ginh
    end
    
    properties (Access = private)
        axesHandle
        gExcSweep
        gInhSweep
        ITheorySweep
        IDeliveredSweep
        ExcReversal
        InhReversal
    end
    
    methods
        
        function obj = FrameTimingFigure(ampDevice, conductanceStruct, injectedCurrentDevice, ExcReversal, InhReversal)
            obj.ampDevice = ampDevice;
            obj.Gexc = conductanceStruct.exc;
            obj.Ginh = conductanceStruct.inh;
            obj.injectedCurrentDevice = injectedCurrentDevice;
            obj.ExcReversal = ExcReversal;
            obj.InhReversal = InhReversal;
            
            obj.createUi();
        end
        
        function createUi(obj)
            obj.axesHandle(1) = subplot(2,2,1,...
                'Parent',obj.figureHandle,...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'),...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            xlabel(obj.axesHandle(1), 'Time');
            ylabel(obj.axesHandle(1), 'gExc (nS)');

            obj.axesHandle(2) = subplot(2,2,2,...
                'Parent',obj.figureHandle,...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'),...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            xlabel(obj.axesHandle(2), 'Time');
            ylabel(obj.axesHandle(2), 'gInh (nS)');
            
            obj.axesHandle(3) = subplot(2,2,3:4,...
                'Parent',obj.figureHandle,...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'),...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'), ...
                'XTickMode', 'auto');
            xlabel(obj.axesHandle(2), 'Time');
            ylabel(obj.axesHandle(2), 'I (pA)');
        end

        
        function handleEpoch(obj, epoch)
            %load amp data
            ampData = epoch.getResponse(obj.ampDevice);
            Vtrace = ampData.getData(); %mV
            currentData = epoch.getResponse(obj.injectedCurrentDevice);
            Itrace = currentData.getData();
            sampleRate = ampData.sampleRate.quantityInBaseUnits;
            tVec = (0:length(Vtrace)-1) ./ sampleRate;

            %plot conductances delivered this trial
            if isempty(obj.gExcSweep)
                obj.gExcSweep = line(tVec, obj.Gexc, 'Parent', obj.axesHandle(1));
            else
                set(obj.gExcSweep, 'XData', tVec, 'YData', obj.Gexc);
            end
            set(obj.gExcSweep, 'Color', 'b');
            
            if isempty(obj.gInhSweep)
                obj.gInhSweep = line(tVec, obj.Ginh, 'Parent', obj.axesHandle(2));
            else
                set(obj.gInhSweep, 'XData', tVec, 'YData', obj.Ginh);
            end
            set(obj.gInhSweep, 'Color', 'r');
            
            %plot delivered current
            % map input (V) to actual current value (I)
            % 10V ADC in = 20 nA current, i.e. 2 nA/V command gain on MCC
            % Also sign inversion to match physiological convention
            % multiclamp convention is positive = inward current
            Itrace_delivered = -Itrace.*2000; %pA
            if isempty(obj.IDeliveredSweep)
                obj.IDeliveredSweep = line(tVec, Itrace_delivered, 'Parent', obj.axesHandle(3));
            else
                set(obj.IDeliveredSweep, 'XData', tVec, 'YData', Itrace_delivered);
            end
            set(obj.IDeliveredSweep, 'Color', 'k');
            
            %plot calculated instantaneous current
            Itheory = obj.Gexc .*(Vtrace - obj.ExcReversal) + ...
                obj.Ginh .*(Vtrace - obj.InhReversal); %pA
            if isempty(obj.ITheorySweep)
                obj.ITheorySweep = line(tVec, Itheory, 'Parent', obj.axesHandle(3));
            else
                set(obj.ITheorySweep, 'XData', tVec, 'YData', Itheory);
            end
            set(obj.ITheorySweep, 'Color','g')

        end
        
    end
    
end

