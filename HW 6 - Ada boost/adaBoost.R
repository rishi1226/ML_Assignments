if(!require("assertthat")) install.packages("assertthat")
if(!require("rpart")) install.packages("rpart")
if(!require("psych")) install.packages("psych")
if(!require("dplyr")) install.packages("dplyr")
if(!require("mvtnorm")) install.packages("mvtnorm")
if(!require("ggplot2")) install.packages("ggplot2")
if(!require("randomForest")) install.packages("randomForest")
if(!require("reshape2")) install.packages("reshape2")
if(!require("adabag")) install.packages("adabag")

get.sigmaXY <- function(rhoXY, sdX, sdY){
  cov <- rhoXY * sdX *sdY
  matrix(c(sdX^2, cov, cov, sdY^2), nrow = 2)
}

get.data <- function(n1 = 100, n2 = 100, mu1, mu2, sd1, sd2, rhoXY, seed = 1000) {
  set.seed(seed)
  features1 <- rmvnorm(n1, mean = c(mu1[1], mu1[2]), 
                       sigma = get.sigmaXY(rhoXY[1], sd1[1], sd1[2]))
  features2 <- rmvnorm(n2, mean = c(mu2[1], mu2[2]), 
                       sigma = get.sigmaXY(rhoXY[2], sd2[1], sd2[2]))
  features <- rbind(features1, features2)
  label <- c(rep(-1, n1), rep(1, n2))
  index <- sample(1:(n1+n2))
  result <- list(features = as.data.frame(rbind(features1, features2))[index,], 
                 label = label[index])
  return(result)
}


draw.plot <- function(feat, lab) {
  data <- data.frame(feat, factor(lab))
  names(data) <- c("X1", "X2", "lab")
  ggplot(data, aes(x = X1, y = X2, fill = lab, color = lab)) +
    geom_point(alpha = 0.5, size = 3) +
    scale_color_manual(values = c("#AD0909", "#202D8F"))
  
}


ada.booster <- function(feat, lab, w, alpha.pred, iter = 10, 
                        diagnostics = FALSE, err.rate = c()) {
  
  tree = rpart(formula = lab~., data = feat, 
               weights = w, method = "class", control = c(maxdepth = 1) )
  pred = ifelse(predict(tree, type = "class") == "-1", -1, 1)
  
  epsilon = (function() sum(w * ifelse(pred == lab, 0, 1))) ()
  alpha   = (function(x) 0.5 * log((1 - x) / x)) (epsilon)
  w       = w * exp((alpha * ifelse(pred != lab, 1, -1)))
  
  alpha.pred = alpha.pred + ifelse(pred == "-1", -1, 1) * alpha
  
  if(diagnostics == TRUE) err.rate <- c(err.rate, 
                                        sum(sign(alpha.pred) != lab) / length(lab)) 
  
  #Check if all weights are 0 i.e data is prefectly seperated
  zero.weights = (max(w) == 0 & min (w) == 0)
  
  if(iter == 1 | zero.weights) {
    if(zero.weights) print("Data is prefectly seperated. Quitting")
    
    if(diagnostics != TRUE) return(sign(alpha.pred))
    else return (err.rate)
  }
  else {
    ada.booster(feat, lab, w, alpha.pred, iter - 1, diagnostics, err.rate)
  }
}

#Create dataset
rhoXY <- c(0.8, 0.5)
sd1 <- c(2, 2)
mu1 <- c(15, 20)
sd2 <- c(1, 1.5)
mu2 <- c(15, 15)

train <- get.data(1000,1000, mu1, mu2, sd1, sd2, rhoXY, 2500)
test <- get.data(500,500, mu1, mu2, sd1, sd2, rhoXY, 1200)

train.feat <- train[[1]]
train.lab <- train[[2]]
test.feat <- test[[1]]
test.lab <- test[[2]]

draw.plot(train.feat, train.lab)
draw.plot(test.feat, test.lab)

iter <- 100

#ADA BOOST
alpha.pred <- rep(0, length(train.lab))
w <- rep(1/length(train.lab), length(train.lab))
ad.err.rates <- ada.booster(train.feat, train.lab, w, alpha.pred, iter, diagnostics = TRUE)

err.df <- data.frame(iter = 1:iter, Ada_Boost_Error = ad.err.rates)
ggplot(err.df, aes(x = iter, y = Ada_Boost_Error)) + geom_point() + geom_line()



#Compare
alpha.pred <- rep(0, length(train.lab))
w <- rep(1/length(test.lab), length(test.lab))
ad.err.rates <- ada.booster(test.feat, test.lab, w, alpha.pred, iter, diagnostics = TRUE)


rf.err.rates <- sapply(X = 1:iter, FUN = function(v) {
  rf = randomForest(train.feat, train.lab, ntree = v)
  pred = sign(predict(rf , test.feat, type = "class"))
  sum(pred != test.lab) / length(test.lab)
})

bag.train <- cbind(lab = factor(train.lab), train.feat)
bag.test <- cbind(lab = factor(test.lab), test.feat)
names(bag.train)
names(bag.test)


bag.err.rates <- sapply(X = 1:iter, FUN = function(v) {
  bag = bagging(lab ~., bag.train, mfinal=v)
  err = predict.bagging(bag, bag.test)$error
  err
})

err.df <- data.frame(iter = 1:iter, ada.boost = ad.err.rates, 
                     rand.forest =rf.err.rates, bagging = bag.err.rates)
melt.error <- melt(err.df, id.vars = "iter", variable.name = "Algorithm", 
                   value.name = "Error")
names(melt.error)
ggplot(melt.error, aes(x = iter, y = Error, color = Algorithm)) + 
  geom_point() + 
  geom_line() +
  scale_color_manual(values = c("#1f78b4", "#33a02c", "#ff7f00")) +
  ggtitle("Error Comparison")
