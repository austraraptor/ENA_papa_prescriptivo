# Pruebas del tablero Shiny
#  1) shiny::testServer  -> lógica del servidor sin navegador (siempre se ejecuta)
#  2) shinytest2::AppDriver -> prueba de extremo a extremo con Chrome (si está instalado)
suppressPackageStartupMessages({ library(testthat); library(shiny) })
RAIZ_T <- normalizePath(Sys.getenv("ENA_ROOT", unset = file.path(getwd(), "..", "..")))
Sys.setenv(ENA_ROOT = RAIZ_T)
APP <- file.path(RAIZ_T, "R", "app")

test_that("el servidor recalcula el plan al cambiar presupuesto y tipo de efecto", {
  testServer(shinyAppDir(APP), {
    session$setInputs(presupuesto = 50, tipo = "robusto", cuota = 30, tope = 25,
                      c_riego = 1500, c_semilla = 3000, c_asist = 600, c_credito = 500)
    v_rob <- solucion()$objetivo
    expect_true(solucion()$gasto <= 50e6 + 1)
    expect_match(output$kpi_valor, "^S/ [0-9.]+ millones$")
    session$setInputs(tipo = "puntual")
    expect_gt(solucion()$objetivo, v_rob)              # el efecto puntual es mayor que el robusto
    session$setInputs(presupuesto = 100)
    expect_true(solucion()$gasto > 50e6)               # más presupuesto -> más gasto
    session$setInputs(c_semilla = 0)                   # costo inválido -> mensaje de validación
    expect_error(palancas(), class = "shiny.silent.error")
  })
})

test_that("shinytest2: la app abre y muestra los indicadores", {
  skip_if_not_installed("shinytest2")
  skip_if(is.null(tryCatch(chromote::find_chrome(), error = function(e) NULL)), "Chrome no disponible")
  app <- shinytest2::AppDriver$new(APP, name = "tablero", height = 900, width = 1300, load_timeout = 60000)
  on.exit(app$stop(), add = TRUE)
  app$set_inputs(presupuesto = 80)
  app$wait_for_idle()
  expect_match(app$get_value(output = "kpi_valor"), "millones")
  expect_match(app$get_value(output = "kpi_bc"), "^[0-9]+\\.[0-9]{2}$")
  app$set_inputs(tipo = "puntual")
  expect_match(app$get_value(output = "kpi_t"), " t$")
})
