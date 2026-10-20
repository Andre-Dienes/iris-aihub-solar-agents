/// Equipment alarms of each plant (maintenance system).
Class SolarAgents.Data.Alarm Extends %Persistent
{

Property PlantCode As %String(MAXLEN = 10) [ Required ];

Property OpenedAt As %TimeStamp [ Required ];

Property ClosedAt As %TimeStamp;

/// Equipment tag, e.g. INV-03, TRK-12, CB-02.
Property Equipment As %String(MAXLEN = 20);

/// Critical, High, Medium, Low
Property Severity As %String(MAXLEN = 10);

Property Code As %String(MAXLEN = 30);

Property Description As %String(MAXLEN = 300);

/// Open or Closed
Property Status As %String(MAXLEN = 10);

/// Production hours lost because of the alarm.
Property DowntimeHours As %Numeric(SCALE = 1);

Index PlantIdx On PlantCode;

}
