/// Seeds the fictional plants with deterministic data (June–September 2026).
///
/// The data tells a story the demo can discover:
///   AUR  Aurora Solar Plant        — reference plant, PR around 84%
///   BLR  Blue Ridge Solar Plant    — inverter INV-03 fails on Aug 10 and is repaired on Aug 18 (availability and PR drop)
///   GRV  Green Valley Solar Plant  — hot site; module soiling lowers the PR during September until the rain of Sep 24
///   HZN  Horizon Solar Plant       — single-axis trackers, commissioned on Jul 1, 2026
///
///   Do ##class(SolarAgents.Data.DemoData).Load()      // idempotent
///   Do ##class(SolarAgents.Data.DemoData).Load(1)     // wipe and reload
Class SolarAgents.Data.DemoData Extends %RegisteredObject
{

Parameter START = "2026-06-01";

Parameter END = "2026-09-30";

ClassMethod Load(reset As %Boolean = 0) As %Status
{
    Set sc = $$$OK
    Try {
        If reset {
            For cls="Plant","Generation","Weather","Alarm","WorkOrder" {
                Do $ClassMethod("SolarAgents.Data."_cls, "%KillExtent")
            }
        }
        Quit:##class(SolarAgents.Data.Plant).CodeIdxExists("AUR")
        Do ..Plants()
        Do ..Daily()
        Do ..Alarms()
        Write "Demo data loaded",!
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Deterministic variation in [-1, 1].
ClassMethod Wave(seed As %Integer, n As %Integer) As %Float
{
    Quit ($ZSin((n * 0.7) + seed) * 0.6) + ($ZCos((n * 1.3) + (seed * 2)) * 0.4)
}

ClassMethod Plants()
{
    // code, name, region, kWp, technology, tracker, commissioned
    For p=$ListBuild("AUR", "Aurora Solar Plant", "North", 5000, "Mono PERC", 0, "2024-03-15"),
          $ListBuild("BLR", "Blue Ridge Solar Plant", "South", 4200, "Mono PERC", 0, "2023-11-02"),
          $ListBuild("GRV", "Green Valley Solar Plant", "East", 3600, "Polycrystalline", 0, "2022-08-20"),
          $ListBuild("HZN", "Horizon Solar Plant", "West", 6000, "Bifacial on single-axis trackers", 1, "2026-07-01") {
        Set plant = ##class(SolarAgents.Data.Plant).%New()
        Set plant.Code = $List(p, 1), plant.Name = $List(p, 2), plant.Region = $List(p, 3)
        Set plant.CapacityKWp = $List(p, 4), plant.Technology = $List(p, 5), plant.Tracker = $List(p, 6)
        Set plant.CommissionedOn = $ZDateH($List(p, 7), 3)
        $$$ThrowOnError(plant.%Save())
    }
}

ClassMethod Daily()
{
    Set start = $ZDateH(..#START, 3), end = $ZDateH(..#END, 3)
    // code, kWp, base PR, irradiation factor, ambient temp offset, seed
    Set plants = $ListBuild($ListBuild("AUR", 5000, 0.84, 1.08, 2, 1), $ListBuild("BLR", 4200, 0.81, 0.92, -4, 2),
                            $ListBuild("GRV", 3600, 0.79, 1.02, 5, 3), $ListBuild("HZN", 6000, 0.83, 1.22, 3, 4))
    Set ptr = 0
    While $ListNext(plants, ptr, p) {
        Set code = $List(p, 1), kwp = $List(p, 2), basePR = $List(p, 3), seed = $List(p, 6)
        Set firstDay = $Select(code="HZN":$ZDateH("2026-07-01", 3), 1:start)
        For day=firstDay:1:end {
            Set n = day - start, month = +$Piece($ZDate(day, 3), "-", 2), dom = +$Piece($ZDate(day, 3), "-", 3)
            // seasonal plane-of-array irradiation (kWh/m2/day), regional factor and daily weather
            Set season = $Case(month, 6:4.6, 7:4.9, 8:5.4, :5.8)
            Set wave = ..Wave(seed, n)
            Set rainy = (wave > 0.72)
            Set gti = season * $List(p, 4) * (1 + (wave * 0.08))
            Set:rainy gti = gti * 0.55
            Set ghi = gti / $Select(code="HZN":1.30, 1:1.08)
            Set ambient = 22 + $List(p, 5) + ($Case(month, 6:-3, 7:-4, 8:-1, :2)) + (..Wave(seed + 7, n) * 2.5)
            Set moduleT = ambient + (gti * 3.4)
            // thermal loss and the scripted events
            Set pr = basePR - ((moduleT - 40) * 0.0012) + (..Wave(seed + 3, n) * 0.012)
            Set availability = 99.4 + (..Wave(seed + 5, n) * 0.5)
            If (code="BLR") && (month=8) && (dom>=10) && (dom<=18) {
                // INV-03 (1 of 4 inverters) down
                Set availability = 74.8 + (..Wave(seed, n) * 0.6)
            }
            If (code="GRV") && (month=9) {
                // soiling builds up until the heavy rain of Sep 24
                Set pr = pr - $Select(dom<24:(dom * 0.0042), 1:0)
                Set:dom=24 rainy = 1
            }
            Set:pr>0.9 pr = 0.9
            Set energy = kwp * gti * pr * (availability / 100)
            Set expected = kwp * gti * 0.82

            Set gen = ##class(SolarAgents.Data.Generation).%New()
            Set gen.PlantCode = code, gen.Day = day
            Set gen.EnergyKWh = $Number(energy, 1), gen.ExpectedKWh = $Number(expected, 1)
            Set gen.PR = $Number(pr * (availability / 100), 4), gen.AvailabilityPct = $Number(availability, 2)
            $$$ThrowOnError(gen.%Save())

            Set w = ##class(SolarAgents.Data.Weather).%New()
            Set w.PlantCode = code, w.Day = day
            Set w.IrradiationKWhM2 = $Number(gti, 3), w.GHIKWhM2 = $Number(ghi, 3)
            Set w.AmbientTempC = $Number(ambient, 1), w.ModuleTempC = $Number(moduleT, 1)
            Set w.RainMm = $Select(rainy:$Number(8 + (..Wave(seed + 9, n) * 6) + $Select((code="GRV")&&(month=9)&&(dom=24):30, 1:0), 1), 1:0)
            Set w.WindSpeedMs = $Number(3 + (..Wave(seed + 11, n) * 1.5), 1)
            $$$ThrowOnError(w.%Save())
        }
    }
}

ClassMethod Alarms()
{
    // plant, opened, closed, equipment, severity, code, description, status, downtime h
    For a=$ListBuild("BLR", "2026-08-09 13:40:00", "2026-08-09 15:10:00", "INV-03", "Medium", "INV-OVERTEMP", "Over-temperature on inverter INV-03", "Closed", 1.5),
          $ListBuild("BLR", "2026-08-10 08:15:00", "2026-08-18 16:40:00", "INV-03", "Critical", "INV-IGBT-FAULT", "IGBT module failure on inverter INV-03 — inverter out of service", "Closed", 64),
          $ListBuild("BLR", "2026-08-21 10:05:00", "2026-08-21 10:50:00", "INV-03", "Low", "INV-RESTART", "Restart after IGBT module replacement", "Closed", 0.5),
          $ListBuild("GRV", "2026-09-15 11:20:00", "", "STR-ALL", "Medium", "LOW-STRING-CURRENT", "String currents below expected across the plant — suspected soiling", "Open", 0),
          $ListBuild("GRV", "2026-07-03 14:00:00", "2026-07-03 16:30:00", "TR-01", "High", "TRAFO-TEMP", "High temperature on transformer TR-01", "Closed", 2.5),
          $ListBuild("HZN", "2026-07-20 09:30:00", "2026-07-20 15:45:00", "TRK-07", "High", "TRACKER-STUCK", "Tracker TRK-07 stuck in flat position", "Closed", 6.2),
          $ListBuild("HZN", "2026-09-02 07:50:00", "2026-09-02 08:20:00", "TRK-02", "Low", "TRACKER-COMM", "Communication loss with tracker controller TRK-02", "Closed", 0),
          $ListBuild("AUR", "2026-06-18 10:10:00", "2026-06-18 10:40:00", "LOG-01", "Low", "COMM-LOSS", "Communication loss with the datalogger", "Closed", 0),
          $ListBuild("AUR", "2026-08-27 12:00:00", "2026-08-27 13:15:00", "CB-02", "Medium", "STRING-FUSE", "Blown string fuse in combiner box CB-02", "Closed", 0.8),
          $ListBuild("BLR", "2026-09-12 09:00:00", "", "CB-05", "Low", "STRING-FUSE", "Blown string fuse in combiner box CB-05", "Open", 0) {
        Set alarm = ##class(SolarAgents.Data.Alarm).%New()
        Set alarm.PlantCode = $List(a, 1), alarm.OpenedAt = $List(a, 2), alarm.ClosedAt = $List(a, 3)
        Set alarm.Equipment = $List(a, 4), alarm.Severity = $List(a, 5), alarm.Code = $List(a, 6)
        Set alarm.Description = $List(a, 7), alarm.Status = $List(a, 8), alarm.DowntimeHours = $List(a, 9)
        $$$ThrowOnError(alarm.%Save())
    }
}

}
