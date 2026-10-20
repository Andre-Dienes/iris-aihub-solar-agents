/// Offline test suite (no API key needed): runs the graphs, tools and guardrails in offline mode.
///
///   Do ##class(SolarAgents.Tests.DemoTest).Run()
Class SolarAgents.Tests.DemoTest Extends %UnitTest.TestCase
{

ClassMethod Run() As %Status
{
    Set:$Get(^UnitTestRoot)="" ^UnitTestRoot = ##class(%File).NormalizeDirectory($System.Util.ManagerDirectory()_"Temp")
    Quit ##class(%UnitTest.Manager).DebugRunTestCase("", $ClassName(), "/nodelete", "")
}

Method OnBeforeAllTests() As %Status
{
    Merge ^||saved = ^SolarAgents.Config
    Do ##class(SolarAgents.Core.Config).Set("SOLAR_LLM_PROVIDER", "mock")
    Do ##class(SolarAgents.Core.Config).Set("SOLAR_AGENT_MODE", "direct")
    Do ##class(SolarAgents.Data.DemoData).Load()
    Quit ##class(SolarAgents.Setup.Installer).EnsureKnowledge()
}

Method OnAfterAllTests() As %Status
{
    Kill ^SolarAgents.Config
    Merge ^SolarAgents.Config = ^||saved
    // re-embed the knowledge base with the provider that is active again
    Quit ##class(SolarAgents.Setup.Installer).EnsureKnowledge()
}

Method TestQueryParser()
{
    Set plants = ##class(SolarAgents.Core.QueryParser).Plants("What was the PR of Blue Ridge and Aurora?")
    Do $$$AssertEquals(plants.codes.%ToJSON(), "[""AUR"",""BLR""]")
    Do $$$AssertEquals(##class(SolarAgents.Core.QueryParser).Plants("ranking of all plants").codes.%Size(), 4)
    Set period = ##class(SolarAgents.Core.QueryParser).Period("energy in August 2026")
    Do $$$AssertEquals(period.start_" "_period.end, "2026-08-01 2026-08-31")
    Set period = ##class(SolarAgents.Core.QueryParser).Period("from 2026-08-10 to 2026-08-18")
    Do $$$AssertEquals(period.start_" "_period.end, "2026-08-10 2026-08-18")
    Do $$$AssertEquals(##class(SolarAgents.Core.QueryParser).Language("Which plant had the best PR in July?"), "en")
    Do $$$AssertEquals(##class(SolarAgents.Core.QueryParser).Language("Qual foi o PR da usina em julho?"), "pt")
}

Method TestSqlGuardrails()
{
    Do $$$AssertEquals(##class(SolarAgents.Core.SQL).Validate("SELECT * FROM SolarAgents_Data.Generation", "Generation,Plant"), "")
    Do $$$AssertTrue(##class(SolarAgents.Core.SQL).Validate("DELETE FROM SolarAgents_Data.Generation", "Generation")'="")
    Do $$$AssertTrue(##class(SolarAgents.Core.SQL).Validate("SELECT * FROM SolarAgents_Data.Alarm", "Generation,Plant")["outside")
    Do $$$AssertTrue(##class(SolarAgents.Core.SQL).Validate("SELECT 1; DROP TABLE x", "")'="")
}

Method TestVectorSearch()
{
    Set hits = ##class(SolarAgents.RAG.VectorStore).SearchObj("glossary", "what is performance ratio", 2)
    Do $$$AssertEquals(hits.%Get(0).metadata.term, "PR")
}

Method TestTelemetryAgent()
{
    Set r = ##class(SolarAgents.Agent.Telemetry).%New().Answer("What was the energy and the PR of each plant in August 2026?")
    Do $$$AssertEquals(r.error, "")
    Do $$$AssertEquals(r.path.%ToJSON(), "[""retrieve"",""sql"",""execute"",""analyze""]")
    Do $$$AssertEquals(r."row_count", 4)
    Do $$$AssertTrue(r."table_md"["Blue Ridge Solar Plant")
}

Method TestMaintenanceAgent()
{
    Set r = ##class(SolarAgents.Agent.Maintenance).%New().Answer("Which alarms did Blue Ridge have in August 2026?")
    Do $$$AssertTrue(r."table_md"["INV-03")
}

Method TestRouterBranches()
{
    Set router = ##class(SolarAgents.Agent.Router).%New()
    Do $$$AssertEquals(router.Answer("What is Performance Ratio?").category, "CONCEPT")
    Do $$$AssertEquals(router.Answer("What is the capital of France?").category, "OFFTOPIC")
    Do $$$AssertEquals(router.Answer("What was the energy?").path.%ToJSON(), "[""triage"",""identify"",""ambiguous"",""finalize""]")
}

Method TestRouterRootCause()
{
    Set r = ##class(SolarAgents.Agent.Router).%New().Answer("Why did the PR of Blue Ridge drop in August 2026?")
    Do $$$AssertEquals(r.agents.%ToJSON(), "[""Telemetry"",""Weather"",""Maintenance""]")
    Do $$$AssertTrue(r.text["2026-08-10", "daily series shows the drop")
    Do $$$AssertTrue(r.text["INV-03", "maintenance finds the failed inverter")
}

Method TestPRCalculator()
{
    Set jul = ##class(%DynamicObject).%FromJSON(##class(SolarAgents.Analysis.Analyzer).CalculatePR("BLR", "2026-07-01", "2026-07-31"))
    Set aug = ##class(%DynamicObject).%FromJSON(##class(SolarAgents.Analysis.Analyzer).CalculatePR("BLR", "2026-08-01", "2026-08-31"))
    Do $$$AssertTrue(aug."pr_pct" < jul."pr_pct", "August PR is lower (inverter failure)")
}

Method TestToolSetAndSkill()
{
    Set mgr = ##class(%AI.ToolMgr).GetOrCreate("/mcp/solar-test", .isNew)
    Do ##class(%AI.MCP.Service).LoadToolSetsToManager(mgr, "SolarAgents.Tools.SolarToolSet")
    Set found = 0, iter = mgr.FindTools("").%GetIterator()
    While iter.%GetNext(, .entry) {
        Set:entry.class="SolarAgents.Tools.SolarToolSet" found = entry.tools.%Size()
    }
    Do $$$AssertEquals(found, 8)
    Do mgr.Cleanup()
    Do $$$AssertTrue(##class(SolarAgents.Skill.PerformanceAnalyst).%Extends("%AI.Agent.Skill"))
}

Method TestWorkOrderAction()
{
    Set before = ##class(%DynamicArray).%FromJSON(##class(SolarAgents.Tools.SolarToolSet).ListWorkOrders()).%Size()
    Set msg = ##class(SolarAgents.Tools.SolarToolSet).CreateWorkOrder("GRV", "STR-ALL", "Medium", "Automated test: module cleaning")
    Do $$$AssertTrue(msg["WO-")
    Set orders = ##class(%DynamicArray).%FromJSON(##class(SolarAgents.Tools.SolarToolSet).ListWorkOrders())
    Do $$$AssertEquals(orders.%Size(), before + 1)
    &sql(DELETE FROM SolarAgents_Data.WorkOrder WHERE Description %STARTSWITH 'Automated test')
}

Method TestTraceRecorded()
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM SolarAgents_Core.Trace WHERE Kind = 'node' AND Agent %STARTSWITH 'Router.'")
    Do rs.%Next()
    Do $$$AssertTrue(rs.N > 0)
}

}
