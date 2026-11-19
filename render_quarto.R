# =============================================================================
# Script de Renderizado y Validación Integral del Entorno Quarto Reproducible
# Proyecto: Analítica prescriptiva del rendimiento de papa (ENA 2015-2025)
# =============================================================================

quarto_bin <- Sys.which("quarto")
if (quarto_bin == "") {
  candidatos <- c(
    "C:/Users/cuervo/AppData/Local/Programs/Positron/resources/app/quarto/bin/quarto.exe",
    "C:/Program Files/Quarto/bin/quarto.exe"
  )
  for (c in candidatos) {
    if (file.exists(c)) {
      quarto_bin <- c
      break
    }
  }
}

if (quarto_bin == "" || !file.exists(quarto_bin)) {
  stop("No se encontró el ejecutable de Quarto en el sistema ni en Positron.")
}

message("[INFO] Usando ejecutable Quarto: ", quarto_bin)
system2(quarto_bin, args = c("--version"))

message("[INFO] Iniciando renderizado completo del proyecto Quarto...")
res <- system2(quarto_bin, args = c("render", "quarto"))

if (res == 0) {
  message("[ÉXITO] El entorno Quarto se compiló satisfactoriamente en 'quarto/_site/'.")
  archivos <- list.files("quarto/_site", pattern = "\\.html$")
  message("Páginas generadas:")
  for (a in archivos) {
    message(" - quarto/_site/", a)
  }
} else {
  stop("[ERROR] Ocurrió un fallo durante la compilación de Quarto (código ", res, ").")
}
