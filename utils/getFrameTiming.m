function [frameTimes, frameRate] = getFrameTiming(frameMonitor,lcrFlag)
    %frameTimes in data points
    %frameRate, mean over all flips, is frames/dataPoint
    %MHT 3/31/16 ported over to symphony 2.0 and split lcr from oled
    
    %shift & scale s.t. fr monitor lives on [0,1]
    frameMonitor = frameMonitor - min(frameMonitor);
    frameMonitor = frameMonitor./max(frameMonitor);
    
    ups = getThresCross(frameMonitor,0.5,1);
    downs = getThresCross(frameMonitor,0.5,-1);
    frameRate = 2/mean(diff(ups)); % 2 because ups are every two frames...
    
    if (lcrFlag == 1) %very fast, so frame times are clear directly from trace
       ups = [1 ups]; %first upswing missed
       timesOdd = ups;
       timesEven = downs;
       frameTimes = round(sort([timesOdd'; timesEven']));
       
    else %OLED monitor, slower
        %odd number of frames, just chop off last time who cares...
        len = min([length(ups),length(downs)]);
        ups = ups(1:len); downs = downs(1:len);
        %more stable threshold cross at 0.5, but call flip time approximately
        %at inflection points...
        timesOdd = ups - (downs-ups)/2; timesOdd(1) = 0;
        timesEven = downs - (downs-ups)/2;
        frameTimes = round(sort([timesOdd'; timesEven']));
    end
    
    
    
    
end