/// One row per graph node, LLM call and embedding call of the demo (observability).
/// Query with:  SELECT TOP 50 * FROM SolarAgents_Core.Trace ORDER BY ID DESC
Class SolarAgents.Core.Trace Extends %Persistent
{

Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDateTime($ZTimeStamp, 3, 1, 3)} ];

/// Correlates every call made while answering one user question.
Property TraceId As %String(MAXLEN = 64);

/// Agent / node that made the call (e.g. "Router.triage", "Telemetry.sql").
Property Agent As %String(MAXLEN = 200);

/// chat | embedding
Property Kind As %String(MAXLEN = 20);

Property Provider As %String(MAXLEN = 50);

Property Model As %String(MAXLEN = 100);

Property DurationMs As %Integer;

Property PromptTokens As %Integer;

Property CompletionTokens As %Integer;

Property Input As %Stream.GlobalCharacter;

Property Output As %Stream.GlobalCharacter;

Property Error As %String(MAXLEN = 4000);

Index TraceIdx On TraceId;

Index AgentIdx On Agent;

/// Current trace id for this process (set by the graph engine per request).
ClassMethod CurrentTraceId() As %String
{
    Quit $Get(^||SolarAgents.TraceId)
}

ClassMethod StartTrace(traceId As %String = "") As %String
{
    Set:traceId="" traceId = $System.Util.CreateGUID()
    Set ^||SolarAgents.TraceId = traceId
    Quit traceId
}

ClassMethod Log(agent As %String, kind As %String, provider As %String, model As %String, durationMs As %Integer, inText As %String, outText As %String, usage As %DynamicObject = "", error As %String = "") As %Status
{
    Set sc = $$$OK
    Try {
        Quit:##class(SolarAgents.Core.Config).Get("SOLAR_TRACE", "1")="0"
        Set call = ..%New()
        Set call.TraceId = ..CurrentTraceId()
        Set call.Agent = agent
        Set call.Kind = kind
        Set call.Provider = provider
        Set call.Model = model
        Set call.DurationMs = durationMs
        Set call.Error = $Extract(error, 1, 4000)
        If $IsObject(usage) {
            Set call.PromptTokens = usage.%Get("prompt_tokens")
            Set call.CompletionTokens = usage.%Get("completion_tokens")
        }
        Do call.Input.Write(inText)
        Do call.Output.Write(outText)
        Set sc = call.%Save()
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

}
