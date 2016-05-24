function res = fitDoGAreaSummation(spotSizes,responses,params0,R0upperBound)
    %params = [Kc,sigmaC,Ks,sigmaS,R0]

    LB = [0, 0, 0, 0, 0]; UB = [Inf Inf Inf Inf R0upperBound];
    fitOptions = optimset('MaxIter',2000,'MaxFunEvals',600*length(LB));
    
    fitfunc = @(params0,spotSizes) DoGAreaSummation(spotSizes,params0(1),params0(2),params0(3),params0(4),params0(5));
    [params, resnorm, residual]=lsqcurvefit(fitfunc,params0,spotSizes,responses,LB,UB,fitOptions);
    
    
    predResp = DoGAreaSummation(spotSizes,params(1),params(2),params(3),params(4),params(5));
    ssErr=sum((responses-predResp).^2); %sum of squares of residual
    ssTot=sum((responses-mean(responses)).^2); %total sum of squares
    rSquared=1-ssErr/ssTot; %coefficient of determination
    
    res.Kc = params(1);
    res.sigmaC = params(2);
    res.Ks = params(3);
    res.sigmaS = params(4);
    res.R0 = params(5);
    res.rSquared=rSquared;
end
