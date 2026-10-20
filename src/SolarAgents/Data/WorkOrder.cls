/// Maintenance work order created by an agent through the Interoperability production
/// (SolarAgents.Interop.WorkOrderOperation) — shows an AI agent triggering a real workflow.
Class SolarAgents.Data.WorkOrder Extends %Persistent
{

Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDateTime($Horolog, 3)} ];

Property PlantCode As %String(MAXLEN = 10);

Property Equipment As %String(MAXLEN = 20);

Property Priority As %String(MAXLEN = 10);

Property Description As %String(MAXLEN = 1000);

Property RequestedBy As %String(MAXLEN = 50);

Property Status As %String(MAXLEN = 20) [ InitialExpression = "Open" ];

}
