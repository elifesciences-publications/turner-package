classdef ContinuousCurrentInjectionProtocol < edu.washington.riekelab.protocols.RiekeLabProtocol
    % Presents a set of infinitely repeating rectangular pulse stimuli to a specified amplifier. This protocol records
    % and displays no responses. Instead it assumes you have an oscilloscope attached to your rig with which you can
    % view the amplifier response.
    
    properties
        amp                             % Output amplifier
        waveFrequency = 10              % (Hz)
        waveMean = 0                   % Pulse mean / background (mV or pA depending on amp mode)
        waveAmplitude = 5              % Pulse amplitude (mV or pA depending on amp mode)
    end

    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end
    
    properties (Hidden)
        ampType
        modeType = symphonyui.core.PropertyType('char', 'row', {'seal', 'leak'})
        modeFigure
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function d = getPropertyDescriptor(obj, name)
            d = getPropertyDescriptor@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, name);
            
            if strncmp(name, 'amp2', 4) && numel(obj.rig.getDeviceNames('Amp')) < 2
                d.isHidden = true;
            end
        end
        
        function p = getPreview(obj, panel)
            p = symphonyui.builtin.previews.StimuliPreview(panel, @()createPreviewStimuli(obj));
            function s = createPreviewStimuli(obj)
                gen = symphonyui.builtin.stimuli.PulseGenerator(obj.createAmpStimulus().parameters);
                s = gen.generate();
            end
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            if isempty(obj.modeFigure) || ~isvalid(obj.modeFigure)
                obj.modeFigure = obj.showFigure('symphonyui.builtin.figures.CustomFigure', @null);
                f = obj.modeFigure.getFigureHandle();
                set(f, 'Name', 'Mode');
                layout = uix.VBox('Parent', f);
                uix.Empty('Parent', layout);
                obj.modeFigure.userData.text = uicontrol( ...
                    'Parent', layout, ...
                    'Style', 'text', ...
                    'FontSize', 24, ...
                    'HorizontalAlignment', 'center', ...
                    'String', '');
                uix.Empty('Parent', layout);
                set(layout, 'Height', [-1 42 -1]);
            end
            
            if isvalid(obj.modeFigure)
                set(obj.modeFigure.userData.text, 'String', [obj.mode ' running...']);
            end
        end
        
        function stim = createAmpStimulus(obj)
            gen = symphonyui.builtin.stimuli.SquareGenerator();
            
            gen.period = (1/obj.waveFrequency) * 1e3; %msec
            gen.stimTime = 1.5*gen.period; %1.5 periods
            gen.preTime = 0;
            gen.tailTime = 0;
            
            gen.amplitude = obj.waveAmplitude;
            gen.mean = obj.waveMean;
            gen.sampleRate = obj.sampleRate;
            gen.units = obj.rig.getDevice(obj.amp).background.displayUnits;
            
            stim = gen.generate();
        end
        
      
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, epoch);
            
            devices = obj.rig.getInputDevices();
            for i = 1:numel(devices)
                if epoch.hasResponse(devices{i})
                    epoch.removeResponse(devices{i});
                end
            end
            
            epoch.addStimulus(obj.rig.getDevice(obj.amp), obj.createAmpStimulus());

            device = obj.rig.getDevice(obj.amp);
            device.background = symphonyui.core.Measurement(obj.ampHoldSignal, device.background.displayUnits);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < 1;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < 1;
        end
        
        function completeRun(obj)
            completeRun@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
        end
        
        function a = get.amp2(obj)
            amps = obj.rig.getDeviceNames('Amp');
            if numel(amps) < 2
                a = '(None)';
            else
                i = find(~ismember(amps, obj.amp), 1);
                a = amps{i};
            end
        end
        
    end
    
end

