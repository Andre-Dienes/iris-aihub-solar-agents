/// Business process that runs an AI Hub agent (SolarAgents.Graph.GraphAgent subclass).
/// One production item per agent, configured with the AgentClass setting.
Class SolarAgents.Interop.AgentProcess Extends Ens.BusinessProcess
{

/// Agent class run by this item, e.g. SolarAgents.Agent.Router
Property AgentClass As %String(MAXLEN = 200);

Parameter SETTINGS = "AgentClass:Basic";

Method OnRequest(request As SolarAgents.Interop.AgentRequest, Output response As SolarAgents.Interop.AgentResponse) As %Status
{
    Set response = ##class(SolarAgents.Interop.AgentResponse).%New()
    Try {
        Do ##class(SolarAgents.Core.Trace).StartTrace(request.TraceId)
        $$$LOGINFO(..AgentClass_" <- "_$Extract(request.Content, 1, 200))
        Set agent = $ClassMethod(..AgentClass, "%New")
        Do response.Payload.Write(agent.Respond(request.Content, request.TraceId))
        Set response.Status = "OK"
    } Catch ex {
        $$$LOGERROR(..AgentClass_": "_ex.DisplayString())
        Do response.Payload.Write({"error": (ex.DisplayString())}.%ToJSON())
        Set response.Status = "ERROR"
    }
    Quit $$$OK
}

}
