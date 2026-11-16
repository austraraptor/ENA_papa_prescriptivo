# =============================================================================
# Funciones de la analítica prescriptiva (rama 5, app Shiny y pruebas)
# Programa lineal: ¿cuánto subir cada palanca en cada departamento para
# maximizar el valor de la producción adicional con un presupuesto fijo?
#
#   max  sum_ik v_ik x_ik                       (S/ adicionales)
#   s.a. sum_ik c_ik x_ik <= B                  (presupuesto)
#        sum_k  c_ik x_ik <= tope * B   para cada i   (no concentrar)
#        sum_{i en P} sum_k c_ik x_ik >= cuota * B    (equidad: priorizados)
#        0 <= x_ik <= min(tope_pp_k, 100 - nivel_ik)
#   x_ik  = puntos porcentuales que sube la palanca k en el departamento i
#   v_ik  = beta_k (kg/ha por pp) * superficie_i (ha) * precio_i (S/ por kg)
#   c_ik  = costo_k * (superficie_i o productores_i) / 100
# =============================================================================

efectos_palancas <- function(beta, ee, palancas, z = Z_ROBUSTO) {
  tibble(var = palancas$var, beta = unname(beta[palancas$var]), ee = unname(ee[palancas$var])) %>%
    mutate(beta_puntual = beta, beta_robusto = pmax(0, beta - z * ee))
}

armar_problema <- function(insumos, palancas, efectos, tipo = c("puntual", "robusto")) {
  tipo <- match.arg(tipo)
  b <- setNames(efectos[[paste0("beta_", tipo)]], efectos$var)
  tidyr::expand_grid(i = seq_len(nrow(insumos)), k = seq_len(nrow(palancas))) %>%
    mutate(DEPARTAMENTO = insumos$DEPARTAMENTO[i], palanca = palancas$nombre[k], var = palancas$var[k],
           prioritario = insumos$prioritario[i],
           nivel = map2_dbl(i, k, ~ insumos[[palancas$var[.y]]][.x]),
           ub = pmax(0, pmin(palancas$tope_pp[k], 100 - nivel)),
           escala = if_else(palancas$base[k] == "area", insumos$area[i], insumos$productores[i]),
           c = palancas$costo[k] * escala / 100,
           ap = insumos$area[i] * insumos$precio[i],
           kg = b[var] * insumos$area[i],
           v = kg * insumos$precio[i]) %>%
    filter(v > 0, ub > 0)            # palancas sin efecto positivo no entran al plan
}

optimizar_plan <- function(insumos, palancas, efectos, presupuesto, cuota = CUOTA_EQUIDAD,
                           tope_depto = TOPE_DEPTO, tipo = "puntual") {
  pr <- armar_problema(insumos, palancas, efectos, tipo)
  n <- nrow(pr)
  if (n == 0) stop("Ninguna palanca tiene efecto positivo: no hay plan que optimizar")
  deps <- unique(pr$DEPARTAMENTO)
  # capacidad de los priorizados: si no alcanza la cuota, la cuota se ajusta a su capacidad
  cap_prior <- sum((pr$c * pr$ub)[pr$prioritario])
  rhs_eq <- min(cuota * presupuesto, cap_prior)
  A <- rbind(pr$c,
             t(vapply(deps, function(d) pr$c * (pr$DEPARTAMENTO == d), numeric(n))),
             pr$c * pr$prioritario,
             diag(n))
  dir <- c("<=", rep("<=", length(deps)), ">=", rep("<=", n))
  rhs <- c(presupuesto, rep(tope_depto * presupuesto, length(deps)), rhs_eq, pr$ub)
  sol <- lpSolve::lp("max", pr$v, A, dir, rhs, compute.sens = TRUE)
  if (sol$status != 0) stop("El programa lineal no tiene solución (status ", sol$status, ")")
  pr$x <- sol$solution
  pr <- mutate(pr, costo = c * x, kg_adic = kg * x, valor = v * x)
  list(plan = pr, objetivo = sol$objval, gasto = sum(pr$costo),
       precio_sombra = sol$duals[1],      # S/ adicionales por cada sol extra de presupuesto
       cuota_efectiva = rhs_eq / presupuesto, cap_prior = cap_prior, status = sol$status)
}

resumen_plan <- function(res) {
  res$plan %>% filter(x > 1e-9) %>% group_by(DEPARTAMENTO, palanca) %>%
    summarise(pp = sum(x), costo = sum(costo), t_adic = sum(kg_adic) / 1000, valor = sum(valor), .groups = "drop")
}

# Montecarlo: incertidumbre de los efectos (normal multivariada con la matriz agrupada)
# valor(beta) = sum_k beta_k * sum_i x_ik * superficie_i * precio_i
simular_plan <- function(res, efectos, vcov_palancas, n = N_MONTECARLO, semilla = SEMILLA) {
  set.seed(semilla)
  vars <- efectos$var
  L <- chol(vcov_palancas[vars, vars])
  draws <- sweep(matrix(rnorm(n * length(vars)), n) %*% L, 2, efectos$beta, "+")
  base <- vapply(vars, function(v) sum((res$plan$x * res$plan$ap)[res$plan$var == v]), 0)
  valor <- drop(draws %*% base)
  tibble(valor = valor, bc = valor / res$gasto)
}

# Distribución exacta: el valor es lineal en beta -> normal con media b'mu y varianza b'Vb
distribucion_exacta <- function(res, efectos, vcov_palancas) {
  vars <- efectos$var
  base <- vapply(vars, function(v) sum((res$plan$x * res$plan$ap)[res$plan$var == v]), 0)
  media <- sum(base * efectos$beta)
  de <- sqrt(drop(t(base) %*% vcov_palancas[vars, vars] %*% base))
  tibble(media_exacta = media, de_exacta = de, p05_exacto = media + qnorm(0.05) * de,
         p95_exacto = media + qnorm(0.95) * de, prob_bc_menor_1_exacta = pnorm((res$gasto - media) / de))
}
