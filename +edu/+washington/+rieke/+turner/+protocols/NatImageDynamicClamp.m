classdef NatImageDynamicClamp < edu.washington.rieke.protocols.RiekeProtocol
    
    properties
        gExcMultiplier = 1
        gInhMultiplier = 1
        ConductanceSet = 'ONparasol_20160112Ec1'
        ExcConductance = 'Image' %Constant, overridden by interleaves below
        InhConductance = 'Image' %Constant, overridden by interleaves below
        InterleaveImage = false; %{image-image / disc-disc / image-disc / disc-image}
        InterleaveTonic = false; %{image-image / image-tonic / tonic-image}
        ExcReversal = 10;
        InhReversal = -70;
        
        amp                             % Input amplifier
        numberOfAverages = uint16(5)    % Number of epochs
        interpulseInterval = 0          % Duration between pulses (s)
    end
    
    properties (Hidden)
        ampType
        ConductanceSetType = symphonyui.core.PropertyType('char', 'row',...
            {'ONparasol_20160112Ec1','ONparasol_20160112Ec3','ONparasol_20160324Ec2',...
            'OFFparasol_20160112Ec2','OFFparasol_20160324Ec4'})
        ExcConductanceType = symphonyui.core.PropertyType('char', 'row', {'Image', 'Disc', 'Tonic'})
        InhConductanceType = symphonyui.core.PropertyType('char', 'row', {'Image', 'Disc', 'Tonic'})
        
        stimSequence %struct with fields .exc and .inh (vals cell array of strings, image, disc, or tonic)
        imageSequence %image ids
        currentImageIndex
        
        currentConductanceStim %struct with fields .exc and .inh (vals str: image, disc, or tonic)
        currentConductanceTrial %struct with fields .exc and .inh (vals int)
        currentConductanceTrace %struct with fields .exc and .inh; before mapped for arduino (still in nS)
    end
    
    properties (Hidden, Transient)
        analysisFigure
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.rieke.protocols.RiekeProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
%         function p = getPreview(obj, panel)
%             p = symphonyui.builtin.previews.StimuliPreview(panel, @()createPreviewStimuli(obj));
%             function s = createPreviewStimuli(obj)
%                 s = cell(1, 2);
%                 s{1} = obj.createConductanceStimulus('exc');
%                 s{2} = obj.createConductanceStimulus('inh');
%             end
%         end
        
        function prepareRun(obj)
            prepareRun@edu.washington.rieke.protocols.RiekeProtocol(obj);
            
            resourcesDir = 'C:\Users\Max Turner\Documents\GitHub\Turner-protocols\resources\gClampStims\NIFgClampTraces\';
            fileID = [obj.ConductanceSet,'.mat'];
            load(fullfile(resourcesDir, fileID));   
            obj.imageSequence = res.imageIndex;
            
            %create conductance label sequence
            if obj.InterleaveImage
                %will cycle through to apply to both sequences
                %to get all the appropriate pairings
                obj.stimSequence.exc = {'Image', 'Image', 'Disc', 'Disc'};
                obj.stimSequence.inh = {'Image', 'Disc','Image','Disc'};
            elseif obj.InterleaveTonic
               obj.stimSequence.exc = {'Image', 'Tonic', 'Image'};
               obj.stimSequence.inh = {'Image', 'Image', 'Tonic'};
            else
                obj.stimSequence.exc = {obj.ExcConductance};
                obj.stimSequence.inh = {obj.InhConductance};
            end

            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('symphonyui.builtin.figures.MeanResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('symphonyui.builtin.figures.ResponseStatisticsFigure', obj.rig.getDevice(obj.amp), {@mean, @var}, ...
                'baselineRegion', [0 obj.preTime], ...
                'measurementRegion', [obj.preTime obj.preTime+obj.stimTime]);
            obj.showFigure('edu.washington.rieke.turner.figures.DynamicClampFigure',...
                obj.rig.getDevice(obj.amp), obj.currentConductanceTrace, obj.rig.getDevice('Injected current'),...
                obj.ExcReversal, obj.InhReversal);
        end
        
        function stim = createConductanceStimulus(obj,conductance)
            %conductance is string: 'exc' or 'inh'
            resourcesDir = 'C:\Users\Max Turner\Documents\GitHub\Turner-protocols\resources\gClampStims\NIFgClampTraces\';
            fileID = [obj.ConductanceSet,'.mat'];
            load(fullfile(resourcesDir, fileID));   
            gen = symphonyui.builtin.stimuli.WaveformGenerator();
            gen.sampleRate = obj.sampleRate;
            gen.units = 'V';
            if strcmp(obj.currentConductanceStim.(conductance),'Image')
                obj.currentConductanceTrial.(conductance) = ...
                    randsample(1:size(res.(conductance).image{obj.currentImageIndex},1),1);
                newConductanceTrace = res.(conductance).image{obj.currentImageIndex}(obj.currentConductanceTrial.(conductance),:);
            elseif strcmp(obj.currentConductanceStim.(conductance),'Disc')
                obj.currentConductanceTrial.(conductance) = ...
                    randsample(1:size(res.(conductance).disc{obj.currentImageIndex},1),1);
                newConductanceTrace = res.(conductance).disc{obj.currentImageIndex}(obj.currentConductanceTrial.(conductance),:);
            elseif strcmp(obj.currentConductanceStim.(conductance),'Tonic')
                obj.currentConductanceTrial.(conductance) = ...
                    randsample(1:size(res.(conductance).image{obj.currentImageIndex},1),1);
                temp = res.(conductance).image{obj.currentImageIndex}(obj.currentConductanceTrial.(conductance),:);
                newConductanceTrace = mean(temp(1:res.stimStart)) .* ones(size(temp));
            end
            obj.currentConductanceTrace.(conductance) = newConductanceTrace; %nS, for display

            %map conductance (nS) to DAC output (V) to match expectation of
            %Arduino...
            % 200 nS = 10 V, 1 nS = 0.05 V
            mappedConductanceTrace = newConductanceTrace .* 0.05;
            if any(mappedConductanceTrace > 10)
                mappedConductanceTrace = zeros(1,length(mappedConductanceTrace));
                error(['G_',conductance, ': voltage command out of range!'])
            end
            gen.waveshape = mappedConductanceTrace;
            stim = gen.generate();
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.rieke.protocols.RiekeProtocol(obj, epoch);
            
            %get image from sequence
            tempIndex = floor(obj.numEpochsCompleted / length(obj.stimSequence.exc));
            drawIndex = mod(tempIndex, length(obj.imageSequence)) + 1;
            % Randomize the image sequence order at the beginning of each image sequence
            if drawIndex == 1
                obj.imageSequence = randsample(obj.imageSequence, length(obj.imageSequence));
            end
            obj.currentImageIndex = obj.imageSequence(drawIndex);
            
            % get conductance stim from sequence
            drawIndex = mod(obj.numEpochsCompleted,length(obj.stimSequence.exc)) + 1;
            obj.currentConductanceStim.exc = obj.stimSequence.exc{drawIndex};
            obj.currentConductanceStim.inh = obj.stimSequence.inh{drawIndex};
            
            epoch.addStimulus(obj.rig.getDevice('Excitatory conductance'), obj.createConductanceStimulus('exc'));
            epoch.addStimulus(obj.rig.getDevice('Inhibitory conductance'), obj.createConductanceStimulus('inh'));
            epoch.addResponse(obj.rig.getDevice(obj.amp));
            epoch.addResponse(obj.rig.getDevice('Injected current'));
            
            epoch.addParameter('currentGexcStim', obj.currentConductanceStim.exc);
            epoch.addParameter('currentGinhStim', obj.currentConductanceStim.inh);
            
            epoch.addParameter('currentGexcTrial', obj.currentConductanceTrial.exc);
            epoch.addParameter('currentGinhTrial', obj.currentConductanceTrial.inh);
            epoch.addParameter('currentImageIndex', obj.currentImageIndex);
        end
        
        function prepareInterval(obj, interval)
            prepareInterval@edu.washington.rieke.protocols.RiekeProtocol(obj, interval);
            
            device = obj.rig.getDevice(obj.amp);
            interval.addDirectCurrentStimulus(device, device.background, obj.interpulseInterval, obj.sampleRate);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
    end
    
end

