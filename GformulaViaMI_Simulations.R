#simulation code for paper 'G-formula for causal inference via multiple imputation'

expit <- function(x) exp(x)/(1+exp(x))

library(mice)
library(gFormulaMI)

#define a function which performs univariate approximate Bayesian bootstrap imputation
#code follows mice.impute.sample with required modification
mice.impute.uniABB <- function(y,ry,x = NULL, wy = NULL, ...) {
  if (is.null(wy)) {
    wy <- !ry
  }
  yry <- y[ry]
  
  #n=number of observed values
  n <- sum(ry)
  #draw of probability values
  unifDraws <- sort(runif(n-1))
  probDraw <- c(unifDraws,1) - c(0,unifDraws)
  #draw sample and return
  sample(x=yry,size=sum(wy),replace=TRUE,prob=probDraw)
}

#function to perform gformula via MI, increasing M or nSyn if necessary to get a positive variance estimate
gformulaViaMI <- function(obsData, M=100,nSynMultiplier=1,increaseM=TRUE,
                          l0ABB=FALSE,missingData,maxit=5) {
  
  n <- nrow(obsData)
  
  if (l0ABB==TRUE) {
    #use approximate Bayesian bootstrap for L0 imputation
    methodVal <- c("uniABB",rep("norm",ncol(obsData)-1))
  } else {
    methodVal <- c(rep("norm",ncol(obsData)))
  }
  
  #we repeat until variance estimate is positive
  #save seed so we can restore if we have to increase number of imps or nSyn
  startSeed <- .Random.seed
  
  if (increaseM==TRUE) {
    currentM <- 0
    currentnSyn <- n*nSynMultiplier
  } else {
    #increase nSyn
    currentM <- M
    currentnSyn <- 0
  }
  
  miVarEst <- 0
  
  while(miVarEst<=0) {
    
    .Random.seed <- startSeed
    
    if (increaseM==TRUE) {
      #add an additional M imputations to what was used previously
      currentM <- currentM + M
    } else {
      #increase nSyn / nSim
      currentnSyn <- currentnSyn + n*nSynMultiplier
    }

    if (missingData==TRUE) {
      #use mice to impute missing data
      intermediateImps <- mice(obsData, m=currentM, defaultMethod = c("norm", "logreg", "polyreg", "polr"),
                               printFlag = FALSE, maxit=maxit)
    } else {
      #if no missing data, set this object to the observed data
      intermediateImps <- obsData
    }

    #perform G-formula imputation
    imps <- gFormulaImpute(intermediateImps,M=currentM,nSim=currentnSyn,
                             trtVars=c("a0","a1","a2"),
                             trtRegimes=list(c(0,0,0),c(1,1,1)),
                             method=methodVal, silent=TRUE)
    
    #analyse imputed datasets
    fits <- with(imps, lm(y~factor(regime)))
    try({pooled <- syntheticPool(fits)})
    if (exists("pooled")==TRUE) {
      miVarEst <- pooled[2,4]
    } else {
      miVarEst <- 0
    }
  }
    
  list(miEst=pooled[2,1],miVarEst=pooled[2,4],M=currentM,nSyn=currentnSyn,
       Bhat=pooled[2,3],Vhat=pooled[2,2])
}

#function to perform gformula using gfoRmula
gfoRmulaRun <- function(obsData, nsimul=NULL) {
  
  #first need to reshape to long format
  longData <- reshape(obsData, direction="long", varying=list(c("a0","a1","a2"),
                                                              c("l0","l1","l2")),
                      v.names=c("a","l"),
                      timevar="time",
                      times=c(0,1,2))
  longData <- longData[order(longData$id,longData$t),]
  #set y to missing at times 0 and 1
  longData$y[longData$t<2] <- NA
  
  id <- 'id'
  time_name <- 'time'
  covnames <- c('l', 'a')
  outcome_name <- 'y'
  covtypes <- c('normal', 'binary')
  histories <- c(lagged)
  histvars <- list(c('a', 'l'))
  covparams <- list(covmodels = c(l ~ lag1_a + lag1_l + lag2_a + lag2_l + factor(time),
                                  a ~ lag1_a + lag1_l + lag2_a + lag2_l + factor(time)))
  ymodel <- y ~ a + lag1_a + lag2_a + l + lag1_l + lag2_l
  intvars <- list('a', 'a')
  interventions <- list(list(c(static, rep(0, 3))),
                        list(c(static, rep(1, 3))))
  int_descript <- c('Never treat', 'Always treat')
  
  #save seed so we can restore random number state afterwards
  startSeed <- .Random.seed
  gform_cont_eof <- gformula_continuous_eof(obs_data = longData,
                                            id = id,
                                            time_name = time_name,
                                            covnames = covnames,
                                            outcome_name = outcome_name,
                                            covtypes = covtypes,
                                            covparams = covparams, ymodel = ymodel,
                                            intvars = intvars,
                                            interventions = interventions,
                                            int_descript = int_descript,
                                            histories = histories, histvars = histvars,
                                            nsimul = nsimul,
                                            seed=sample.int(2^30, size = 1),
                                            model_fits=TRUE)
  .Random.seed <- startSeed
  
  list(gfoRmulaEst = gform_cont_eof$result[3,4]-gform_cont_eof$result[2,4])
}

simData <- function(n, missingData=FALSE, missingProp=0.5) {
  
  #simulate data
  l0 <- rnorm(n)
  a0 <- 1*(runif(n)<expit(l0))
  l1 <- l0+a0+rnorm(n)
  a1 <- 1*(runif(n)<expit(l1+a0))
  l2 <- l1+a1+rnorm(n)
  a2 <- 1*(runif(n)<expit(l2+a1))
  y <- l2+a2+rnorm(n)
  
  obsData <- data.frame(l0=l0,a0=a0,l1=l1,a1=a1,l2=l2,a2=a2,y=y)
  
  if (missingData==TRUE) {
    #make some data missing completely at random
    obsData$l1[runif(n)<missingProp] <- NA
    obsData$a1[runif(n)<missingProp] <- NA
    obsData$l2[runif(n)<missingProp] <- NA
    obsData$a2[runif(n)<missingProp] <- NA
    obsData$y[runif(n)<missingProp] <- NA
  }
  
  obsData
}

#function to perform gformula MI simulations increasing M if needed, nSyn=n
gformulaMISimIncM <- function(nSim=1000,M=100,n=500,l0ABB=FALSE,
                          missingData=FALSE, missingProp=0.5, progress=TRUE,maxit=5) {

  #set up lists/arrays to store results
  resultList <- list(est=array(0, dim=nSim),
                        var=array(0, dim=nSim),
                        Bhat=array(0, dim=nSim),
                        Vhat=array(0, dim=nSim),
                        finalM=array(0, dim=nSim),
                        nSyn=n)
  #run simulations
  for (sim in 1:nSim) {
    
    if (progress==TRUE) {
      print(sim)
    }
    
    obsData <- simData(n=n,missingData=missingData,missingProp=missingProp)
    
    #gFormula via MI, increasing M if necessary
    gformMIResult <- gformulaViaMI(obsData=obsData,M=M,increaseM=TRUE,l0ABB=l0ABB,
                                   missingData=missingData,maxit=maxit)
    resultList$est[sim] <- gformMIResult$miEst
    resultList$var[sim] <- gformMIResult$miVarEst
    resultList$Bhat[sim] <- gformMIResult$Bhat
    resultList$Vhat[sim] <- gformMIResult$Vhat
    resultList$finalM[sim] <- gformMIResult$M
    
  }
  
  resultList

}

#function to perform gformula MI simulations increasing nSyn if needed
gformulaMISimIncnsyn <- function(nSim=1000,M=100,n=500,l0ABB=FALSE,nSynMultiplier=1,
                              missingData=FALSE, missingProp=0.5, progress=TRUE,maxit=5) {
  
  #set up lists/arrays to store results
  resultList <- list(est=array(0, dim=nSim),
                     var=array(0, dim=nSim),
                     Bhat=array(0, dim=nSim),
                     Vhat=array(0, dim=nSim),
                     finalnsyn=array(0, dim=nSim),
                     M=M)
  #run simulations
  for (sim in 1:nSim) {
    
    if (progress==TRUE) {
      print(sim)
    }
    
    obsData <- simData(n=n,missingData=missingData,missingProp=missingProp)
    
    #gFormula via MI, increasing nSyn if necessary
    gformMIResult <- gformulaViaMI(obsData=obsData,M=M,increaseM=FALSE,l0ABB=l0ABB,
                                   nSynMultiplier=nSynMultiplier,
                                   missingData=missingData,maxit=maxit)
    resultList$est[sim] <- gformMIResult$miEst
    resultList$var[sim] <- gformMIResult$miVarEst
    resultList$Bhat[sim] <- gformMIResult$Bhat
    resultList$Vhat[sim] <- gformMIResult$Vhat
    resultList$finalnsyn[sim] <- gformMIResult$nSyn
    
  }
  
  resultList
  
}

#function to perform gformula MI simulations increasing nSyn if needed
gfoRmulaSim <- function(nSim=1000,nsimul=500,missingData=FALSE,
                        missingProp=0.5, progress=TRUE) {
  
  #set up lists/arrays to store results
  resultList <- list(est=array(0, dim=nSim))
  
  #run simulations
  for (sim in 1:nSim) {
    
    if (progress==TRUE) {
      print(sim)
    }
    
    obsData <- simData(n=n,missingData=missingData,missingProp=missingProp)
    
    #gfoRmula package  
    gfoRmulaResult <- gfoRmulaRun(obsData=obsData, nsimul=gfoRmulansimul)
    resultList$est[sim] <- as.numeric(gfoRmulaResult$gfoRmulaEst)
    
  }
  
  resultList
  
}

####################################################################
# run simulations
####################################################################

#specify number of simulations to use throughout
numSims <- 10

#GFormulaMI, no missing data, increasing M if needed, different initial M
set.seed(738355)
mVals <- c(5,10,25,50,100)
mSims <- vector("list", length(mVals))
for (i in 1:length(mVals)) {
  print(paste("M=",mVals[i],sep=""))
  mSims[[i]] <- gformulaMISimIncM(nSim=numSims,M=mVals[i],progress=FALSE)
}

#GFormulaMI, no missing data, increasing nSyn if needed, different initial nSyn
set.seed(82621)
nSynMultVals <- c(1,2,5,10)
nSynSims <- vector("list", length(nSynMultVals))
for (i in 1:length(nSynMultVals)) {
  print(paste("nSyn mult=",nSynMultVals[i],sep=""))
  nSynSims[[i]] <- gformulaMISimIncnsyn(nSim=numSims,nSynMultiplier=nSynMultVals[i],
                                        M=10,progress=FALSE)
}

#gfoRmula, no missing data
set.seed(8946565)
nsimulVals <- c(500,1000,2000,5000)
nSynSims <- vector("list", length(nSynMultVals))
for (i in 1:length(nSynMultVals)) {
  print(paste("nSyn mult=",nSynMultVals[i],sep=""))
  nSynSims[[i]] <- gformulaMISimIncnsyn(nSim=numSims,nSynMultiplier=nSynMultVals[i],
                                        M=10,progress=FALSE)
}


resTable <- array(0, dim=c(length(mVals),8))
for (i in 1:length(mVals)) {
  print(i)
  #initial M
  resTable[[i,1]] <- mVals[i]
  #mean treatment effect
  resTable[[i,2]] <- round(mean(mSims[[i]]$miEst),3) - 3
  #empirical SD
  resTable[[i,3]] <- round(sd(mSims[[i]]$miEst),3)
  #mean SD estimate
  resTable[[i,4]] <- round(mean(sqrt(mSims[[i]]$miVar)),3)
  #CI coverage
  tdf <- (mSims[[i]]$MRequired-1)*(1-(mSims[[i]]$MRequired*mSims[[i]]$Vhat)/((mSims[[i]]$MRequired+1)*mSims[[i]]$Bhat))^2
  resTable[[i,5]] <- round(100*mean(1*((mSims[[i]]$miEst-qt(0.975,df=tdf)*sqrt(mSims[[i]]$miVar)<3) &
                               (mSims[[i]]$miEst+qt(0.975,df=tdf)*sqrt(mSims[[i]]$miVar)>3))),1)
  resTable[[i,6]] <- round(100*mean(1*((mSims[[i]]$miEst-1.96*sqrt(mSims[[i]]$miVar)<3) &
                                         (mSims[[i]]$miEst+1.96*sqrt(mSims[[i]]$miVar)>3))),1)
  #mean number of actual imputations performed
  resTable[[i,7]] <- round(mean(mSims[[i]]$MRequired),1)
  #max number of actual imputations performed
  resTable[[i,8]] <- max(mSims[[i]]$MRequired)
  #degrees of freedom
  #resTable[[i,8]] <- median(tdf)
}

resTable
colnames(resTable) <- c("M", "Bias", "Emp. SE", "Est. SE", "Raghu df 95% CI","Z 95% CI", "Mean M", "Max M")
library(xtable)
xtable(resTable, digits=c(0,0,3,3,3,1,1,1,0))

# resulted in:
# % latex table generated in R 4.2.2 by xtable 1.8-4 package
# % Wed Mar  8 03:45:47 2023
# \begin{table}[ht]
# \centering
# \begin{tabular}{rrrrrrrrr}
# \hline
# & M & Bias & Emp. SE & Est. SE & Raghu df 95\% CI & Z 95\% CI & Mean M & Max M \\ 
# \hline
# 1 & 5 & 0.002 & 0.244 & 0.238 & 99.7 & 87.1 & 5.6 & 15 \\ 
# 2 & 10 & -0.007 & 0.233 & 0.223 & 98.3 & 89.1 & 10.2 & 30 \\ 
# 3 & 25 & 0.002 & 0.223 & 0.219 & 95.5 & 92.7 & 25.0 & 25 \\ 
# 4 & 50 & 0.002 & 0.221 & 0.219 & 94.9 & 93.7 & 50.0 & 50 \\ 
# 5 & 100 & -0.003 & 0.219 & 0.219 & 95.0 & 94.6 & 100.0 & 100 \\ 
# \hline
# \end{tabular}
# \end{table}

#approximate Bayesian bootstrap, at M=50
set.seed(738355)
abbSim <- gformulaMISim(nSim=numSims,M=50,progress=FALSE,l0ABB=TRUE)
mean(abbSim$miEst)-3
sd(abbSim$miEst)
mean(abbSim$miVar^0.5)
tdf <- (abbSim$MRequired-1)*(1-(abbSim$MRequired*abbSim$Vhat)/((abbSim$MRequired+1)*abbSim$Bhat))^2
#Raghu df
100*mean(1*((abbSim$miEst-qt(0.975,df=tdf)*sqrt(abbSim$miVar)<3) &
                    (abbSim$miEst+qt(0.975,df=tdf)*sqrt(abbSim$miVar)>3)))
#N(0,1)
100*mean(1*((abbSim$miEst-1.96*sqrt(abbSim$miVar)<3) &
              (abbSim$miEst+1.96*sqrt(abbSim$miVar)>3)))

# results from this chunk:
# > #approximate Bayesian bootstrap, at M=50
#   > set.seed(738355)
# > abbSim <- gformulaMISim(nSim=numSims,M=50,progress=FALSE,l0ABB=TRUE)
# > mean(abbSim$miEst)-3
# [1] -0.001460614
# > sd(abbSim$miEst)
# [1] 0.2220345
# > mean(abbSim$miVar^0.5)
# [1] 0.2193811
# > tdf <- (abbSim$MRequired-1)*(1-(abbSim$MRequired*abbSim$Vhat)/((abbSim$MRequired+1)*abbSim$Bhat))^2
# > #Raghu df
#   > 100*mean(1*((abbSim$miEst-qt(0.975,df=tdf)*sqrt(abbSim$miVar)<3) &
#                   +                     (abbSim$miEst+qt(0.975,df=tdf)*sqrt(abbSim$miVar)>3)))
# [1] 94.91
# > #N(0,1)
#   > 100*mean(1*((abbSim$miEst-1.96*sqrt(abbSim$miVar)<3) &
#                   +               (abbSim$miEst+1.96*sqrt(abbSim$miVar)>3)))
# [1] 93.82

#now with missing data with different proportions of missing data MCAR
set.seed(738355)
missingProps <- c(0.05,0.10,0.25,0.50)
missingMiceSims <- vector("list", length(missingProps))
for (i in 1:length(missingProps)) {
  print(paste("Missingness proportion=",missingProps[i],sep=""))
  if (missingProps[i]==0.5) {
    #more iterations needed in mice for missing data imputation with 50% missingness
    missingMiceSims[[i]] <- gformulaMISim(nSim=numSims,M=50,missingData=TRUE,missingProp=missingProps[i],
                                          progress=FALSE,maxit=50)  
  } else {
    missingMiceSims[[i]] <- gformulaMISim(nSim=numSims,M=50,missingData=TRUE,missingProp=missingProps[i],
                              progress=FALSE)
  }
}

resTable <- array(0, dim=c(length(missingProps),6))
for (i in 1:length(missingProps)) {
  print(i)
  #missingness proportion
  resTable[[i,1]] <- missingProps[i]
  #mean treatment effect
  resTable[[i,2]] <- round(mean(missingMiceSims[[i]]$miEst),3) - 3
  #empirical SD
  resTable[[i,3]] <- round(sd(missingMiceSims[[i]]$miEst),3)
  #mean SD estimate
  resTable[[i,4]] <- round(mean(sqrt(missingMiceSims[[i]]$miVar)),3)
  #CI coverage
  tdf <- (missingMiceSims[[i]]$MRequired-1)*(1-(missingMiceSims[[i]]$MRequired*missingMiceSims[[i]]$Vhat)/((missingMiceSims[[i]]$MRequired+1)*missingMiceSims[[i]]$Bhat))^2
  resTable[[i,5]] <- round(100*mean(1*((missingMiceSims[[i]]$miEst-qt(0.975,df=tdf)*sqrt(missingMiceSims[[i]]$miVar)<3) &
                                         (missingMiceSims[[i]]$miEst+qt(0.975,df=tdf)*sqrt(missingMiceSims[[i]]$miVar)>3))),1)
  resTable[[i,6]] <- round(100*mean(1*((missingMiceSims[[i]]$miEst-1.96*sqrt(missingMiceSims[[i]]$miVar)<3) &
                                         (missingMiceSims[[i]]$miEst+1.96*sqrt(missingMiceSims[[i]]$miVar)>3))),1)
  #median number of actual imputations performed
  #resTable[[i,6]] <- round(mean(missingMiceSims[[i]]$MRequired),1)
  #max number of actual imputations performed
  #resTable[[i,7]] <- max(missingMiceSims[[i]]$MRequired)
}

resTable
colnames(resTable) <- c("\\pi", "Bias", "Emp. SE", "Est. SE", "Raghu df 95% CI","Z 95% CI")
xtable(resTable, digits=c(0,2,3,3,3,1,1))

# resulted in:
# % latex table generated in R 4.2.2 by xtable 1.8-4 package
# % Mon Mar 13 12:11:16 2023
# \begin{table}[ht]
# \centering
# \begin{tabular}{rrrrrrr}
# \hline
# & $\backslash$pi & Bias & Emp. SE & Est. SE & Raghu df 95\% CI & Z 95\% CI \\ 
# \hline
# 1 & 0.05 & 0.000 & 0.226 & 0.225 & 94.9 & 93.8 \\ 
# 2 & 0.10 & -0.005 & 0.232 & 0.232 & 95.2 & 94.2 \\ 
# 3 & 0.25 & -0.010 & 0.260 & 0.258 & 95.0 & 94.1 \\ 
# 4 & 0.50 & -0.013 & 0.357 & 0.361 & 95.3 & 94.5 \\ 
# \hline
# \end{tabular}
# \end{table}