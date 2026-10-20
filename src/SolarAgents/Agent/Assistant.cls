/// Autonomous assistant — declarative IRIS AI Hub %AI.Agent:
///   PROVIDER / MODEL     : LLM (OpenAI)
///   TOOLSETS             : SolarAgents.Tools.SolarToolSet (the LLM decides which tools to call)
///   SKILLS               : SolarAgents.Skill.PerformanceAnalyst (activated on demand)
///   XData INSTRUCTIONS   : system prompt
/// Conversations are persistent %AI.Agent.Session objects, so a session id continues a chat.
/// Requires an OpenAI key (in offline mode use the Router instead).
///
///   Set reply = ##class(SolarAgents.Agent.Assistant).Converse("Why did Blue Ridge underperform in August 2026?", .sessionId)
Class SolarAgents.Agent.Assistant Extends %AI.Agent
{

Parameter PROVIDER = "openai";

Parameter MODEL = "gpt-4o";

Parameter TOOLSETS = "SolarAgents.Tools.SolarToolSet";

Parameter SKILLS = "SolarAgents.Skill.PerformanceAnalyst";

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
# Solar plant assistant

You help the operations team of four solar plants (Aurora, Blue Ridge, Green Valley and Horizon).

- For numbers and comparisons use **AskRouter** (multi-agent router) or **QueryAgent** (a single source).
- For the formal Performance Ratio of a period use **CalculatePR**.
- For concepts use **SearchKnowledge** with collection=glossary.
- To diagnose a performance drop, activate the **performance-diagnosis** skill.
- Open maintenance work orders (**CreateWorkOrder**) only when the user asks or confirms.
- Never invent numbers: use only what the tools return. Answer in the user's language, in markdown,
  objectively.
}

/// Own %AI.Provider instance (the tools call the LLM through SolarAgents.Core.LLM in other processes).
Method %OnNew(provider As %AI.Provider = "") As %Status
{
    Set sc = $$$OK
    Try {
        If '$IsObject(provider), ##class(SolarAgents.Core.Config).ApiKey()'="" {
            Set provider = ##class(%AI.Provider).Create("openai", ##class(SolarAgents.Core.Config).ProviderSettings())
        }
        Set sc = ##super(provider)
        Set:..Model="" ..Model = ##class(SolarAgents.Core.Config).StrongModel()
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Entry point for web requests: runs Converse() in a fresh process (SolarAgents.Core.Isolate) so the
/// long-lived CSP server process never hosts the AI-Core agent loop. Returns the JSON of Converse().
ClassMethod Ask(message As %String, sessionId As %String = "") As %DynamicObject
{
    Quit ##class(%DynamicObject).%FromJSON(##class(SolarAgents.Core.Isolate).Call($ClassName(), "ConverseJSON", 900, message, sessionId))
}

ClassMethod ConverseJSON(message As %String, sessionId As %String = "") As %String
{
    Quit ..Converse(message, .sessionId).%ToJSON()
}

/// Sends a message; sessionId "" starts a new persistent conversation (returned by reference).
/// Returns {"text", "session_id", "stats"}.
ClassMethod Converse(message As %String, ByRef sessionId As %String = "") As %DynamicObject
{
    If ##class(SolarAgents.Core.LLM).IsMock() {
        Quit {"text": "The autonomous assistant needs an OpenAI key (OPENAI_API_KEY). In offline mode use the **Router** mode.", "session_id": "", "stats": {}}
    }
    Set agent = ..%New()
    Set session = ""
    If sessionId'="" {
        Set session = ##class(%AI.Agent.Session).%OpenId(sessionId)
    }
    If $IsObject(session) {
        $$$ThrowOnError(agent.%InitWithSession(session))
    } Else {
        $$$ThrowOnError(agent.%Init())
        Set session = agent.CreateSession()
    }
    Set start = $ZHorolog
    Set response = agent.Chat(session, message)
    Do ##class(SolarAgents.Core.Trace).Log("Assistant.chat", "chat", "openai", agent.Model, ($ZHorolog - start) * 1000 \ 1, message, response.Content, response.Usage)
    Do session.%Save()
    Set sessionId = session.%Id()
    Quit {"text": (response.Content), "session_id": (sessionId), "stats": (session.GetStats())}
}

}
