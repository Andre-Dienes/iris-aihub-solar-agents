/// Data agent "Weather" — Weather: GTI/GHI irradiation, ambient and module temperature, rain and wind.
Class SolarAgents.Agent.Weather Extends SolarAgents.Agent.DataAgent
{

Parameter AGENTNAME = "Weather";

Parameter TABLES = "Weather,Plant";

Parameter TOPIC = "Weather: GTI/GHI irradiation, ambient and module temperature, rain and wind";

/// Icon used in the synthesized answer.
Parameter ICON = "☀️";

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
# Weather agent

Weather: GTI/GHI irradiation, ambient and module temperature, rain and wind.
Writes SQL only over the tables: Weather,Plant (schema SolarAgents_Data).
}

}
