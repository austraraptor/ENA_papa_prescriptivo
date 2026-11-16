# =============================================================================
# RAMA 5 - ANALÍTICA PRESCRIPTIVA
# RETO: con un presupuesto fijo por campaña, ¿en qué departamentos y en qué
# palancas (riego, semilla certificada, asistencia técnica, crédito) conviene
# invertir para obtener el mayor valor de producción adicional de papa,
# sin dejar de lado a los departamentos con riesgo de heladas?
#   5.1 alerta temprana 2026 (ensamble + intervalo conformal)  -> priorizados
#   5.2 efectos de las palancas (efectos fijos, EE agrupados)   -> beta y beta robusto
#   5.3 programa lineal (lpSolve), plan puntual y plan robusto
#   5.4 incertidumbre (Montecarlo), frontera de presupuesto, costo de la equidad
# =============================================================================
source(file.path(RAIZ, "R", "funciones_prescriptivas.R"))

# ---- 5.1 alerta temprana 2026 (supuesto: covariables 2026 = 2025, persistencia)
base25 <- filter(panel, ANIO == 2025)
te26 <- base25 %>% mutate(ANIO = 2026L, y_lag = y, y = NA_real_)
o26 <- ajustar_predecir(panel, te26)
oc25 <- ajustar_predecir(filter(panel, ANIO < 2025), base25)
q80_26 <- cuantil_conformal(abs(base25$y - oc25$pred$`Ensamble informado`), 0.8)
P25_hist <- panel %>% group_by(DEPARTAMENTO) %>% summarise(p25 = quantile(y, .25), media = mean(y),
                                                           helada_media = mean(pct_perd_helada[ANIO >= 2021]))
ALERTA <- tibble(DEPARTAMENTO = te26$DEPARTAMENTO, y_2025 = te26$y_lag,
                 pron_2026 = o26$pred$`Ensamble informado`) %>%
  mutate(lo80 = pron_2026 - q80_26, hi80 = pron_2026 + q80_26) %>%
  left_join(P25_hist, by = "DEPARTAMENTO") %>%
  mutate(alerta = pron_2026 < media,                  # caída esperada respecto a su media
         riesgo_bajo_p25 = lo80 < p25,                 # el intervalo alcanza su peor cuartil
         helada_alta = helada_media >= 5,               # >= 5 % de productores con pérdida (2021-2025)
         bajo_promedio = media < mean(xl_nac$rendimiento_kg_ha),
         prioritario = helada_alta & (alerta | bajo_promedio)) %>%
  arrange(pron_2026)
chequear("Prescriptivo", "Pronóstico 2026 completo y positivo", all(ALERTA$pron_2026 > 0) && nrow(ALERTA) == 19)
chequear("Prescriptivo", "Hay departamentos priorizados", any(ALERTA$prioritario), paste(ALERTA$DEPARTAMENTO[ALERTA$prioritario], collapse = ", "))

# ---- 5.2 efectos de las palancas
EFECTOS <- efectos_palancas(coef(M_EF), sqrt(diag(VC_EF)), PALANCAS)
VC_PAL <- VC_EF[PALANCAS$var, PALANCAS$var]
chequear("Prescriptivo", "Matriz de covarianza de palancas definida positiva",
         all(eigen(VC_PAL, only.values = TRUE)$values > 0))

INSUMOS <- base25 %>%
  transmute(DEPARTAMENTO, area = superficie_cosechada_ha, productores = productores_expandidos,
            precio = coalesce(precio_venta_kg, PRECIO_KG), y_2025 = y,
            pct_area_con_riego, pct_area_semilla_cert, pct_asist, pct_credito) %>%
  left_join(select(ALERTA, DEPARTAMENTO, prioritario, alerta, helada_alta), by = "DEPARTAMENTO")
chequear("Prescriptivo", "Insumos sin faltantes", !anyNA(INSUMOS))

# ---- 5.3 planes óptimos
PLAN_P <- optimizar_plan(INSUMOS, PALANCAS, EFECTOS, PRESUPUESTO, tipo = "puntual")
PLAN_R <- optimizar_plan(INSUMOS, PALANCAS, EFECTOS, PRESUPUESTO, tipo = "robusto")

validar_plan <- function(res, nombre) {
  pl <- res$plan; tol <- 1e-4
  chequear("Prescriptivo", paste(nombre, "- respeta el presupuesto"), res$gasto <= PRESUPUESTO * (1 + 1e-9))
  chequear("Prescriptivo", paste(nombre, "- respeta topes por palanca y 100 %"),
           all(pl$x >= -tol & pl$x <= pl$ub + tol) && all(pl$nivel + pl$x <= 100 + tol))
  chequear("Prescriptivo", paste(nombre, "- ningún departamento supera el 25 %"),
           all(tapply(pl$costo, pl$DEPARTAMENTO, sum) <= TOPE_DEPTO * PRESUPUESTO * (1 + 1e-9)))
  chequear("Prescriptivo", paste(nombre, "- cuota de equidad cumplida"),
           sum(pl$costo[pl$prioritario]) >= res$cuota_efectiva * PRESUPUESTO * (1 - 1e-9))
  chequear("Prescriptivo", paste(nombre, "- objetivo = suma de valores"), abs(res$objetivo - sum(pl$valor)) < 1e-3)
  # el óptimo debe superar a un reparto ingenuo factible (mismo gasto, proporcional a la capacidad)
  w <- pl$c * pl$ub; esc <- min(1, res$gasto / sum(w))
  chequear("Prescriptivo", paste(nombre, "- supera al reparto proporcional"), res$objetivo >= esc * sum(pl$v * pl$ub) - 1e-6)
}
validar_plan(PLAN_P, "Plan puntual"); validar_plan(PLAN_R, "Plan robusto")

# ---- 5.4 incertidumbre, frontera, equidad, costos
MC <- bind_rows(simular_plan(PLAN_P, EFECTOS, VC_EF) %>% mutate(plan = "Plan puntual"),
                simular_plan(PLAN_R, EFECTOS, VC_EF) %>% mutate(plan = "Plan robusto"))
TAB_MC <- MC %>% group_by(plan) %>%
  summarise(valor_medio = mean(valor), p05 = quantile(valor, .05), p95 = quantile(valor, .95),
            bc_medio = mean(bc), prob_bc_menor_1 = mean(bc < 1)) %>%
  bind_cols(bind_rows(distribucion_exacta(PLAN_P, EFECTOS, VC_EF), distribucion_exacta(PLAN_R, EFECTOS, VC_EF)))
chequear("Prescriptivo", "Montecarlo = distribución exacta (media a < 4 EE, P05 a < 0.1 DE)",
         all(abs(TAB_MC$valor_medio - TAB_MC$media_exacta) < 4 * TAB_MC$de_exacta / sqrt(N_MONTECARLO)) &&
           all(abs(TAB_MC$p05 - TAB_MC$p05_exacto) < 0.1 * TAB_MC$de_exacta))
chequear("Prescriptivo", "Media exacta = valor del plan puntual", abs(TAB_MC$media_exacta[1] / PLAN_P$objetivo - 1) < 1e-9)

FRONTERA <- expand_grid(B = seq(5e6, 300e6, by = 5e6), tipo = c("puntual", "robusto")) %>%
  mutate(r = map2(B, tipo, ~ optimizar_plan(INSUMOS, PALANCAS, EFECTOS, .x, tipo = .y)),
         valor = map_dbl(r, "objetivo"), gasto = map_dbl(r, "gasto"),
         precio_sombra = map_dbl(r, "precio_sombra")) %>% select(-r)
chequear("Prescriptivo", "Frontera no decreciente en el presupuesto",
         all(FRONTERA %>% group_by(tipo) %>% summarise(ok = all(diff(valor) >= -1e-6)) %>% pull(ok)))

# presupuesto eficiente: último nivel en que un sol adicional aún rinde más de un sol
B_EFICIENTE <- FRONTERA %>% group_by(tipo) %>% summarise(B_max_eficiente = max(B[precio_sombra >= 1]))
EQUIDAD <- tibble(cuota = c(0, 0.1, 0.2, 0.3, 0.4, 0.5)) %>%
  mutate(valor = map_dbl(cuota, ~ optimizar_plan(INSUMOS, PALANCAS, EFECTOS, PRESUPUESTO, cuota = .x)$objetivo),
         costo_equidad = first(valor) - valor)
COSTOS <- tibble(factor = c(0.5, 1, 1.5)) %>%
  mutate(valor = map_dbl(factor, function(f) { pa <- PALANCAS; pa$costo <- pa$costo * f
           optimizar_plan(INSUMOS, pa, EFECTOS, PRESUPUESTO)$objetivo }),
         bc = valor / PRESUPUESTO)

RES_P <- resumen_plan(PLAN_P); RES_R <- resumen_plan(PLAN_R)
POR_PALANCA <- bind_rows(RES_P %>% mutate(plan = "Plan puntual"), RES_R %>% mutate(plan = "Plan robusto")) %>%
  group_by(plan, palanca) %>% summarise(costo = sum(costo), t_adic = sum(t_adic), valor = sum(valor), .groups = "drop")

# ---- figuras
ga <- ALERTA %>% ggplot(aes(pron_2026, reorder(DEPARTAMENTO, pron_2026), colour = prioritario)) +
  geom_errorbarh(aes(xmin = lo80, xmax = hi80), height = .3) + geom_point() +
  geom_point(aes(x = media), shape = 124, size = 3, colour = "black") +
  scale_colour_manual(values = c(`FALSE` = COL[["azul"]], `TRUE` = COL[["rojo"]]), labels = c("No", "Sí")) +
  scale_x_continuous(labels = scales::comma) +
  labs(x = "Pronóstico 2026 e intervalo conformal 80 % (kg/ha); | = media 2015-2025",
       y = NULL, colour = "Priorizado", title = "Alerta temprana 2026") + theme(legend.position = "bottom")
guardar_fig(ga, "r09_alerta_2026.png", 6.4, 4.8)

gp <- bind_rows(RES_P %>% mutate(plan = "Plan puntual"), RES_R %>% mutate(plan = "Plan robusto")) %>%
  ggplot(aes(costo / 1e6, reorder(DEPARTAMENTO, costo, sum), fill = palanca)) + geom_col() +
  facet_wrap(~plan) + scale_fill_manual(values = c(COL[["verde"]], COL[["naranja"]], COL[["azul"]], COL[["rojo"]])) +
  labs(x = "Inversión asignada (millones de S/)", y = NULL, fill = NULL,
       title = sprintf("Asignación óptima de S/ %.0f millones", PRESUPUESTO / 1e6)) + theme(legend.position = "bottom")
guardar_fig(gp, "r10_plan_optimo.png", 7.6, 4.4)

gf <- FRONTERA %>% ggplot(aes(B / 1e6, valor / 1e6, colour = tipo)) + geom_line() + geom_point(size = .8) +
  geom_abline(linetype = 3) + scale_colour_manual(values = c(COL[["azul"]], COL[["rojo"]])) +
  labs(x = "Presupuesto (millones de S/)", y = "Valor adicional (millones de S/)", colour = "Efecto",
       title = "Frontera presupuesto-valor (punteada: B/C = 1)") + theme(legend.position = "bottom")
gm <- MC %>% ggplot(aes(bc, fill = plan)) + geom_density(alpha = .4) + geom_vline(xintercept = 1, linetype = 2) +
  scale_fill_manual(values = c(COL[["azul"]], COL[["rojo"]])) +
  labs(x = "Beneficio / costo (20 000 simulaciones)", y = "Densidad", fill = NULL, title = "Incertidumbre del plan") +
  theme(legend.position = "bottom")
guardar_fig(gf + gm, "r11_frontera_montecarlo.png", 8, 3.6)

write_csv(ALERTA, file.path(RUTAS$tab, "alerta_2026.csv"))
write_csv(EFECTOS, file.path(RUTAS$tab, "efectos_palancas.csv"))
write_csv(INSUMOS, file.path(RUTAS$tab, "insumos_prescriptivos.csv"))
write.csv(VC_PAL, file.path(RUTAS$tab, "vcov_palancas.csv"))
write_csv(PALANCAS, file.path(RUTAS$tab, "palancas_supuestos.csv"))
write_csv(RES_P, file.path(RUTAS$tab, "plan_puntual.csv"))
write_csv(RES_R, file.path(RUTAS$tab, "plan_robusto.csv"))
write_csv(POR_PALANCA, file.path(RUTAS$tab, "plan_por_palanca.csv"))
write_csv(TAB_MC, file.path(RUTAS$tab, "montecarlo_planes.csv"))
write_csv(FRONTERA, file.path(RUTAS$tab, "frontera_presupuesto.csv"))
write_csv(B_EFICIENTE, file.path(RUTAS$tab, "presupuesto_eficiente.csv"))
write_csv(EQUIDAD, file.path(RUTAS$tab, "costo_equidad.csv"))
write_csv(COSTOS, file.path(RUTAS$tab, "sensibilidad_costos.csv"))
message(sprintf("Rama 5 OK: plan puntual S/ %.1f M de valor; robusto S/ %.1f M",
                PLAN_P$objetivo / 1e6, PLAN_R$objetivo / 1e6))
