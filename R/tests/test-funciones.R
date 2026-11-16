# Pruebas unitarias de las funciones del pipeline (testthat)
# Ejecutar: testthat::test_dir("R/tests")  desde la raíz del proyecto
suppressPackageStartupMessages({ library(testthat); library(tidyverse) })
RAIZ_T <- normalizePath(Sys.getenv("ENA_ROOT", unset = file.path(getwd(), "..", "..")))
Sys.setenv(ENA_ROOT = RAIZ_T)
source(file.path(RAIZ_T, "R", "00_config.R"))
source(file.path(RAIZ_T, "R", "funciones_modelos.R"))
source(file.path(RAIZ_T, "R", "funciones_prescriptivas.R"))

test_that("escalador replica StandardScaler (media 0, DE poblacional 1)", {
  set.seed(1); X <- matrix(rnorm(60, 5, 3), 20)
  A <- escalador(X)$aplicar(X)
  expect_equal(unname(colMeans(A)), rep(0, 3), tolerance = 1e-12)
  expect_equal(unname(sqrt(colMeans(A^2))), rep(1, 3), tolerance = 1e-12)
})

test_that("Ridge con alpha -> 0 coincide con MCO", {
  set.seed(2); A <- scale(matrix(rnorm(100), 25)); y <- drop(A %*% c(1, -2, .5, 3) + rnorm(25))
  r <- ridge_ajustar(A, y, 1e-10)
  expect_equal(unname(r$b), unname(coef(lm(y ~ A))[-1]), tolerance = 1e-6)
})

test_that("ElasticNet cumple KKT y anula todo con penalización grande", {
  set.seed(3); A <- scale(matrix(rnorm(200), 40)); y <- drop(A %*% c(2, 0, -1, 0, 1) + rnorm(40))
  f <- enet_ajustar(A, y, 0.3, 0.5)
  expect_true(all(enet_kkt(A, y, f, 0.3, 0.5) < 1e-8))
  expect_true(all(enet_ajustar(A, y, 1e4, 0.5)$b == 0))
})

test_that("métricas y cuantil conformal en casos conocidos", {
  m <- metricas(c(100, 200), c(110, 180))
  expect_equal(m[["MAE"]], 15); expect_equal(m[["RMSE"]], sqrt((100 + 400) / 2))
  expect_equal(cuantil_conformal(1:19, 0.8), 16)   # ceiling(20 * 0.8) = 16
  expect_equal(cuantil_conformal(1:19, 0.9), 18)
  expect_equal(cuantil_conformal(1:5, 0.99), 5)    # se acota a n
  expect_equal(winkler(c(5, 0), c(4, 1), c(6, 2), 0.2), mean(c(2, 1 + 10 * 1)))
})

test_that("programa lineal: caso de juguete con solución conocida", {
  ins <- tibble(DEPARTAMENTO = c("A", "B"), area = c(100, 100), productores = c(10, 10), precio = c(1, 2),
                pct_area_con_riego = 0, pct_area_semilla_cert = c(0, 95), pct_asist = 0, pct_credito = 0,
                prioritario = c(TRUE, FALSE))
  pal <- data.frame(var = "pct_area_semilla_cert", nombre = "Semilla", base = "area", costo = 100, tope_pp = 10)
  ef <- tibble(var = "pct_area_semilla_cert", beta = 10, ee = 1, beta_puntual = 10, beta_robusto = 8)
  # B tiene doble precio pero solo puede subir 5 pp (95 % -> 100 %); cada pp cuesta S/ 100
  r <- optimizar_plan(ins, pal, ef, presupuesto = 800, cuota = 0, tope_depto = 1)
  x <- setNames(r$plan$x, r$plan$DEPARTAMENTO)
  expect_equal(unname(x["B"]), 5); expect_equal(unname(x["A"]), 3)
  expect_equal(r$objetivo, 5 * 10 * 100 * 2 + 3 * 10 * 100 * 1)
  # con cuota 100 % todo va al priorizado A (hasta su tope de 10 pp = S/ 1000)
  r2 <- optimizar_plan(ins, pal, ef, presupuesto = 800, cuota = 1, tope_depto = 1)
  expect_equal(sum(r2$plan$costo[r2$plan$DEPARTAMENTO == "A"]), 800)
  # el plan robusto usa beta 8
  expect_equal(optimizar_plan(ins, pal, ef, 800, 0, 1, tipo = "robusto")$objetivo, r$objetivo * 0.8)
})

test_that("efectos robustos nunca son negativos", {
  e <- efectos_palancas(c(a = 5, b = -2), c(a = 10, b = 1), data.frame(var = c("a", "b")))
  expect_true(all(e$beta_robusto >= 0)); expect_equal(e$beta_robusto, c(0, 0))
})
