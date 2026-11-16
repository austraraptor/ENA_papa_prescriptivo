# =============================================================================
# RAMA 0 - RUTA DEL PIPELINE (configuración, rutas y parámetros) - Julia
# Proyecto: Analítica prescriptiva del rendimiento de papa (ENA 2015-2025)
# Autor: Rodrigo Claudio Rosas Tuni - FINESI, UNA Puno
# =============================================================================

const RAIZ = normpath(get(ENV, "ENA_ROOT", joinpath(@__DIR__, "..")))

const RUTAS = (
    cultivo     = joinpath(RAIZ, "data", "raw", "ENA_cultivo_filas.csv"),
    productores = joinpath(RAIZ, "data", "raw", "ENA_productores.csv"),
    series      = joinpath(RAIZ, "data", "raw", "series_ENA_papa.xlsx"),
    ref_metric  = joinpath(RAIZ, "data", "referencia", "metricas_articulo.csv"),
    ref_pron    = joinpath(RAIZ, "data", "referencia", "pronosticos_python_articulo.csv"),
    tab_R       = joinpath(RAIZ, "outputs", "R", "tablas"),        # para la verificación cruzada R vs Julia
    out         = joinpath(RAIZ, "outputs", "julia"),
    fig         = joinpath(RAIZ, "outputs", "julia", "figuras"),
    tab         = joinpath(RAIZ, "outputs", "julia", "tablas"),
)

const SHA256_ESPERADO = Dict(
    :cultivo     => "7ad30d56d047e88d77d648c883c5854f7cc49735a2745c379f154652e475e6a4",
    :productores => "57988a3ad07fa83c63533a4fb6d196f7abafa42e1d68548d0e7c4431040401eb",
    :series      => "37026ebabe7f09eca560e912da6033f2487d6a5098c6c4b7a1c00c01213bf3b3",
)

# ---- modelo predictivo (fijado antes de evaluar, igual que el artículo)
const ANIOS_PRUEBA = 2021:2025
const SEMILLA = 7
const N_SEMILLAS_XGB = 10
const XGB_PARAMS = (num_round = 300, eta = 0.05, subsample = 0.8, colsample_bytree = 0.8,
                    min_child_weight = 3, lambda = 5.0)
const RIDGE_ALPHA = 10.0
const ENET_ALPHA = 50.0
const ENET_L1 = 0.5

const XCOLS = ["pct_area_con_riego", "pct_area_semilla_cert", "pct_fert", "pct_abono", "pct_asist",
               "pct_capac", "pct_asoc", "pct_credito", "pct_perd_helada", "pct_perd_sequia"]
const NOMBRES_COV = Dict(zip(XCOLS, ["Riego", "Semilla cert.", "Fertilizante", "Abono", "Asist. técnica",
                                     "Capacitación", "Asociatividad", "Crédito", "Pérdida helada", "Pérdida sequía"]))

# ---- analítica prescriptiva (SUPUESTOS editables, ver informe)
# riego: inversión S/ 15 000 por ha con vida útil de 10 años -> S/ 1 500 por ha y campaña
const PALANCAS = (
    var     = ["pct_area_con_riego", "pct_area_semilla_cert", "pct_asist", "pct_credito"],
    nombre  = ["Riego tecnificado", "Semilla certificada", "Asistencia técnica", "Crédito agrario"],
    base    = ["area", "area", "productores", "productores"],
    costo   = [1500.0, 3000.0, 600.0, 500.0],   # S/ por ha o por productor y campaña
    tope_pp = [10.0, 10.0, 15.0, 10.0],          # aumento máximo en puntos porcentuales
)
const PRESUPUESTO   = 50e6
const PRECIO_KG     = 1.42
const CUOTA_EQUIDAD = 0.30
const TOPE_DEPTO    = 0.25
const Z_ROBUSTO     = 1.2815515655446004   # cuantil 0.90 de la normal estándar
const N_MONTECARLO  = 20000

foreach(d -> mkpath(d), (RUTAS.out, RUTAS.fig, RUTAS.tab))
