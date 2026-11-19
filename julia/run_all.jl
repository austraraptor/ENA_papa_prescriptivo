# =============================================================================
# PIPELINE COMPLETO EN JULIA - Analítica prescriptiva de la papa (ENA 2015-2025)
# Uso (desde la raíz del proyecto):
#   julia --project=julia -e 'using Pkg; Pkg.instantiate()'   # solo la primera vez
#   julia --project=julia julia/run_all.jl
# Conviene correr antes R/run_all.R: Julia compara sus resultados con los de R.
# =============================================================================
const T0 = time()
include("00_config.jl")              # Rama 0: rutas y parámetros
include("01_librerias.jl")           # Rama 1: librerías
include("02_datos_validacion.jl")    # Rama 2: datos + validación
include("03_descriptivo.jl")         # Rama 3: descriptivo + diagnóstico
include("04_predictivo.jl")          # Rama 4: predictivo (réplica del artículo)
include("05_prescriptivo.jl")        # Rama 5: prescriptivo (JuMP + HiGHS)
include("06_comunicacion_pruebas.jl")   # Rama 6: pruebas + ficha HTML

resumen = Dict("lenguaje" => "Julia", "version" => string(VERSION), "segundos" => time() - T0,
               "validaciones" => nrow(VALIDACIONES), "validaciones_ok" => sum(VALIDACIONES.ok),
               "xgboost_igual_python" => XGB_IGUAL_PY,
               "plan_puntual" => PLAN_P.objetivo, "plan_robusto" => PLAN_R.objetivo,
               "precio_sombra_puntual" => PLAN_P.precio_sombra, "precio_sombra_robusto" => PLAN_R.precio_sombra)
write(joinpath(RUTAS.out, "resumen_julia.json"), JSON.json(resumen))
println(@sprintf("PIPELINE JULIA TERMINADO en %.0f s - %d/%d validaciones aprobadas",
                 resumen["segundos"], resumen["validaciones_ok"], resumen["validaciones"]))
