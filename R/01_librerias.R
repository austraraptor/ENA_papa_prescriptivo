# =============================================================================
# RAMA 1 - LIBRERÍAS
#   tidyverse  : lectura, limpieza, agregación y gráficos
#   caret      : interfaz común de modelos con índices walk-forward propios
#   easystats  : performance, parameters, correlation, see, report (diagnóstico)
#   xgboost    : árbol restringido + SHAP exacto (predcontrib)
#   glmnet     : verificación cruzada de ElasticNet
#   sandwich   : errores estándar agrupados por departamento
#   lpSolve    : optimización lineal (analítica prescriptiva)
#   shiny / shinytest2 / testthat : comunicación y pruebas
# =============================================================================

PAQUETES <- c("tidyverse", "readxl", "writexl", "caret", "easystats", "xgboost", "glmnet",
              "sandwich", "lpSolve", "shiny", "shinytest2", "testthat", "patchwork",
              "ggrepel", "digest", "jsonlite")

faltan <- PAQUETES[!vapply(PAQUETES, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltan) > 0) {
  stop("Faltan paquetes: ", paste(faltan, collapse = ", "),
       "\nInstálelos con install.packages(c('", paste(faltan, collapse = "','"), "'))")
}

suppressPackageStartupMessages({
  library(tidyverse)
  library(readxl)
  library(caret)
  library(easystats)
  library(xgboost)
  library(sandwich)
  library(lpSolve)
  library(patchwork)
  library(ggrepel)
})

VERSIONES <- tibble(paquete = c("R", PAQUETES),
                    version = c(paste(R.version$major, R.version$minor, sep = "."),
                                vapply(PAQUETES, function(p) as.character(packageVersion(p)), "")))

# Paleta y tema comunes para todas las figuras
COL <- c(azul = "#2F5D8C", rojo = "#B03A2E", gris = "#8C8C8C", verde = "#3B8C5A", naranja = "#D98E04")
theme_set(theme_minimal(base_size = 9) +
            theme(panel.grid.minor = element_blank(), plot.title = element_text(face = "bold", size = 10)))
guardar_fig <- function(g, nombre, w = 7, h = 3.6) {
  ggsave(file.path(RUTAS$fig, nombre), g, width = w, height = h, dpi = 200, bg = "white")
  invisible(nombre)
}
