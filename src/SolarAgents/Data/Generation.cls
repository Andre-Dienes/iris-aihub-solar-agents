/// Daily telemetry of each plant (inverter monitoring system).
Class SolarAgents.Data.Generation Extends %Persistent
{

Property PlantCode As %String(MAXLEN = 10) [ Required ];

Property Day As %Date [ Required ];

/// Energy injected into the grid in the day (kWh).
Property EnergyKWh As %Numeric(SCALE = 1);

/// Energy expected by the plant model for the measured irradiation (kWh).
Property ExpectedKWh As %Numeric(SCALE = 1);

/// Performance Ratio as a fraction (0.82 = 82%).
Property PR As %Numeric(SCALE = 4);

/// Inverter availability in percent.
Property AvailabilityPct As %Numeric(SCALE = 2);

Index PlantDayIdx On (PlantCode, Day) [ Unique ];

}
