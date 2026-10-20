/// MCP endpoint (%AI.MCP.Service) — web application /mcp/solar.
/// Exposes SolarAgents.Tools.SolarToolSet to MCP clients through the iris-mcp-server sidecar.
Class SolarAgents.MCP.Service Extends %AI.MCP.Service
{

Parameter SPECIFICATION = "SolarAgents.Tools.SolarToolSet";

}
