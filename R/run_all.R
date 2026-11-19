# =============================================================================
# PIPELINE COMPLETO EN R  -  Analítica prescriptiva de la papa (ENA 2015-2025)
# Uso:  Rscript R/run_all.R      (desde la raíz del proyecto)
#       o en RStudio: abrir ENA_papa_prescriptivo.Rproj y ejecutar source("R/run_all.R")
# Cada rama se detiene con un mensaje claro si alguna validación falla.
# =============================================================================
t0 <- Sys.time()
source("R/00_config.R")              # Rama 0: rutas y parámetros
source("R/01_librerias.R")           # Rama 1: librerías
source("R/02_datos_validacion.R")    # Rama 2: datos + validación
source("R/03_descriptivo_easystats.R")  # Rama 3: descriptivo + easystats
source("R/04_predictivo_walkforward.R") # Rama 4: predictivo (réplica del artículo)
source("R/05_prescriptivo.R")        # Rama 5: prescriptivo (programa lineal)
source("R/06_comunicacion_pruebas.R")   # Rama 6: Shiny + pruebas

# resumen en JSON para el informe y para comparar con Julia
resumen <- list(
  lenguaje = "R", version = R.version.string, segundos = as.numeric(difftime(Sys.time(), t0, units = "secs")),
  validaciones = nrow(VALIDACIONES), validaciones_ok = sum(VALIDACIONES$ok),
  modelos = TAB_MODELOS, conformal = TAB_CONF, heladas = TAB_HEL, sensibilidad = TAB_SENS,
  efectos = EFECTOS, alerta = ALERTA, plan_puntual = list(valor = PLAN_P$objetivo, gasto = PLAN_P$gasto,
  precio_sombra = PLAN_P$precio_sombra), plan_robusto = list(valor = PLAN_R$objetivo, gasto = PLAN_R$gasto,
  precio_sombra = PLAN_R$precio_sombra), por_palanca = POR_PALANCA, montecarlo = TAB_MC,
  equidad = EQUIDAD, presupuesto_eficiente = B_EFICIENTE, semillas = SEMILLAS)
jsonlite::write_json(resumen, file.path(RUTAS$out, "resumen_R.json"), auto_unbox = TRUE, digits = 10, pretty = TRUE)
message(sprintf("PIPELINE R TERMINADO en %.0f s - %d/%d validaciones aprobadas",
                resumen$segundos, resumen$validaciones_ok, resumen$validaciones))
