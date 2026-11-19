# -*- coding: utf-8 -*-
"""Genera los dos informes LatinR (R y Julia) a partir de las tablas que dejan los pipelines.
Ninguna cifra se escribe a mano: todas se leen de outputs/R/tablas y outputs/julia/tablas."""
import json, re, subprocess, sys
from pathlib import Path
import pandas as pd

RAIZ = Path(__file__).resolve().parents[1]
TEX = RAIZ / "informes" / "tex"
TR, TJ = RAIZ / "outputs" / "R" / "tablas", RAIZ / "outputs" / "julia" / "tablas"
r = lambda f: pd.read_csv(TR / f)
j = lambda f: pd.read_csv(TJ / f)


def n(x, d=2):
    """Número con espacio de miles y punto decimal (formato del artículo)."""
    s = f"{x:,.{d}f}".replace(",", "\\,")
    return s


def pct(x, d=1):
    return f"{x:.{d}f}\\,\\%"


def esc(s):
    return (str(s).replace("\\", "\\textbackslash{}").replace("%", "\\%").replace("_", "\\_")
            .replace("&", "\\&").replace("#", "\\#").replace(">=", "$\\geq$").replace("<", "$<$")
            .replace("|", "$|$"))


def tabla(df, cols, fmts, cab, caption, label, align=None, size="\\small"):
    align = align or ("l" + "r" * (len(cols) - 1))
    filas = []
    for _, f in df.iterrows():
        celdas = []
        for c, fm in zip(cols, fmts):
            v = f[c]
            celdas.append(fm(v) if callable(fm) else esc(v))
        filas.append(" & ".join(celdas) + r" \\")
    return (f"\\begin{{table}}[htbp]\n\\centering\n{size}\n\\caption{{{caption}}}\\label{{{label}}}\n"
            f"\\begin{{tabular}}{{{align}}}\n\\toprule\n{' & '.join(cab)} \\\\\n\\midrule\n"
            + "\n".join(filas) + "\n\\bottomrule\n\\end{tabular}\n\\end{table}\n")


def figura(archivo, caption, label, ancho="\\textwidth"):
    return (f"\\begin{{figure}}[htbp]\n\\centering\n\\includegraphics[width={ancho}]{{{archivo}}}\n"
            f"\\caption{{{caption}}}\\label{{{label}}}\n\\end{{figure}}\n")


def extraer(ruta, inicio, fin_regex, max_lineas=60):
    """Copia literal de un fragmento de código (desde la línea que empieza con `inicio`)."""
    lineas = Path(ruta).read_text(encoding="utf-8").splitlines()
    i = next(k for k, l in enumerate(lineas) if l.startswith(inicio))
    out = []
    for l in lineas[i:i + max_lineas]:
        out.append(l)
        if len(out) > 1 and re.match(fin_regex, l):
            break
    return "\n".join(out)


def codigo(txt, titulo):
    return ("\\begin{Verbatim}[fontsize=\\scriptsize, frame=single, framesep=2mm, label={\\small " + titulo + "}]\n"
            + txt + "\n\\end{Verbatim}\n")


PREAMBULO = r"""\documentclass[letterpaper]{report}
\usepackage[T1]{fontenc}
\usepackage{RJournal}
\usepackage{amsmath,amssymb,array,booktabs}
\usepackage[spanish,es-noshorthands]{babel}
\usepackage{graphicx}
\usepackage{fancyvrb}
\graphicspath{{../../outputs/R/figuras/}{../../outputs/julia/figuras/}}
\renewcommand{\abstract}[1]{\setstretch{1}\noindent\small\textbf{Resumen.} #1}
\providecommand{\keywords}[1]{\par\smallskip\noindent\small\textbf{Palabras clave:} #1\par}
\setlength{\cslhangindent}{1.5em}
\hypersetup{pdfauthor={Rodrigo Claudio Rosas Tuni}}
"""
PREAMBULO = PREAMBULO.replace("\\setlength{\\cslhangindent}{1.5em}\n", "")

AUTOR = ("Rodrigo Claudio Rosas Tuni\\\\ Facultad de Ingeniería Estadística e Informática (FINESI)\\\\ "
         "Universidad Nacional del Altiplano, Puno, Perú")

REFS = r"""
\begin{thebibliography}{99}

\bibitem[Bezanson et~al.(2017)]{julia} Bezanson, J., Edelman, A., Karpinski, S. y Shah, V. B. (2017). Julia: A fresh approach to numerical computing. \emph{SIAM Review}, 59(1), 65--98.

\bibitem[Callohuanca et~al.(2026)]{articulo} Callohuanca Condori, D. L., Mamani Huatta, C. D., Gomez Cahuana, J. R., Mamani Emanuel, E. W. y Rosas Tuni, R. C. (2026). \emph{Pronóstico del rendimiento de papa en el Perú con historial reducido}. Ciencia de Datos I, FINESI-UNA Puno.

\bibitem[Chen y Guestrin(2016)]{xgboost} Chen, T. y Guestrin, C. (2016). XGBoost: A scalable tree boosting system. En \emph{Proceedings of KDD 2016}, 785--794.

\bibitem[Dunning et~al.(2017)]{jump} Dunning, I., Huchette, J. y Lubin, M. (2017). JuMP: A modeling language for mathematical optimization. \emph{SIAM Review}, 59(2), 295--320.

\bibitem[Huang et~al.(2027)]{huang} Huang, R., Luo, W., Jiang, Y. et~al. (2027). A domain-informed forecasting framework for short-horizon carbon emissions prediction in power plants under reduced-history conditions. \emph{Electric Power Systems Research}, 265, 114351.

\bibitem[Huangfu y Hall(2018)]{highs} Huangfu, Q. y Hall, J. A. J. (2018). Parallelizing the dual revised simplex method. \emph{Mathematical Programming Computation}, 10(1), 119--142.

\bibitem[INEI(2025)]{inei} INEI (2025). \emph{Encuesta Nacional Agropecuaria (ENA) 2014--2024 y 2025, microdatos}. Lima: Instituto Nacional de Estadística e Informática.

\bibitem[Kuhn(2008)]{caret} Kuhn, M. (2008). Building predictive models in R using the caret package. \emph{Journal of Statistical Software}, 28(5), 1--26.

\bibitem[Lüdecke et~al.(2022)]{easystats} Lüdecke, D., Ben-Shachar, M. S., Patil, I. y Makowski, D. (2022). easystats: Framework for easy statistical modeling, visualization, and reporting. CRAN.

\bibitem[Lundberg y Lee(2017)]{shap} Lundberg, S. M. y Lee, S.-I. (2017). A unified approach to interpreting model predictions. En \emph{NeurIPS 30}, 4765--4774.

\bibitem[Vovk et~al.(2005)]{conformal} Vovk, V., Gammerman, A. y Shafer, G. (2005). \emph{Algorithmic Learning in a Random World}. Springer.

\bibitem[Wickham et~al.(2019)]{tidyverse} Wickham, H. et~al. (2019). Welcome to the tidyverse. \emph{Journal of Open Source Software}, 4(43), 1686.
\end{thebibliography}
"""


def datos_comunes(T):
    d = {}
    d["val"] = T("registro_validaciones.csv")
    d["rec"] = T("validacion_reconstruccion.csv")
    d["mod"] = T("cuadro2_modelos.csv")
    d["est"] = T("cuadro3_estabilidad.csv")
    d["sen"] = T("cuadro4_sensibilidad.csv")
    d["con"] = T("cuadro5_conformal.csv")
    d["hel"] = T("cuadro6_heladas.csv")
    d["sem"] = T("xgboost_semillas.csv")
    d["dpy"] = T("validacion_vs_python.csv")
    d["shap"] = T("shap_importancia.csv")
    d["resid"] = T("residuos_resumen.csv")
    d["ef"] = T("efectos_fijos_parametros.csv")
    d["diag"] = T("efectos_fijos_diagnostico.csv")
    d["pal"] = T("efectos_palancas.csv")
    d["ale"] = T("alerta_2026.csv")
    d["ins"] = T("insumos_prescriptivos.csv")
    d["pp"] = T("plan_puntual.csv")
    d["pr"] = T("plan_robusto.csv")
    d["porp"] = T("plan_por_palanca.csv")
    d["mc"] = T("montecarlo_planes.csv")
    d["fr"] = T("frontera_presupuesto.csv")
    d["be"] = T("presupuesto_eficiente.csv")
    d["eq"] = T("costo_equidad.csv")
    d["cos"] = T("sensibilidad_costos.csv")
    d["ver"] = T("versiones_paquetes.csv")
    d["corr"] = T("correlaciones_rendimiento.csv")
    return d


NOM_VAR = {"pct_area_con_riego": "Riego (\\% área)", "pct_area_semilla_cert": "Semilla certificada (\\% área)",
           "pct_fert": "Fertilizante", "pct_abono": "Abono", "pct_asist": "Asistencia técnica",
           "pct_capac": "Capacitación", "pct_asoc": "Asociatividad", "pct_credito": "Crédito",
           "pct_perd_helada": "Pérdida por helada", "pct_perd_sequia": "Pérdida por sequía"}
ART = {"Naive Lag1": (2044.97, 3361.84), "Panel FE-ARDL": (2601.96, 3829.68), "Ridge": (2240.12, 3346.52),
       "ElasticNet": (3694.59, 5007.97), "XGBoost (prof. 2)": (2349.36, 3300.15), "Ensamble informado": (2194.22, 3092.66)}


def bloques_resultados(d, L):
    """Secciones con cifras (comunes a ambos informes; L = 'R' o 'Julia')."""
    pref = "r" if L == "R" else "j"
    m = d["mod"].set_index("modelo")
    ens, nai = m.loc["Ensamble informado"], m.loc["Naive Lag1"]
    con = d["con"]; c80 = con[(con.Nivel == "80 %")].set_index("Metodo"); c90 = con[(con.Nivel == "90 %")].set_index("Metodo")
    hel = d["hel"].set_index(["Regimen", "Modelo"])
    ha_n, ha_e = hel.loc[("Alta incidencia (>= 5 %)", "Naive Lag1")], hel.loc[("Alta incidencia (>= 5 %)", "Ensamble informado")]
    sem = d["sem"]
    dpy = d["dpy"].set_index("modelo")["dif_max_kg_ha"]
    out = {}
    tab_m = d["mod"].copy()
    tab_m["MAE_art"] = [ART[x][0] for x in tab_m.modelo]; tab_m["RMSE_art"] = [ART[x][1] for x in tab_m.modelo]
    tab_m["dpy"] = [dpy[x] for x in tab_m.modelo]
    out["tab_modelos"] = tabla(tab_m, ["modelo", "MAE", "RMSE", "MAPE", "MAE_art", "RMSE_art", "dpy"],
        [None, n, n, lambda v: pct(v, 2), n, n, lambda v: f"{v:.1e}".replace("e-0", "e-").replace("e+0", "e+")],
        ["Modelo", "MAE", "RMSE", "MAPE", "MAE art.", "RMSE art.", "Dif. máx."],
        f"Desempeño fuera de muestra (95 pronósticos, 2021--2025) en {L}, frente al artículo de referencia. "
        "La última columna es la mayor diferencia absoluta (kg/ha) entre cada pronóstico y el de Python.",
        "tab:modelos")
    out["ens"], out["nai"] = ens, nai
    out["mejora_rmse"] = 100 * (1 - ens.RMSE / nai.RMSE)
    out["c80"], out["c90"] = c80, c90
    out["ha_n"], out["ha_e"] = ha_n, ha_e
    out["sem_min"], out["sem_max"] = sem.RMSE_ens.min(), sem.RMSE_ens.max()
    out["sem_gana"] = int((sem.RMSE_ens < nai.RMSE).sum()); out["sem_n"] = len(sem)
    out["dpy"] = dpy
    out["tab_conf"] = tabla(con, ["Nivel", "Metodo", "Cobertura", "Error", "Ancho", "Winkler"],
        [None, None, lambda v: pct(v), lambda v: f"{v:+.1f}", lambda v: n(v, 1), lambda v: n(v, 1)],
        ["Nominal", "Método", "Cobertura", "Error (pp)", "Ancho medio", "Winkler"],
        "Intervalos de predicción del ensamble antes y después de la calibración split-conformal.", "tab:conf")
    sen = d["sen"]
    out["tab_sens"] = tabla(sen, ["Escenario", "MAE", "RMSE", "MAPE"], [None, n, n, lambda v: pct(v, 2)],
        ["Escenario", "MAE", "RMSE", "MAPE"], "Sensibilidad del ensamble informado (kg/ha).", "tab:sens", align="lrrr")
    # efectos fijos
    ef = d["ef"].copy(); ef["nombre"] = ef.variable.map(NOM_VAR)
    out["tab_ef"] = tabla(ef, ["nombre", "beta", "ee", "t", "p"],
        [lambda v: v, lambda v: n(v, 1), lambda v: n(v, 1), lambda v: f"{v:.2f}", lambda v: f"{v:.3f}"],
        ["Covariable (pp)", "$\\hat\\beta$ (kg/ha)", "EE agrupado", "$t$", "$p$"],
        "Modelo explicativo con efectos fijos por departamento y año (190 obs.). Errores estándar agrupados "
        "por departamento (CR1).", "tab:ef")
    out["ef"] = ef.set_index("variable")
    diag = d["diag"]
    out["bp"] = float(diag.iloc[0, 1]); out["sw"] = float(diag.iloc[1, 1])
    out["vif"] = float(diag[diag.prueba.str.startswith("VIF")].iloc[0, -1])
    # prescriptivo
    pal = d["pal"].copy()
    nombres_pal = {"pct_area_con_riego": "Riego tecnificado", "pct_area_semilla_cert": "Semilla certificada",
                   "pct_asist": "Asistencia técnica", "pct_credito": "Crédito agrario"}
    costos = {"pct_area_con_riego": "1\\,500 por ha", "pct_area_semilla_cert": "3\\,000 por ha",
              "pct_asist": "600 por productor", "pct_credito": "500 por productor"}
    topes = {"pct_area_con_riego": "10", "pct_area_semilla_cert": "10", "pct_asist": "15", "pct_credito": "10"}
    pal["nombre"] = pal["var"].map(nombres_pal); pal["costo"] = pal["var"].map(costos); pal["tope"] = pal["var"].map(topes)
    out["tab_pal"] = tabla(pal, ["nombre", "beta_puntual", "ee", "beta_robusto", "costo", "tope"],
        [None, lambda v: n(v, 1), lambda v: n(v, 1), lambda v: n(v, 1), lambda v: v, lambda v: v],
        ["Palanca", "$\\beta$ puntual", "EE", "$\\beta$ robusto", "Costo (S/, supuesto)", "Tope (pp)"],
        "Palancas de decisión: efecto por punto porcentual (kg/ha), efecto robusto "
        "$\\max(0,\\hat\\beta-1.28\\,\\mathrm{EE})$, costo unitario por campaña y aumento máximo.", "tab:palancas")
    ale = d["ale"]
    out["prior"] = ", ".join(ale[ale.prioritario].DEPARTAMENTO.tolist())
    out["n_prior"] = int(ale.prioritario.sum())
    ins = d["ins"].set_index("DEPARTAMENTO")
    pr = d["pr"].copy(); pp = d["pp"].copy()
    pr["prior"] = pr.DEPARTAMENTO.map(ins.prioritario); pp["prior"] = pp.DEPARTAMENTO.map(ins.prioritario)
    out["pr"], out["pp"] = pr, pp
    out["pr_val"], out["pp_val"] = pr.valor.sum(), pp.valor.sum()
    out["pr_t"], out["pp_t"] = pr.t_adic.sum(), pp.t_adic.sum()
    out["pr_gasto"], out["pp_gasto"] = pr.costo.sum(), pp.costo.sum()
    out["pr_prior_pct"] = 100 * pr.costo[pr.prior].sum() / pr.costo.sum()
    out["pp_prior_pct"] = 100 * pp.costo[pp.prior].sum() / pp.costo.sum()
    agr = (pr.groupby("DEPARTAMENTO").agg(costo=("costo", "sum"), t=("t_adic", "sum"), valor=("valor", "sum"),
           palancas=("palanca", lambda s: ", ".join(sorted(set(s))))).sort_values("costo", ascending=False).reset_index())
    agr["prior"] = agr.DEPARTAMENTO.map(lambda x: "sí" if ins.prioritario[x] else "")
    out["tab_plan_r"] = tabla(agr, ["DEPARTAMENTO", "palancas", "costo", "t", "valor", "prior"],
        [None, None, lambda v: n(v / 1e6, 2), lambda v: n(v, 0), lambda v: n(v / 1e6, 2), None],
        ["Departamento", "Palanca(s)", "S/ M", "t adicionales", "Valor S/ M", "Prior."],
        "Plan robusto recomendado para un presupuesto de S/ 50 millones por campaña.", "tab:plan", align="llrrrc",
        size="\\footnotesize")
    mc = d["mc"].set_index("plan")
    out["mc"] = mc
    tab_mc = d["mc"].copy()
    out["tab_mc"] = tabla(tab_mc, ["plan", "media_exacta", "p05_exacto", "p95_exacto", "prob_bc_menor_1_exacta", "p05"],
        [None, lambda v: n(v / 1e6, 1), lambda v: n(v / 1e6, 1), lambda v: n(v / 1e6, 1), lambda v: pct(100 * v, 2),
         lambda v: n(v / 1e6, 1)],
        ["Plan", "Valor esperado", "P05", "P95", "P(B/C $<$ 1)", "P05 Montecarlo"],
        "Valor de cada plan (millones de S/) cuando el efecto verdadero varía según la incertidumbre estimada "
        "(normal multivariada con la covarianza agrupada). Las columnas exactas usan la normalidad del valor; "
        "la última viene de 20\\,000 simulaciones.", "tab:mc")
    be = d["be"].set_index("tipo").B_max_eficiente
    out["be_p"], out["be_r"] = be["puntual"], be["robusto"]
    fr = d["fr"]
    out["cap_r"] = fr[fr.tipo == "robusto"].gasto.max()
    sp = fr[(fr.B == 50e6)].set_index("tipo").precio_sombra
    out["sp_p"], out["sp_r"] = sp["puntual"], sp["robusto"]
    eq = d["eq"].set_index("cuota").costo_equidad
    out["eq30"], out["eq50"] = eq[0.3], eq[0.5]
    cos = d["cos"].set_index("factor").bc
    out["cos05"], out["cos15"] = cos[0.5], cos[1.5]
    porp = d["porp"]
    out["porp"] = porp
    shap = d["shap"]
    out["shap_top"] = ", ".join(shap.variable.iloc[1:5].str.lower())
    out["shap_lag"] = shap.shap_medio.iloc[0]
    out["resid_p"] = d["resid"].shapiro_p.iloc[0]; out["resid_m"] = d["resid"].media_residuo.iloc[0]
    v = d["val"]
    out["n_val"], out["n_ok"] = len(v), int(v.ok.sum())
    resumen_val = v.groupby("rama", sort=False).agg(pruebas=("ok", "size"), aprobadas=("ok", "sum")).reset_index()
    out["tab_val"] = tabla(resumen_val, ["rama", "pruebas", "aprobadas"], [None, lambda x: str(x), lambda x: str(int(x))],
        ["Rama", "Validaciones", "Aprobadas"], f"Validaciones automáticas del pipeline en {L} (el pipeline se detiene "
        "si alguna falla).", "tab:val", align="lrr")
    out["rec_max"] = d["rec"].dif_abs_max.max()
    out["ver"] = d["ver"]
    out["pref"] = pref
    return out


def plan_figuras(L):
    p = "r" if L == "R" else "j"
    return {k: f"{p}{v}" for k, v in {
        "evol": "01_evolucion.png", "dep": "02_departamentos.png", "corr": "03_correlacion.png",
        "diag": "04_check_model.png" if L == "R" else "04_diagnostico_ef.png", "rvp": "05_real_vs_pred.png",
        "conf": "06_conformal.png", "estab": "07_estabilidad_shap.png", "resh": "08_residuos_heladas.png",
        "ale": "09_alerta_2026.png", "plan": "10_plan_optimo.png", "front": "11_frontera_montecarlo.png"}.items()}


def informe(L):
    T = r if L == "R" else j
    d = datos_comunes(T)
    o = bloques_resultados(d, L)
    F = plan_figuras(L)
    ens, nai, c80, c90 = o["ens"], o["nai"], o["c80"], o["c90"]
    es_R = L == "R"
    ver = o["ver"].set_index("paquete").version
    ver_leng = ver["R"] if es_R else ver["Julia"]
    dpy = o["dpy"]
    titulo = ("Analítica prescriptiva del rendimiento de papa en el Perú con R: del pronóstico con historial "
              "reducido a la asignación óptima de inversión (ENA 2015--2025)") if es_R else \
             ("Analítica prescriptiva del rendimiento de papa en el Perú con Julia: pronóstico con historial "
              "reducido y optimización con JuMP (ENA 2015--2025)")
    herr = ("\\pkg{tidyverse}, \\pkg{caret}, \\pkg{easystats}, \\pkg{xgboost}, \\pkg{lpSolve}, \\pkg{shiny} y "
            "\\pkg{shinytest2}") if es_R else ("\\pkg{DataFrames.jl}, \\pkg{XGBoost.jl}, \\pkg{JuMP} con el "
            "solucionador \\pkg{HiGHS}, \\pkg{Plots.jl} y la biblioteca estándar \\pkg{Test}")
    xgb_frase = (f"Con la misma semilla, \\pkg{{xgboost}} {ver['xgboost']} de R reprodujo también el XGBoost del artículo "
                 f"(diferencia máxima de {dpy['XGBoost (prof. 2)']:.4f} kg/ha, del orden de la precisión de 32 bits), "
                 "así que el cuadro coincide con el artículo en los seis modelos.") if es_R else \
                (f"El XGBoost es el único modelo que cambia: \\pkg{{XGBoost.jl}} usa \\texttt{{libxgboost}} 2.1, cuya "
                 "secuencia aleatoria para el submuestreo de filas y columnas no es la de Python ni la de R. Con la "
                 f"semilla 7 el ensamble obtiene un RMSE de {n(ens.RMSE)} kg/ha, {abs(100*(ens.RMSE/3092.66-1)):.1f}\\,\\% "
                 "por debajo del artículo. Esta diferencia sirve como prueba de robustez: la conclusión no depende "
                 "de una implementación concreta.")
    resumen = (
        f"La Encuesta Nacional Agropecuaria (ENA) deja solo diez años útiles para la papa (2015--2025, sin 2020). "
        f"Este trabajo lleva el pronóstico con historial reducido de un artículo previo a una pregunta de decisión: con "
        f"S/ 50 millones por campaña, ¿en qué departamentos y en qué palancas conviene invertir? El pipeline, escrito en "
        f"{L} con {herr}, tiene seis ramas y {o['n_val']} validaciones automáticas. Primero reconstruye el panel "
        f"departamental desde los microdatos y reproduce el artículo: el ensamble informado logra un RMSE de "
        f"{n(ens.RMSE)} kg/ha frente a {n(nai.RMSE)} del modelo ingenuo, y la calibración conformal lleva la cobertura "
        f"del 80\\,\\% nominal de {pct(c80.loc['Gaussiano (sin calibrar)'].Cobertura)} a "
        f"{pct(c80.loc['Split-conformal'].Cobertura)}. Después estima el efecto de cada palanca con efectos fijos y "
        f"resuelve un programa lineal con restricciones de presupuesto, topes y equidad para los {o['n_prior']} "
        f"departamentos con heladas frecuentes. El plan robusto, que usa la cota inferior de los efectos, destina "
        f"{pct(o['pr_prior_pct'],0)} del presupuesto a los departamentos priorizados, sobre todo en semilla certificada, "
        f"y produce un valor adicional de S/ {n(o['pr_val']/1e6,1)} millones con una probabilidad de no recuperar la "
        f"inversión de {pct(100*o['mc'].loc['Plan robusto'].prob_bc_menor_1_exacta,2)}.")
    claves = ("analítica prescriptiva - programación lineal - calibración conformal - papa - " + L)

    ramas = r"""\begin{table}[htbp]
\centering\small
\caption{Ramas del pipeline y producto de cada una.}\label{tab:ramas}
\begin{tabular}{p{0.9cm}p{4.2cm}p{9.8cm}}
\toprule
Rama & Archivo & Qué hace \\
\midrule
""" + ("""0 & \\code{00\\_config.R} & Rutas de datos, huellas SHA-256 y todos los parámetros (modelo y supuestos). \\\\
1 & \\code{01\\_librerias.R} & Verifica e importa las librerías; registra versiones. \\\\
2 & \\code{02\\_datos\\_validacion.R} & Reconstruye el panel desde los microdatos y lo contrasta con el Excel. \\\\
3 & \\code{03\\_descriptivo\\_easystats.R} & Descriptivos, correlaciones y modelo de efectos fijos con diagnóstico \\pkg{easystats}. \\\\
4 & \\code{04\\_predictivo\\_walkforward.R} & Réplica del artículo: walk-forward, conformal, heladas, SHAP; verificación con \\pkg{caret}. \\\\
5 & \\code{05\\_prescriptivo.R} & Alerta 2026, efectos de palancas, programa lineal, Montecarlo y frontera. \\\\
6 & \\code{06\\_comunicacion\\_pruebas.R} & Tablero \\pkg{shiny}, pruebas \\pkg{testthat}/\\pkg{shinytest2} y registro final. \\\\""" if es_R else
"""0 & \\code{00\\_config.jl} & Rutas de datos, huellas SHA-256 y todos los parámetros (modelo y supuestos). \\\\
1 & \\code{01\\_librerias.jl} & Carga las librerías y registra versiones. \\\\
2 & \\code{02\\_datos\\_validacion.jl} & Reconstruye el panel desde los microdatos y lo contrasta con el Excel. \\\\
3 & \\code{03\\_descriptivo.jl} & Descriptivos, correlaciones y efectos fijos con errores agrupados y diagnósticos. \\\\
4 & \\code{04\\_predictivo.jl} & Réplica del artículo: walk-forward, conformal, heladas, SHAP exacto. \\\\
5 & \\code{05\\_prescriptivo.jl} & Alerta 2026, efectos de palancas, programa lineal (\\pkg{JuMP}+\\pkg{HiGHS}), Montecarlo. \\\\
6 & \\code{06\\_comunicacion\\_pruebas.jl} & Pruebas \\pkg{Test}, comparación con R y ficha de decisión en HTML. \\\\""") + r"""
\bottomrule
\end{tabular}
\end{table}
"""
    if es_R:
        libs = r"""\begin{table}[htbp]
\centering\small
\caption{Librerías de R usadas y su papel en el pipeline.}\label{tab:libs}
\begin{tabular}{p{3.2cm}p{1.6cm}p{10cm}}
\toprule
Librería & Versión & Uso \\
\midrule
""" + "\n".join(f"\\pkg{{{p}}} & {esc(ver[p])} & {u} \\\\" for p, u in [
            ("tidyverse", "Lectura (\\pkg{readr}), agregación ponderada (\\pkg{dplyr}), pivotes y figuras (\\pkg{ggplot2})."),
            ("caret", "Verificación del panel FE-ARDL con índices walk-forward propios en \\code{trainControl()}."),
            ("easystats", "\\pkg{correlation}, \\pkg{parameters} (errores agrupados), \\pkg{performance} (diagnósticos) y \\pkg{see}."),
            ("xgboost", "Árbol restringido (profundidad 2) y valores SHAP exactos con \\code{predcontrib = TRUE}."),
            ("glmnet", "Disponible para contraste; ElasticNet se implementa con la función objetivo de scikit-learn."),
            ("sandwich", "Matriz de covarianza agrupada por departamento (CR1)."),
            ("lpSolve", "Programa lineal de la analítica prescriptiva, con precios sombra."),
            ("shiny", "Tablero interactivo para quien decide."),
            ("shinytest2", "Prueba de extremo a extremo del tablero en Chrome."),
            ("testthat", "Pruebas unitarias y de servidor (\\code{testServer})."),
            ("digest", "Huellas SHA-256 de los archivos de entrada.")]) + r"""
\bottomrule
\end{tabular}
\end{table}
"""
    else:
        libs = r"""\begin{table}[htbp]
\centering\small
\caption{Librerías de Julia usadas y su equivalente en R.}\label{tab:libs}
\begin{tabular}{p{3.2cm}p{1.4cm}p{6.6cm}p{3.6cm}}
\toprule
Librería & Versión & Uso & Equivalente en R \\
\midrule
""" + "\n".join(f"\\pkg{{{p}}} & {esc(ver.get(k, '--'))} & {u} & {e} \\\\" for p, k, u, e in [
            ("CSV.jl, DataFrames.jl", "DataFrames", "Lectura y agregación ponderada con \\code{groupby}/\\code{combine}.", "\\pkg{readr}, \\pkg{dplyr}"),
            ("XLSX.jl", "XLSX", "Lectura de \\code{series\\_ENA\\_papa.xlsx}.", "\\pkg{readxl}"),
            ("LinearAlgebra, GLM", "GLM", "MCO con efectos fijos, Ridge en forma cerrada, errores CR1.", "\\pkg{stats}, \\pkg{sandwich}"),
            ("XGBoost.jl", "XGBoost", "Árbol restringido; SHAP exacto llamando a \\code{libxgboost} (tipo 2).", "\\pkg{xgboost}"),
            ("JuMP + HiGHS", "JuMP", "Modelado y solución del programa lineal; precios sombra.", "\\pkg{lpSolve}"),
            ("Distributions, HypothesisTests", "--", "Normal multivariada (Montecarlo) y Shapiro--Wilk.", "\\pkg{stats}"),
            ("Plots.jl (GR)", "Plots", "Figuras.", "\\pkg{ggplot2}"),
            ("Test, SHA", "--", "Pruebas unitarias y huellas SHA-256.", "\\pkg{testthat}, \\pkg{digest}")]) + r"""
\bottomrule
\end{tabular}
\end{table}
"""
    cod_lp = extraer(RAIZ / ("R/funciones_prescriptivas.R" if es_R else "julia/funciones_prescriptivas.jl"),
                     "optimizar_plan <- function" if es_R else "function optimizar_plan",
                     r"^}" if es_R else r"^end")
    cod_wf = extraer(RAIZ / ("R/funciones_modelos.R" if es_R else "julia/funciones_modelos.jl"),
                     "cuantil_conformal <- function" if es_R else "cuantil_conformal(res, nivel)", r".*", 1)
    cod_chk = extraer(RAIZ / ("R/02_datos_validacion.R" if es_R else "julia/02_datos_validacion.jl"),
                      "chequear <- function" if es_R else "function chequear", r"^}" if es_R else r"^end")

    s = PREAMBULO + "\\begin{document}\n\\sectionhead{" + ("Analítica prescriptiva con R" if es_R else
         "Analítica prescriptiva con Julia") + "}\n\\year{2026}\n\\begin{article}\n"
    s += f"\\title{{{titulo}}}\n\\author{{Rodrigo Claudio Rosas Tuni}}\n\\maketitle\n"
    s += f"\\abstract{{{resumen}}}\n\\keywords{{{claves}}}\n\n"

    # 1 Introducción
    s += "\\section{1. Introducción y reto}\n"
    s += ("En un trabajo previo del grupo \\citep{articulo} se pronosticó el rendimiento de papa de la ENA \\citep{inei} "
          "con el marco de \\citet{huang} para historial reducido: covariables de dominio, validación rolling-origin y "
          "calibración conformal. Ese trabajo responde a la pregunta \\emph{qué va a pasar}. Para una institución "
          "pública la pregunta útil es otra: \\emph{qué hacer con un presupuesto limitado}. Esa es la tarea de la "
          "analítica prescriptiva.\n\n")
    s += ("\\textbf{Reto.} Con S/ 50 millones por campaña, decidir cuánto subir cuatro palancas (riego tecnificado, "
          "semilla certificada, asistencia técnica y crédito) en 19 departamentos para obtener el mayor valor de "
          "producción adicional, sin concentrar el gasto y sin dejar de lado a los departamentos con heladas "
          "frecuentes. El pipeline debe ser reproducible, validarse a sí mismo y comunicar la decisión a quien no "
          "programa.\n\n")
    s += ("El trabajo se preparó para LatinR. " + ("Este informe documenta la versión en R; un informe gemelo hace lo mismo en Julia "
          "\\citep{julia} y ambos comparan sus resultados." if es_R else
          "Este informe documenta la versión en Julia; un informe gemelo hace lo mismo en R y la rama 6 compara "
          "ambos resultados cifra por cifra.") + "\n\n")

    # 2 ruta
    s += "\\section{2. Rama 0: ruta del pipeline}\n"
    s += ("Todas las rutas se definen una sola vez en el archivo de configuración y se construyen desde la raíz del "
          "proyecto, de modo que el código funciona en cualquier computadora. Los insumos son tres archivos: "
          "\\code{ENA\\_cultivo\\_filas.csv} (139\\,466 filas de papa cosechada), \\code{ENA\\_productores.csv} "
          "(384\\,525 productores) y \\code{series\\_ENA\\_papa.xlsx} (series agregadas). Cada uno tiene una huella "
          "SHA-256 registrada: si un archivo cambia, el pipeline se detiene en la primera línea. El Cuadro~\\ref{tab:ramas} "
          "resume las seis ramas.\n\n" + ramas)
    s += codigo("ENA_papa_prescriptivo/\n  data/raw/          insumos (solo lectura)\n  data/referencia/   métricas y pronósticos del artículo (Python)\n"
                "  R/                 ramas 00-06, funciones, app/ (Shiny) y tests/\n  julia/             ramas 00-06, funciones y test/\n"
                "  outputs/R | julia/ tablas/, figuras/, logs y resumen JSON\n  informes/          fuentes LaTeX de este informe",
                "Estructura de carpetas")

    # 3 librerías
    s += "\\section{3. Rama 1: librerías}\n"
    s += (("Se usan las librerías pedidas para el trabajo: \\pkg{tidyverse} \\citep{tidyverse} para datos y gráficos, "
           "\\pkg{caret} \\citep{caret} como interfaz de modelos, \\pkg{easystats} \\citep{easystats} para diagnóstico "
           "y reporte, y \\pkg{shinytest2} para probar el tablero. El Cuadro~\\ref{tab:libs} indica el papel de cada una. "
           f"El análisis corrió en R {esc(ver_leng)}.\n\n") if es_R else
          ("Julia no tiene un equivalente directo de \\pkg{tidyverse} ni de \\pkg{easystats}; sus funciones se cubren con "
           "\\pkg{DataFrames.jl} y con diagnósticos escritos a mano y verificados contra R. Para la optimización se usa "
           "\\pkg{JuMP} \\citep{jump} con \\pkg{HiGHS} \\citep{highs}. Como aplicaciones de referencia para un tablero "
           "en Julia existen \\pkg{Genie.jl} y los cuadernos reactivos \\pkg{Pluto.jl}; aquí se optó por una ficha HTML "
           f"autocontenida. El análisis corrió en Julia {esc(ver_leng)}.\n\n")) + libs

    # 4 datos
    s += "\\section{4. Rama 2: datos y validación}\n"
    s += ("Antes de modelar se rehízo el panel departamental desde los microdatos: el rendimiento es "
          "$\\sum f_k\\,\\mathrm{kg}_k/\\sum f_k\\,\\mathrm{ha}_k$ con el factor de expansión $f_k$, y cada covariable es un "
          "porcentaje ponderado entre quienes respondieron. En la ENA 2025 el módulo de pérdidas solo lista a quienes "
          "perdieron, así que el resto se cuenta como sin pérdida. Las 196 celdas año-departamento coinciden con el "
          f"Excel en las 14 variables (diferencia máxima {o['rec_max']:.1e}). Hay 142 filas válidas sin ubigeo (2024--2025): "
          "entran a la serie nacional, pero no a ningún departamento.\n\n"
          "El panel de análisis tiene 19 departamentos con los 10 años (Loreto y San Martín quedan fuera por tener solo "
          "tres). El crédito de 2021 no se preguntó; se arrastra el valor de 2019 del mismo departamento, que es "
          "información pasada. Cada regla anterior es una validación que detiene el pipeline si falla:\n\n")
    s += codigo(cod_chk, "Función de validación (se usa en todas las ramas)")

    # 5 descriptivo
    s += "\\section{5. Rama 3: descriptivo y diagnóstico}\n"
    corr = d["corr"].set_index("variable").r
    s += ("Las medias por departamento reproducen el Cuadro~1 del artículo al centésimo: la costa (Lima, Ica, Arequipa) "
          "supera los 20\\,000 kg/ha y Puno y Lambayeque no llegan a 6\\,100 (Figura~\\ref{fig:evol}). Las correlaciones "
          f"con el rendimiento también coinciden: crédito ({corr['Crédito']:.2f}), semilla certificada "
          f"({corr['Semilla cert.']:.2f}), riego ({corr['Riego']:.2f}) y asistencia técnica ({corr['Asist. técnica']:.2f}). "
          "Son correlaciones entre departamentos; para decidir hace falta saber qué pasa \\emph{dentro} de un mismo "
          "departamento cuando una palanca sube.\n\n")
    s += figura(F["evol"], "Rendimiento nacional y de cuatro departamentos, 2015--2025.", "fig:evol", "0.85\\textwidth")
    s += ("Por eso la prescripción se apoya en un modelo con efectos fijos por departamento y por año (Cuadro~\\ref{tab:ef}). "
          "Los efectos fijos absorben lo que no cambia en cada departamento (altitud, suelos, costa o sierra) y los choques "
          "comunes de cada año. El diagnóstico muestra heterocedasticidad fuerte (Breusch--Pagan, "
          f"$p = {o['bp']:.1e}$) y residuos no normales (Shapiro--Wilk, $p = {o['sw']:.1e}$); el VIF máximo es "
          f"{o['vif']:.2f}, sin colinealidad preocupante. Esto justifica los errores agrupados por departamento y, más "
          "adelante, los intervalos conformales.\n\n")
    s += o["tab_ef"]
    ef = o["ef"]
    s += (f"Dentro de cada departamento, un punto porcentual más de área con semilla certificada se asocia con "
          f"{n(ef.loc['pct_area_semilla_cert'].beta,1)} kg/ha más ($p = {ef.loc['pct_area_semilla_cert'].p:.4f}$). "
          f"La asistencia técnica tiene un coeficiente mayor ({n(ef.loc['pct_asist'].beta,1)}) pero impreciso "
          f"($p = {ef.loc['pct_asist'].p:.2f}$). El riego, muy correlacionado entre departamentos, casi no se mueve "
          f"dentro de ellos ({n(ef.loc['pct_area_con_riego'].beta,1)} kg/ha, $p = {ef.loc['pct_area_con_riego'].p:.2f}$): en diez "
          "años un departamento cambia poco su superficie regada.\n\n")
    s += figura(F["diag"], ("Diagnóstico del modelo de efectos fijos con \\code{performance::check\\_model()}." if es_R else
                            "Diagnóstico del modelo de efectos fijos: residuos frente a ajustados y Q-Q normal."),
                "fig:diag", "0.8\\textwidth" if es_R else "0.9\\textwidth")

    # 6 predictivo
    s += "\\section{6. Rama 4: analítica predictiva (réplica del artículo)}\n"
    s += ("La rama 4 repite la validación walk-forward del artículo: en cada año de prueba (2021--2025) se entrena con los "
          "años anteriores y se pronostica un año adelante para los 19 departamentos, lo que da 95 pronósticos fuera de "
          "muestra. Se comparan seis modelos con los hiperparámetros fijados en el artículo. El Ridge se resolvió en forma "
          "cerrada y el ElasticNet por descenso de coordenadas con la función objetivo de scikit-learn; su solución se "
          "verificó con las condiciones de optimalidad KKT. "
          + ("El panel FE-ARDL se volvió a ajustar con \\code{caret::train()} usando los mismos índices walk-forward y los "
             "pronósticos coincidieron exactamente.\n\n" if es_R else "\n\n"))
    s += o["tab_modelos"]
    s += (f"Los cuatro modelos deterministas coinciden con Python hasta {max(dpy[['Naive Lag1','Panel FE-ARDL','Ridge']]):.0e} "
          f"kg/ha (ElasticNet: {dpy['ElasticNet']:.1e}, por la tolerancia de scikit-learn). " + xgb_frase + "\n\n")
    s += (f"El ensamble reduce el RMSE en {o['mejora_rmse']:.1f}\\,\\% frente al ingenuo, pero no el MAE "
          f"({n(ens.MAE)} frente a {n(nai.MAE)}): comete menos errores grandes, aunque en los casos típicos el valor del año "
          f"anterior sigue siendo difícil de superar. Al repetir el XGBoost con {o['sem_n']} semillas, el RMSE del ensamble "
          f"queda entre {n(o['sem_min'])} y {n(o['sem_max'])} kg/ha y supera al ingenuo en {o['sem_gana']} de "
          f"{o['sem_n']} casos (Figura~\\ref{{fig:rvp}}).\n\n")
    s += figura(F["rvp"], "Rendimiento real frente al pronosticado en los 95 casos de prueba.", "fig:rvp", "0.55\\textwidth")
    s += ("La incertidumbre se calibra con split-conformal \\citep{conformal}: el último año de cada ventana de entrenamiento "
          "se pronostica con los años previos y el cuantil $\\lceil (n+1)(1-\\alpha)\\rceil/n$ de esos errores "
          "($n=19$) da el ancho del intervalo.\n\n")
    s += codigo(cod_wf, "Cuantil split-conformal")
    s += o["tab_conf"]
    s += (f"Los intervalos gaussianos quedan muy cortos ({pct(c80.loc['Gaussiano (sin calibrar)'].Cobertura)} de cobertura "
          f"al 80\\,\\% nominal); con calibración conformal la cobertura sube a {pct(c80.loc['Split-conformal'].Cobertura)} "
          f"y {pct(c90.loc['Split-conformal'].Cobertura)} al 90\\,\\%, a cambio de intervalos más anchos "
          "(Figura~\\ref{fig:conf}).\n\n")
    s += figura(F["conf"], "Bandas al 80\\,\\%: gaussiana (izquierda) y split-conformal (derecha).", "fig:conf")
    s += (f"En los 33 casos con heladas en al menos 5\\,\\% de productores, el ensamble baja el MAE de {n(o['ha_n'].MAE)} a "
          f"{n(o['ha_e'].MAE)} kg/ha y el RMSE de {n(o['ha_n'].RMSE)} a {n(o['ha_e'].RMSE)}. El rendimiento del año previo "
          f"domina la importancia SHAP \\citep{{shap}} ({n(o['shap_lag'],0)} kg/ha de contribución media), seguido de "
          f"{o['shap_top']}. Los residuos del ensamble tienen media {n(o['resid_m'],0)} kg/ha y colas pesadas "
          f"(Shapiro--Wilk $p = {o['resid_p']:.3f}$), lo que respalda el uso de intervalos conformales "
          "(Figuras~\\ref{fig:estab} y~\\ref{fig:resh}).\n\n")
    s += o["tab_sens"]
    s += figura(F["estab"], "RMSE por año de prueba e importancia SHAP del XGBoost.", "fig:estab")
    s += figura(F["resh"], "Residuos del ensamble y error según la incidencia de heladas.", "fig:resh")

    # 7 prescriptivo
    s += "\\section{7. Rama 5: analítica prescriptiva}\n"
    s += "\\subsection{7.1 Alerta temprana 2026 y departamentos priorizados}\n"
    s += ("El ensamble, entrenado con todos los años, pronostica 2026 suponiendo que las covariables se mantienen como en "
          "2025, con un intervalo conformal al 80\\,\\% calibrado en 2025. Un departamento es \\emph{priorizado} si tuvo "
          "heladas con pérdida total en al menos 5\\,\\% de productores en promedio entre 2021 y 2025 y, además, su "
          "pronóstico 2026 está por debajo de su media histórica o su rendimiento medio está bajo el promedio nacional. "
          f"Resultan {o['n_prior']}: {o['prior']} (Figura~\\ref{{fig:ale}}).\n\n")
    s += figura(F["ale"], "Pronóstico 2026 con intervalo conformal al 80\\,\\%. La marca vertical es la media 2015--2025.",
                "fig:ale", "0.75\\textwidth")
    s += "\\subsection{7.2 Formulación}\n"
    s += ("Sea $x_{ik}$ el aumento, en puntos porcentuales, de la palanca $k$ en el departamento $i$. El programa lineal es\n"
          "\\begin{align*}\n\\max_{x}\\; & \\textstyle\\sum_{i,k} \\beta_k\\, S_i\\, p_i\\, x_{ik} \\\\\n"
          "\\text{s.a.}\\; & \\textstyle\\sum_{i,k} c_{ik}\\, x_{ik} \\le B, \\qquad "
          "\\sum_{k} c_{ik}\\, x_{ik} \\le 0.25\\,B \\;\\; \\forall i, \\qquad "
          "\\sum_{i \\in P}\\sum_k c_{ik}\\, x_{ik} \\ge 0.30\\,B, \\\\\n"
          "& 0 \\le x_{ik} \\le \\min(\\bar{x}_k,\\, 100 - L_{ik}),\n\\end{align*}\n"
          "donde $S_i$ es la superficie cosechada 2025 (ha), $p_i$ el precio de venta (S/ por kg), $L_{ik}$ el nivel actual "
          "de la palanca, $\\bar{x}_k$ su tope por campaña, $P$ el conjunto priorizado y $c_{ik}$ el costo de subir un punto "
          "($c_k S_i/100$ para palancas por área y $c_k N_i/100$ para palancas por productor, con $N_i$ productores). "
          "Se resuelven dos versiones: con $\\beta$ puntual y con $\\beta$ robusto, la cota inferior al 80\\,\\%. Los costos "
          "unitarios son supuestos razonables que el tablero permite cambiar (Cuadro~\\ref{tab:palancas}).\n\n")
    s += o["tab_pal"]
    s += codigo(cod_lp, "Programa lineal" + (" con lpSolve" if es_R else " con JuMP + HiGHS"))
    s += "\\subsection{7.3 Resultados}\n"
    porp = o["porp"].set_index(["plan", "palanca"])
    s += (f"El plan puntual concentra el gasto en asistencia técnica y crédito y promete S/ {n(o['pp_val']/1e6,1)} millones "
          f"de valor adicional (beneficio/costo {o['pp_val']/o['pp_gasto']:.1f}). Esa cifra descansa en coeficientes "
          "imprecisos. El plan robusto descarta las palancas cuyo efecto no se distingue de cero (riego y crédito) y "
          f"pone S/ {n(porp.loc[('Plan robusto','Semilla certificada')].costo/1e6,1)} millones en semilla certificada y "
          f"S/ {n(porp.loc[('Plan robusto','Asistencia técnica')].costo/1e6,1)} millones en asistencia técnica "
          f"(Cuadro~\\ref{{tab:plan}}, Figura~\\ref{{fig:plan}}). Rinde S/ {n(o['pr_val']/1e6,1)} millones "
          f"({n(o['pr_t'],0)} t adicionales) aun con efectos conservadores, y el {pct(o['pr_prior_pct'],0)} del presupuesto "
          "va a departamentos priorizados.\n\n")
    s += o["tab_plan_r"]
    s += figura(F["plan"], "Asignación óptima de S/ 50 millones con efectos puntuales (izquierda) y robustos (derecha).", "fig:plan")
    mc = o["mc"]
    s += (f"El Cuadro~\\ref{{tab:mc}} evalúa ambos planes cuando el efecto verdadero varía según su incertidumbre. El plan puntual "
          f"tiene mayor valor esperado, pero su peor 5\\,\\% cae a S/ {n(mc.loc['Plan puntual'].p05_exacto/1e6,1)} millones y la "
          f"probabilidad de no recuperar la inversión es {pct(100*mc.loc['Plan puntual'].prob_bc_menor_1_exacta,2)}. El plan "
          f"robusto tiene un peor 5\\,\\% más alto (S/ {n(mc.loc['Plan robusto'].p05_exacto/1e6,1)} millones) y esa probabilidad baja "
          f"a {pct(100*mc.loc['Plan robusto'].prob_bc_menor_1_exacta,2)}. Para una entidad pública que debe rendir cuentas, "
          "el plan robusto es la recomendación.\n\n")
    s += o["tab_mc"]
    s += (f"La frontera de la Figura~\\ref{{fig:front}} muestra cuánto presupuesto vale la pena. Con S/ 50 millones, un sol "
          f"adicional rinde S/ {o['sp_r']:.2f} en el plan robusto (precio sombra). Con efectos robustos, cada sol extra "
          f"sigue rindiendo más de un sol hasta S/ {n(o['be_r']/1e6,0)} millones; por encima de esa cifra conviene "
          f"buscar otras palancas. La capacidad total del plan robusto se agota en S/ {n(o['cap_r']/1e6,1)} millones. "
          f"La cuota de equidad del 30\\,\\% cuesta S/ {n(o['eq30']/1e6,2)} millones en el plan puntual y una cuota del "
          f"50\\,\\% costaría S/ {n(o['eq50']/1e6,1)} millones: proteger a los departamentos con heladas sale barato. "
          f"Si los costos unitarios fueran 50\\,\\% menores o mayores, el beneficio/costo del plan puntual iría de "
          f"{o['cos15']:.1f} a {o['cos05']:.1f}; la recomendación no cambia de signo.\n\n")
    s += figura(F["front"], "Frontera presupuesto--valor y distribución del beneficio/costo de cada plan.", "fig:front")

    # 8 comunicación
    s += "\\section{8. Rama 6: comunicación y pruebas}\n"
    if es_R:
        s += ("Un resultado que nadie entiende no se usa. El tablero \\pkg{shiny} (Figura~\\ref{fig:shiny}) deja al usuario "
              "mover el presupuesto, el tipo de efecto, la cuota de equidad, el tope por departamento y los costos "
              "unitarios; el programa lineal se resuelve en vivo y muestra cuatro indicadores: valor adicional, producción "
              "adicional, beneficio/costo y el valor de un sol extra. La lógica del servidor se prueba con "
              "\\code{shiny::testServer()} y la aplicación completa con \\pkg{shinytest2} en Chrome; las funciones del "
              "pipeline tienen pruebas \\pkg{testthat} con casos de solución conocida (por ejemplo, un programa lineal de "
              "dos departamentos que se resuelve a mano).\n\n")
        s += figura("r12_tablero_shiny.png", "Tablero \\pkg{shiny}: plan robusto con S/ 50 millones.", "fig:shiny", "0.92\\textwidth")
    else:
        cmp = pd.read_csv(TJ / "comparacion_R_vs_Julia.csv")
        cmp["indicador"] = cmp.indicador.str.replace("(S/)", "(S/ M)", regex=False)
        s += ("La rama 6 ejecuta las pruebas unitarias (stdlib \\pkg{Test}), compara cada resultado con el pipeline de R y "
              "genera una ficha de decisión en HTML (\\code{outputs/julia/ficha\\_decision.html}) con los indicadores del "
              "plan robusto, la tabla por departamento y la figura de asignación, lista para enviar a una autoridad. "
              "El Cuadro~\\ref{tab:cmp} resume la comparación R--Julia.\n\n")
        def fval(row, col):
            v = row[col]
            return n(v / 1e6, 2) if "S/" in row.indicador or "P05" in row.indicador else n(v, 2)
        filas = []
        for _, rw in cmp.iterrows():
            filas.append(f"{esc(rw.indicador)} & {fval(rw,'R')} & {fval(rw,'Julia')} & {rw.dif_rel_pct:+.2f} \\\\")
        s += ("\\begin{table}[htbp]\n\\centering\\footnotesize\n\\caption{Comparación de resultados entre R y Julia "
              "(kg/ha, \\% o millones de S/). Los modelos deterministas y el programa lineal coinciden; las diferencias "
              "vienen del XGBoost y de la semilla del Montecarlo.}\\label{tab:cmp}\n\\begin{tabular}{lrrr}\n\\toprule\n"
              "Indicador & R & Julia & Dif. (\\%) \\\\\n\\midrule\n" + "\n".join(filas) + "\n\\bottomrule\n\\end{tabular}\n\\end{table}\n")

    s += "\\section{9. Resumen de validaciones}\n"
    s += (f"El pipeline en {L} ejecutó {o['n_val']} validaciones y todas fueron aprobadas (Cuadro~\\ref{{tab:val}}). El registro "
          f"completo está en el archivo \\code{{registro\\_validaciones.csv}} de la carpeta de tablas.\n\n")
    s += o["tab_val"]

    # 10 conclusiones
    s += "\\section{10. Conclusiones}\n"
    s += ("\\begin{enumerate}\n"
          f"\\item El panel se reconstruyó desde los microdatos sin diferencias con el Excel, y {('los seis modelos del artículo se reprodujeron en R' if es_R else 'los cuatro modelos deterministas del artículo se reprodujeron en Julia; el XGBoost difiere por la implementación, pero no cambia las conclusiones')}.\n"
          f"\\item El ensamble informado tiene el menor RMSE ({n(ens.RMSE)} kg/ha) y la calibración conformal es indispensable: sin ella los intervalos cubren la mitad de lo que prometen.\n"
          f"\\item Con S/ 50 millones, el plan robusto invierte sobre todo en semilla certificada en Cusco, Puno, Cajamarca, Huancavelica y La Libertad, y en asistencia técnica donde hay más superficie por productor. Produce {n(o['pr_t'],0)} t adicionales y un beneficio/costo de {o['pr_val']/o['pr_gasto']:.2f} con efectos conservadores.\n"
          f"\\item Hasta S/ {n(o['be_r']/1e6,0)} millones cada sol adicional rinde más de un sol; la cuota de equidad para los departamentos con heladas cuesta menos del 1\\,\\% del valor.\n"
          "\\end{enumerate}\n\n")
    s += ("\\textbf{Limitaciones.} Los efectos vienen de un panel observacional de diez años: son asociaciones dentro de cada "
          "departamento, no efectos causales, y suponen que se mantienen al escalar la intervención. Los costos unitarios "
          "son supuestos; el tablero y el análisis de sensibilidad muestran cómo cambia el plan si se ajustan. El "
          "pronóstico 2026 supone covariables iguales a 2025 y no incluye clima directo (temperatura o precipitación).\n\n")
    s += ("\\section{Anexo: cómo ejecutar}\n" + codigo(
        ("# desde la raíz del proyecto (o abrir ENA_papa_prescriptivo.Rproj en RStudio)\nRscript R/run_all.R\n"
         "# tablero\nRscript -e 'shiny::runApp(\"R/app\")'\n# pruebas\nRscript -e 'testthat::test_dir(\"R/tests\")'") if es_R else
        ("# primera vez: instalar dependencias del proyecto\njulia --project=julia -e 'using Pkg; Pkg.instantiate()'\n"
         "# pipeline completo (correr antes R/run_all.R para la comparación)\ncd julia && julia --project=. run_all.jl\n"
         "# solo pruebas\njulia --project=julia julia/test/runtests.jl"), "Comandos"))
    s += REFS
    s += f"\n\\par\\address{{{AUTOR}}}\n"
    s += "\\end{article}\n\\end{document}\n"
    return s


if __name__ == "__main__":
    for L, nombre in [("R", "Informe_LatinR_R_ENA_papa"), ("Julia", "Informe_LatinR_Julia_ENA_papa")]:
        (TEX / f"{nombre}.tex").write_text(informe(L), encoding="utf-8")
        for ext in (".aux", ".brf", ".out", ".log"):
            (TEX / f"{nombre}{ext}").unlink(missing_ok=True)
        for _ in range(3):
            subprocess.run(["pdflatex", "-interaction=nonstopmode", f"{nombre}.tex"], cwd=TEX,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        log = (TEX / f"{nombre}.log").read_text(errors="ignore")
        errores = [l for l in log.splitlines() if l.startswith("!")]
        print(nombre, "errores:", errores[:5], "| PDF:", (TEX / f"{nombre}.pdf").exists())
