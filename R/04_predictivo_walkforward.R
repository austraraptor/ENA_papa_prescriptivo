# =============================================================================
# RAMA 4 - ANALÍTICA PREDICTIVA (réplica del artículo)
# Walk-forward 2021-2025, seis modelos, calibración conformal, heladas,
# sensibilidad, SHAP, variación por semilla y verificación cruzada con caret.
# =============================================================================
source(file.path(RAIZ, "R", "funciones_modelos.R"))

WF <- walk_forward(panel, shap = TRUE)
SHAP <- attr(WF, "shap")
chequear("Predictivo", "95 pronósticos fuera de muestra (19 x 5)", nrow(WF) == 95)
chequear("Predictivo", "Sin pronósticos NA", !anyNA(WF[MODELOS]))

TAB_MODELOS <- map_dfr(MODELOS, ~ c(modelo = .x, as.list(metricas(WF$y, WF[[.x]])))) %>%
  mutate(across(MAE:sMAPE, as.numeric))

# ---- validación contra el artículo (Python): modelos deterministas deben coincidir
ref <- read_csv(RUTAS$ref_metric, show_col_types = FALSE)
ref_pron <- read_csv(RUTAS$ref_pron, show_col_types = FALSE)
cmp_m <- inner_join(TAB_MODELOS, ref, by = "modelo", suffix = c("", "_art"))
det <- c("Naive Lag1", "Panel FE-ARDL", "Ridge", "ElasticNet")
for (m in det) {
  r <- filter(cmp_m, modelo == m)
  chequear("Predictivo", paste(m, "= artículo (MAE y RMSE ±0.01)"),
           abs(r$MAE - r$MAE_art) < 0.01 && abs(r$RMSE - r$RMSE_art) < 0.01,
           sprintf("RMSE %.2f vs %.2f", r$RMSE, r$RMSE_art))
}
pp <- inner_join(WF, ref_pron, by = c("ANIO", "DEPARTAMENTO"), suffix = c("", "_py"))
DIF_PY <- tibble(modelo = MODELOS,
                 dif_max_kg_ha = map_dbl(MODELOS, ~ max(abs(pp[[.x]] - pp[[paste0(.x, "_py")]]))))
chequear("Predictivo", "Pronósticos deterministas = Python (dif. < 0.01 kg/ha)",
         all(DIF_PY$dif_max_kg_ha[DIF_PY$modelo %in% c("Naive Lag1", "Panel FE-ARDL", "Ridge")] < 0.01))
chequear("Predictivo", "ElasticNet = Python (dif. < 1 kg/ha; sklearn usa tol = 1e-4)",
         DIF_PY$dif_max_kg_ha[DIF_PY$modelo == "ElasticNet"] < 1)
chequear("Predictivo", "XGBoost semilla 7 = Python (dif. < 0.01 kg/ha, precisión float32)",
         DIF_PY$dif_max_kg_ha[DIF_PY$modelo == "XGBoost (prof. 2)"] < 0.01)

# KKT de ElasticNet en la última ventana (prueba de optimalidad independiente de Python)
o_last <- ajustar_predecir(filter(panel, ANIO < 2025), filter(panel, ANIO == 2025))
kkt <- enet_kkt(o_last$A, o_last$ytr, o_last$enet, ENET_ALPHA, ENET_L1)
chequear("Predictivo", "ElasticNet cumple KKT (|grad| < 1e-6)", all(kkt < 1e-6), sprintf("%.1e", max(kkt)))

# ---- XGBoost: variación por semilla (el artículo usa una sola semilla)
SEMILLAS <- tibble(semilla = SEMILLA + 0:(N_SEMILLAS_XGB - 1)) %>%
  mutate(res = map(semilla, function(s) {
    w <- walk_forward(panel, semilla = s)
    tibble(RMSE_xgb = metricas(w$y, w$`XGBoost (prof. 2)`)[["RMSE"]],
           RMSE_ens = metricas(w$y, w$`Ensamble informado`)[["RMSE"]],
           MAE_ens = metricas(w$y, w$`Ensamble informado`)[["MAE"]])
  })) %>% unnest(res)
rmse_naive <- metricas(WF$y, WF$`Naive Lag1`)[["RMSE"]]
chequear("Predictivo", "Ensamble con RMSE < ingenuo en la mayoría de semillas",
         mean(SEMILLAS$RMSE_ens < rmse_naive) >= 0.5,
         sprintf("%d de %d", sum(SEMILLAS$RMSE_ens < rmse_naive), nrow(SEMILLAS)))

# ---- verificación cruzada con caret: índices walk-forward propios
pc <- filter(panel, !is.na(y_lag)) %>% mutate(DEPARTAMENTO = factor(DEPARTAMENTO))
idx_tr <- map(ANIOS_PRUEBA, ~ which(pc$ANIO < .x)); names(idx_tr) <- paste0("A", ANIOS_PRUEBA)
idx_te <- map(ANIOS_PRUEBA, ~ which(pc$ANIO == .x)); names(idx_te) <- names(idx_tr)
ctrl <- caret::trainControl(method = "cv", index = idx_tr, indexOut = idx_te, savePredictions = "all")
f_fe <- as.formula(paste("y ~ y_lag +", paste(XCOLS, collapse = " + "), "+ DEPARTAMENTO"))
CARET_FE <- caret::train(f_fe, data = pc, method = "lm", trControl = ctrl)
caret_pred <- CARET_FE$pred %>% mutate(ANIO = pc$ANIO[rowIndex], DEPARTAMENTO = as.character(pc$DEPARTAMENTO[rowIndex]))
cc <- inner_join(caret_pred, WF, by = c("ANIO", "DEPARTAMENTO"))
chequear("Predictivo", "caret (lm, walk-forward) = FE-ARDL propio", max(abs(cc$pred - cc$`Panel FE-ARDL`)) < 1e-6,
         sprintf("dif máx %.1e", max(abs(cc$pred - cc$`Panel FE-ARDL`))))

# ---- estabilidad por año
TAB_ESTAB <- WF %>% group_by(ANIO) %>%
  group_modify(~ map_dfr(c("Naive Lag1", "Ensamble informado"),
                         function(m) c(Modelo = m, as.list(metricas(.x$y, .x[[m]]))))) %>%
  ungroup() %>% mutate(across(MAE:sMAPE, as.numeric))

# ---- sensibilidad
escenarios <- list(
  "Base: ventana expansiva, 10 covariables, profundidad 2" = list(),
  "Ventana móvil de 4 años" = list(ventana = 4),
  "Ventana móvil de 3 años" = list(ventana = 3),
  "XGBoost con profundidad 3" = list(depth = 3),
  "Sin covariables de pérdidas climáticas" = list(cols = setdiff(XCOLS, c("pct_perd_helada", "pct_perd_sequia"))),
  "Solo riego, semilla y fertilizante" = list(cols = c("pct_area_con_riego", "pct_area_semilla_cert", "pct_fert")))
TAB_SENS <- imap_dfr(escenarios, function(a, nm) {
  w <- if (length(a) == 0) WF else do.call(walk_forward, c(list(datos = panel), a))
  c(Escenario = nm, as.list(metricas(w$y, w$`Ensamble informado`)))
}) %>% mutate(across(MAE:sMAPE, as.numeric))

# ---- calibración conformal vs gaussiana
TAB_CONF <- map_dfr(c(0.8, 0.9), function(nv) {
  a <- 1 - nv; z <- qnorm(1 - a / 2); f <- WF$`Ensamble informado`
  q <- if (nv == 0.8) WF$q80 else WF$q90
  bandas <- list("Gaussiano (sin calibrar)" = cbind(f - z * WF$sd_in, f + z * WF$sd_in),
                 "Split-conformal" = cbind(f - q, f + q))
  imap_dfr(bandas, function(b, met) {
    cub <- mean(WF$y >= b[, 1] & WF$y <= b[, 2])
    tibble(Nivel = paste0(100 * nv, " %"), Metodo = met, Cobertura = 100 * cub,
           Error = 100 * (cub - nv), Ancho = mean(b[, 2] - b[, 1]), Winkler = winkler(WF$y, b[, 1], b[, 2], a))
  })
})
cub_conf <- filter(TAB_CONF, Metodo == "Split-conformal")$Cobertura
cub_gaus <- filter(TAB_CONF, Metodo != "Split-conformal")$Cobertura
chequear("Predictivo", "Conformal mejora la cobertura respecto al gaussiano", all(cub_conf > cub_gaus))
chequear("Predictivo", "Cobertura conformal a menos de 10 pp del nominal",
         all(abs(filter(TAB_CONF, Metodo == "Split-conformal")$Error) < 10))

# ---- heladas
TAB_HEL <- WF %>% mutate(Regimen = if_else(helada >= 5, "Alta incidencia (>= 5 %)", "Baja incidencia (< 5 %)")) %>%
  group_by(Regimen) %>%
  group_modify(~ map_dfr(c("Naive Lag1", "Ensamble informado"),
                         function(m) c(Modelo = m, Obs = nrow(.x), as.list(metricas(.x$y, .x[[m]]))))) %>%
  ungroup() %>% mutate(across(c(Obs, MAE:sMAPE), as.numeric))
chequear("Predictivo", "33 casos con heladas >= 5 % (igual que el artículo)",
         sum(WF$helada >= 5) == 33, as.character(sum(WF$helada >= 5)))

# ---- SHAP y residuos
TAB_SHAP <- tibble(variable = c("Rendimiento año previo", unname(COVARIABLES)),
                   shap_medio = colMeans(abs(SHAP))[c("y_lag", XCOLS)]) %>% arrange(desc(shap_medio))
RES <- WF$y - WF$`Ensamble informado`
SHAPIRO <- shapiro.test(RES)

# ---- figuras
g5 <- WF %>% select(y, all_of(c("Naive Lag1", "XGBoost (prof. 2)", "Ensamble informado"))) %>%
  pivot_longer(-y, names_to = "Modelo", values_to = "f") %>%
  ggplot(aes(y, f, colour = Modelo, shape = Modelo)) + geom_abline(linetype = 2, linewidth = .3) +
  geom_point(alpha = .7, size = 1.4) +
  scale_colour_manual(values = c(COL[["rojo"]], COL[["gris"]], COL[["verde"]])) +
  scale_x_continuous(labels = scales::comma) + scale_y_continuous(labels = scales::comma) +
  labs(x = "Real (kg/ha)", y = "Pronosticado (kg/ha)", title = "Real vs. pronosticado (95 casos fuera de muestra)") +
  theme(legend.position = "bottom")
guardar_fig(g5, "r05_real_vs_pred.png", 5.6, 4.6)

g6 <- WF %>% arrange(`Ensamble informado`) %>% mutate(i = row_number(), f = `Ensamble informado`,
        z = qnorm(.9)) %>%
  { bind_rows(mutate(., Metodo = "Gaussiano (sin calibrar)", lo = f - z * sd_in, hi = f + z * sd_in),
              mutate(., Metodo = "Split-conformal", lo = f - q80, hi = f + q80)) } %>%
  mutate(fuera = y < lo | y > hi) %>%
  ggplot(aes(i)) + geom_ribbon(aes(ymin = lo, ymax = hi), fill = COL[["azul"]], alpha = .25) +
  geom_line(aes(y = f), colour = COL[["azul"]]) +
  geom_point(aes(y = y, colour = fuera, shape = fuera), size = 1) +
  scale_colour_manual(values = c(`FALSE` = "black", `TRUE` = COL[["rojo"]]), labels = c("Dentro", "Fuera")) +
  scale_shape_manual(values = c(16, 4), labels = c("Dentro", "Fuera")) +
  facet_wrap(~Metodo) + labs(x = "Casos ordenados por pronóstico", y = "kg/ha", colour = NULL, shape = NULL,
                             title = "Bandas de predicción al 80 %") + theme(legend.position = "bottom")
guardar_fig(g6, "r06_conformal.png", 7.6, 3.4)

g7 <- TAB_ESTAB %>% ggplot(aes(ANIO, RMSE, colour = Modelo)) + geom_line() + geom_point() +
  scale_colour_manual(values = c(COL[["rojo"]], COL[["gris"]])) +
  labs(x = "Año de prueba", y = "RMSE (kg/ha)", title = "Estabilidad del error por año") +
  theme(legend.position = "bottom")
g8 <- TAB_SHAP %>% ggplot(aes(shap_medio, reorder(variable, shap_medio))) + geom_col(fill = COL[["azul"]]) +
  labs(x = "Media |SHAP| (kg/ha)", y = NULL, title = "Importancia SHAP (XGBoost)")
guardar_fig(g7 + g8, "r07_estabilidad_shap.png", 8, 3.4)

g9 <- tibble(res = RES) %>% ggplot(aes(sample = res)) + stat_qq(colour = COL[["azul"]], size = 1) +
  stat_qq_line(colour = COL[["rojo"]]) + labs(title = sprintf("Q-Q de residuos (Shapiro p = %.3f)", SHAPIRO$p.value),
                                               x = "Teórico", y = "Residuo (kg/ha)")
g10 <- TAB_HEL %>% ggplot(aes(Regimen, MAE, fill = Modelo)) + geom_col(position = "dodge") +
  geom_text(aes(label = round(MAE)), position = position_dodge(.9), vjust = -.3, size = 2.6) +
  scale_fill_manual(values = c(COL[["rojo"]], COL[["gris"]])) +
  labs(x = NULL, y = "MAE (kg/ha)", title = "Error según incidencia de heladas") + theme(legend.position = "bottom")
guardar_fig(g9 + g10, "r08_residuos_heladas.png", 8, 3.4)

write_csv(WF, file.path(RUTAS$tab, "pronosticos_fuera_de_muestra.csv"))
write_csv(TAB_MODELOS, file.path(RUTAS$tab, "cuadro2_modelos.csv"))
write_csv(TAB_ESTAB, file.path(RUTAS$tab, "cuadro3_estabilidad.csv"))
write_csv(TAB_SENS, file.path(RUTAS$tab, "cuadro4_sensibilidad.csv"))
write_csv(TAB_CONF, file.path(RUTAS$tab, "cuadro5_conformal.csv"))
write_csv(TAB_HEL, file.path(RUTAS$tab, "cuadro6_heladas.csv"))
write_csv(SEMILLAS, file.path(RUTAS$tab, "xgboost_semillas.csv"))
write_csv(DIF_PY, file.path(RUTAS$tab, "validacion_vs_python.csv"))
write_csv(TAB_SHAP, file.path(RUTAS$tab, "shap_importancia.csv"))
write_csv(tibble(shapiro_p = SHAPIRO$p.value, media_residuo = mean(RES)), file.path(RUTAS$tab, "residuos_resumen.csv"))
message("Rama 4 OK: RMSE ensamble = ", round(TAB_MODELOS$RMSE[6], 2))
