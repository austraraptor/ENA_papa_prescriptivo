# Analítica prescriptiva del rendimiento de papa (ENA 2015–2025) — R y Julia

Autor: Rodrigo Claudio Rosas Tuni — FINESI, UNA Puno.

Reto: con S/ 50 millones por campaña, decidir en qué departamentos y en qué palancas
(riego, semilla certificada, asistencia técnica, crédito) invertir para obtener el mayor valor
de producción adicional de papa, protegiendo a los departamentos con heladas frecuentes.

## Ramas del pipeline (iguales en R y Julia)

| Rama | R | Julia | Qué hace |
|---|---|---|---|
| 0 | `R/00_config.R` | `julia/00_config.jl` | Rutas, huellas SHA-256, parámetros y supuestos |
| 1 | `R/01_librerias.R` | `julia/01_librerias.jl` | Librerías (tidyverse, caret, easystats, xgboost, lpSolve, shiny, shinytest2 / DataFrames, XGBoost, JuMP+HiGHS, Plots, Test) |
| 2 | `R/02_datos_validacion.R` | `julia/02_datos_validacion.jl` | Reconstruye el panel desde los microdatos y lo contrasta con el Excel |
| 3 | `R/03_descriptivo_easystats.R` | `julia/03_descriptivo.jl` | Descriptivos, correlaciones, efectos fijos y diagnóstico |
| 4 | `R/04_predictivo_walkforward.R` | `julia/04_predictivo.jl` | Réplica del artículo: walk-forward, conformal, heladas, SHAP |
| 5 | `R/05_prescriptivo.R` | `julia/05_prescriptivo.jl` | Alerta 2026, programa lineal, Montecarlo, frontera de presupuesto |
| 6 | `R/06_comunicacion_pruebas.R` | `julia/06_comunicacion_pruebas.jl` | Shiny + pruebas / pruebas + comparación R–Julia + ficha HTML |

## Cómo ejecutar

```bash
# R (desde la raíz; o abrir ENA_papa_prescriptivo.Rproj en RStudio y source("R/run_all.R"))
Rscript R/run_all.R
Rscript -e 'shiny::runApp("R/app")'          # tablero
Rscript -e 'testthat::test_dir("R/tests")'   # pruebas (shinytest2 necesita Chrome y NOT_CRAN=true)

# Julia (correr R antes para que Julia compare sus resultados)
julia --project=julia -e 'using Pkg; Pkg.instantiate()'
cd julia && julia --project=. run_all.jl
```

Paquetes de R necesarios: tidyverse, readxl, writexl, caret, easystats, xgboost (>= 3.0 para
reproducir exactamente el XGBoost del artículo), glmnet, sandwich, lpSolve, shiny, shinytest2,
testthat, patchwork, ggrepel, digest, jsonlite.

## Resultados

- `informes/Informe_LatinR_R_ENA_papa.pdf` y `informes/Informe_LatinR_Julia_ENA_papa.pdf` (formato LatinR).
- `outputs/R/` y `outputs/julia/`: tablas CSV, figuras, logs, `registro_validaciones.csv`, resumen JSON.
- `outputs/julia/ficha_decision.html`: ficha de decisión para autoridades.
- `informes/generar_informes.py` arma los dos informes leyendo las tablas (ninguna cifra se copia a mano).

Los costos unitarios de las palancas son supuestos (editables en `00_config` y en el tablero).
