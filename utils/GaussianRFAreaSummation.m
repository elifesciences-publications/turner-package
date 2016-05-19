function res = GaussianRFAreaSummation(spotSizes,Kc,sigmaC,R0)
res = zeros(size(spotSizes));
for jj = 1:length(spotSizes);
sSize = spotSizes(jj);
ss = -sSize/2 : sSize/2; %spot axis
wt = Kc*exp(-(ss./(2*sigmaC)).^2); %weight at each location

res(jj) = R0 + trapz(wt); %integrate to get DoG response

end