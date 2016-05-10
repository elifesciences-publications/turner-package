classdef ConfocalWithLightCrafter < edu.washington.riekelab.rigs.Confocal
    
    methods
        
        function obj = ConfocalWithLightCrafter()
            import symphonyui.builtin.devices.*;

            lightCrafter = edu.washington.riekelab.devices.LightCrafterDevice('micronsPerPixel', 1.3);
            obj.addDevice(lightCrafter);
            
            % Binding the lightCrafter to an unused stream only so its configuration settings are written to each epoch.
            daq = obj.daqController;
            lightCrafter.bindStream(daq.getStream('DIGITAL_OUT.1'));
            daq.getStream('DIGITAL_OUT.1').setBitPosition(lightCrafter, 15);
            
            frameMonitor = UnitConvertingDevice('Frame Monitor', 'V').bindStream(obj.daqController.getStream('ANALOG_IN.7'));
            obj.addDevice(frameMonitor);
        end
        
    end
    
end

