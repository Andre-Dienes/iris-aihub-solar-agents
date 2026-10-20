/// Request to open a maintenance work order (sent by the assistant's CreateWorkOrder tool).
Class SolarAgents.Interop.WorkOrderRequest Extends Ens.Request
{

Property PlantCode As %String(MAXLEN = 10);

Property Equipment As %String(MAXLEN = 20);

/// High | Medium | Low
Property Priority As %String(MAXLEN = 10);

Property Description As %String(MAXLEN = 1000);

Property RequestedBy As %String(MAXLEN = 50);

}
