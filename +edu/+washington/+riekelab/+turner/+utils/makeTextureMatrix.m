function mat = makeTextureMatrix(textureSize, sigma, randSeed, meanIntensity,contrast)
% set random seed
stream = RandStream('mt19937ar','Seed',randSeed);
mat = double(rand(stream, [textureSize,textureSize]));
% make gaussian filter
h = fspecial('gaussian',6*sigma,sigma);
h = h ./ sum(h(:)); % normalize
mat = imfilter(mat,h,'replicate');

% make histogram of pixel values uniform
% From Schwartz lab
bins = [-Inf prctile(mat(:),1:1:100)];
m_orig = mat;
for bb=1:length(bins)-1
    mat(m_orig>bins(bb) & m_orig<=bins(bb+1)) = bb*(1/(length(bins)-1));
end
% scale to [0 1]
mat = mat - min(mat(:));
mat = 2* meanIntensity .* (mat ./ max(mat(:)));
% scale by contrast
mat = (mat - meanIntensity).*contrast + meanIntensity;
end