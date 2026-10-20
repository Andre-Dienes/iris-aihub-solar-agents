/// Multi-agent router — an IRIS AI Hub %AI.Agent running a declarative graph:
/// <pre>
///   triage ─┬─ CONCEPT ──► knowledge (RAG over the glossary) ──────────────────────┐
///           ├─ OFFTOPIC ─► offtopic ───────────────────────────────────────────────┤
///           └─ DATA ─────► identify ─┬─ ok ─► plan ─► call_agents ─► synthesize ───┼─► finalize ─► END
///                                    └─ ambiguous ─► ambiguous ────────────────────┘
/// </pre>
///   triage      : LLM classification + keyword guardrails (offline: keywords only)
///   identify    : plants and period, deterministic (QueryParser)
///   plan        : which data agents answer (Telemetry, Weather, Maintenance; "why" questions use all three)
///   call_agents : each agent runs as its own business process when the production is up
///   synthesize  : tables from every source + integrated analysis by the LLM (offline: highlights)
///   finalize    : translation to Portuguese when the question is in Portuguese
///
///   Write ##class(SolarAgents.Agent.Router).%New().Answer("Why did the PR of Blue Ridge drop in August 2026?").text
Class SolarAgents.Agent.Router Extends SolarAgents.Graph.GraphAgent
{

Parameter AGENTNAME = "Router";

Parameter MODEL = "gpt-4o-mini";

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
# Solar plant router

Classifies the question, identifies plants and period, calls the data agents (Telemetry, Weather,
Maintenance), cross-checks their answers and delivers an integrated analysis.
}

XData Graph [ MimeType = application/json ]
{
{
  "start": "triage",
  "nodes": {
    "triage":      "TriageNode",
    "knowledge":   "KnowledgeNode",
    "offtopic":    "OffTopicNode",
    "identify":    "IdentifyNode",
    "ambiguous":   "AmbiguousNode",
    "plan":        "PlanNode",
    "call_agents": "CallAgentsNode",
    "synthesize":  "SynthesizeNode",
    "finalize":    "FinalizeNode"
  },
  "edges": {
    "triage":      { "router": "RouteCategory", "map": { "CONCEPT": "knowledge", "OFFTOPIC": "offtopic", "DATA": "identify" } },
    "identify":    { "router": "RouteScope", "map": { "ok": "plan", "ambiguous": "ambiguous" } },
    "plan":        "call_agents",
    "call_agents": "synthesize",
    "synthesize":  "finalize",
    "knowledge":   "finalize",
    "offtopic":    "finalize",
    "ambiguous":   "finalize",
    "finalize":    "END"
  }
}
}

Method Answer(question As %String, sessionId As %String = "") As %DynamicObject
{
    Set state = {"question": (question), "category": "", "text": "", "agents": [], "responses": {}, "error": ""}
    Set state = ..RunGraph(state)
    Quit {
        "text": (state.text),
        "category": (state.category),
        "language": (state.%Get("language")),
        "plants": ($Select($IsObject(state.%Get("plants")):state.plants.names, 1:[])),
        "period": ($Select($IsObject(state.%Get("period")):state.period.label, 1:"")),
        "agents": (state.agents),
        "path": (state.%Get("_path")),
        "trace_id": (##class(SolarAgents.Core.Trace).CurrentTraceId()),
        "error": (state.error)
    }
}

Method Respond(question As %String, sessionId As %String = "") As %String
{
    Quit ..Answer(question, sessionId).%ToJSON()
}

// ---------------------------------------------------------------- triage

Method TriageNode(state As %DynamicObject) As %Status
{
    Set q = " "_$Translate(##class(SolarAgents.Core.QueryParser).Normalize(state.question), "?!.,;:", "      ")_" "
    Set state.language = ##class(SolarAgents.Core.QueryParser).Language(state.question)
    Set hasPlant = (##class(SolarAgents.Core.QueryParser).Plants(state.question).codes.%Size() > 0)
    Set solar = hasPlant
    For kw="plant","solar","photovolt"," pv ","energy","generation","generated","output"," pr ","performance","irradia","ghi","gti","inverter","module","panel","alarm","failure","fault","availability","temperature","rain","weather","soiling","tracker","kwp","kwh","mwh","capacity","maintenance","downtime","usina","geracao","energia","inversor","alarme","clima","manutencao" {
        If q[kw {
            Set solar = 1
            Quit
        }
    }
    Set concept = 0
    For kw=" what is"," what are"," what does"," define "," explain what"," how does"," meaning of"," o que e"," o que sao"," como funciona" {
        If $Extract(q, 1, $Length(kw))=kw {
            Set concept = 1
            Quit
        }
    }
    Set category = $Select('solar:"OFFTOPIC", concept && 'hasPlant:"CONCEPT", 1:"DATA")
    If '##class(SolarAgents.Core.LLM).IsMock() {
        Set system = "Classify a question sent to a solar plant monitoring system. Categories: "_
                     "CONCEPT (asks to explain a technical concept, no data requested), "_
                     "DATA (asks for numbers, comparisons or diagnostics of plants), "_
                     "OFFTOPIC (not related to solar energy). "_
                     "Answer only JSON: {""category"": ""CONCEPT|DATA|OFFTOPIC""}"
        Set llm = ##class(SolarAgents.Core.LLM).ParseJSON(..LLM(system, state.question, "", 0)).%Get("category")
        Set:$ListFind($ListBuild("CONCEPT", "DATA", "OFFTOPIC"), llm) category = llm
        // guardrails: a named plant is always a data question; no solar vocabulary is always off-topic
        Set:hasPlant category = "DATA"
        Set:'solar category = "OFFTOPIC"
    }
    Set state.category = category
    Set state.step = "triaged"
    Quit $$$OK
}

Method RouteCategory(state As %DynamicObject) As %String
{
    Quit state.category
}

// ---------------------------------------------------------------- non-data branches

Method KnowledgeNode(state As %DynamicObject) As %Status
{
    Set hits = ##class(SolarAgents.RAG.VectorStore).SearchObj("glossary", state.question, 3)
    Set context = "", nl = $Char(10), iter = hits.%GetIterator()
    While iter.%GetNext(, .hit) {
        Set context = context_"- "_hit.content_nl
    }
    If ##class(SolarAgents.Core.LLM).IsMock() {
        Set best = hits.%Get(0)
        Set state.text = $Select($IsObject(best):best.content, 1:"I could not find this concept in the glossary.")_nl_nl_"_Source: knowledge base glossary (vector search)._"
    } Else {
        Set system = "You are a photovoltaic solar energy expert. Explain clearly and concisely (up to 6 sentences), "_
                     "using the glossary context. At the end, suggest a question about the plants' data."
        Set state.text = ..LLM(system, "Context:"_nl_context_nl_"Question: "_state.question, "", 0.3)
    }
    Set state.step = "knowledge_answered"
    Quit $$$OK
}

Method OffTopicNode(state As %DynamicObject) As %Status
{
    Set state.text = "I am a solar plant assistant. I can help with energy, Performance Ratio, irradiation, temperature, "_
                     "alarms and maintenance of the Aurora, Blue Ridge, Green Valley and Horizon solar plants."
    Set state.step = "offtopic_answered"
    Quit $$$OK
}

Method AmbiguousNode(state As %DynamicObject) As %Status
{
    Set state.text = "I need a bit more context: **which plant** (Aurora, Blue Ridge, Green Valley, Horizon or all of them) "_
                     "and **which period** (e.g. August 2026, last 30 days)?"_$Char(10,10)_
                     "Example: _What was the PR of Blue Ridge in August 2026?_"
    Set state."needs_clarification" = 1
    Set state.step = "clarification_requested"
    Quit $$$OK
}

// ---------------------------------------------------------------- data branch

Method IdentifyNode(state As %DynamicObject) As %Status
{
    Set state.plants = ##class(SolarAgents.Core.QueryParser).Plants(state.question)
    Set state.period = ##class(SolarAgents.Core.QueryParser).Period(state.question)
    Set state.step = "identified"
    Quit $$$OK
}

/// Without a plant and without a period the question is too vague ("what was the energy?").
Method RouteScope(state As %DynamicObject) As %String
{
    Quit:(state.plants.codes.%Size()=0)&&('state.period.explicit) "ambiguous"
    Set:state.plants.codes.%Size()=0 state.plants = ##class(SolarAgents.Core.QueryParser).Plants("all")
    Quit "ok"
}

Method PlanNode(state As %DynamicObject) As %Status
{
    Set q = " "_$Translate(##class(SolarAgents.Core.QueryParser).Normalize(state.question), "?!.,;:", "      ")_" "
    Set agents = []
    Set why = 0
    For kw=" why "," cause"," reason"," root cause"," diagnos"," explain the drop"," por que"," causa" {
        Set:q[kw why = 1
    }
    If why {
        Set agents = ["Telemetry", "Weather", "Maintenance"]
    } Else {
        Set rules = {
            "Telemetry": ["energy","generat","output"," pr ","performance","availability","expected","kwh","mwh","yield","compare","ranking","best","worst","geracao","energia","disponib"],
            "Weather": ["irradia","ghi","gti","temperature","weather","rain","wind","sun ","clima","chuva","temperatura"],
            "Maintenance": ["alarm","failure","fault","downtime","maintenance","inverter","equipment","work order","tracker","alarme","falha","manutencao","inversor"]
        }
        Set iter = rules.%GetIterator()
        While iter.%GetNext(.agent, .words) {
            Set wi = words.%GetIterator()
            While wi.%GetNext(, .w) {
                If q[w {
                    Do agents.%Push(agent)
                    Quit
                }
            }
        }
        Set:agents.%Size()=0 agents = ["Telemetry"]
    }
    Set state.agents = agents
    Set state.step = "planned"
    Quit $$$OK
}

Method CallAgentsNode(state As %DynamicObject) As %Status
{
    Set content = {"question": (state.question), "context": {"plants": (state.plants), "period": (state.period), "language": (state.language)}}.%ToJSON()
    Set iter = state.agents.%GetIterator()
    While iter.%GetNext(, .agent) {
        Try {
            Set payload = ##class(%DynamicObject).%FromJSON(##class(SolarAgents.Core.Dispatch).Call(agent, content))
        } Catch ex {
            Set payload = {"agent": (agent), "error": (ex.DisplayString())}
        }
        Do state.responses.%Set(agent, payload)
    }
    Set state.step = "agents_called"
    Quit $$$OK
}

Method SynthesizeNode(state As %DynamicObject) As %Status
{
    Set nl = $Char(10)
    Set text = "**Plants:** "_##class(SolarAgents.Agent.DataAgent).JoinArray(state.plants.names)_" · **Period:** "_state.period.label_nl_nl
    Set evidence = "", highlights = []
    Set iter = state.agents.%GetIterator()
    While iter.%GetNext(, .agent) {
        Set r = state.responses.%Get(agent)
        Set text = text_"### "_$Parameter("SolarAgents.Agent."_agent, "ICON")_" "_agent_nl_nl
        If r.%Get("error")'="" {
            Set text = text_"⚠️ "_r.error_nl_nl
            Continue
        }
        Set text = text_r."table_md"_nl
        Set:r.narrative'="" text = text_"> "_$Replace(r.narrative, nl, " ")_nl_nl
        Set evidence = evidence_agent_": highlights="_r.highlights.%ToJSON()_" statistics="_r.stats.%ToJSON()_" summary="_r.narrative_nl
        Set hi = r.highlights.%GetIterator()
        While hi.%GetNext(, .h) {
            Do highlights.%Push(agent_": "_h)
        }
    }
    If state.agents.%Size() > 1 {
        If ##class(SolarAgents.Core.LLM).IsMock() {
            Set text = text_"### 💡 Highlights"_nl
            Set hi = highlights.%GetIterator()
            While hi.%GetNext(, .h) {
                Set text = text_"- "_h_nl
            }
        } Else {
            Set system = "You are a senior solar plant performance analyst. Cross-check the evidence from the sources "_
                         "(telemetry, weather, maintenance), explain the most likely causes and recommend up to 3 actions. "_
                         "Be objective (up to 8 sentences), quote numbers and use only the evidence provided."
            Set text = text_"### 💡 Integrated analysis"_nl_..LLM(system, "Question: "_state.question_nl_nl_"Evidence:"_nl_evidence, "strong", 0.2)_nl
        }
    }
    Set state.text = text
    Set state.step = "synthesized"
    Quit $$$OK
}

/// Answers are produced in English; a question in Portuguese gets the answer translated.
Method FinalizeNode(state As %DynamicObject) As %Status
{
    If (state.%Get("language")="pt") && (state.text'="") && '##class(SolarAgents.Core.LLM).IsMock() {
        Set system = "Translate the following markdown from English to Brazilian Portuguese. Keep tables, numbers and "_
                     "markdown formatting exactly as they are. Never translate plant names (Aurora Solar Plant, "_
                     "Blue Ridge Solar Plant, Green Valley Solar Plant, Horizon Solar Plant). Return only the translation."
        Set state.text = ..LLM(system, state.text, "", 0)
    }
    Set state.step = "finalized"
    Quit $$$OK
}

}
