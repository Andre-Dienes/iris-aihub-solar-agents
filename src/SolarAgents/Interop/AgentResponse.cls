/// Answer of an agent business process (JSON payload of the agent).
Class SolarAgents.Interop.AgentResponse Extends Ens.Response
{

Property Payload As %Stream.GlobalCharacter;

/// OK | ERROR
Property Status As %String(MAXLEN = 10);

}
