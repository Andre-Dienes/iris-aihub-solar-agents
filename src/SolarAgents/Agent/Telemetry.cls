/// Data agent "Telemetry" — Inverter telemetry: daily energy, expected energy, Performance Ratio and availability.
Class SolarAgents.Agent.Telemetry Extends SolarAgents.Agent.DataAgent
{

Parameter AGENTNAME = "Telemetry";

Parameter TABLES = "Generation,Plant";

Parameter TOPIC = "Inverter telemetry: daily energy, expected energy, Performance Ratio and availability";

/// Icon used in the synthesized answer.
Parameter ICON = "📊";

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
# Telemetry agent

Inverter telemetry: daily energy, expected energy, Performance Ratio and availability.
Writes SQL only over the tables: Generation,Plant (schema SolarAgents_Data).
}

}
