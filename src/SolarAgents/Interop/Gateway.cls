/// Entry point into the production. REST, tools and the router send requests through it, so every
/// agent call and every action shows up in the Interoperability Visual Trace.
Class SolarAgents.Interop.Gateway Extends Ens.BusinessService
{

/// Sends a request to a production item and waits for the response.
ClassMethod Send(target As %String, request As Ens.Request, Output response As Ens.Response, timeout As %Integer = 600) As %Status
{
    Set sc = ##class(Ens.Director).CreateBusinessService("Gateway", .service)
    Quit:$$$ISERR(sc) sc
    Quit service.SendRequestSync(target, request, .response, timeout)
}

/// Asks an agent business process (e.g. "Agent.Router") and returns its JSON payload.
ClassMethod Ask(target As %String, content As %String, traceId As %String = "") As %String
{
    Set request = ##class(SolarAgents.Interop.AgentRequest).%New()
    Set request.Content = content
    Set request.TraceId = $Select(traceId'="":traceId, 1:##class(SolarAgents.Core.Trace).CurrentTraceId())
    $$$ThrowOnError(..Send(target, request, .response))
    Quit:'$IsObject(response) {"error": ("Sem resposta de "_target)}.%ToJSON()
    Do response.Payload.Rewind()
    Quit response.Payload.Read(response.Payload.Size + 1)
}

}
