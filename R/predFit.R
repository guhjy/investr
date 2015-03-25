#' Predictions from a Fitted Model
#'
#' Generic prediction method for various types of fitted models. (For internal 
#' use only.)
#' 
#' @keywords internal
predFit <- function(object, ...) {
  UseMethod("predFit")
} 


#' @rdname predFit
#' @keywords internal
predFit.lm <- function(object, newdata, se.fit = TRUE,
                        interval = c("none", "confidence", "prediction"), 
                        level = 0.95, 
                        adjust = c("none", "Bonferroni", "Scheffe"), k, 
                        ...) {
  
  # Prediction data
  newdata <- if (missing(newdata)) {
    eval(object$call$data, envir = parent.frame()) 
  } else {
    as.data.frame(newdata) 
  } 

  # Predicted values and, if requested (default), standard errors
  pred <- predict(object, newdata = newdata, se.fit = se.fit)  # FIXME: suppressWarnings
  
  # Compute results
  interval <- match.arg(interval)
  if (interval == "none") {
    
    res <- pred  
    
  } else { 
    
    # Critical value for interval computations
    adjust <- match.arg(adjust)
    crit <- if (adjust == "Bonferroni") {  # Bonferroni adjustment -------------
      
      qt((level + 2*k - 1) / (2*k), pred$df)
      
    } else if (adjust == "Scheffe") {  # Scheffe adjustment --------------------
      
      # Working-Hotelling band or adjusted prediction band for k predictions
      if (interval == "confidence") {
        p <- length(coef(object))
        sqrt(p * qf(level, p, pred$df))  # Working-Hotelling band
      } else {
        sqrt(k * qf(level, k, pred$df))  # need k for prediction
      }  
      
    } else {   # no adjustment -------------------------------------------------
      
      qt((level + 1) / 2, pred$df)    
      
    }
    
    # Interval calculations
    if (interval == "confidence") {  # confidence interval for mean response
      lwr <- pred$fit - crit * pred$se.fit
      upr <- pred$fit + crit * pred$se.fit
    } else {  # prediction interval for individual response
      lwr <- pred$fit - crit * sqrt(Sigma(object)^2 + pred$se.fit^2)
      upr <- pred$fit + crit * sqrt(Sigma(object)^2 + pred$se.fit^2)
    }
    
    # Store results in a list
    res <- list(fit = as.numeric(pred$fit), 
                lwr = as.numeric(lwr), 
                upr = as.numeric(upr),
                se.fit = as.numeric(pred$se.fit))
    
  }
  
  # Return results
  return(res)
  
}


#' @rdname predFit
#' @keywords internal
predFit.nls <- function(object, newdata, se.fit = TRUE,
                        interval = c("none", "confidence", "prediction"), 
                        level = 0.95, 
                        adjust = c("none", "Bonferroni", "Scheffe"), k, 
                        ...) {
  
  # No support for the Golub-Pereyra algorithm for partially linear 
  # least-squares models
  if (object$call$algorithm == "plinear") {
    stop(paste("The Golub-Pereyra algorithm for partially linear least-squares 
               models is currently not supported."), call. = FALSE)
  }
  
  # Prediction data
  newdata <- if (missing(newdata)) {
    eval(object$call$data, envir = parent.frame()) 
  } else {
    as.data.frame(newdata) 
  }
  
  # Name of independent variable
  xname <- intersect(all.vars(formula(object)[[3]]), colnames(newdata)) 
  
  # Predicted values
  pred <- object$m$predict(newdata)
  
  # Compute standard error
  if (se.fit) {
    
    # Assign values to parameter names in current environment
    param.names <- names(coef(object))  
    for (i in 1:length(param.names)) { 
      assign(param.names[i], coef(object)[i])  
    }
    
    # Assign values to independent variable name
    assign(xname, newdata[, xname])  
    
    # Calculate gradient (numerically)
    form <- object$m$formula()
    rhs <- eval(form[[3]])
    if (is.null(attr(rhs, "gradient"))) {
      f0 <- attr(numericDeriv(form[[3]], param.names), "gradient")
    } else {  # self start models should have gradient attribute
      f0 <- attr(rhs, "gradient")
    }
    
    # Calculate standard error
    R1 <- object$m$Rmat()
    v0 <- diag(f0 %*% solve(t(R1) %*% R1) %*% t(f0))
    se_fit <- sqrt(Sigma(object)^2 * v0)
    
    # Add standard error to list of results
    pred <- list(fit = pred, se.fit = se_fit)
    
  }
  
  # Compute results
  interval <- match.arg(interval)
  if (interval == "none") {
    
    res <- pred    
    
  } else { 
    
    # Adjustment for simultaneous inference
    adjust <- match.arg(adjust)
    crit <- if (adjust == "Bonferroni") {  # Bonferroni adjustment -------------
                                           
      qt((level + 2*k - 1) / (2*k), df.residual(object))
      
    } else if (adjust == "Scheffe") {  # Scheffe adjustment --------------------
      
      if (interval == "confidence") {
        p <- length(coef(object))  # number of regression parameters
        sqrt(p * qf((level + 1) / 2, p, df.residual(object))) 
      } else {
        sqrt(k * qf((level + 1) / 2, k, df.residual(object))) 
      }     
      
    } else {  # no adjustment --------------------------------------------------   
      
      qt((level + 1) / 2, df.residual(object))   
      
    }
    
    # Interval calculations
    if (interval == "confidence") {  # confidence limits for mean response
      lwr <- pred$fit - crit * pred$se.fit  # lower limits
      upr <- pred$fit + crit * pred$se.fit  # upper limits
    } else {  # prediction limits for individual response
      lwr <- pred$fit - crit * sqrt(Sigma(object)^2 + pred$se.fit^2)  # lower limits
      upr <- pred$fit + crit * sqrt(Sigma(object)^2 + pred$se.fit^2)  # upper limits
    }
    
    # Store results in a list
    res <- list(fit = as.numeric(pred$fit), 
                lwr = as.numeric(lwr), 
                upr = as.numeric(upr),
                se.fit = as.numeric(pred$se.fit))
    
  }
  
  # Return list of results
  return(res)
  
  }


#' @rdname predFit
#' @keywords internal
predFit.lme <- function(object, newdata, se.fit = TRUE, ...) {
  
  # Prediction data
  newdata <- if (missing(newdata)) {
    object$data 
  } else {
    as.data.frame(newdata) 
  }  
  
  # Names of independent variables
  xname <- intersect(all.vars(formula(object)[[3]]), colnames(newdata)) 
  
  # Population predicted values
  pred <- predict(object, newdata = newdata, level = 0)
  
  # Approximate standard error of fitted values
  if (se.fit) {
    Xmat <- makeX(object, newdata)  # fixed-effects design matrix
#     Xmat <- makeX(object, newdata = makeData(newdata, xname))
    se_fit <- sqrt(diag(Xmat %*% vcov(object) %*% t(Xmat)))
    list(fit = pred, se.fit = se_fit)
  } else {
    pred
  }

}