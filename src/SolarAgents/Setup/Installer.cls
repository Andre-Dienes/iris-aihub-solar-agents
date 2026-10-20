Include Ensemble

/// Installation and startup of the demo.
///   Build()    — image build (docker/iris.script): demo data, production auto-start
///   Startup()  — every container start (docker/entrypoint.sh): knowledge base, MCP tools, production
Class SolarAgents.Setup.Installer Extends %RegisteredObject
{

Parameter PRODUCTION = "SolarAgents.Interop.Production";

ClassMethod Build() As %Status
{
    Set sc = $$$OK
    Try {
        $$$ThrowOnError(##class(SolarAgents.Data.DemoData).Load())
        If ##class(%Dictionary.CompiledClass).%ExistsId(..#PRODUCTION) {
            $$$ThrowOnError(##class(Ens.Director).SetAutoStart(..#PRODUCTION))
        }
        Write "Demo installed",!
    } Catch ex {
        Set sc = ex.AsStatus()
        Write "Install error: ",ex.DisplayString(),!
    }
    Quit sc
}

ClassMethod Startup() As %Status
{
    Set sc = $$$OK
    Try {
        Write "LLM provider: ",##class(SolarAgents.Core.Config).Provider(),!
        Do ..EnsureKnowledge()
        Do ..RegisterTools()
        If ##class(%Dictionary.CompiledClass).%ExistsId(..#PRODUCTION), '##class(SolarAgents.Core.Dispatch).ProductionRunning() {
            Set psc = ##class(Ens.Director).StartProduction(..#PRODUCTION)
            If $$$ISERR(psc), '$System.Status.Equals(psc, $$$EnsErrProductionAlreadyRunning) {
                $$$ThrowStatus(psc)
            }
        }
        Write "Demo ready",!
    } Catch ex {
        Set sc = ex.AsStatus()
        Write "Startup error: ",ex.DisplayString(),!
    }
    Quit sc
}

/// (Re)embeds the knowledge base when the provider (OpenAI vs offline hash vectors) or the
/// content of SolarAgents.Knowledge.Base changed since the last load.
ClassMethod EnsureKnowledge() As %Status
{
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId("SolarAgents.Knowledge.Base||Knowledge")
    Set version = ##class(SolarAgents.Core.Config).Provider()_":"_$ZCRC(xdata.Data.Read(3000000), 7)
    If (version'=$Get(^SolarAgents.KnowledgeVersion)) || '##class(SolarAgents.RAG.VectorStore).Exists("examples") {
        $$$ThrowOnError(##class(SolarAgents.Knowledge.Base).Load())
        Set ^SolarAgents.KnowledgeVersion = version
    }
    Quit $$$OK
}

/// Pre-loads the MCP tool catalog of /mcp/solar.
ClassMethod RegisterTools() As %Status
{
    Set sc = $$$OK
    Try {
        Quit:'##class(%Dictionary.CompiledClass).%ExistsId("SolarAgents.Tools.SolarToolSet")
        Set mgr = ##class(%AI.ToolMgr).GetOrCreate("/mcp/solar", .isNew)
        Do mgr.Cleanup()
        Set mgr = ##class(%AI.ToolMgr).GetOrCreate("/mcp/solar", .isNew)
        Set sc = ##class(%AI.MCP.Service).LoadToolSetsToManager(mgr, "SolarAgents.Tools.SolarToolSet")
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

}
