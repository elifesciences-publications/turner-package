function res = GaussianRFAreaSummation(spotSizes,Kc,sigmaC,R0)
res = zeros(size(spotSizes));
stimSize = round(max(spotSizes));

RFCenter = Kc * fspecial('gaussian',stimSize,sigmaC);

[rr, cc] = meshgrid(1:stimSize,1:stimSize);
for ss = 1:length(spotSizes)
    currentStimulus = sqrt((rr-round(stimSize/2)).^2+(cc-round(stimSize/2)).^2)<spotSizes(ss)/2;
    res(ss) = R0 + sum(sum(currentStimulus .* RFCenter));
end

