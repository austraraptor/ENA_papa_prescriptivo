# =============================================================================
# RAMA 2 - DATOS Y VALIDACIÓN (Julia)
# Integridad SHA-256, reconstrucción del panel desde microdatos, contraste con
# el Excel y armado del panel balanceado 19 x 10.
# =============================================================================

const VALIDACIONES = DataFrame(rama = String[], prueba = String[], ok = Bool[], detalle = String[])
function chequear(rama, prueba, condicion, detalle = "")
    ok = condicion === true
    push!(VALIDACIONES, (rama, prueba, ok, string(detalle)))
    ok || error("[VALIDACIÓN FALLIDA] $rama - $prueba $detalle")
    return ok
end

# ---- 2.1 integridad
for (k, ruta) in pairs((cultivo = RUTAS.cultivo, productores = RUTAS.productores, series = RUTAS.series))
    chequear("Datos", "Existe $(basename(ruta))", isfile(ruta))
    h = bytes2hex(open(sha256, ruta))
    chequear("Datos", "SHA-256 $(basename(ruta))", h == SHA256_ESPERADO[k], h[1:12])
end

# ---- 2.2 lectura
leer_hoja(hoja) = DataFrame(XLSX.readtable(RUTAS.series, hoja))
function a_float!(df, cols)
    for c in cols
        df[!, c] = [ismissing(v) ? missing : v isa AbstractString ? parse(Float64, v) : Float64(v) for v in df[!, c]]
    end
    df
end
xl_panel = leer_hoja("panel_departamental")
xl_nac = leer_hoja("serie_nacional")
num_panel = setdiff(names(xl_panel), ["DEPARTAMENTO"])
a_float!(xl_panel, num_panel); a_float!(xl_nac, names(xl_nac))
xl_panel.ANIO = Int.(xl_panel.ANIO); xl_panel.CCDD = Int.(xl_panel.CCDD)
xl_panel.DEPARTAMENTO = String.(xl_panel.DEPARTAMENTO)
xl_nac.ANIO = Int.(xl_nac.ANIO)

cult = CSV.read(RUTAS.cultivo, DataFrame; types = Dict(:CCDD => String), truestrings = ["True"], falsestrings = ["False"])
prod = CSV.read(RUTAS.productores, DataFrame; types = Dict(:CCDD => String, :CCPP => String, :CCDI => String,
                :CONGLO => String, :SEL => String))
cult.ANIO = Int.(cult.ANIO); prod.ANIO = Int.(prod.ANIO)

chequear("Datos", "Filas de cultivo = 139 466", nrow(cult) == 139466, nrow(cult))
chequear("Datos", "Filas válidas = 129 915", sum(cult.valida) == 129915, sum(cult.valida))
chequear("Datos", "Sin 2020 en microdatos", !any(==(2020), cult.ANIO) && !any(==(2020), prod.ANIO))
val = cult[cult.valida, :]
rend_fila = val.produccion_kg ./ val.sup_ha
chequear("Datos", "Rendimiento de filas válidas en [300, 80 000] kg/ha",
         all(r -> 300 - 1e-9 <= r <= 80000 + 1e-9, rend_fila))
chequear("Datos", "Factores de expansión positivos", all(>(0), val.factor))

# ---- 2.3 reconstrucción desde microdatos
dep_cod(x) = ismissing(x) ? missing : parse(Int, x[1:2])   # sin ubigeo -> sin departamento
val.CCDD_i = dep_cod.(val.CCDD)
val.wa = val.factor .* val.sup_ha
rec_cult = combine(groupby(val, [:ANIO, :CCDD_i]),
    [:factor, :produccion_kg] => ((f, p) -> sum(f .* p) / 1000) => :produccion_t,
    :wa => sum => :superficie_cosechada_ha,
    [:wa, :riego] => ((w, r) -> 100 * sum(w .* r) / sum(w)) => :pct_area_con_riego,
    [:wa, :sem_cert] => ((w, s) -> 100 * sum(w .* s) / sum(w)) => :pct_area_semilla_cert)
rec_cult.rendimiento_kg_ha = 1000 .* rec_cult.produccion_t ./ rec_cult.superficie_cosechada_ha

const VARS_PROD = ["fert", "abono", "asist", "capac", "asoc", "seguro", "credito", "perd_helada", "perd_sequia"]
function pct_pond(x, w)                 # % ponderado sobre quienes respondieron
    ok = .!ismissing.(x) .& .!ismissing.(w)
    any(ok) || return missing
    100 * sum(w[ok] .* x[ok]) / sum(w[ok])
end
pr = prod[(coalesce.(prod.tiene_cultivo, 0.0) .== 1) .& .!ismissing.(prod.w), :]
pr.CCDD_i = dep_cod.(pr.CCDD)
for v in ("perd_helada", "perd_sequia")   # ENA 2025: el módulo de pérdidas solo lista a quienes perdieron
    pr[!, v] = [a == 2025 && ismissing(x) ? 0.0 : x for (a, x) in zip(pr.ANIO, pr[!, v])]
end
rec_prod = combine(groupby(pr, [:ANIO, :CCDD_i]),
    [[Symbol(v), :w] => ((x, w) -> pct_pond(x, w)) => Symbol("pct_" * v) for v in VARS_PROD]...)

n_sin_dep = count(ismissing, val.CCDD_i)
chequear("Datos", "Filas válidas sin ubigeo: 142 (solo 2024-2025; cuentan en la serie nacional)",
         n_sin_dep == 142 && issubset(unique(val.ANIO[ismissing.(val.CCDD_i)]), [2024, 2025]), n_sin_dep)
rec = innerjoin(dropmissing(rec_cult, :CCDD_i), dropmissing(rec_prod, :CCDD_i), on = [:ANIO, :CCDD_i])
rename!(rec, :CCDD_i => :CCDD)

# ---- 2.4 contraste con el Excel
const COMPARAR = ["rendimiento_kg_ha", "produccion_t", "superficie_cosechada_ha", "pct_area_con_riego",
                  "pct_area_semilla_cert", ("pct_" .* VARS_PROD)...]
cmp = innerjoin(select(xl_panel, [:ANIO, :CCDD, :DEPARTAMENTO, Symbol.(COMPARAR)...]), rec,
                on = [:ANIO, :CCDD], makeunique = true)
chequear("Datos", "Mismo número de celdas año-departamento", nrow(cmp) == nrow(xl_panel), "$(nrow(cmp)) de $(nrow(xl_panel))")
function dif_max(a, b)
    d = 0.0
    for (x, y) in zip(a, b)
        ismissing(x) && ismissing(y) && continue
        (ismissing(x) || ismissing(y)) && return Inf
        d = max(d, abs(x - y))
    end
    d
end
TAB_RECONSTRUCCION = DataFrame(variable = COMPARAR,
                               dif_abs_max = [dif_max(cmp[!, v], cmp[!, v * "_1"]) for v in COMPARAR])
chequear("Datos", "Panel reconstruido = Excel (dif. < 1e-6)", all(<(1e-6), TAB_RECONSTRUCCION.dif_abs_max),
         @sprintf("máx = %.2e", maximum(TAB_RECONSTRUCCION.dif_abs_max)))
rec_nac = combine(groupby(val, :ANIO), [:factor, :produccion_kg, :sup_ha] =>
                  ((f, p, s) -> sum(f .* p) / sum(f .* s)) => :y)
nac_map = Dict(zip(xl_nac.ANIO, xl_nac.rendimiento_kg_ha))
chequear("Datos", "Serie nacional reconstruida = Excel",
         maximum(abs.(rec_nac.y .- [nac_map[a] for a in rec_nac.ANIO])) < 1e-6)

# ---- 2.5 panel balanceado
conteo = combine(groupby(xl_panel, :DEPARTAMENTO), nrow => :n)
const DEPS = sort(conteo.DEPARTAMENTO[conteo.n .== maximum(conteo.n)])
const EXCLUIDOS = sort(conteo.DEPARTAMENTO[conteo.n .< maximum(conteo.n)])

panel = sort(xl_panel[in.(xl_panel.DEPARTAMENTO, Ref(Set(DEPS))), :], [:DEPARTAMENTO, :ANIO])
panel.credito_imputado = ismissing.(panel.pct_credito)
panel.y = Float64.(panel.rendimiento_kg_ha)
panel.y_lag = Vector{Union{Missing, Float64}}(missing, nrow(panel))
for g in groupby(panel, :DEPARTAMENTO)
    ult = missing
    for i in 1:nrow(g)                      # crédito: arrastre hacia adelante (solo pasado)
        ismissing(g.pct_credito[i]) ? (g.pct_credito[i] = ult) : (ult = g.pct_credito[i])
        i > 1 && (g.y_lag[i] = g.y[i-1])     # 2021 toma 2019 (no hubo ENA 2020)
    end
end
for c in XCOLS
    panel[!, c] = Float64.(panel[!, c])
end
const ANIOS = sort(unique(panel.ANIO))

chequear("Datos", "Panel balanceado 19 x 10 = 190", length(DEPS) == 19 && nrow(panel) == 190)
chequear("Datos", "Excluidos solo Loreto y San Martín", EXCLUIDOS == ["Loreto", "San Martín"], join(EXCLUIDOS, ", "))
chequear("Datos", "Sin duplicados año-departamento", !any(nonunique(panel, [:ANIO, :DEPARTAMENTO])))
chequear("Datos", "Covariables en [0, 100] %", all(x -> 0 <= x <= 100, Matrix(panel[:, XCOLS])))
chequear("Datos", "Crédito imputado solo en 2021", all(==(2021), panel.ANIO[panel.credito_imputado]))
let a21 = panel[panel.ANIO .== 2021, :], a19 = panel[panel.ANIO .== 2019, :]
    chequear("Datos", "y_lag de 2021 es el valor de 2019",
             all(a21.y_lag .== a19.y[indexin(a21.DEPARTAMENTO, a19.DEPARTAMENTO)]))
end

CSV.write(joinpath(RUTAS.tab, "panel_analisis.csv"), panel)
CSV.write(joinpath(RUTAS.tab, "validacion_reconstruccion.csv"), TAB_RECONSTRUCCION)
println("Rama 2 OK: panel $(nrow(panel)) filas; reconstrucción máx dif = ",
        @sprintf("%.2e", maximum(TAB_RECONSTRUCCION.dif_abs_max)))
