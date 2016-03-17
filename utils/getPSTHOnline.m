function res = getPSTHOnline(spikeTrials,binSize,binaryFlag)
%For online analysis
%spikeTrials is a n * d matrix of cell-attached spike recordings
%    where d=number data points per trial and n is number trials
%binsize (in data points)
% binaryFlag = 1 for input that is a binary string of spike times
% MHT 080814
[n d]=size(spikeTrials);

if binaryFlag %input is binary matrix of spike times
    binarySpikes=spikeTrials;
else
    S=spikeDetectorOnline(spikeTrials);
    
    binarySpikes=zeros(n,d);
    for i=1:size(S.sp,1)
        if (size(S.sp,1)==1)
            trialSpikes=S.sp;
        else
            trialSpikes=S.sp{i};
        end
        binarySpikes(i,trialSpikes)=1;
    end
end

noBins=floor(d/binSize);
binCenters=binSize/2:binSize:noBins*binSize-binSize/2;
binSpikes=zeros(n,noBins);
for j=1:n %for trials
    for i=1:noBins %for bins
        binSpikes(j,i)=sum(binarySpikes(j,(i-1)*binSize+1:i*binSize));
    end
end
spikeSTD=std(binSpikes,1);
spikeSEM=spikeSTD./sqrt(n);

binSpikes=mean(binSpikes,1); %average over trials


res.binCenters = binCenters; %data points
res.spikeCounts = binSpikes; %mean per bin
res.spikeSEM = spikeSEM; %sem per bin
res.spikeSTD = spikeSTD;

end