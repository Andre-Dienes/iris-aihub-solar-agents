/// Business operation that opens a maintenance work order (here a row in SolarAgents.Data.WorkOrder;
/// in a real deployment it would call the maintenance system / ERP API).
Class SolarAgents.Interop.WorkOrderOperation Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method Open(request As SolarAgents.Interop.WorkOrderRequest, Output response As SolarAgents.Interop.WorkOrderResponse) As %Status
{
    Set response = ##class(SolarAgents.Interop.WorkOrderResponse).%New()
    Set wo = ##class(SolarAgents.Data.WorkOrder).%New()
    Set wo.PlantCode = request.PlantCode, wo.Equipment = request.Equipment
    Set wo.Priority = request.Priority, wo.Description = request.Description
    Set wo.RequestedBy = $Select(request.RequestedBy'="":request.RequestedBy, 1:"AI Assistant")
    Set sc = wo.%Save()
    Quit:$$$ISERR(sc) sc
    Set response.WorkOrderId = "WO-"_$Translate($Justify(wo.%Id(), 5), " ", "0")
    Set response.Message = "Work order "_response.WorkOrderId_" opened for "_request.PlantCode_" / "_request.Equipment
    $$$LOGINFO(response.Message)
    Quit $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="SolarAgents.Interop.WorkOrderRequest">
    <Method>Open</Method>
  </MapItem>
</MapItems>
}

}
