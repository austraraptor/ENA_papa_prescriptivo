# Pruebas unitarias (Julia, stdlib Test). Ejecutar desde la raíz:
#   julia --project=julia julia/test/runtests.jl
if !@isdefined(RAIZ)
    include(joinpath(@__DIR__, "..", "00_config.jl"))
    include(joinpath(@__DIR__, "..", "01_librerias.jl"))
    include(joinpath(@__DIR__, "..", "funciones_modelos.jl"))
    include(joinpath(@__DIR__, "..", "funciones_prescriptivas.jl"))
end

RESULTADO_TESTS = @testset "Pipeline ENA papa (Julia)" begin
    @testset "Escalador = StandardScaler" begin
        X = randn(MersenneTwister(1), 20, 3) .* 3 .+ 5
        A = escalador(X)(X)
        @test all(abs.(mean(A, dims = 1)) .< 1e-12)
        @test all(abs.(sqrt.(mean(A .^ 2, dims = 1)) .- 1) .< 1e-12)
    end
    @testset "Ridge con alpha -> 0 = MCO" begin
        rng = MersenneTwister(2); A = randn(rng, 25, 4); A = (A .- mean(A, dims = 1)) ./ std(A, dims = 1)
        y = A * [1, -2, 0.5, 3] .+ randn(rng, 25)
        r = ridge_ajustar(A, y, 1e-10)
        @test r.b ≈ (hcat(ones(25), A) \ y)[2:end] atol = 1e-6
    end
    @testset "ElasticNet: KKT y anulación" begin
        rng = MersenneTwister(3); A = randn(rng, 40, 5); A = (A .- mean(A, dims = 1)) ./ std(A, dims = 1)
        y = A * [2, 0, -1, 0, 1] .+ randn(rng, 40)
        f = enet_ajustar(A, y, 0.3, 0.5)
        @test max(enet_kkt(A, y, f, 0.3, 0.5)...) < 1e-8
        @test all(enet_ajustar(A, y, 1e4, 0.5).b .== 0)
    end
    @testset "Métricas, conformal y Winkler" begin
        m = metricas([100.0, 200], [110.0, 180])
        @test m.MAE == 15 && m.RMSE ≈ sqrt(250)
        @test cuantil_conformal(collect(1.0:19), 0.8) == 16
        @test cuantil_conformal(collect(1.0:19), 0.9) == 18
        @test cuantil_conformal(collect(1.0:5), 0.99) == 5
        @test winkler([5.0, 0], [4.0, 1], [6.0, 2], 0.2) ≈ mean([2, 1 + 10])
    end
    @testset "Programa lineal de juguete" begin
        ins = DataFrame(DEPARTAMENTO = ["A", "B"], area = [100.0, 100], productores = [10.0, 10], precio = [1.0, 2],
                        pct_area_semilla_cert = [0.0, 95], prioritario = [true, false])
        pal = (var = ["pct_area_semilla_cert"], nombre = ["Semilla"], base = ["area"], costo = [100.0], tope_pp = [10.0])
        ef = DataFrame(var = ["pct_area_semilla_cert"], beta = [10.0], ee = [1.0], beta_puntual = [10.0], beta_robusto = [8.0])
        r = optimizar_plan(ins, pal, ef, 800.0; cuota = 0.0, tope_depto = 1.0)
        x = Dict(zip(r.plan.DEPARTAMENTO, r.plan.x))
        @test x["B"] ≈ 5 && x["A"] ≈ 3
        @test r.objetivo ≈ 5 * 10 * 100 * 2 + 3 * 10 * 100
        r2 = optimizar_plan(ins, pal, ef, 800.0; cuota = 1.0, tope_depto = 1.0)
        @test sum(r2.plan.costo[r2.plan.DEPARTAMENTO .== "A"]) ≈ 800
        @test optimizar_plan(ins, pal, ef, 800.0; cuota = 0.0, tope_depto = 1.0, tipo = "robusto").objetivo ≈ 0.8r.objetivo
    end
    @testset "Efectos robustos no negativos" begin
        e = efectos_palancas(DataFrame(variable = ["a", "b"], beta = [5.0, -2], ee = [10.0, 1]), (var = ["a", "b"],))
        @test all(e.beta_robusto .>= 0)
    end
end
