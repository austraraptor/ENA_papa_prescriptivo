# =============================================================================
# Funciones del modelo predictivo (las usan la rama 4, las pruebas y la app)
# Réplica exacta de la especificación del artículo (scikit-learn / xgboost)
# =============================================================================

# Estandarización como StandardScaler: media y desviación poblacional (ddof = 0)
escalador <- function(X) {
  mu <- colMeans(X)
  s <- sqrt(colMeans(sweep(X, 2, mu)^2))
  s[s == 0] <- 1
  list(mu = mu, s = s, aplicar = function(Z) sweep(sweep(Z, 2, mu), 2, s, "/"))
}

# Ridge (intercepto sin penalizar): b = (A'A + alpha I)^-1 A'(y - ybar)
ridge_ajustar <- function(A, y, alpha) {
  b <- solve(crossprod(A) + diag(alpha, ncol(A)), crossprod(A, y - mean(y)))
  list(b0 = mean(y), b = drop(b))
}

# ElasticNet con la función objetivo de scikit-learn:
#   1/(2n)||y - b0 - A b||^2 + alpha*l1*||b||_1 + 0.5*alpha*(1-l1)*||b||^2
# Descenso por coordenadas hasta convergencia estricta (tol 1e-12)
enet_ajustar <- function(A, y, alpha, l1, tol = 1e-12, max_iter = 100000L) {
  n <- nrow(A); p <- ncol(A)
  yc <- y - mean(y)
  b <- numeric(p); r <- yc
  z <- colSums(A^2) / n
  for (it in seq_len(max_iter)) {
    cambio <- 0
    for (j in seq_len(p)) {
      bj_old <- b[j]
      rho <- sum(A[, j] * r) / n + z[j] * bj_old
      bj <- sign(rho) * max(abs(rho) - alpha * l1, 0) / (z[j] + alpha * (1 - l1))
      if (bj != bj_old) { r <- r - A[, j] * (bj - bj_old); b[j] <- bj }
      cambio <- max(cambio, abs(bj - bj_old))
    }
    if (cambio < tol * max(1, max(abs(b)))) break
  }
  list(b0 = mean(y), b = b, iter = it)
}

# Condiciones KKT de ElasticNet: prueba independiente de optimalidad
enet_kkt <- function(A, y, fit, alpha, l1) {
  n <- nrow(A); r <- (y - fit$b0) - A %*% fit$b
  g <- drop(crossprod(A, r)) / n - alpha * (1 - l1) * fit$b
  activo <- fit$b != 0
  c(activos = max(c(0, abs(g[activo] - alpha * l1 * sign(fit$b[activo])))),
    inactivos = max(c(0, abs(g[!activo]) - alpha * l1)))
}

matriz_x <- function(df, cols) as.matrix(df[, c("y_lag", cols)])

xgb_ajustar <- function(X, y, depth = 2, semilla = 7L) {
  set.seed(semilla)
  p <- list(objective = "reg:squarederror", max_depth = depth, eta = XGB_PARAMS$eta,
            subsample = XGB_PARAMS$subsample, colsample_bytree = XGB_PARAMS$colsample_bytree,
            min_child_weight = XGB_PARAMS$min_child_weight, lambda = XGB_PARAMS$lambda,
            nthread = 1, seed = semilla)
  xgboost::xgb.train(params = p, data = xgboost::xgb.DMatrix(X, label = y),
                     nrounds = XGB_PARAMS$nrounds, verbose = 0)
}

# Ajusta los seis modelos con 'tr' y pronostica 'te'
ajustar_predecir <- function(tr, te, cols = XCOLS, depth = 2, semilla = SEMILLA) {
  tr <- filter(tr, !is.na(y_lag))
  out <- list(`Naive Lag1` = te$y_lag)
  # Panel dinámico FE-ARDL (MCO con efectos fijos por departamento)
  f_fe <- as.formula(paste("y ~ y_lag +", paste(cols, collapse = " + "), "+ factor(DEPARTAMENTO)"))
  fe <- lm(f_fe, data = tr)
  out$`Panel FE-ARDL` <- unname(predict(fe, newdata = te))
  # Ridge y ElasticNet sobre covariables estandarizadas con la media/DE de entrenamiento
  Xtr <- matriz_x(tr, cols); Xte <- matriz_x(te, cols)
  sc <- escalador(Xtr); A <- sc$aplicar(Xtr); B <- sc$aplicar(Xte)
  rg <- ridge_ajustar(A, tr$y, RIDGE_ALPHA)
  out$Ridge <- rg$b0 + drop(B %*% rg$b)
  en <- enet_ajustar(A, tr$y, ENET_ALPHA, ENET_L1)
  out$ElasticNet <- en$b0 + drop(B %*% en$b)
  # XGBoost restringido
  xg <- xgb_ajustar(Xtr, tr$y, depth, semilla)
  out$`XGBoost (prof. 2)` <- predict(xg, xgboost::xgb.DMatrix(Xte))
  out$`Ensamble informado` <- (out$`Panel FE-ARDL` + out$`XGBoost (prof. 2)`) / 2
  list(pred = out, xgb = xg, Xte = Xte, enet = en, A = A, ytr = tr$y)
}

MODELOS <- c("Naive Lag1", "Panel FE-ARDL", "Ridge", "ElasticNet", "XGBoost (prof. 2)", "Ensamble informado")

metricas <- function(y, f) {
  e <- y - f
  c(MAE = mean(abs(e)), RMSE = sqrt(mean(e^2)), MAPE = 100 * mean(abs(e) / y),
    sMAPE = 100 * mean(2 * abs(e) / (abs(y) + abs(f))))
}

# Cuantil split-conformal: k = ceiling((n+1)(1-a)), acotado a n
cuantil_conformal <- function(res_abs, nivel) {
  r <- sort(res_abs); n <- length(r)
  r[min(ceiling((n + 1) * nivel), n)]
}

winkler <- function(y, lo, hi, a) mean((hi - lo) + (2 / a) * (lo - y) * (y < lo) + (2 / a) * (y - hi) * (y > hi))

# Validación walk-forward (rolling-origin) con ventana expansiva o móvil
walk_forward <- function(datos, anios_prueba = ANIOS_PRUEBA, ventana = NULL, cols = XCOLS,
                         depth = 2, semilla = SEMILLA, shap = FALSE) {
  anios <- sort(unique(datos$ANIO))
  filas <- list(); shap_l <- list()
  for (t in anios_prueba) {
    prev <- anios[anios < t]
    if (!is.null(ventana)) prev <- tail(prev, ventana)
    tr <- filter(datos, ANIO %in% prev); te <- filter(datos, ANIO == t)
    o <- ajustar_predecir(tr, te, cols, depth, semilla)
    # calibración conformal: último año de entrenamiento pronosticado con los anteriores
    cal_t <- tail(prev, 1)
    oc <- ajustar_predecir(filter(datos, ANIO %in% head(prev, -1)), filter(datos, ANIO == cal_t),
                           cols, depth, semilla)
    cal <- filter(datos, ANIO == cal_t)
    res_cal <- abs(cal$y - oc$pred$`Ensamble informado`)
    # desviación de residuos dentro de muestra (intervalo gaussiano)
    tr_in <- filter(tr, !is.na(y_lag))
    oi <- ajustar_predecir(tr, tr_in, cols, depth, semilla)
    sd_in <- sd(tr_in$y - oi$pred$`Ensamble informado`)
    d <- tibble(ANIO = t, DEPARTAMENTO = te$DEPARTAMENTO, y = te$y, helada = te$pct_perd_helada,
                sd_in = sd_in, q80 = cuantil_conformal(res_cal, 0.8), q90 = cuantil_conformal(res_cal, 0.9))
    for (m in MODELOS) d[[m]] <- o$pred[[m]]
    filas[[as.character(t)]] <- d
    if (shap) {
      sv <- predict(o$xgb, xgboost::xgb.DMatrix(o$Xte), predcontrib = TRUE)
      shap_l[[as.character(t)]] <- sv[, colnames(o$Xte), drop = FALSE]
    }
  }
  wf <- bind_rows(filas)
  if (shap) attr(wf, "shap") <- do.call(rbind, shap_l)
  wf
}
