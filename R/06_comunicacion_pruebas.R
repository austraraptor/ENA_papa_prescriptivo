# =============================================================================
# RAMA 6 - COMUNICACIÓN Y PRUEBAS
# Corre las pruebas (testthat + testServer + shinytest2), captura el tablero
# y guarda el registro de validaciones y versiones.
# =============================================================================
Sys.setenv(ENA_ROOT = RAIZ, NOT_CRAN = "true")
res_tests <- as.data.frame(testthat::test_dir(file.path(RAIZ, "R", "tests"), reporter = "silent",
                                              stop_on_failure = FALSE))
TAB_TESTS <- tibble(archivo = res_tests$file, prueba = res_tests$test,
                    aprobadas = res_tests$nb - res_tests$failed, fallidas = res_tests$failed,
                    omitida = res_tests$skipped)
chequear("Comunicación", "Pruebas testthat/Shiny sin fallas", sum(TAB_TESTS$fallidas) == 0,
         sprintf("%d expectativas, %d omitidas", sum(res_tests$nb), sum(TAB_TESTS$omitida)))

# captura del tablero para el informe (requiere Chrome)
cap <- file.path(RUTAS$fig, "r12_tablero_shiny.png")
ok_cap <- tryCatch({
  app <- shinytest2::AppDriver$new(file.path(RAIZ, "R", "app"), height = 1000, width = 1400, load_timeout = 60000)
  app$set_inputs(presupuesto = 50, tipo = "robusto", wait_ = FALSE); app$wait_for_idle(2000)
  app$get_screenshot(cap, selector = "viewport"); app$stop(); TRUE
}, error = function(e) { message("Captura omitida: ", conditionMessage(e)); FALSE })

write_csv(TAB_TESTS, file.path(RUTAS$tab, "pruebas_testthat.csv"))
write_csv(VALIDACIONES, file.path(RUTAS$tab, "registro_validaciones.csv"))
write_csv(VERSIONES, file.path(RUTAS$tab, "versiones_paquetes.csv"))
message("Rama 6 OK: ", nrow(VALIDACIONES), " validaciones, todas aprobadas = ", all(VALIDACIONES$ok))
