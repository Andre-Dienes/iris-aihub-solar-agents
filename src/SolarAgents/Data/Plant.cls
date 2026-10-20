/// Fictional solar plant (all names and numbers are invented for the demo).
Class SolarAgents.Data.Plant Extends %Persistent
{

/// Short code used by every other table (AUR, BLR, GRV, HZN).
Property Code As %String(MAXLEN = 10) [ Required ];

/// EXACT collation keeps "Aurora Solar Plant" (not "AURORA SOLAR PLANT") in GROUP BY results.
Property Name As %String(COLLATION = "EXACT", MAXLEN = 100) [ Required ];

Property Region As %String(MAXLEN = 50);

/// Installed DC power in kWp.
Property CapacityKWp As %Numeric(SCALE = 1);

Property Technology As %String(MAXLEN = 100);

/// 1 = single-axis tracker, 0 = fixed tilt.
Property Tracker As %Boolean;

Property CommissionedOn As %Date;

Index CodeIdx On Code [ Unique ];

}
