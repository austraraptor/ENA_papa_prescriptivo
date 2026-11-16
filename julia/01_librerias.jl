# =============================================================================
# RAMA 1 - LIBRERÍAS (Julia)
#   CSV, DataFrames, XLSX     : lectura y manipulación (equivalente a tidyverse)
#   Statistics, StatsBase     : descriptivos y correlaciones
#   GLM, LinearAlgebra        : MCO, efectos fijos, Ridge en forma cerrada
#   HypothesisTests, Distributions : Shapiro-Wilk, normal multivariada (Montecarlo)
#   XGBoost                   : árbol restringido y SHAP exacto (TreeSHAP de libxgboost)
#   JuMP + HiGHS              : programación lineal (analítica prescriptiva)
#   Plots (GR)                : figuras
#   Test, SHA                 : pruebas y huellas de integridad
# =============================================================================
ENV["GKSwstype"] = "100"     # GR sin ventana (servidor / consola)

using CSV, DataFrames, XLSX, Statistics, StatsBase, LinearAlgebra, Random, Printf, Dates
using GLM, HypothesisTests, Distributions
using XGBoost, JuMP, HiGHS, Plots, Test, SHA, JSON

const VERSIONES = DataFrame(paquete = ["Julia"; ["CSV", "DataFrames", "XLSX", "GLM", "XGBoost", "JuMP", "HiGHS", "Plots"]],
                            version = [string(VERSION); [string(pkgversion(m)) for m in (CSV, DataFrames, XLSX, GLM, XGBoost, JuMP, HiGHS, Plots)]])

const COL = (azul = "#2F5D8C", rojo = "#B03A2E", gris = "#8C8C8C", verde = "#3B8C5A", naranja = "#D98E04")
default(fontfamily = "sans-serif", titlefontsize = 9, guidefontsize = 8, tickfontsize = 7, legendfontsize = 7,
        framestyle = :box, grid = true, gridalpha = 0.15, dpi = 200, formatter = :plain)
guardar_fig(p, nombre) = (savefig(p, joinpath(RUTAS.fig, nombre)); nombre)
