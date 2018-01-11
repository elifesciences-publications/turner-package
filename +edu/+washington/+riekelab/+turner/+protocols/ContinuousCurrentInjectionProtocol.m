classdef ContinuousCurrentInjectionProtocol < edu.washington.riekelab.protocols.RiekeLabProtocol

    properties
        amp                             % Output amplifier
        stimTime = 1000;                % (msec)
        waveFrequency = 10              % (Hz)
        waveMean = 0                   % Pulse mean / background (mV or pA depending on amp mode)
        waveAmplitude = 100              % Pulse amplitude (mV or pA depending on amp mode)
        numberOfAverages = uint16(5)    % Number of epochs
    end

    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end
    
    properties (Hidden)
        ampType
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
                gen = symphonyui.builtin.stimuli.SquareGenerator(obj.createAmpStimulus().parameters);
                s = gen.generate();
            end
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
        end
        
        function stim = createAmpStimulus(obj)
            gen = symphonyui.builtin.stimuli.SquareGenerator();
            
            gen.period = (1/obj.waveFrequency) * 1e3; %msec
            gen.stimTime = obj.stimTime;
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
            device.background = symphonyui.core.Measurement(obj.waveMean, device.background.displayUnits);
            epoch.addResponse(obj.rig.getDevice(obj.amp));
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
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

