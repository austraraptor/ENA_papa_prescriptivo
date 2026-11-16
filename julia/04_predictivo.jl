# =============================================================================
# RAMA 4 - ANALÍTICA PREDICTIVA (Julia): réplica del artículo
# =============================================================================
include(joinpath(RAIZ, "julia", "funciones_modelos.jl"))

WF, SHAP = walk_forward(panel; shap = true)
chequear("Predictivo", "95 pronósticos fuera de muestra (19 x 5)", nrow(WF) == 95)
chequear("Predictivo", "Sin pronósticos NaN", all(m -> all(isfinite, WF[!, m]), MODELOS))

fila_m(nombre, y, f) = (m = metricas(y, f); (modelo = nombre, MAE = m.MAE, RMSE = m.RMSE, MAPE = m.MAPE, sMAPE = m.sMAPE))
TAB_MODELOS = DataFrame([fila_m(m, WF.y, WF[!, m]) for m in MODELOS])

# ---- validación contra el artículo (Python) y contra R
ref = CSV.read(RUTAS.ref_metric, DataFrame)
for m in ["Naive Lag1", "Panel FE-ARDL", "Ridge", "ElasticNet"]
    a = TAB_MODELOS[TAB_MODELOS.modelo .== m, :]; r = ref[ref.modelo .== m, :]
    chequear("Predictivo", "$m = artículo (MAE y RMSE ±0.01)",
             abs(a.MAE[1] - r.MAE[1]) < 0.01 && abs(a.RMSE[1] - r.RMSE[1]) < 0.01,
             @sprintf("RMSE %.2f vs %.2f", a.RMSE[1], r.RMSE[1]))
end
ref_pron = CSV.read(RUTAS.ref_pron, DataFrame)
pp = innerjoin(WF, ref_pron, on = [:ANIO, :DEPARTAMENTO], makeunique = true)
DIF_PY = DataFrame(modelo = MODELOS, dif_max_kg_ha = [maximum(abs.(pp[!, m] .- pp[!, m * "_1"])) for m in MODELOS])
dpy(m) = DIF_PY.dif_max_kg_ha[DIF_PY.modelo .== m][1]
chequear("Predictivo", "Pronósticos deterministas = Python (dif. < 0.01 kg/ha)",
         all(dpy(m) < 0.01 for m in ["Naive Lag1", "Panel FE-ARDL", "Ridge"]))
chequear("Predictivo", "ElasticNet = Python (dif. < 1 kg/ha; sklearn usa tol = 1e-4)", dpy("ElasticNet") < 1)
XGB_IGUAL_PY = dpy("XGBoost (prof. 2)") < 0.01

o_last = ajustar_predecir(panel[panel.ANIO .< 2025, :], panel[panel.ANIO .== 2025, :])
kkt = enet_kkt(o_last.A, o_last.ytr, o_last.enet, ENET_ALPHA, ENET_L1)
chequear("Predictivo", "ElasticNet cumple KKT (|grad| < 1e-6)", max(kkt...) < 1e-6, @sprintf("%.1e", max(kkt...)))

ruta_R = joinpath(RUTAS.tab_R, "pronosticos_fuera_de_muestra.csv")
if isfile(ruta_R)
    wfR = CSV.read(ruta_R, DataFrame)
    pr_ = innerjoin(WF, wfR, on = [:ANIO, :DEPARTAMENTO], makeunique = true)
    global DIF_R = DataFrame(modelo = MODELOS, dif_max_kg_ha = [maximum(abs.(pr_[!, m] .- pr_[!, m * "_1"])) for m in MODELOS])
    chequear("Predictivo", "Modelos deterministas = R (dif. < 1e-6 kg/ha)",
             all(DIF_R.dif_max_kg_ha[1:4] .< 1e-6), @sprintf("máx %.1e", maximum(DIF_R.dif_max_kg_ha[1:4])))
end

# ---- XGBoost: variación por semilla (libxgboost 2.1 en Julia; la secuencia aleatoria difiere de Python/R)
SEMILLAS = DataFrame(map(SEMILLA .+ (0:N_SEMILLAS_XGB-1)) do s
    w = walk_forward(panel; semilla = s)
    (semilla = s, RMSE_xgb = metricas(w.y, w[!, "XGBoost (prof. 2)"]).RMSE,
     RMSE_ens = metricas(w.y, w[!, "Ensamble informado"]).RMSE, MAE_ens = metricas(w.y, w[!, "Ensamble informado"]).MAE)
end)
rmse_naive = metricas(WF.y, WF[!, "Naive Lag1"]).RMSE
chequear("Predictivo", "Ensamble con RMSE < ingenuo en la mayoría de semillas",
         mean(SEMILLAS.RMSE_ens .< rmse_naive) >= 0.5, "$(sum(SEMILLAS.RMSE_ens .< rmse_naive)) de $(nrow(SEMILLAS))")
chequear("Predictivo", "RMSE del ensamble a menos de 5 % del artículo (3 092.66)",
         abs(TAB_MODELOS.RMSE[6] / 3092.66 - 1) < 0.05, @sprintf("%.2f", TAB_MODELOS.RMSE[6]))

# ---- estabilidad, sensibilidad, conformal, heladas
TAB_ESTAB = DataFrame([(ANIO = t, Modelo = m, metricas(WF.y[WF.ANIO .== t], WF[WF.ANIO .== t, m])...)
                       for t in ANIOS_PRUEBA for m in ["Naive Lag1", "Ensamble informado"]])

escenarios = [("Base: ventana expansiva, 10 covariables, profundidad 2", NamedTuple()),
              ("Ventana móvil de 4 años", (ventana = 4,)), ("Ventana móvil de 3 años", (ventana = 3,)),
              ("XGBoost con profundidad 3", (depth = 3,)),
              ("Sin covariables de pérdidas climáticas", (cols = setdiff(XCOLS, ["pct_perd_helada", "pct_perd_sequia"]),)),
              ("Solo riego, semilla y fertilizante", (cols = ["pct_area_con_riego", "pct_area_semilla_cert", "pct_fert"],))]
TAB_SENS = DataFrame(map(escenarios) do (nm, a)
    w = isempty(a) ? WF : walk_forward(panel; a...)
    (Escenario = nm, metricas(w.y, w[!, "Ensamble informado"])...)
end)

TAB_CONF = DataFrame()
for nv in (0.8, 0.9)
    a = 1 - nv; z = quantile(Normal(), 1 - a / 2); f = WF[!, "Ensamble informado"]
    q = nv == 0.8 ? WF.q80 : WF.q90
    for (met, lo, hi) in [("Gaussiano (sin calibrar)", f .- z .* WF.sd_in, f .+ z .* WF.sd_in),
                          ("Split-conformal", f .- q, f .+ q)]
        cub = mean((WF.y .>= lo) .& (WF.y .<= hi))
        push!(TAB_CONF, (Nivel = "$(round(Int, 100nv)) %", Metodo = met, Cobertura = 100cub,
                         Error = 100(cub - nv), Ancho = mean(hi .- lo), Winkler = winkler(WF.y, lo, hi, a)))
    end
end
cc = TAB_CONF[TAB_CONF.Metodo .== "Split-conformal", :]; cg = TAB_CONF[TAB_CONF.Metodo .!= "Split-conformal", :]
chequear("Predictivo", "Conformal mejora la cobertura respecto al gaussiano", all(cc.Cobertura .> cg.Cobertura))
chequear("Predictivo", "Cobertura conformal a menos de 10 pp del nominal", all(abs.(cc.Error) .< 10))

TAB_HEL = DataFrame()
for (reg, msk) in [("Alta incidencia (>= 5 %)", WF.helada .>= 5), ("Baja incidencia (< 5 %)", WF.helada .< 5)]
    for m in ["Naive Lag1", "Ensamble informado"]
        push!(TAB_HEL, (Regimen = reg, Modelo = m, Obs = sum(msk), metricas(WF.y[msk], WF[msk, m])...))
    end
end
chequear("Predictivo", "33 casos con heladas >= 5 % (igual que el artículo)", sum(WF.helada .>= 5) == 33)

nombres_x = ["Rendimiento año previo"; [NOMBRES_COV[c] for c in XCOLS]]
TAB_SHAP = sort(DataFrame(variable = nombres_x, shap_medio = vec(mean(abs.(SHAP), dims = 1))), :shap_medio, rev = true)
RES = WF.y .- WF[!, "Ensamble informado"]
SW_P = pvalue(ShapiroWilkTest(RES))

# ---- figuras
p5 = plot([0, 36000], [0, 36000], ls = :dash, color = :black, label = "", xlabel = "Real (kg/ha)",
          ylabel = "Pronosticado (kg/ha)", title = "Real vs. pronosticado (95 casos)", size = (650, 560))
for (m, c, mk) in [("Naive Lag1", COL.gris, :circle), ("XGBoost (prof. 2)", COL.verde, :rect), ("Ensamble informado", COL.rojo, :diamond)]
    scatter!(p5, WF.y, WF[!, m], color = c, marker = mk, ms = 3, alpha = 0.7, label = m)
end
guardar_fig(p5, "j05_real_vs_pred.png")

o = sort(WF, "Ensamble informado"); x = 1:nrow(o); z8 = quantile(Normal(), 0.9)
paneles = map([("Gaussiano (sin calibrar)", z8 .* o.sd_in, COL.azul), ("Split-conformal", o.q80, COL.verde)]) do (met, h, c)
    f = o[!, "Ensamble informado"]; lo = f .- h; hi = f .+ h; fuera = (o.y .< lo) .| (o.y .> hi)
    p = plot(x, f, ribbon = h, fillalpha = 0.25, color = c, label = "Pronóstico y banda 80 %", title = met,
             xlabel = "Casos ordenados por pronóstico", ylabel = "kg/ha", legend = :topleft)
    scatter!(p, x[.!fuera], o.y[.!fuera], ms = 2, color = :black, label = "Real dentro")
    scatter!(p, x[fuera], o.y[fuera], ms = 3.5, marker = :x, color = COL.rojo, label = "Real fuera ($(sum(fuera)))")
end
guardar_fig(plot(paneles..., layout = (1, 2), size = (1150, 430), left_margin = 5Plots.mm, bottom_margin = 5Plots.mm),
            "j06_conformal.png")

pe = plot(title = "RMSE por año de prueba", xlabel = "Año", ylabel = "RMSE (kg/ha)", xticks = ANIOS_PRUEBA)
for (m, c) in [("Naive Lag1", COL.gris), ("Ensamble informado", COL.rojo)]
    s = TAB_ESTAB[TAB_ESTAB.Modelo .== m, :]; plot!(pe, s.ANIO, s.RMSE, marker = :circle, color = c, label = m)
end
ts = reverse(TAB_SHAP)
psh = bar(1:nrow(ts), ts.shap_medio, orientation = :h, yticks = (1:nrow(ts), ts.variable), color = COL.azul,
          label = "", xlabel = "Media |SHAP| (kg/ha)", title = "Importancia SHAP (XGBoost)",
          ylims = (0.4, nrow(ts) + 0.6), bar_width = 0.7)
guardar_fig(plot(pe, psh, layout = (1, 2), size = (1150, 430), left_margin = 6Plots.mm, bottom_margin = 5Plots.mm),
            "j07_estabilidad_shap.png")

qs = quantile.(Normal(), ((1:95) .- 0.5) ./ 95)
pqq = scatter(qs, sort(RES), ms = 2.5, color = COL.azul, label = "", xlabel = "Cuantil teórico", ylabel = "Residuo (kg/ha)",
              title = @sprintf("Q-Q de residuos (Shapiro p = %.3f)", SW_P))
plot!(pqq, qs, mean(RES) .+ std(RES) .* qs, color = COL.rojo, label = "")
mae_de(reg, m) = TAB_HEL.MAE[(TAB_HEL.Regimen .== reg) .& (TAB_HEL.Modelo .== m)][1]
regs = ["Alta incidencia (>= 5 %)", "Baja incidencia (< 5 %)"]
phel = bar([1, 2] .- 0.2, [mae_de(r, "Naive Lag1") for r in regs], bar_width = 0.4, color = COL.gris, label = "Naive Lag1",
           xticks = ([1, 2], ["Alta (>= 5 %), n = 33", "Baja (< 5 %), n = 62"]), ylabel = "MAE (kg/ha)",
           title = "Error según incidencia de heladas", legend = :top)
bar!(phel, [1, 2] .+ 0.2, [mae_de(r, "Ensamble informado") for r in regs], bar_width = 0.4, color = COL.rojo,
     label = "Ensamble informado")
guardar_fig(plot(pqq, phel, layout = (1, 2), size = (1150, 430), left_margin = 6Plots.mm, bottom_margin = 5Plots.mm),
            "j08_residuos_heladas.png")

CSV.write(joinpath(RUTAS.tab, "pronosticos_fuera_de_muestra.csv"), WF)
CSV.write(joinpath(RUTAS.tab, "cuadro2_modelos.csv"), TAB_MODELOS)
CSV.write(joinpath(RUTAS.tab, "cuadro3_estabilidad.csv"), TAB_ESTAB)
CSV.write(joinpath(RUTAS.tab, "cuadro4_sensibilidad.csv"), TAB_SENS)
CSV.write(joinpath(RUTAS.tab, "cuadro5_conformal.csv"), TAB_CONF)
CSV.write(joinpath(RUTAS.tab, "cuadro6_heladas.csv"), TAB_HEL)
CSV.write(joinpath(RUTAS.tab, "xgboost_semillas.csv"), SEMILLAS)
CSV.write(joinpath(RUTAS.tab, "validacion_vs_python.csv"), DIF_PY)
CSV.write(joinpath(RUTAS.tab, "shap_importancia.csv"), TAB_SHAP)
CSV.write(joinpath(RUTAS.tab, "residuos_resumen.csv"), DataFrame(shapiro_p = SW_P, media_residuo = mean(RES)))
println("Rama 4 OK: RMSE ensamble = ", round(TAB_MODELOS.RMSE[6], digits = 2))
