# =============================================================================
# RAMA 3 - DESCRIPTIVO Y DIAGNÓSTICO (tidyverse + easystats)
# Reproduce el Cuadro 1 y las correlaciones del artículo, y diagnostica el
# modelo explicativo de efectos fijos que usará la analítica prescriptiva.
# =============================================================================

ref_cuadro1 <- tribble(~DEPARTAMENTO, ~media_art,
  "Lima", 23175.93, "Ica", 22924.56, "Arequipa", 20976.80, "Puno", 6017.71,
  "Lambayeque", 4037.20, "Cusco", 7298.62, "Junín", 13488.40)

TAB_DESC <- panel %>% group_by(DEPARTAMENTO) %>%
  summarise(anios = n(), media = mean(y), de = sd(y), minimo = min(y), maximo = max(y)) %>%
  arrange(desc(media))
nac_y <- xl_nac$rendimiento_kg_ha
TAB_DESC <- bind_rows(TAB_DESC, tibble(DEPARTAMENTO = "Promedio nacional", anios = length(nac_y),
                                       media = mean(nac_y), de = sd(nac_y),
                                       minimo = min(nac_y), maximo = max(nac_y)))
chk <- inner_join(TAB_DESC, ref_cuadro1, by = "DEPARTAMENTO")
chequear("Descriptivo", "Medias = Cuadro 1 del artículo (±0.01)", all(abs(chk$media - chk$media_art) < 0.01))
chequear("Descriptivo", "Media nacional = 11 138.60", abs(mean(nac_y) - 11138.60) < 0.01)
write_csv(TAB_DESC, file.path(RUTAS$tab, "cuadro1_descriptivos.csv"))

# ---- correlaciones con easystats::correlation
nombres_cov <- c(Rendimiento = "y", setNames(XCOLS, COVARIABLES))
COR <- panel %>% select(all_of(nombres_cov)) %>% correlation::correlation(method = "pearson")
COR_Y <- COR %>% as_tibble() %>% filter(Parameter1 == "Rendimiento") %>%
  select(variable = Parameter2, r, p) %>% arrange(desc(r))
ref_r <- c("Crédito" = 0.55, "Semilla cert." = 0.49, "Riego" = 0.45, "Asist. técnica" = 0.41,
           "Pérdida helada" = -0.16)
chequear("Descriptivo", "Correlaciones = artículo (±0.005)",
         all(abs(COR_Y$r[match(names(ref_r), COR_Y$variable)] - ref_r) < 0.005))
write_csv(COR_Y, file.path(RUTAS$tab, "correlaciones_rendimiento.csv"))

# ---- figuras descriptivas
f1 <- bind_rows(panel %>% filter(DEPARTAMENTO %in% c("Puno", "Junín", "Arequipa", "Cusco")) %>%
                  select(ANIO, serie = DEPARTAMENTO, y),
                tibble(ANIO = xl_nac$ANIO, serie = "Nacional", y = nac_y)) %>%
  ggplot(aes(ANIO, y, colour = serie, linewidth = serie == "Nacional")) +
  annotate("rect", xmin = 2019.5, xmax = 2020.5, ymin = -Inf, ymax = Inf, alpha = .2, fill = "grey60") +
  geom_line() + geom_point(size = 1.2) +
  scale_linewidth_manual(values = c(0.5, 1.2), guide = "none") +
  scale_colour_manual(values = c(Arequipa = COL[["naranja"]], Cusco = "#7B5EA7", Junín = COL[["verde"]],
                                 Nacional = "black", Puno = COL[["rojo"]])) +
  scale_x_continuous(breaks = 2015:2025) + scale_y_continuous(labels = scales::comma) +
  labs(x = NULL, y = "Rendimiento (kg/ha)", colour = NULL,
       title = "Rendimiento de papa, Perú 2015–2025 (franja gris: 2020 sin ENA)") +
  theme(legend.position = "top")
guardar_fig(f1, "r01_evolucion.png", 7, 3.4)

f2 <- TAB_DESC %>% filter(DEPARTAMENTO != "Promedio nacional") %>%
  ggplot(aes(media, reorder(DEPARTAMENTO, media))) +
  geom_col(fill = COL[["azul"]], alpha = .85) +
  geom_errorbarh(aes(xmin = media - de, xmax = media + de), height = .3, linewidth = .3) +
  scale_x_continuous(labels = scales::comma) +
  labs(x = "Rendimiento medio ± 1 DE (kg/ha)", y = NULL, title = "Heterogeneidad entre departamentos")
guardar_fig(f2, "r02_departamentos.png", 6, 4.4)

f3 <- COR %>% summary(redundant = TRUE) %>% as_tibble() %>%
  pivot_longer(-Parameter, names_to = "v2", values_to = "r") %>%
  mutate(Parameter = factor(Parameter, levels = names(nombres_cov)),
         v2 = factor(v2, levels = names(nombres_cov))) %>%
  ggplot(aes(v2, Parameter, fill = r)) + geom_tile(colour = "white") +
  geom_text(aes(label = sprintf("%.2f", r)), size = 2) +
  scale_fill_gradient2(low = COL[["azul"]], high = COL[["rojo"]], limits = c(-1, 1)) +
  labs(x = NULL, y = NULL, title = "Correlación de Pearson (panel 19 × 10)") +
  theme(axis.text.x = element_text(angle = 50, hjust = 1))
guardar_fig(f3, "r03_correlacion.png", 6.4, 5.2)

# ---- modelo explicativo: efectos fijos por departamento y año (base de la prescripción)
form_ef <- as.formula(paste("y ~", paste(XCOLS, collapse = " + "), "+ factor(DEPARTAMENTO) + factor(ANIO)"))
M_EF <- lm(form_ef, data = panel)
VC_EF <- sandwich::vcovCL(M_EF, cluster = ~DEPARTAMENTO, type = "HC1")   # CR1 agrupado

PAR_EF <- parameters::model_parameters(M_EF, vcov = VC_EF, keep = paste0("^(", paste(XCOLS, collapse = "|"), ")$")) %>%
  as_tibble() %>% select(variable = Parameter, beta = Coefficient, ee = SE, ic_inf = CI_low,
                         ic_sup = CI_high, t = t, p = p)
PERF_EF <- performance::model_performance(M_EF) %>% as_tibble()
DIAG_EF <- tibble(
  prueba = c("Heterocedasticidad (Breusch-Pagan)", "Normalidad de residuos (Shapiro-Wilk)",
             "Autocorrelación (Durbin-Watson)", "VIF máximo de covariables"),
  p_valor = c(as.numeric(performance::check_heteroscedasticity(M_EF)),
              as.numeric(performance::check_normality(M_EF)),
              as.numeric(performance::check_autocorrelation(M_EF)), NA),
  valor = c(NA, NA, NA, max(performance::check_collinearity(lm(as.formula(paste("y ~", paste(XCOLS, collapse = "+"))), data = panel))$VIF)))
write_csv(PAR_EF, file.path(RUTAS$tab, "efectos_fijos_parametros.csv"))
write_csv(DIAG_EF, file.path(RUTAS$tab, "efectos_fijos_diagnostico.csv"))
chequear("Descriptivo", "Modelo EF estimado con 190 obs. y sin coeficientes NA",
         nobs(M_EF) == 190 && !anyNA(coef(M_EF)[XCOLS]))

png(file.path(RUTAS$fig, "r04_check_model.png"), width = 2000, height = 1700, res = 200)
print(plot(performance::check_model(M_EF, check = c("linearity", "homogeneity", "qq", "outliers"))))
dev.off()

REPORTE_EF <- tryCatch(paste(capture.output(print(report::report_performance(M_EF))), collapse = " "),
                       error = function(e) "report no disponible")
message("Rama 3 OK: R2 within-panel = ", round(PERF_EF$R2, 3))
