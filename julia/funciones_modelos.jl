# =============================================================================
# Funciones del modelo predictivo (Julia) - réplica exacta del artículo
# =============================================================================

# StandardScaler: media y desviación poblacional (ddof = 0)
function escalador(X::AbstractMatrix)
    mu = vec(mean(X, dims = 1))
    s = vec(sqrt.(mean((X .- mu') .^ 2, dims = 1)))
    s[s .== 0] .= 1.0
    Z -> (Z .- mu') ./ s'
end

# Ridge con intercepto sin penalizar
function ridge_ajustar(A, y, alpha)
    b = (A'A + alpha * I) \ (A' * (y .- mean(y)))
    (b0 = mean(y), b = b)
end

# ElasticNet (función objetivo de scikit-learn) por descenso de coordenadas
function enet_ajustar(A, y, alpha, l1; tol = 1e-12, max_iter = 100_000)
    n, p = size(A)
    b = zeros(p); r = y .- mean(y)
    z = vec(sum(A .^ 2, dims = 1)) ./ n
    it = 0
    for k in 1:max_iter
        it = k; cambio = 0.0
        for j in 1:p
            bj_old = b[j]
            rho = dot(view(A, :, j), r) / n + z[j] * bj_old
            bj = sign(rho) * max(abs(rho) - alpha * l1, 0.0) / (z[j] + alpha * (1 - l1))
            if bj != bj_old
                r .-= view(A, :, j) .* (bj - bj_old); b[j] = bj
            end
            cambio = max(cambio, abs(bj - bj_old))
        end
        cambio < tol * max(1.0, maximum(abs.(b))) && break
    end
    (b0 = mean(y), b = b, iter = it)
end

function enet_kkt(A, y, fit, alpha, l1)
    n = size(A, 1); r = (y .- fit.b0) .- A * fit.b
    g = (A' * r) ./ n .- alpha * (1 - l1) .* fit.b
    act = fit.b .!= 0
    (activos = maximum([0.0; abs.(g[act] .- alpha * l1 .* sign.(fit.b[act]))]),
     inactivos = maximum([0.0; abs.(g[.!act]) .- alpha * l1]))
end

matriz_x(df, cols) = hcat(Float64.(df.y_lag), Matrix{Float64}(df[:, cols]))

# MCO con efectos fijos por departamento: intercepto + X + dummies (se omite la primera)
function fe_ajustar_predecir(tr, te, cols)
    niv = sort(unique(tr.DEPARTAMENTO))
    dis(df) = hcat(ones(nrow(df)), matriz_x(df, cols), [Float64(d == n) for d in df.DEPARTAMENTO, n in niv[2:end]])
    β = dis(tr) \ tr.y
    dis(te) * β
end

function xgb_ajustar(X, y; depth = 2, semilla = SEMILLA)
    xgboost((X, y); num_round = XGB_PARAMS.num_round, max_depth = depth, eta = XGB_PARAMS.eta,
            subsample = XGB_PARAMS.subsample, colsample_bytree = XGB_PARAMS.colsample_bytree,
            min_child_weight = XGB_PARAMS.min_child_weight, lambda = XGB_PARAMS.lambda,
            objective = "reg:squarederror", seed = semilla, nthread = 1, watchlist = Dict())
end

# TreeSHAP exacto: predicción tipo 2 (contribuciones) directamente desde libxgboost
function xgb_shap(b, X)
    dm = XGBoost.DMatrix(X)
    opts = JSON.json(Dict("type" => 2, "iteration_begin" => 0, "iteration_end" => 0,
                          "strict_shape" => false, "training" => false))
    oshape = Ref{Ptr{XGBoost.Lib.bst_ulong}}(); odim = Ref{XGBoost.Lib.bst_ulong}(); o = Ref{Ptr{Cfloat}}()
    XGBoost.xgbcall(XGBoost.Lib.XGBoosterPredictFromDMatrix, b.handle, dm.handle, opts, oshape, odim, o)
    dims = reverse(unsafe_wrap(Array, oshape[], odim[]))
    permutedims(copy(unsafe_wrap(Array, o[], tuple(Int.(dims)...))))   # n x (p + 1); última = sesgo
end

const MODELOS = ["Naive Lag1", "Panel FE-ARDL", "Ridge", "ElasticNet", "XGBoost (prof. 2)", "Ensamble informado"]

function ajustar_predecir(tr, te; cols = XCOLS, depth = 2, semilla = SEMILLA)
    tr = tr[.!ismissing.(tr.y_lag), :]
    out = Dict{String, Vector{Float64}}()
    out["Naive Lag1"] = Float64.(te.y_lag)
    out["Panel FE-ARDL"] = fe_ajustar_predecir(tr, te, cols)
    Xtr = matriz_x(tr, cols); Xte = matriz_x(te, cols)
    sc = escalador(Xtr); A = sc(Xtr); B = sc(Xte)
    rg = ridge_ajustar(A, tr.y, RIDGE_ALPHA); out["Ridge"] = rg.b0 .+ B * rg.b
    en = enet_ajustar(A, tr.y, ENET_ALPHA, ENET_L1); out["ElasticNet"] = en.b0 .+ B * en.b
    xg = xgb_ajustar(Xtr, tr.y; depth = depth, semilla = semilla)
    out["XGBoost (prof. 2)"] = Float64.(XGBoost.predict(xg, Xte))
    out["Ensamble informado"] = (out["Panel FE-ARDL"] .+ out["XGBoost (prof. 2)"]) ./ 2
    (pred = out, xgb = xg, Xte = Xte, enet = en, A = A, ytr = tr.y)
end

function metricas(y, f)
    e = y .- f
    (MAE = mean(abs.(e)), RMSE = sqrt(mean(e .^ 2)), MAPE = 100 * mean(abs.(e) ./ y),
     sMAPE = 100 * mean(2 .* abs.(e) ./ (abs.(y) .+ abs.(f))))
end

cuantil_conformal(res, nivel) = (r = sort(res); n = length(r); r[min(ceil(Int, (n + 1) * nivel), n)])
winkler(y, lo, hi, a) = mean((hi .- lo) .+ (2 / a) .* (lo .- y) .* (y .< lo) .+ (2 / a) .* (y .- hi) .* (y .> hi))

function walk_forward(datos; anios_prueba = ANIOS_PRUEBA, ventana = nothing, cols = XCOLS, depth = 2,
                      semilla = SEMILLA, shap = false)
    anios = sort(unique(datos.ANIO))
    filas = DataFrame[]; shaps = Matrix{Float64}[]
    for t in anios_prueba
        prev = anios[anios .< t]
        ventana === nothing || (prev = prev[max(1, end - ventana + 1):end])
        tr = datos[in.(datos.ANIO, Ref(Set(prev))), :]; te = datos[datos.ANIO .== t, :]
        o = ajustar_predecir(tr, te; cols, depth, semilla)
        cal_t = prev[end]
        oc = ajustar_predecir(datos[in.(datos.ANIO, Ref(Set(prev[1:end-1]))), :], datos[datos.ANIO .== cal_t, :];
                              cols, depth, semilla)
        res_cal = abs.(datos.y[datos.ANIO .== cal_t] .- oc.pred["Ensamble informado"])
        tr_in = tr[.!ismissing.(tr.y_lag), :]
        oi = ajustar_predecir(tr, tr_in; cols, depth, semilla)
        sd_in = std(tr_in.y .- oi.pred["Ensamble informado"])
        d = DataFrame(ANIO = t, DEPARTAMENTO = te.DEPARTAMENTO, y = te.y, helada = te.pct_perd_helada,
                      sd_in = sd_in, q80 = cuantil_conformal(res_cal, 0.8), q90 = cuantil_conformal(res_cal, 0.9))
        for m in MODELOS
            d[!, m] = o.pred[m]
        end
        push!(filas, d)
        shap && push!(shaps, xgb_shap(o.xgb, o.Xte)[:, 1:end-1])
    end
    wf = vcat(filas...)
    shap ? (wf, vcat(shaps...)) : wf
end
