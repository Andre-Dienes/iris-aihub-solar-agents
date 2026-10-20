/// Daily weather of each plant (on-site station + satellite irradiance).
Class SolarAgents.Data.Weather Extends %Persistent
{

Property PlantCode As %String(MAXLEN = 10) [ Required ];

Property Day As %Date [ Required ];

/// Plane-of-array irradiation (GTI) in kWh/m2 per day.
Property IrradiationKWhM2 As %Numeric(SCALE = 3);

/// Global horizontal irradiation (GHI) in kWh/m2 per day.
Property GHIKWhM2 As %Numeric(SCALE = 3);

Property AmbientTempC As %Numeric(SCALE = 1);

/// Average module temperature during production hours.
Property ModuleTempC As %Numeric(SCALE = 1);

Property RainMm As %Numeric(SCALE = 1);

Property WindSpeedMs As %Numeric(SCALE = 1);

Index PlantDayIdx On (PlantCode, Day) [ Unique ];

}
