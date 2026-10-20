/// Agent skill (%AI.Agent.Skill): a packaged procedure the assistant activates on its own when a
/// question asks for a performance diagnosis. Contributes its instructions and its tools.
Class SolarAgents.Skill.PerformanceAnalyst Extends %AI.Agent.Skill
{

Parameter TOOLS = "SolarAgents.Tools.SolarToolSet";

XData SUMMARY [ MimeType = text/yaml ]
{
name: performance-diagnosis
description: Diagnoses a performance drop of a solar plant (PR, availability, weather and alarms) and recommends an action
tags: [solar, pr, diagnosis, maintenance]
}

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
# Performance diagnosis

Use this procedure when the user asks why a plant produced less, asks for a diagnosis or wants to know
whether it needs maintenance.

1. **CalculatePR** for the plant in the requested period and in the previous period of the same length (compare both).
2. **QueryAgent** with agent=Telemetry to see the daily evolution of PR and availability.
3. **QueryAgent** with agent=Maintenance to list alarms and downtime hours in the period.
4. **QueryAgent** with agent=Weather if the drop could be explained by weather (rain, irradiation, heat).
5. Conclude with: most likely cause, estimated impact in kWh and PR (percentage points) and the recommended action.
6. If an equipment has a recurring failure or an open alarm, **offer** to open a maintenance work order
   (CreateWorkOrder) — open it only if the user confirms.
}

}
