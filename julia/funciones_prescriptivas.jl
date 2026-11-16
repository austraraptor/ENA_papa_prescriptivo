# =============================================================================
# Funciones de la analítica prescriptiva (Julia, JuMP + HiGHS)
#   max  sum v_ik x_ik
#   s.a. sum c_ik x_ik <= B ; sum_k c_ik x_ik <= tope*B (cada i) ;
#        sum_{i en P} c_ik x_ik >= cuota*B ; 0 <= x_ik <= min(tope_pp_k, 100 - nivel_ik)
# =============================================================================

function efectos_palancas(par_ef, palancas; z = Z_ROBUSTO)
    idx = [findfirst(==(v), par_ef.variable) for v in palancas.var]
    b = par_ef.beta[idx]; e = par_ef.ee[idx]
    DataFrame(var = palancas.var, beta = b, ee = e, beta_puntual = b, beta_robusto = max.(0.0, b .- z .* e))
end

function armar_problema(ins, palancas, efectos; tipo = "puntual")
    b = Dict(zip(efectos.var, efectos[!, "beta_" * tipo]))
    filas = NamedTuple[]
    for i in 1:nrow(ins), k in eachindex(palancas.var)
        v = palancas.var[k]; nivel = ins[i, v]
        escala = palancas.base[k] == "area" ? ins.area[i] : ins.productores[i]
        kg = b[v] * ins.area[i]
        push!(filas, (DEPARTAMENTO = ins.DEPARTAMENTO[i], palanca = palancas.nombre[k], var = v,
                      prioritario = ins.prioritario[i], nivel = nivel,
                      ub = max(0.0, min(palancas.tope_pp[k], 100 - nivel)),
                      c = palancas.costo[k] * escala / 100, ap = ins.area[i] * ins.precio[i],
                      kg = kg, v = kg * ins.precio[i]))
    end
    pr = DataFrame(filas)
    pr[(pr.v .> 0) .& (pr.ub .> 0), :]
end

function optimizar_plan(ins, palancas, efectos, presupuesto; cuota = CUOTA_EQUIDAD, tope_depto = TOPE_DEPTO,
                        tipo = "puntual")
    pr = armar_problema(ins, palancas, efectos; tipo)
    nrow(pr) > 0 || error("Ninguna palanca tiene efecto positivo")
    n = nrow(pr)
    cap_prior = sum(pr.c[pr.prioritario] .* pr.ub[pr.prioritario])
    rhs_eq = min(cuota * presupuesto, cap_prior)
    m = Model(HiGHS.Optimizer); set_silent(m)
    @variable(m, 0 <= x[j = 1:n] <= pr.ub[j])
    @objective(m, Max, sum(pr.v[j] * x[j] for j in 1:n))
    @constraint(m, presup, sum(pr.c[j] * x[j] for j in 1:n) <= presupuesto)
    for d in unique(pr.DEPARTAMENTO)
        @constraint(m, sum(pr.c[j] * x[j] for j in 1:n if pr.DEPARTAMENTO[j] == d) <= tope_depto * presupuesto)
    end
    @constraint(m, sum(pr.c[j] * x[j] for j in 1:n if pr.prioritario[j]) >= rhs_eq)
    optimize!(m)
    termination_status(m) == MOI.OPTIMAL || error("Programa lineal sin óptimo: $(termination_status(m))")
    pr.x = value.(x)
    pr.costo = pr.c .* pr.x; pr.kg_adic = pr.kg .* pr.x; pr.valor = pr.v .* pr.x
    (plan = pr, objetivo = objective_value(m), gasto = sum(pr.costo), precio_sombra = shadow_price(presup),
     cuota_efectiva = rhs_eq / presupuesto, cap_prior = cap_prior)
end

function resumen_plan(res)
    p = res.plan[res.plan.x .> 1e-9, :]
    sort(combine(groupby(p, [:DEPARTAMENTO, :palanca]), :x => sum => :pp, :costo => sum => :costo,
                 :kg_adic => (k -> sum(k) / 1000) => :t_adic, :valor => sum => :valor), [:DEPARTAMENTO, :palanca])
end

function simular_plan(res, efectos, V; n = N_MONTECARLO, semilla = SEMILLA)
    rng = MersenneTwister(semilla)
    d = MvNormal(efectos.beta, Symmetric(V))
    draws = rand(rng, d, n)'                          # n x 4
    base = [sum(res.plan.x[res.plan.var .== v] .* res.plan.ap[res.plan.var .== v]) for v in efectos.var]
    valor = draws * base
    DataFrame(valor = valor, bc = valor ./ res.gasto)
end

# Distribución exacta: el valor es lineal en beta -> normal con media b'mu y varianza b'Vb
function distribucion_exacta(res, efectos, V)
    base = [sum(res.plan.x[res.plan.var .== v] .* res.plan.ap[res.plan.var .== v]) for v in efectos.var]
    media = dot(base, efectos.beta); de = sqrt(base' * V * base)
    (media_exacta = media, de_exacta = de, p05_exacto = media + quantile(Normal(), 0.05) * de,
     p95_exacto = media + quantile(Normal(), 0.95) * de, prob_bc_menor_1_exacta = cdf(Normal(), (res.gasto - media) / de))
end
