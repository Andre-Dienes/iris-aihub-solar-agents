/// Data agent "Maintenance" — Maintenance: equipment alarms, severity, status and downtime hours.
Class SolarAgents.Agent.Maintenance Extends SolarAgents.Agent.DataAgent
{

Parameter AGENTNAME = "Maintenance";

Parameter TABLES = "Alarm,Plant";

Parameter TOPIC = "Maintenance: equipment alarms, severity, status and downtime hours";

/// Icon used in the synthesized answer.
Parameter ICON = "🛠️";

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
# Maintenance agent

Maintenance: equipment alarms, severity, status and downtime hours.
Writes SQL only over the tables: Alarm,Plant (schema SolarAgents_Data).
}

}
