# =============================================================================
# RAMA 2 - DATOS Y VALIDACIÓN
# 1) Verifica que los insumos existan y no hayan cambiado (SHA-256)
# 2) Reconstruye el panel departamental desde los microdatos (CSV)
# 3) Compara la reconstrucción con series_ENA_papa.xlsx (debe coincidir)
# 4) Arma el panel balanceado de análisis (19 departamentos x 10 años)
# =============================================================================

VALIDACIONES <- tibble(rama = character(), prueba = character(), ok = logical(), detalle = character())
chequear <- function(rama, prueba, condicion, detalle = "") {
  ok <- isTRUE(all(condicion))
  VALIDACIONES <<- add_row(VALIDACIONES, rama = rama, prueba = prueba, ok = ok, detalle = as.character(detalle))
  if (!ok) stop(sprintf("[VALIDACIÓN FALLIDA] %s - %s %s", rama, prueba, detalle), call. = FALSE)
  invisible(ok)
}

# ---- 2.1 integridad de archivos
for (k in names(SHA256)) {
  chequear("Datos", paste("Existe", basename(RUTAS[[k]])), file.exists(RUTAS[[k]]))
  h <- digest::digest(file = RUTAS[[k]], algo = "sha256")
  chequear("Datos", paste("SHA-256", basename(RUTAS[[k]])), h == SHA256[[k]], substr(h, 1, 12))
}

# ---- 2.2 lectura
xl_nac   <- read_excel(RUTAS$series, sheet = "serie_nacional")
xl_panel <- read_excel(RUTAS$series, sheet = "panel_departamental") %>%
  mutate(CCDD = as.integer(CCDD), ANIO = as.integer(ANIO))
xl_nac <- mutate(xl_nac, ANIO = as.integer(ANIO))
cult <- read_csv(RUTAS$cultivo, col_types = cols(CCDD = col_character(), .default = col_guess()),
                 show_col_types = FALSE)
prod <- read_csv(RUTAS$productores, col_types = cols(CCDD = col_character(), CCPP = col_character(),
                 CCDI = col_character(), CONGLO = col_character(), SEL = col_character(),
                 .default = col_double()), show_col_types = FALSE)
cult <- mutate(cult, ANIO = as.integer(ANIO))
prod <- mutate(prod, ANIO = as.integer(ANIO))

chequear("Datos", "Filas de cultivo = 139 466", nrow(cult) == 139466, format(nrow(cult)))
chequear("Datos", "Filas válidas = 129 915", sum(cult$valida) == 129915, format(sum(cult$valida)))
chequear("Datos", "Sin 2020 en microdatos", !any(cult$ANIO == 2020) && !any(prod$ANIO == 2020))
chequear("Datos", "Rendimiento de filas válidas en [300, 80 000] kg/ha",
         with(filter(cult, valida), all(produccion_kg / sup_ha >= 300 - 1e-9 &
                                          produccion_kg / sup_ha <= 80000 + 1e-9)))
chequear("Datos", "Factores de expansión positivos", all(cult$factor[cult$valida] > 0))

# ---- 2.3 reconstrucción desde microdatos
dep_cod <- function(x) as.integer(substr(x, 1, 2))

rec_cult <- cult %>%
  filter(valida) %>%
  mutate(CCDD = dep_cod(CCDD), wa = factor * sup_ha) %>%
  group_by(ANIO, CCDD) %>%
  summarise(produccion_t = sum(factor * produccion_kg) / 1000,
            superficie_cosechada_ha = sum(wa),
            rendimiento_kg_ha = 1000 * produccion_t / superficie_cosechada_ha,
            pct_area_con_riego = 100 * sum(wa * riego) / sum(wa),
            pct_area_semilla_cert = 100 * sum(wa * sem_cert) / sum(wa),
            .groups = "drop")

vars_prod <- c(fert = "pct_fert", abono = "pct_abono", asist = "pct_asist", capac = "pct_capac",
               asoc = "pct_asoc", seguro = "pct_seguro", credito = "pct_credito",
               perd_helada = "pct_perd_helada", perd_sequia = "pct_perd_sequia")
pct_pond <- function(x, w) {             # % ponderado sobre quienes respondieron
  ok <- !is.na(x) & !is.na(w)
  if (!any(ok)) return(NA_real_)
  100 * sum(w[ok] * x[ok]) / sum(w[ok])
}
rec_prod <- prod %>%
  filter(tiene_cultivo == 1, !is.na(w)) %>%
  mutate(CCDD = dep_cod(CCDD),
         # ENA 2025: el módulo de pérdidas solo lista a quienes perdieron -> el resto es 0
         across(c(perd_helada, perd_sequia), ~ if_else(ANIO == 2025 & is.na(.x), 0, .x))) %>%
  group_by(ANIO, CCDD) %>%
  summarise(productores_expandidos = sum(w),
            across(all_of(names(vars_prod)), ~ pct_pond(.x, w)), .groups = "drop") %>%
  rename(any_of(setNames(names(vars_prod), vars_prod)))

sin_dep <- filter(cult, valida, is.na(CCDD))
chequear("Datos", "Filas válidas sin ubigeo: 142 (solo 2024-2025; cuentan en la serie nacional)",
         nrow(sin_dep) == 142 && all(sin_dep$ANIO %in% c(2024, 2025)), nrow(sin_dep))
reconstruido <- inner_join(filter(rec_cult, !is.na(CCDD)), filter(rec_prod, !is.na(CCDD)), by = c("ANIO", "CCDD"))

# ---- 2.4 contraste con el Excel entregado
comparar <- c("rendimiento_kg_ha", "produccion_t", "superficie_cosechada_ha", "pct_area_con_riego",
              "pct_area_semilla_cert", unname(vars_prod))
cmp <- xl_panel %>% select(ANIO, CCDD, DEPARTAMENTO, all_of(comparar)) %>%
  inner_join(reconstruido, by = c("ANIO", "CCDD"), suffix = c("_xl", "_rec"))
chequear("Datos", "Mismo número de celdas año-departamento", nrow(cmp) == nrow(xl_panel),
         paste(nrow(cmp), "de", nrow(xl_panel)))
dif_max <- map_dbl(comparar, function(v) {
  a <- cmp[[paste0(v, "_xl")]]; b <- cmp[[paste0(v, "_rec")]]
  ok <- !(is.na(a) & is.na(b))
  max(abs(a[ok] - b[ok]), na.rm = FALSE)
})
TAB_RECONSTRUCCION <- tibble(variable = comparar, dif_abs_max = dif_max)
chequear("Datos", "Panel reconstruido = Excel (dif. < 1e-6)", all(dif_max < 1e-6),
         sprintf("máx = %.2e", max(dif_max)))

# serie nacional reconstruida
rec_nac <- cult %>% filter(valida) %>% group_by(ANIO) %>%
  summarise(y = sum(factor * produccion_kg) / sum(factor * sup_ha))
chequear("Datos", "Serie nacional reconstruida = Excel",
         max(abs(rec_nac$y - xl_nac$rendimiento_kg_ha[match(rec_nac$ANIO, xl_nac$ANIO)])) < 1e-6)

# ---- 2.5 panel balanceado de análisis
conteo <- count(xl_panel, DEPARTAMENTO)
DEPS <- conteo$DEPARTAMENTO[conteo$n == max(conteo$n)]
EXCLUIDOS <- conteo$DEPARTAMENTO[conteo$n < max(conteo$n)]

panel <- xl_panel %>%
  filter(DEPARTAMENTO %in% DEPS) %>%
  arrange(DEPARTAMENTO, ANIO) %>%
  group_by(DEPARTAMENTO) %>%
  mutate(credito_imputado = is.na(pct_credito)) %>%
  fill(pct_credito, .direction = "down") %>%   # solo hacia adelante: no usa información futura
  mutate(y = rendimiento_kg_ha, y_lag = lag(y)) %>%
  ungroup()

ANIOS <- sort(unique(panel$ANIO))
chequear("Datos", "Panel balanceado 19 x 10 = 190", length(DEPS) == 19 && nrow(panel) == 190)
chequear("Datos", "Excluidos solo Loreto y San Martín", setequal(EXCLUIDOS, c("Loreto", "San Martín")),
         paste(EXCLUIDOS, collapse = ", "))
chequear("Datos", "Sin duplicados año-departamento", !any(duplicated(panel[c("ANIO", "DEPARTAMENTO")])))
chequear("Datos", "Covariables en [0, 100] %", all(between(as.matrix(panel[XCOLS]), 0, 100), na.rm = TRUE))
chequear("Datos", "Sin faltantes en covariables tras imputar crédito", !anyNA(panel[XCOLS]))
chequear("Datos", "Crédito imputado solo en 2021", all(panel$ANIO[panel$credito_imputado] == 2021))
chequear("Datos", "y_lag de 2021 es el valor de 2019",
         with(panel, all(y_lag[ANIO == 2021] == y[ANIO == 2019][match(DEPARTAMENTO[ANIO == 2021],
                                                                      DEPARTAMENTO[ANIO == 2019])])))

write_csv(panel, file.path(RUTAS$tab, "panel_analisis.csv"))
write_csv(TAB_RECONSTRUCCION, file.path(RUTAS$tab, "validacion_reconstruccion.csv"))
message("Rama 2 OK: panel ", nrow(panel), " filas; reconstrucción máx dif = ", signif(max(dif_max), 3))
