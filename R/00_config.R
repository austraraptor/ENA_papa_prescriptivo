# =============================================================================
# RAMA 0 - RUTA DEL PIPELINE (configuración, rutas de datos y parámetros)
# Proyecto: Analítica prescriptiva del rendimiento de papa (ENA 2015-2025)
# Autor: Rodrigo Claudio Rosas Tuni - FINESI, UNA Puno
# Ejecutar desde la raíz del proyecto (abrir ENA_papa_prescriptivo.Rproj)
# =============================================================================

# Tildes y eñes: forzar UTF-8 si la sesión no lo está (Linux con locale C)
if (!isTRUE(l10n_info()[["UTF-8"]])) invisible(suppressWarnings(Sys.setlocale("LC_CTYPE", "C.UTF-8")))
options(encoding = "UTF-8", dplyr.summarise.inform = FALSE, readr.show_progress = FALSE)

RAIZ <- normalizePath(Sys.getenv("ENA_ROOT", unset = "."), mustWork = TRUE)

RUTAS <- list(
  cultivo     = file.path(RAIZ, "data", "raw", "ENA_cultivo_filas.csv"),
  productores = file.path(RAIZ, "data", "raw", "ENA_productores.csv"),
  series      = file.path(RAIZ, "data", "raw", "series_ENA_papa.xlsx"),
  ref_metric  = file.path(RAIZ, "data", "referencia", "metricas_articulo.csv"),
  ref_pron    = file.path(RAIZ, "data", "referencia", "pronosticos_python_articulo.csv"),
  out         = file.path(RAIZ, "outputs", "R"),
  fig         = file.path(RAIZ, "outputs", "R", "figuras"),
  tab         = file.path(RAIZ, "outputs", "R", "tablas")
)

# Huellas SHA-256 de los insumos: si alguien cambia un archivo, el pipeline se detiene
SHA256 <- c(
  cultivo     = "7ad30d56d047e88d77d648c883c5854f7cc49735a2745c379f154652e475e6a4",
  productores = "57988a3ad07fa83c63533a4fb6d196f7abafa42e1d68548d0e7c4431040401eb",
  series      = "37026ebabe7f09eca560e912da6033f2487d6a5098c6c4b7a1c00c01213bf3b3"
)

# ---- parámetros del modelo predictivo (fijados antes de evaluar, como en el artículo)
ANIOS_PRUEBA <- 2021:2025
SEMILLA      <- 7L
N_SEMILLAS_XGB <- 10L          # repeticiones de XGBoost para medir la variación por semilla
XGB_PARAMS <- list(nrounds = 300, max_depth = 2, eta = 0.05, subsample = 0.8,
                   colsample_bytree = 0.8, min_child_weight = 3, lambda = 5)
RIDGE_ALPHA <- 10
ENET_ALPHA  <- 50
ENET_L1     <- 0.5

COVARIABLES <- c(pct_area_con_riego = "Riego", pct_area_semilla_cert = "Semilla cert.",
                 pct_fert = "Fertilizante", pct_abono = "Abono", pct_asist = "Asist. técnica",
                 pct_capac = "Capacitación", pct_asoc = "Asociatividad", pct_credito = "Crédito",
                 pct_perd_helada = "Pérdida helada", pct_perd_sequia = "Pérdida sequía")
XCOLS <- names(COVARIABLES)

# ---- parámetros de la analítica prescriptiva (SUPUESTOS editables, ver informe)
# Palancas que un programa público puede mover. Costo unitario en soles:
#   base "area"        -> costo por hectárea adicional cubierta
#   base "productores" -> costo por productor adicional atendido
PALANCAS <- data.frame(
  var   = c("pct_area_con_riego", "pct_area_semilla_cert", "pct_asist", "pct_credito"),
  nombre = c("Riego tecnificado", "Semilla certificada", "Asistencia técnica", "Crédito agrario"),
  base  = c("area", "area", "productores", "productores"),
  # riego: inversión de S/ 15 000 por ha con vida útil de 10 años -> S/ 1 500 por ha y campaña
  costo = c(1500, 3000, 600, 500),        # S/ por ha o por productor y campaña (supuesto)
  tope_pp = c(10, 10, 15, 10),            # aumento máximo en puntos porcentuales por campaña
  stringsAsFactors = FALSE
)
PRESUPUESTO   <- 50e6      # S/ 50 millones por campaña (escenario base)
PRECIO_KG     <- 1.42      # S/ por kg (precio medio ENA 2025, serie nacional)
CUOTA_EQUIDAD <- 0.30      # al menos 30 % del presupuesto a departamentos priorizados
TOPE_DEPTO    <- 0.25      # ningún departamento recibe más del 25 % del presupuesto
Z_ROBUSTO     <- qnorm(0.90)  # efecto conservador = beta - 1.28 EE (cota inferior 80 %)
N_MONTECARLO  <- 20000L

for (d in c(RUTAS$out, RUTAS$fig, RUTAS$tab)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
