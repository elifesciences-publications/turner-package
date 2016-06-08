classdef SingleSpot < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   % Spot leading duration (ms)
        stimTime = 250                 % Spot duration (ms)
        tailTime = 250                  % Spot trailing duration (ms)
        spotIntensity = 1.0             % Spot light intensity (0-1)
        spotDiameter = 300              % Spot diameter size (um)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0, 0]           % Spot [x, y] center offset (um)
        onlineAnalysis = 'none'
        numberOfAverages = uint16(1)    % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function p = getPreview(obj, panel)
            if isempty(obj.rig.getDevices('Stage'))
                p = [];
                return;
            end
            p = io.github.stage_vss.previews.StagePreview(panel, @()obj.createPresentation(), ...
                'windowSize', obj.rig.getDevice('Stage').getCanvasSize());
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.turner.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis);
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
        end
        
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            
            spotDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.spotDiameter);
            centerOffsetPix = obj.rig.getDevice('Stage').um2pix(obj.centerOffset);
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            spot = stage.builtin.stimuli.Ellipse();
            spot.color = obj.spotIntensity;
            spot.radiusX = spotDiameterPix/2;
            spot.radiusY = spotDiameterPix/2;
            spot.position = canvasSize/2 + centerOffsetPix;
            p.addStimulus(spot);
            
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
        end
        
        %same presentation each epoch in a run. Replay.
        function controllerDidStartHardware(obj)
            controllerDidStartHardware@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            if (obj.numEpochsCompleted >= 1) && (obj.numEpochsCompleted < obj.numberOfAverages)
                obj.rig.getDevice('Stage').replay
            else
                obj.rig.getDevice('Stage').play(obj.createPresentation());
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

