Include Ensemble

/// Calls an agent by name ("Router", "Telemetry", "Weather", "Maintenance").
/// With the production running the call goes through it (Gateway -> Agent.<Name>, visible in the
/// Visual Trace); otherwise the agent runs in this process.
Class SolarAgents.Core.Dispatch Extends %RegisteredObject
{

/// Returns the agent JSON payload. content: plain question or {"question","context"} JSON.
ClassMethod Call(name As %String, content As %String) As %String
{
    If ..ProductionRunning() && (##class(SolarAgents.Core.Config).Get("SOLAR_AGENT_MODE", "interop")="interop") {
        Quit ##class(SolarAgents.Interop.Gateway).Ask("Agent."_name, content)
    }
    Quit $ClassMethod("SolarAgents.Agent."_name, "%New").Respond(content)
}

ClassMethod ProductionRunning() As %Boolean
{
    Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
    Quit $$$ISOK(sc) && (state = $$$eProductionStateRunning)
}

}
