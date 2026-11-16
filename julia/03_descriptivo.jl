# =============================================================================
# RAMA 3 - DESCRIPTIVO Y DIAGNÓSTICO (Julia)
# Cuadro 1 y correlaciones del artículo; modelo de efectos fijos (departamento
# y año) con errores agrupados CR1 y diagnósticos (equivalente a easystats).
# =============================================================================

TAB_DESC = combine(groupby(panel, :DEPARTAMENTO), nrow => :anios, :y => mean => :media, :y => std => :de,
                   :y => minimum => :minimo, :y => maximum => :maximo)
sort!(TAB_DESC, :media, rev = true)
nac_y = xl_nac.rendimiento_kg_ha
push!(TAB_DESC, ("Promedio nacional", length(nac_y), mean(nac_y), std(nac_y), minimum(nac_y), maximum(nac_y)))
ref_c1 = Dict("Lima" => 23175.93, "Ica" => 22924.56, "Arequipa" => 20976.80, "Puno" => 6017.71,
              "Lambayeque" => 4037.20, "Cusco" => 7298.62, "Junín" => 13488.40)
chequear("Descriptivo", "Medias = Cuadro 1 del artículo (±0.01)",
         all(abs(TAB_DESC.media[findfirst(==(k), TAB_DESC.DEPARTAMENTO)] - v) < 0.01 for (k, v) in ref_c1))
chequear("Descriptivo", "Media nacional = 11 138.60", abs(mean(nac_y) - 11138.60) < 0.01)
CSV.write(joinpath(RUTAS.tab, "cuadro1_descriptivos.csv"), TAB_DESC)

M = hcat(panel.y, Matrix(panel[:, XCOLS]))
CORM = cor(M)
COR_Y = sort(DataFrame(variable = [NOMBRES_COV[c] for c in XCOLS], r = CORM[1, 2:end]), :r, rev = true)
ref_r = Dict("Crédito" => 0.55, "Semilla cert." => 0.49, "Riego" => 0.45, "Asist. técnica" => 0.41, "Pérdida helada" => -0.16)
chequear("Descriptivo", "Correlaciones = artículo (±0.005)",
         all(abs(COR_Y.r[findfirst(==(k), COR_Y.variable)] - v) < 0.005 for (k, v) in ref_r))
CSV.write(joinpath(RUTAS.tab, "correlaciones_rendimiento.csv"), COR_Y)

# ---- figuras
p1 = plot(xl_nac.ANIO, nac_y, lw = 2.2, color = :black, marker = :circle, ms = 3, label = "Nacional",
          xticks = 2015:2025, ylabel = "Rendimiento (kg/ha)", title = "Rendimiento de papa, Perú 2015–2025 (gris: 2020 sin ENA)",
          legend = :topleft, size = (1050, 480), left_margin = 5Plots.mm, bottom_margin = 3Plots.mm)
vspan!(p1, [2019.5, 2020.5], color = :grey, alpha = 0.2, label = "")
for (d, c) in [("Puno", COL.rojo), ("Junín", COL.verde), ("Arequipa", COL.naranja), ("Cusco", "#7B5EA7")]
    s = panel[panel.DEPARTAMENTO .== d, :]
    plot!(p1, s.ANIO, s.y, ls = :dash, marker = :circle, ms = 2.5, color = c, label = d)
end
guardar_fig(p1, "j01_evolucion.png")

dd = sort(TAB_DESC[TAB_DESC.DEPARTAMENTO .!= "Promedio nacional", :], :media)
nd = nrow(dd)
p2 = bar(1:nd, dd.media, orientation = :h, color = COL.azul, alpha = 0.85, label = "",
         xlabel = "Rendimiento medio ± 1 DE (kg/ha)", title = "Heterogeneidad entre departamentos",
         yticks = (1:nd, dd.DEPARTAMENTO), ylims = (0.4, nd + 0.6), size = (900, 650), left_margin = 4Plots.mm)
scatter!(p2, dd.media, 1:nd, xerror = dd.de, ms = 0, color = :black, label = "")
guardar_fig(p2, "j02_departamentos.png")

etq = ["Rendimiento"; [NOMBRES_COV[c] for c in XCOLS]]
p3 = heatmap(etq, etq, CORM, c = cgrad([COL.azul, :white, COL.rojo]), clims = (-1, 1), yflip = true,
             xrotation = 50, title = "Correlación de Pearson (panel 19 × 10)", size = (900, 760),
             bottom_margin = 10Plots.mm, left_margin = 6Plots.mm)
for i in 1:11, j in 1:11
    annotate!(p3, j - 0.5, i - 0.5, text(@sprintf("%.2f", CORM[i, j]), 6))
end
guardar_fig(p3, "j03_correlacion.png")

# ---- modelo de efectos fijos (departamento + año), MCO con dummies
function ols_ef(df, cols)
    deps = sort(unique(df.DEPARTAMENTO)); anios = sort(unique(df.ANIO))
    X = hcat(ones(nrow(df)), Matrix{Float64}(df[:, cols]),
             [Float64(d == n) for d in df.DEPARTAMENTO, n in deps[2:end]],
             [Float64(a == n) for a in df.ANIO, n in anios[2:end]])
    β = X \ df.y
    u = df.y .- X * β
    n, K = size(X)
    XtXi = inv(X'X)
    # CR1 agrupado por departamento: G/(G-1) * (n-1)/(n-K), igual que sandwich::vcovCL(type = "HC1")
    G = length(deps)
    meat = zeros(K, K)
    for d in deps
        idx = df.DEPARTAMENTO .== d
        s = X[idx, :]' * u[idx]
        meat .+= s * s'
    end
    V = (G / (G - 1)) * ((n - 1) / (n - K)) .* (XtXi * meat * XtXi)
    (β = β, V = V, u = u, X = X, ajuste = X * β, nombres = ["(Intercepto)"; cols], n = n, K = K)
end
M_EF = ols_ef(panel, XCOLS)
k = 2:(1 + length(XCOLS))
ee = sqrt.(diag(M_EF.V))[k]
tdist = TDist(M_EF.n - M_EF.K)
PAR_EF = DataFrame(variable = XCOLS, beta = M_EF.β[k], ee = ee, t = M_EF.β[k] ./ ee,
                   p = 2 .* ccdf.(tdist, abs.(M_EF.β[k] ./ ee)))
r2 = 1 - sum(M_EF.u .^ 2) / sum((panel.y .- mean(panel.y)) .^ 2)

# diagnósticos (equivalentes a performance::check_*)
function breusch_pagan_ncv(u, ajuste)        # prueba de varianza no constante (car::ncvTest)
    n = length(u); w = u .^ 2 ./ (sum(u .^ 2) / n)
    Z = hcat(ones(n), ajuste); g = Z \ w
    est = sum((Z * g .- mean(w)) .^ 2) / 2
    ccdf(Chisq(1), est)
end
function vif_max(df, cols)                    # VIF_j = 1 / (1 - R²_j)
    X = Matrix{Float64}(df[:, cols]); n = size(X, 1)
    vifs = map(eachindex(cols)) do j
        Z = hcat(ones(n), X[:, setdiff(1:size(X, 2), j)])
        e = X[:, j] .- Z * (Z \ X[:, j])
        r2j = 1 - sum(e .^ 2) / sum((X[:, j] .- mean(X[:, j])) .^ 2)
        1 / (1 - r2j)
    end
    maximum(vifs)
end
DIAG_EF = DataFrame(prueba = ["Heterocedasticidad (Breusch-Pagan, ncvTest)", "Normalidad de residuos (Shapiro-Wilk)",
                              "VIF máximo de covariables"],
                    valor = [breusch_pagan_ncv(M_EF.u, M_EF.ajuste), pvalue(ShapiroWilkTest(M_EF.u)), vif_max(panel, XCOLS)])
chequear("Descriptivo", "Modelo EF con 190 obs. y rango completo", M_EF.n == 190 && rank(M_EF.X) == M_EF.K)

# verificación cruzada con R (si el pipeline de R ya corrió)
ruta_R = joinpath(RUTAS.tab_R, "efectos_fijos_parametros.csv")
if isfile(ruta_R)
    efR = CSV.read(ruta_R, DataFrame)
    chequear("Descriptivo", "Coeficientes y EE agrupados = R (dif. < 1e-6)",
             maximum(abs.(efR.beta .- PAR_EF.beta)) < 1e-6 && maximum(abs.(efR.ee .- PAR_EF.ee)) < 1e-6,
             @sprintf("dif máx EE %.1e", maximum(abs.(efR.ee .- PAR_EF.ee))))
end
CSV.write(joinpath(RUTAS.tab, "efectos_fijos_parametros.csv"), PAR_EF)
CSV.write(joinpath(RUTAS.tab, "efectos_fijos_diagnostico.csv"), DIAG_EF)

pq = scatter(M_EF.ajuste, M_EF.u, ms = 2.5, color = COL.azul, label = "", xlabel = "Ajustado (kg/ha)",
             ylabel = "Residuo", title = "Residuos vs. ajustados (EF)")
hline!(pq, [0], color = COL.rojo, label = "")
qs = quantile.(Normal(), ((1:190) .- 0.5) ./ 190)
pq2 = scatter(qs, sort(M_EF.u), ms = 2.5, color = COL.azul, label = "", xlabel = "Cuantil teórico",
              ylabel = "Residuo", title = "Q-Q normal (EF)")
plot!(pq2, qs, std(M_EF.u) .* qs, color = COL.rojo, label = "")
guardar_fig(plot(pq, pq2, layout = (1, 2), size = (1100, 420), left_margin = 5Plots.mm, bottom_margin = 5Plots.mm),
            "j04_diagnostico_ef.png")
println("Rama 3 OK: R² = ", round(r2, digits = 3))
