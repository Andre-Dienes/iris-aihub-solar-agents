Include %AI

/// Tools of the demo (%AI.ToolSet). Used by the autonomous assistant (SolarAgents.Agent.Assistant)
/// and exposed to any MCP client by SolarAgents.MCP.Service at /mcp/solar.
Class SolarAgents.Tools.SolarToolSet Extends %AI.ToolSet
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="SolarTools">
  <Description>Monitoring of fictional solar plants (Aurora, Blue Ridge, Green Valley, Horizon): energy, PR, weather, alarms and maintenance work orders.</Description>
  <Tool Name="ListPlants" Method="ListPlants">
    <Description>Lists the plants with code, name, region, capacity (kWp) and technology.</Description>
  </Tool>
  <Tool Name="AskRouter" Method="AskRouter">
    <Description>Natural-language question about the plants. Runs the multi-agent router (telemetry, weather, maintenance) and returns tables and analysis. Pass question.</Description>
  </Tool>
  <Tool Name="QueryAgent" Method="QueryAgent">
    <Description>Direct query to one data agent: agent = Telemetry, Weather or Maintenance. Returns the generated SQL, the table and the highlights.</Description>
  </Tool>
  <Tool Name="CalculatePR" Method="CalculatePR">
    <Description>Computes the IEC 61724 Performance Ratio (with temperature correction) of a plant. Pass plantCode (AUR, BLR, GRV, HZN), startDate and endDate as YYYY-MM-DD.</Description>
  </Tool>
  <Tool Name="SearchKnowledge" Method="SearchKnowledge">
    <Description>Semantic search (IRIS vectors) in the knowledge base. collection: glossary (concepts), schema (tables) or examples (questions and SQL).</Description>
  </Tool>
  <Tool Name="CreateWorkOrder" Method="CreateWorkOrder">
    <Description>Opens a maintenance work order through the Interoperability production. Pass plantCode, equipment (e.g. INV-03), priority (High, Medium or Low) and description. Use only when the user asks or agrees.</Description>
  </Tool>
  <Tool Name="ListWorkOrders" Method="ListWorkOrders">
    <Description>Lists the maintenance work orders opened by the assistant.</Description>
  </Tool>
  <Tool Name="GetTrace" Method="GetTrace">
    <Description>Shows the latest LLM calls, embeddings and graph nodes (observability).</Description>
  </Tool>
</ToolSet>
}

ClassMethod ListPlants() As %String
{
    Set out = [], rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Code, Name, Region, CapacityKWp, Technology, Tracker FROM SolarAgents_Data.Plant ORDER BY Code")
    While rs.%Next() {
        Do out.%Push({"code": (rs.Code), "name": (rs.Name), "region": (rs.Region), "kwp": (+rs.CapacityKWp), "technology": (rs.Technology), "tracker": (+rs.Tracker)})
    }
    Quit out.%ToJSON()
}

// AskRouter and QueryAgent make LLM calls of their own. An LLM call nested inside a tool call of
// a running %AI.Agent re-enters the AI-Core bridge, so their bodies run in another process
// (SolarAgents.Core.Isolate); when the production is up they also go through it (Visual Trace).

ClassMethod AskRouter(question As %String) As %String
{
    Quit ##class(SolarAgents.Core.Isolate).Call($ClassName(), "AskRouterRun", 600, question)
}

ClassMethod AskRouterRun(question As %String) As %String
{
    Set payload = ##class(%DynamicObject).%FromJSON(##class(SolarAgents.Core.Dispatch).Call("Router", question))
    Quit payload.%Get("text")_$Char(10,10)_"[agents: "_payload.agents.%ToJSON()_"]"
}

ClassMethod QueryAgent(agent As %String, question As %String) As %String
{
    Quit:'$ListFind($ListBuild("Telemetry", "Weather", "Maintenance"), agent) "Invalid agent: use Telemetry, Weather or Maintenance."
    Quit ##class(SolarAgents.Core.Isolate).Call($ClassName(), "QueryAgentRun", 600, agent, question)
}

ClassMethod QueryAgentRun(agent As %String, question As %String) As %String
{
    Set payload = ##class(%DynamicObject).%FromJSON(##class(SolarAgents.Core.Dispatch).Call(agent, question))
    Quit:payload.%Get("error")'="" "Error: "_payload.error_$Select(payload.%Get("sql")'="":$Char(10)_"SQL: "_payload.sql, 1:"")
    Quit "SQL: "_payload.sql_$Char(10,10)_payload."table_md"_$Char(10)_payload.narrative
}

ClassMethod CalculatePR(plantCode As %String, startDate As %String, endDate As %String) As %String
{
    Quit ##class(SolarAgents.Analysis.Analyzer).CalculatePR($ZConvert(plantCode, "U"), startDate, endDate)
}

ClassMethod SearchKnowledge(collection As %String, query As %String, k As %Integer = 3) As %String
{
    Quit:'$ListFind($ListBuild("glossary", "schema", "examples"), collection) "Invalid collection: use glossary, schema or examples."
    Quit ##class(SolarAgents.RAG.VectorStore).Search(collection, query, k)
}

/// Sends a WorkOrderRequest through the production (Gateway -> WorkOrders).
ClassMethod CreateWorkOrder(plantCode As %String, equipment As %String, priority As %String, description As %String) As %String
{
    Set request = ##class(SolarAgents.Interop.WorkOrderRequest).%New()
    Set request.PlantCode = $ZConvert(plantCode, "U"), request.Equipment = equipment
    Set request.Priority = priority, request.Description = description, request.RequestedBy = "AI Assistant"
    If ##class(SolarAgents.Core.Dispatch).ProductionRunning() {
        Set sc = ##class(SolarAgents.Interop.Gateway).Send("WorkOrders", request, .response)
        Quit:$$$ISERR(sc) "Could not open the work order: "_$System.Status.GetErrorText(sc)
        Quit response.Message
    }
    Set operation = ##class(SolarAgents.Interop.WorkOrderOperation).%New("WorkOrders")
    Set sc = operation.Open(request, .response)
    Quit $Select($$$ISOK(sc):response.Message, 1:"Could not open the work order: "_$System.Status.GetErrorText(sc))
}

ClassMethod ListWorkOrders() As %String
{
    Set out = [], rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, CreatedAt, PlantCode, Equipment, Priority, Description, Status FROM SolarAgents_Data.WorkOrder ORDER BY ID DESC")
    While rs.%Next() {
        Do out.%Push({"id": ("WO-"_$Translate($Justify(rs.ID, 5), " ", "0")), "created": (rs.CreatedAt), "plant": (rs.PlantCode), "equipment": (rs.Equipment), "priority": (rs.Priority), "description": (rs.Description), "status": (rs.Status)})
    }
    Quit out.%ToJSON()
}

ClassMethod GetTrace(limit As %Integer = 20) As %String
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP ? CreatedAt, TraceId, Agent, Kind, Model, DurationMs, PromptTokens, CompletionTokens, Error FROM SolarAgents_Core.Trace ORDER BY ID DESC", limit)
    While rs.%Next() {
        Do out.%Push({"at": (rs.CreatedAt), "trace": (rs.TraceId), "agent": (rs.Agent), "kind": (rs.Kind), "model": (rs.Model), "ms": (rs.DurationMs), "tokens_in": (rs.PromptTokens), "tokens_out": (rs.CompletionTokens), "error": (rs.Error)})
    }
    Quit out.%ToJSON()
}

}
