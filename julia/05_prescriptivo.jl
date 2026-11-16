# =============================================================================
# RAMA 5 - ANALÍTICA PRESCRIPTIVA (Julia, JuMP + HiGHS)
# RETO: repartir un presupuesto fijo entre departamentos y palancas para obtener
# el mayor valor de producción adicional de papa, protegiendo a los priorizados.
# =============================================================================
include(joinpath(RAIZ, "julia", "funciones_prescriptivas.jl"))

# ---- 5.1 alerta temprana 2026 (covariables 2026 = 2025)
base25 = panel[panel.ANIO .== 2025, :]
te26 = copy(base25); te26.ANIO .= 2026; te26.y_lag = Vector{Union{Missing, Float64}}(base25.y)
o26 = ajustar_predecir(panel, te26)
oc25 = ajustar_predecir(panel[panel.ANIO .< 2025, :], base25)
q80_26 = cuantil_conformal(abs.(base25.y .- oc25.pred["Ensamble informado"]), 0.8)
hist = combine(groupby(panel, :DEPARTAMENTO), :y => (y -> quantile(y, 0.25)) => :p25, :y => mean => :media,
               [:pct_perd_helada, :ANIO] => ((h, a) -> mean(h[a .>= 2021])) => :helada_media)
ALERTA = DataFrame(DEPARTAMENTO = te26.DEPARTAMENTO, y_2025 = base25.y, pron_2026 = o26.pred["Ensamble informado"])
ALERTA.lo80 = ALERTA.pron_2026 .- q80_26; ALERTA.hi80 = ALERTA.pron_2026 .+ q80_26
ALERTA = leftjoin(ALERTA, hist, on = :DEPARTAMENTO)
ALERTA.alerta = ALERTA.pron_2026 .< ALERTA.media
ALERTA.helada_alta = ALERTA.helada_media .>= 5
ALERTA.bajo_promedio = ALERTA.media .< mean(xl_nac.rendimiento_kg_ha)
ALERTA.prioritario = ALERTA.helada_alta .& (ALERTA.alerta .| ALERTA.bajo_promedio)
sort!(ALERTA, :pron_2026)
chequear("Prescriptivo", "Pronóstico 2026 completo y positivo", all(>(0), ALERTA.pron_2026) && nrow(ALERTA) == 19)
chequear("Prescriptivo", "Hay departamentos priorizados", any(ALERTA.prioritario), join(ALERTA.DEPARTAMENTO[ALERTA.prioritario], ", "))

# ---- 5.2 efectos de las palancas y su covarianza agrupada
EFECTOS = efectos_palancas(PAR_EF, PALANCAS)
ip = [findfirst(==(v), M_EF.nombres) for v in PALANCAS.var]
VC_PAL = Matrix(Symmetric(M_EF.V[ip, ip]))
chequear("Prescriptivo", "Matriz de covarianza de palancas definida positiva", isposdef(VC_PAL))

INSUMOS = DataFrame(DEPARTAMENTO = base25.DEPARTAMENTO, area = base25.superficie_cosechada_ha,
                    productores = base25.productores_expandidos,
                    precio = coalesce.(base25.precio_venta_kg, PRECIO_KG), y_2025 = base25.y)
for v in PALANCAS.var
    INSUMOS[!, v] = base25[!, v]
end
INSUMOS = leftjoin(INSUMOS, select(ALERTA, :DEPARTAMENTO, :prioritario, :alerta, :helada_alta), on = :DEPARTAMENTO)
sort!(INSUMOS, :DEPARTAMENTO)
chequear("Prescriptivo", "Insumos sin faltantes", !any(c -> any(ismissing, c), eachcol(INSUMOS)))

# ---- 5.3 planes óptimos
PLAN_P = optimizar_plan(INSUMOS, PALANCAS, EFECTOS, PRESUPUESTO; tipo = "puntual")
PLAN_R = optimizar_plan(INSUMOS, PALANCAS, EFECTOS, PRESUPUESTO; tipo = "robusto")
function validar_plan(res, nombre)
    pl = res.plan; tol = 1e-4
    chequear("Prescriptivo", "$nombre - respeta el presupuesto", res.gasto <= PRESUPUESTO * (1 + 1e-7))
    chequear("Prescriptivo", "$nombre - respeta topes por palanca y 100 %",
             all(pl.x .>= -tol) && all(pl.x .<= pl.ub .+ tol) && all(pl.nivel .+ pl.x .<= 100 + tol))
    porD = combine(groupby(pl, :DEPARTAMENTO), :costo => sum => :c)
    chequear("Prescriptivo", "$nombre - ningún departamento supera el 25 %", all(porD.c .<= TOPE_DEPTO * PRESUPUESTO * (1 + 1e-7)))
    chequear("Prescriptivo", "$nombre - cuota de equidad cumplida",
             sum(pl.costo[pl.prioritario]) >= res.cuota_efectiva * PRESUPUESTO * (1 - 1e-7))
    chequear("Prescriptivo", "$nombre - objetivo = suma de valores", abs(res.objetivo - sum(pl.valor)) < 1e-3 * max(1, res.objetivo / 1e9))
    esc = min(1, res.gasto / sum(pl.c .* pl.ub))
    chequear("Prescriptivo", "$nombre - supera al reparto proporcional", res.objetivo >= esc * sum(pl.v .* pl.ub) - 1e-6)
end
validar_plan(PLAN_P, "Plan puntual"); validar_plan(PLAN_R, "Plan robusto")

# verificación cruzada con R: mismo óptimo (lpSolve vs HiGHS)
for (nm, res, f) in [("puntual", PLAN_P, "plan_puntual.csv"), ("robusto", PLAN_R, "plan_robusto.csv")]
    ruta = joinpath(RUTAS.tab_R, f)
    isfile(ruta) || continue
    pR = CSV.read(ruta, DataFrame)
    chequear("Prescriptivo", "Plan $nm: valor óptimo = R (lpSolve) con dif. relativa < 1e-6",
             abs(sum(pR.valor) / res.objetivo - 1) < 1e-6, @sprintf("R %.0f vs Julia %.0f", sum(pR.valor), res.objetivo))
end

# ---- 5.4 incertidumbre, frontera, equidad, costos
MC = vcat(insertcols!(simular_plan(PLAN_P, EFECTOS, VC_PAL), :plan => "Plan puntual"),
          insertcols!(simular_plan(PLAN_R, EFECTOS, VC_PAL), :plan => "Plan robusto"))
TAB_MC = combine(groupby(MC, :plan), :valor => mean => :valor_medio, :valor => (v -> quantile(v, 0.05)) => :p05,
                 :valor => (v -> quantile(v, 0.95)) => :p95, :bc => mean => :bc_medio, :bc => (b -> mean(b .< 1)) => :prob_bc_menor_1)
TAB_MC = hcat(TAB_MC, DataFrame([distribucion_exacta(PLAN_P, EFECTOS, VC_PAL), distribucion_exacta(PLAN_R, EFECTOS, VC_PAL)]))
chequear("Prescriptivo", "Montecarlo = distribución exacta (media a < 4 EE, P05 a < 0.1 DE)",
         all(abs.(TAB_MC.valor_medio .- TAB_MC.media_exacta) .< 4 .* TAB_MC.de_exacta ./ sqrt(N_MONTECARLO)) &&
         all(abs.(TAB_MC.p05 .- TAB_MC.p05_exacto) .< 0.1 .* TAB_MC.de_exacta))
chequear("Prescriptivo", "Media exacta = valor del plan puntual", abs(TAB_MC.media_exacta[1] / PLAN_P.objetivo - 1) < 1e-9)

FRONTERA = DataFrame([(B = B, tipo = t, (r = optimizar_plan(INSUMOS, PALANCAS, EFECTOS, B; tipo = t);
                       (valor = r.objetivo, gasto = r.gasto, precio_sombra = r.precio_sombra))...)
                      for B in 5e6:5e6:300e6 for t in ("puntual", "robusto")])
chequear("Prescriptivo", "Frontera no decreciente en el presupuesto",
         all(all(diff(FRONTERA.valor[FRONTERA.tipo .== t]) .>= -1e-6) for t in ("puntual", "robusto")))
B_EFICIENTE = combine(groupby(FRONTERA, :tipo), [:B, :precio_sombra] => ((b, s) -> maximum(b[s .>= 1])) => :B_max_eficiente)
EQUIDAD = DataFrame(cuota = [0, 0.1, 0.2, 0.3, 0.4, 0.5])
EQUIDAD.valor = [optimizar_plan(INSUMOS, PALANCAS, EFECTOS, PRESUPUESTO; cuota = c).objetivo for c in EQUIDAD.cuota]
EQUIDAD.costo_equidad = EQUIDAD.valor[1] .- EQUIDAD.valor
COSTOS = DataFrame(factor = [0.5, 1.0, 1.5])
COSTOS.valor = [optimizar_plan(INSUMOS, merge(PALANCAS, (costo = PALANCAS.costo .* f,)), EFECTOS, PRESUPUESTO).objetivo
                for f in COSTOS.factor]
COSTOS.bc = COSTOS.valor ./ PRESUPUESTO

RES_P = resumen_plan(PLAN_P); RES_R = resumen_plan(PLAN_R)
POR_PALANCA = vcat(insertcols!(combine(groupby(RES_P, :palanca), :costo => sum => :costo, :t_adic => sum => :t_adic,
                                       :valor => sum => :valor), 1, :plan => "Plan puntual"),
                   insertcols!(combine(groupby(RES_R, :palanca), :costo => sum => :costo, :t_adic => sum => :t_adic,
                                       :valor => sum => :valor), 1, :plan => "Plan robusto"))

# ---- figuras
na = nrow(ALERTA)
pa = scatter(ALERTA.pron_2026, 1:na, xerror = (ALERTA.pron_2026 .- ALERTA.lo80, ALERTA.hi80 .- ALERTA.pron_2026),
             color = [p ? COL.rojo : COL.azul for p in ALERTA.prioritario], ms = 4, label = "",
             yticks = (1:na, ALERTA.DEPARTAMENTO), xlabel = "Pronóstico 2026 e intervalo conformal 80 % (kg/ha)",
             title = "Alerta temprana 2026 (rojo = priorizado; | = media 2015–2025)", size = (900, 650), left_margin = 4Plots.mm)
scatter!(pa, ALERTA.media, 1:na, marker = :vline, ms = 7, color = :black, label = "")
guardar_fig(pa, "j09_alerta_2026.png")

function barras_plan(res_df, titulo)
    pal = ["Asistencia técnica", "Crédito agrario", "Riego tecnificado", "Semilla certificada"]
    cols = Dict("Asistencia técnica" => COL.rojo, "Crédito agrario" => COL.azul, "Riego tecnificado" => COL.naranja,
                "Semilla certificada" => COL.verde)
    tot = sort(combine(groupby(res_df, :DEPARTAMENTO), :costo => sum => :t), :t)
    deps = tot.DEPARTAMENTO; nd = length(deps)
    p = plot(title = titulo, xlabel = "Inversión (millones de S/)", yticks = (1:nd, deps), legend = :bottomright)
    izq = zeros(nd)
    for pa_ in pal
        val = [sum(res_df.costo[(res_df.DEPARTAMENTO .== d) .& (res_df.palanca .== pa_)]; init = 0.0) for d in deps] ./ 1e6
        any(val .> 0) || continue
        bar!(p, 1:nd, izq .+ val, fillrange = izq, orientation = :h, color = cols[pa_], label = pa_, bar_width = 0.7, lw = 0)
        izq .+= val
    end
    p
end
guardar_fig(plot(barras_plan(RES_P, "Plan puntual"), barras_plan(RES_R, "Plan robusto"), layout = (1, 2),
                 size = (1150, 520), left_margin = 5Plots.mm, bottom_margin = 5Plots.mm), "j10_plan_optimo.png")

pf = plot(xlabel = "Presupuesto (millones de S/)", ylabel = "Valor adicional (millones de S/)",
          title = "Frontera presupuesto-valor (punteada: B/C = 1)", legend = :topleft)
for (t, c) in [("puntual", COL.azul), ("robusto", COL.rojo)]
    s = FRONTERA[FRONTERA.tipo .== t, :]; plot!(pf, s.B ./ 1e6, s.valor ./ 1e6, marker = :circle, ms = 2, color = c, label = t)
end
plot!(pf, [0, 300], [0, 300], ls = :dot, color = :black, label = "")
pm = histogram(MC.bc[MC.plan .== "Plan puntual"], normalize = :pdf, alpha = 0.45, color = COL.azul, label = "Plan puntual",
               bins = 60, xlabel = "Beneficio / costo (20 000 simulaciones)", ylabel = "Densidad", title = "Incertidumbre del plan")
histogram!(pm, MC.bc[MC.plan .== "Plan robusto"], normalize = :pdf, alpha = 0.45, color = COL.rojo, label = "Plan robusto", bins = 40)
vline!(pm, [1], ls = :dash, color = :black, label = "")
guardar_fig(plot(pf, pm, layout = (1, 2), size = (1150, 450), left_margin = 6Plots.mm, bottom_margin = 5Plots.mm),
            "j11_frontera_montecarlo.png")

CSV.write(joinpath(RUTAS.tab, "alerta_2026.csv"), ALERTA)
CSV.write(joinpath(RUTAS.tab, "efectos_palancas.csv"), EFECTOS)
CSV.write(joinpath(RUTAS.tab, "insumos_prescriptivos.csv"), INSUMOS)
CSV.write(joinpath(RUTAS.tab, "plan_puntual.csv"), RES_P)
CSV.write(joinpath(RUTAS.tab, "plan_robusto.csv"), RES_R)
CSV.write(joinpath(RUTAS.tab, "plan_por_palanca.csv"), POR_PALANCA)
CSV.write(joinpath(RUTAS.tab, "montecarlo_planes.csv"), TAB_MC)
CSV.write(joinpath(RUTAS.tab, "frontera_presupuesto.csv"), FRONTERA)
CSV.write(joinpath(RUTAS.tab, "presupuesto_eficiente.csv"), B_EFICIENTE)
CSV.write(joinpath(RUTAS.tab, "costo_equidad.csv"), EQUIDAD)
CSV.write(joinpath(RUTAS.tab, "sensibilidad_costos.csv"), COSTOS)
println(@sprintf("Rama 5 OK: plan puntual S/ %.1f M; robusto S/ %.1f M", PLAN_P.objetivo / 1e6, PLAN_R.objetivo / 1e6))
