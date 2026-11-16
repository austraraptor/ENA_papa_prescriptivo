# =============================================================================
# RAMA 6 - COMUNICACIÓN: tablero Shiny "¿Dónde invertir en papa?"
# Lee los insumos que deja la rama 5 y resuelve el programa lineal en vivo.
# Ejecutar desde la raíz:  shiny::runApp("R/app")
# =============================================================================
library(shiny)
suppressPackageStartupMessages({ library(tidyverse) })

raiz_app <- normalizePath(Sys.getenv("ENA_ROOT", unset = file.path(getwd(), "..", "..")), mustWork = FALSE)
if (!file.exists(file.path(raiz_app, "R", "00_config.R"))) raiz_app <- normalizePath(".")
Sys.setenv(ENA_ROOT = raiz_app)
source(file.path(raiz_app, "R", "00_config.R"), local = TRUE)
source(file.path(raiz_app, "R", "funciones_prescriptivas.R"), local = TRUE)

tab <- file.path(raiz_app, "outputs", "R", "tablas")
INS <- read_csv(file.path(tab, "insumos_prescriptivos.csv"), show_col_types = FALSE)
EFE <- read_csv(file.path(tab, "efectos_palancas.csv"), show_col_types = FALSE)
PAL <- read_csv(file.path(tab, "palancas_supuestos.csv"), show_col_types = FALSE) %>% as.data.frame()

ui <- fluidPage(
  titlePanel("¿Dónde invertir para producir más papa? — ENA 2015–2025"),
  sidebarLayout(
    sidebarPanel(width = 3,
      sliderInput("presupuesto", "Presupuesto (millones de S/)", 5, 300, PRESUPUESTO / 1e6, step = 5),
      radioButtons("tipo", "Efecto de las palancas",
                   c("Robusto (cota inferior 80 %)" = "robusto", "Puntual (estimado)" = "puntual")),
      sliderInput("cuota", "Mínimo para departamentos priorizados (%)", 0, 60, 100 * CUOTA_EQUIDAD, step = 5),
      sliderInput("tope", "Máximo por departamento (%)", 10, 100, 100 * TOPE_DEPTO, step = 5),
      tags$hr(), tags$b("Costos unitarios (supuestos)"),
      numericInput("c_riego", "Riego (S/ por ha y campaña)", PAL$costo[1], min = 1),
      numericInput("c_semilla", "Semilla certificada (S/ por ha)", PAL$costo[2], min = 1),
      numericInput("c_asist", "Asistencia técnica (S/ por productor)", PAL$costo[3], min = 1),
      numericInput("c_credito", "Crédito (S/ por productor)", PAL$costo[4], min = 1)
    ),
    mainPanel(width = 9,
      fluidRow(column(3, h4("Valor adicional"), textOutput("kpi_valor")),
               column(3, h4("Producción adicional"), textOutput("kpi_t")),
               column(3, h4("Beneficio/costo"), textOutput("kpi_bc")),
               column(3, h4("Valor de S/ 1 extra"), textOutput("kpi_sombra"))),
      plotOutput("grafico", height = "380px"),
      tableOutput("tabla"),
      tags$small("Efectos estimados con efectos fijos por departamento y año (ENA 2015–2025). ",
                 "Son asociaciones, no efectos causales: use el modo robusto para decidir.")
    )
  )
)

server <- function(input, output, session) {
  palancas <- reactive({
    p <- PAL
    p$costo <- c(input$c_riego, input$c_semilla, input$c_asist, input$c_credito)
    validate(need(all(p$costo > 0), "Los costos deben ser positivos"))
    p
  })
  solucion <- reactive({
    optimizar_plan(INS, palancas(), EFE, input$presupuesto * 1e6, cuota = input$cuota / 100,
                   tope_depto = input$tope / 100, tipo = input$tipo)
  })
  resumen <- reactive(resumen_plan(solucion()))
  output$kpi_valor  <- renderText(sprintf("S/ %.1f millones", solucion()$objetivo / 1e6))
  output$kpi_t      <- renderText(sprintf("%s t", format(round(sum(resumen()$t_adic)), big.mark = " ")))
  output$kpi_bc     <- renderText(sprintf("%.2f", solucion()$objetivo / max(solucion()$gasto, 1)))
  output$kpi_sombra <- renderText(sprintf("S/ %.2f", solucion()$precio_sombra))
  output$grafico <- renderPlot({
    resumen() %>% ggplot(aes(costo / 1e6, reorder(DEPARTAMENTO, costo, sum), fill = palanca)) + geom_col() +
      labs(x = "Inversión (millones de S/)", y = NULL, fill = NULL) + theme_minimal(base_size = 13) +
      theme(legend.position = "bottom")
  })
  output$tabla <- renderTable(
    resumen() %>% group_by(DEPARTAMENTO) %>%
      summarise(`Inversión (S/ M)` = sum(costo) / 1e6, `Producción adicional (t)` = sum(t_adic),
                `Valor (S/ M)` = sum(valor) / 1e6, Palancas = paste(unique(palanca), collapse = ", ")) %>%
      arrange(desc(`Inversión (S/ M)`)), digits = 2)
}

shinyApp(ui, server)
