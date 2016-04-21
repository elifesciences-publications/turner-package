classdef ConfocalWithLightCrafter < edu.washington.riekelab.rigs.Confocal
    
    methods
        
        function obj = ConfocalWithLightCrafter()
            import symphonyui.builtin.devices.*;
            
            lightCrafter = edu.washington.riekelab.devices.LightCrafterDevice();
            lightCrafter.addConfigurationSetting('micronsPerPixel', 1.3, 'isReadOnly', true);
            obj.addDevice(lightCrafter);
            
            frameMonitor = UnitConvertingDevice('Frame Monitor', 'V').bindStream(obj.daqController.getStream('ANALOG_IN.7'));
            obj.addDevice(frameMonitor);
        end
        
    end
    
end

