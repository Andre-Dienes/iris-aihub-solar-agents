/// Deterministic analysis written in IRIS Embedded Python: statistics, highlights and a markdown
/// table for the rows a data agent fetched, plus the IEC 61724 Performance Ratio calculator.
/// The LLM only writes the narrative on top of these numbers (and offline mode does without it).
Class SolarAgents.Analysis.Analyzer Extends %RegisteredObject
{

/// rowsJSON: [{"col": value, ...}, ...]. Returns JSON {"row_count","columns","stats","highlights","table_md"}.
ClassMethod Describe(rowsJSON As %String) As %String [ Language = python ]
{
    import json
    import statistics

    rows = json.loads(rowsJSON or "[]")
    if not rows:
        return json.dumps({"row_count": 0, "columns": [], "stats": {}, "highlights": ["No records found for the requested filter."], "table_md": ""}, ensure_ascii=False)

    columns = list(rows[0].keys())

    def num(v):
        try:
            return float(v)
        except (TypeError, ValueError):
            return None

    numeric = [c for c in columns if all(num(r.get(c)) is not None for r in rows if r.get(c) not in (None, ""))
               and any(num(r.get(c)) is not None for r in rows)]
    label_col = next((c for c in columns if c.lower() == "plant"), None)
    day_col = next((c for c in columns if c.lower() in ("day", "opened")), None)

    stats = {}
    for c in numeric:
        vals = [num(r.get(c)) for r in rows if num(r.get(c)) is not None]
        if vals:
            stats[c] = {"avg": round(statistics.mean(vals), 3), "min": min(vals), "max": max(vals),
                        "sum": round(sum(vals), 3), "count": len(vals)}

    highlights = []
    metric = next((c for c in numeric if c != day_col), None)
    if metric and len(rows) > 1:
        best = max(rows, key=lambda r: num(r.get(metric)) or float("-inf"))
        worst = min(rows, key=lambda r: num(r.get(metric)) if num(r.get(metric)) is not None else float("inf"))
        key = day_col or label_col
        if key:
            highlights.append(f"Highest {metric}: {best.get(key)} ({best.get(metric)})")
            highlights.append(f"Lowest {metric}: {worst.get(key)} ({worst.get(metric)})")
        if day_col and len(rows) >= 6:
            half = len(rows) // 2
            first = statistics.mean([num(r.get(metric)) for r in rows[:half] if num(r.get(metric)) is not None] or [0])
            second = statistics.mean([num(r.get(metric)) for r in rows[half:] if num(r.get(metric)) is not None] or [0])
            if first:
                delta = (second - first) / abs(first) * 100
                trend = "up" if delta > 3 else "down" if delta < -3 else "stable"
                highlights.append(f"{metric} trend: {trend} ({delta:+.1f}% in the second half of the period)")
    elif rows:
        label = rows[0].get(label_col) if label_col else ""
        parts = [f"{c} {rows[0].get(c)}" for c in numeric]
        if parts:
            highlights.append((f"{label}: " if label else "") + "; ".join(parts))
    if "Severity" in columns:
        crit = [r for r in rows if str(r.get("Severity")) in ("Critical", "High")]
        if crit:
            highlights.append(f"{len(crit)} critical/high alarm(s): " + "; ".join(f"{r.get('Equipment')} — {r.get('Description')}" for r in crit[:3]))

    def fmt(v):
        n = num(v)
        if n is None:
            return "" if v is None else str(v)
        if abs(n) >= 1000:
            return f"{n:,.1f}"
        return f"{n:.2f}".rstrip("0").rstrip(".")

    shown = rows[:31]
    table = "| " + " | ".join(columns) + " |\n| " + " | ".join("---" for _ in columns) + " |\n"
    for r in shown:
        table += "| " + " | ".join(fmt(r.get(c)) for c in columns) + " |\n"
    if len(rows) > len(shown):
        table += "\n_... " + str(len(rows) - len(shown)) + " more rows_\n"

    return json.dumps({"row_count": len(rows), "columns": columns, "stats": stats, "highlights": highlights,
                       "table_md": table}, ensure_ascii=False)
}

/// Performance Ratio (IEC 61724) of one plant and period, with temperature correction.
/// PR = E_actual / (P_nom × H_poa); PR_corr = PR / (1 + γ × (T_mod − 25)), γ = −0.35%/°C.
ClassMethod CalculatePR(plantCode As %String, startDate As %String, endDate As %String, gamma As %Double = -0.0035) As %String [ Language = python ]
{
    import json
    import iris

    rows = list(iris.sql.exec(
        "SELECT p.Name, p.CapacityKWp, SUM(g.EnergyKWh), SUM(w.IrradiationKWhM2), AVG(w.ModuleTempC), COUNT(*) "
        "FROM SolarAgents_Data.Generation g "
        "JOIN SolarAgents_Data.Weather w ON w.PlantCode = g.PlantCode AND w.Day = g.Day "
        "JOIN SolarAgents_Data.Plant p ON p.Code = g.PlantCode "
        "WHERE g.PlantCode = ? AND g.Day BETWEEN TO_DATE(?, 'YYYY-MM-DD') AND TO_DATE(?, 'YYYY-MM-DD') "
        "GROUP BY p.Name, p.CapacityKWp", plantCode, startDate, endDate))
    if not rows or not rows[0][2]:
        return json.dumps({"error": f"No data for {plantCode} between {startDate} and {endDate}"}, ensure_ascii=False)
    name, kwp, energy, h_poa, t_mod, days = rows[0]
    kwp, energy, h_poa, t_mod = float(kwp), float(energy), float(h_poa), float(t_mod)
    theoretical = kwp * h_poa
    pr = energy / theoretical
    pr_corr = pr / (1 + gamma * (t_mod - 25))
    return json.dumps({
        "plant": name, "period": f"{startDate} to {endDate}", "days": int(days),
        "energy_kwh": round(energy, 1), "theoretical_kwh": round(theoretical, 1),
        "irradiation_kwh_m2": round(h_poa, 2), "module_temp_c": round(t_mod, 1),
        "pr_pct": round(pr * 100, 2), "pr_temp_corrected_pct": round(pr_corr * 100, 2),
        "method": "IEC 61724: PR = E / (P_nom × H_poa); PR_corr = PR / (1 + γ(T_mod − 25)), γ = −0.35%/°C"
    }, ensure_ascii=False)
}

}
