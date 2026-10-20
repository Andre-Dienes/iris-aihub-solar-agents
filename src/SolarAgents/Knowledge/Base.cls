/// Knowledge base of the demo, stored as IRIS native vectors (SolarAgents.RAG.VectorStore):
///
///   schema    — one chunk per table plus the SQL rules (used to build the text-to-SQL prompt)
///   examples  — question -> SQL pairs per agent; {PLANTS}, {START}, {END} are filled at run time
///   glossary  — solar energy concepts (used by the CONCEPT branch of the router)
///
///   Do ##class(SolarAgents.Knowledge.Base).Load()      // idempotent: reloads every collection
Class SolarAgents.Knowledge.Base Extends %RegisteredObject
{

ClassMethod Load() As %Status
{
    Set sc = $$$OK
    Try {
        Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($ClassName()_"||Knowledge")
        Set kb = ##class(%DynamicObject).%FromJSON(xdata.Data)
        Set iter = kb.%GetIterator()
        While iter.%GetNext(.collection, .docs) {
            Do ##class(SolarAgents.RAG.VectorStore).DeleteCollection(collection)
            Set n = ##class(SolarAgents.RAG.VectorStore).AddDocuments(collection, docs)
            Write "  knowledge ",collection,": ",n," chunks",!
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Examples of one agent as a %DynamicArray of {"question","sql"}.
ClassMethod Examples(agent As %String) As %DynamicArray
{
    Set out = []
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($ClassName()_"||Knowledge")
    Set kb = ##class(%DynamicObject).%FromJSON(xdata.Data)
    Set iter = kb.examples.%GetIterator()
    While iter.%GetNext(, .doc) {
        Continue:doc.metadata.agent'=agent
        Do out.%Push({"question": (doc.content), "sql": (doc.metadata.sql)})
    }
    Quit out
}

XData Knowledge [ MimeType = application/json ]
{
{
  "schema": [
    {"content": "Table SolarAgents_Data.Plant (alias p): plant registry. Columns: Code (short code: AUR, BLR, GRV, HZN), Name (e.g. 'Aurora Solar Plant'), Region, CapacityKWp (installed power in kWp), Technology, Tracker (1 = single-axis tracker), CommissionedOn (DATE). Join the other tables with p.Code = <table>.PlantCode.",
     "metadata": {"agents": "Telemetry,Weather,Maintenance", "type": "table"}},
    {"content": "Table SolarAgents_Data.Generation (alias g): daily inverter telemetry. Columns: PlantCode, Day (DATE), EnergyKWh (energy exported in the day, kWh), ExpectedKWh (energy expected by the plant model, kWh), PR (Performance Ratio as a FRACTION 0-1: multiply by 100 for %), AvailabilityPct (inverter availability in %). Energy of a period = SUM(g.EnergyKWh); PR of a period = AVG(g.PR).",
     "metadata": {"agents": "Telemetry", "type": "table"}},
    {"content": "Table SolarAgents_Data.Weather (alias w): daily weather. Columns: PlantCode, Day (DATE), IrradiationKWhM2 (plane-of-array irradiation, GTI, kWh/m2 per day), GHIKWhM2 (global horizontal irradiation, kWh/m2 per day), AmbientTempC, ModuleTempC (°C), RainMm (rain in mm), WindSpeedMs (m/s).",
     "metadata": {"agents": "Weather", "type": "table"}},
    {"content": "Table SolarAgents_Data.Alarm (alias a): equipment alarms. Columns: PlantCode, OpenedAt and ClosedAt (TIMESTAMP 'YYYY-MM-DD HH:MM:SS'), Equipment (INV-03, TRK-07, CB-02...), Severity ('Critical','High','Medium','Low'), Code, Description, Status ('Open' or 'Closed'), DowntimeHours (production hours lost).",
     "metadata": {"agents": "Maintenance", "type": "table"}},
    {"content": "SQL rules (InterSystems IRIS): write ONE single SELECT; never use LIMIT: to limit rows use TOP n right after SELECT (SELECT TOP 1 ...); dates are literals 'YYYY-MM-DD' on DATE columns and 'YYYY-MM-DD HH:MM:SS' on TIMESTAMP columns; filter plants with PlantCode IN ('AUR', ...) using the codes provided; always include the plant name (p.Name AS Plant) when grouping by plant; give readable English aliases to computed columns (Energy_kWh, Avg_PR_Pct, Avg_Irradiation_kWhm2_day...); round with ROUND(x, 1).",
     "metadata": {"agents": "Telemetry,Weather,Maintenance", "type": "rules"}}
  ],
  "examples": [
    {"content": "What was the energy and the PR of Aurora in August 2026?",
     "metadata": {"agent": "Telemetry", "sql": "SELECT p.Name AS Plant, ROUND(SUM(g.EnergyKWh), 1) AS Energy_kWh, ROUND(AVG(g.PR) * 100, 1) AS Avg_PR_Pct, ROUND(AVG(g.AvailabilityPct), 2) AS Availability_Pct FROM SolarAgents_Data.Generation g JOIN SolarAgents_Data.Plant p ON p.Code = g.PlantCode WHERE g.PlantCode IN ({PLANTS}) AND g.Day BETWEEN '{START}' AND '{END}' GROUP BY p.Name ORDER BY Avg_PR_Pct DESC"}},
    {"content": "How did the PR and the availability of Blue Ridge evolve day by day in August?",
     "metadata": {"agent": "Telemetry", "sql": "SELECT p.Name AS Plant, g.Day AS Day, g.EnergyKWh AS Energy_kWh, ROUND(g.PR * 100, 1) AS PR_Pct, g.AvailabilityPct AS Availability_Pct FROM SolarAgents_Data.Generation g JOIN SolarAgents_Data.Plant p ON p.Code = g.PlantCode WHERE g.PlantCode IN ({PLANTS}) AND g.Day BETWEEN '{START}' AND '{END}' ORDER BY p.Name, g.Day"}},
    {"content": "Compare actual versus expected energy for each plant in the period",
     "metadata": {"agent": "Telemetry", "sql": "SELECT p.Name AS Plant, ROUND(SUM(g.EnergyKWh), 1) AS Energy_kWh, ROUND(SUM(g.ExpectedKWh), 1) AS Expected_kWh, ROUND(SUM(g.EnergyKWh) / SUM(g.ExpectedKWh) * 100, 1) AS Actual_vs_Expected_Pct FROM SolarAgents_Data.Generation g JOIN SolarAgents_Data.Plant p ON p.Code = g.PlantCode WHERE g.PlantCode IN ({PLANTS}) AND g.Day BETWEEN '{START}' AND '{END}' GROUP BY p.Name ORDER BY Actual_vs_Expected_Pct DESC"}},
    {"content": "What was the irradiation and the average temperature at Green Valley in September?",
     "metadata": {"agent": "Weather", "sql": "SELECT p.Name AS Plant, ROUND(AVG(w.IrradiationKWhM2), 2) AS Avg_Irradiation_kWhm2_day, ROUND(SUM(w.IrradiationKWhM2), 1) AS Total_Irradiation_kWhm2, ROUND(AVG(w.AmbientTempC), 1) AS Avg_Ambient_Temp_C, ROUND(AVG(w.ModuleTempC), 1) AS Avg_Module_Temp_C, ROUND(SUM(w.RainMm), 1) AS Rain_mm FROM SolarAgents_Data.Weather w JOIN SolarAgents_Data.Plant p ON p.Code = w.PlantCode WHERE w.PlantCode IN ({PLANTS}) AND w.Day BETWEEN '{START}' AND '{END}' GROUP BY p.Name"}},
    {"content": "On which days did it rain at the plant and how much?",
     "metadata": {"agent": "Weather", "sql": "SELECT p.Name AS Plant, w.Day AS Day, w.RainMm AS Rain_mm, w.IrradiationKWhM2 AS Irradiation_kWhm2 FROM SolarAgents_Data.Weather w JOIN SolarAgents_Data.Plant p ON p.Code = w.PlantCode WHERE w.PlantCode IN ({PLANTS}) AND w.Day BETWEEN '{START}' AND '{END}' AND w.RainMm > 0 ORDER BY w.Day"}},
    {"content": "Which alarms did Blue Ridge have in August?",
     "metadata": {"agent": "Maintenance", "sql": "SELECT p.Name AS Plant, a.OpenedAt AS Opened, a.ClosedAt AS Closed, a.Equipment AS Equipment, a.Severity AS Severity, a.Description AS Description, a.Status AS Status, a.DowntimeHours AS Downtime_h FROM SolarAgents_Data.Alarm a JOIN SolarAgents_Data.Plant p ON p.Code = a.PlantCode WHERE a.PlantCode IN ({PLANTS}) AND a.OpenedAt BETWEEN '{START} 00:00:00' AND '{END} 23:59:59' ORDER BY a.OpenedAt"}},
    {"content": "How many downtime hours did each plant have because of alarms?",
     "metadata": {"agent": "Maintenance", "sql": "SELECT p.Name AS Plant, COUNT(*) AS Alarms, ROUND(SUM(a.DowntimeHours), 1) AS Downtime_h FROM SolarAgents_Data.Alarm a JOIN SolarAgents_Data.Plant p ON p.Code = a.PlantCode WHERE a.PlantCode IN ({PLANTS}) AND a.OpenedAt BETWEEN '{START} 00:00:00' AND '{END} 23:59:59' GROUP BY p.Name ORDER BY Downtime_h DESC"}},
    {"content": "Which alarms are still open?",
     "metadata": {"agent": "Maintenance", "sql": "SELECT p.Name AS Plant, a.OpenedAt AS Opened, a.Equipment AS Equipment, a.Severity AS Severity, a.Description AS Description FROM SolarAgents_Data.Alarm a JOIN SolarAgents_Data.Plant p ON p.Code = a.PlantCode WHERE a.PlantCode IN ({PLANTS}) AND a.Status = 'Open' ORDER BY a.OpenedAt"}}
  ],
  "glossary": [
    {"content": "Performance Ratio (PR): ratio between the energy the plant actually delivered and the theoretical energy it would deliver with the measured irradiation and its nominal power (IEC 61724). PR = E_actual / (P_nom × H_poa / 1 kW/m²). Healthy plants typically run between 78% and 86%. Below 75% points to relevant losses (failures, soiling, shading, temperature).",
     "metadata": {"term": "PR"}},
    {"content": "GHI (Global Horizontal Irradiation): total solar irradiation on a horizontal plane, in kWh/m². GTI or POA (Plane of Array): irradiation on the tilted plane of the modules; it is the reference used to compute the PR. Single-axis trackers raise GTI by 15% to 30% compared with fixed-tilt structures.",
     "metadata": {"term": "GHI/GTI"}},
    {"content": "Availability: share of time (or energy) during which the inverters were able to produce. Losing 1 of 4 inverters drops plant availability to about 75% and lowers the PR in the same proportion.",
     "metadata": {"term": "Availability"}},
    {"content": "Soiling: dust and debris accumulating on the modules, gradually reducing generation, typically 0.1% to 0.5% per day in dry periods. Heavy rain or module cleaning recovers the loss at once.",
     "metadata": {"term": "Soiling"}},
    {"content": "Thermal loss: photovoltaic modules lose efficiency with heat. The typical temperature coefficient is -0.35%/°C to -0.45%/°C above 25 °C cell temperature. Plants in hot regions show a lower PR in summer.",
     "metadata": {"term": "Temperature"}},
    {"content": "Expected energy: generation predicted by a plant model for the measured irradiation and temperature. The actual/expected ratio separates operational losses (failures, soiling) from the effect of the weather.",
     "metadata": {"term": "Expected energy"}},
    {"content": "Capacity factor: energy generated in the period divided by the energy the plant would generate running 24 h at nominal power. Utility-scale solar plants typically range from 18% to 28%.",
     "metadata": {"term": "Capacity factor"}},
    {"content": "kWp (kilowatt-peak): nominal power of the modules under standard test conditions (1000 W/m², 25 °C). It is the basis for comparing the specific yield (kWh/kWp) of plants of different sizes.",
     "metadata": {"term": "kWp"}}
  ]
}
}

}
