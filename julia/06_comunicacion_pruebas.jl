# =============================================================================
# RAMA 6 - COMUNICACIÓN Y PRUEBAS (Julia)
# Pruebas unitarias (Test), comparación R vs Julia y ficha de decisión en HTML.
# =============================================================================
include(joinpath(RAIZ, "julia", "test", "runtests.jl"))
cnt = Test.get_test_counts(RESULTADO_TESTS)
n_ok, n_fail, n_err = cnt.passes + cnt.cumulative_passes, cnt.fails + cnt.cumulative_fails, cnt.errors + cnt.cumulative_errors
chequear("Comunicación", "Pruebas unitarias Julia sin fallas", n_fail + n_err == 0, "$n_ok aprobadas")

# ---- comparación final R vs Julia (si el pipeline de R ya corrió)
COMPARA = DataFrame(indicador = String[], R = Float64[], Julia = Float64[])
if isfile(joinpath(RUTAS.tab_R, "cuadro2_modelos.csv"))
    mR = CSV.read(joinpath(RUTAS.tab_R, "cuadro2_modelos.csv"), DataFrame)
    for m in MODELOS
        push!(COMPARA, ("RMSE " * m, mR.RMSE[mR.modelo .== m][1], TAB_MODELOS.RMSE[TAB_MODELOS.modelo .== m][1]))
    end
    cR = CSV.read(joinpath(RUTAS.tab_R, "cuadro5_conformal.csv"), DataFrame)
    for i in 1:nrow(cR)
        push!(COMPARA, ("Cobertura " * cR.Nivel[i] * " " * cR.Metodo[i], cR.Cobertura[i], TAB_CONF.Cobertura[i]))
    end
    for (f, nm, res) in [("plan_puntual.csv", "Valor plan puntual (S/)", PLAN_P), ("plan_robusto.csv", "Valor plan robusto (S/)", PLAN_R)]
        push!(COMPARA, (nm, sum(CSV.read(joinpath(RUTAS.tab_R, f), DataFrame).valor), res.objetivo))
    end
    mcR = CSV.read(joinpath(RUTAS.tab_R, "montecarlo_planes.csv"), DataFrame)
    for i in 1:2
        push!(COMPARA, ("P05 exacto del valor, " * mcR.plan[i], mcR.p05_exacto[i], TAB_MC.p05_exacto[i]))
        push!(COMPARA, ("P05 Montecarlo, " * mcR.plan[i], mcR.p05[i], TAB_MC.p05[i]))
    end
    COMPARA.dif_rel_pct = 100 .* (COMPARA.Julia ./ COMPARA.R .- 1)
    CSV.write(joinpath(RUTAS.tab, "comparacion_R_vs_Julia.csv"), COMPARA)
end

# ---- ficha de decisión (HTML autocontenido, para autoridades)
fmt(x; d = 1) = replace(@sprintf("%.*f", d, x), r"(\d)(?=(\d{3})+(?!\d))" => s"\1 ")
filas = join(["<tr><td>$(r.DEPARTAMENTO)</td><td>$(r.palanca)</td><td>$(fmt(r.pp))</td><td>$(fmt(r.costo / 1e6, d = 2))</td><td>$(fmt(r.t_adic, d = 0))</td></tr>"
              for r in eachrow(sort(RES_R, :costo, rev = true))], "\n")
prior = join(ALERTA.DEPARTAMENTO[ALERTA.prioritario], ", ")
html = """<!DOCTYPE html><html lang="es"><head><meta charset="utf-8"><title>Ficha de decisión - papa ENA</title>
<style>body{font-family:Arial,sans-serif;max-width:900px;margin:24px auto;color:#222}h1{color:#2F5D8C;font-size:22px}
.k{display:inline-block;width:23%;background:#f3f6fa;border-left:4px solid #2F5D8C;padding:8px;margin:4px;vertical-align:top}
.k b{font-size:20px;display:block}table{border-collapse:collapse;width:100%;font-size:13px}td,th{border-bottom:1px solid #ddd;padding:4px 6px;text-align:right}
td:first-child,td:nth-child(2),th:first-child,th:nth-child(2){text-align:left}small{color:#666}</style></head><body>
<h1>¿Dónde invertir S/ $(fmt(PRESUPUESTO / 1e6, d = 0)) millones para producir más papa? (plan robusto)</h1>
<div class="k">Valor adicional<b>S/ $(fmt(PLAN_R.objetivo / 1e6)) M</b></div>
<div class="k">Producción adicional<b>$(fmt(sum(RES_R.t_adic), d = 0)) t</b></div>
<div class="k">Beneficio/costo<b>$(fmt(PLAN_R.objetivo / PLAN_R.gasto, d = 2))</b></div>
<div class="k">Prob. B/C &lt; 1<b>$(fmt(100 * TAB_MC.prob_bc_menor_1_exacta[2], d = 2)) %</b></div>
<p><b>Departamentos priorizados</b> (heladas ≥ 5 % y caída esperada o rendimiento bajo): $prior.</p>
<table><tr><th>Departamento</th><th>Palanca</th><th>Aumento (pp)</th><th>Inversión (S/ M)</th><th>Producción adicional (t)</th></tr>
$filas</table>
<p><img src="figuras/j10_plan_optimo.png" style="width:100%"></p>
<small>Fuente: ENA 2015–2025 (INEI). Efectos de efectos fijos con errores agrupados; plan robusto = cota inferior al 80 %.
Costos unitarios son supuestos. Generado con Julia $(VERSION), JuMP + HiGHS, $(Dates.today()).</small></body></html>"""
write(joinpath(RUTAS.out, "ficha_decision.html"), html)

CSV.write(joinpath(RUTAS.tab, "registro_validaciones.csv"), VALIDACIONES)
CSV.write(joinpath(RUTAS.tab, "versiones_paquetes.csv"), VERSIONES)
println("Rama 6 OK: ", nrow(VALIDACIONES), " validaciones; todas aprobadas = ", all(VALIDACIONES.ok))
