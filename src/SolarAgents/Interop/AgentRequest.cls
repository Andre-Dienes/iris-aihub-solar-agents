/// Question for an agent business process. Content may be plain text or {"question","context"} JSON.
Class SolarAgents.Interop.AgentRequest Extends Ens.Request
{

Property Content As %String(MAXLEN = "");

/// Trace id shared by every step of one question (SolarAgents.Core.Trace).
Property TraceId As %String(MAXLEN = 64);

}
