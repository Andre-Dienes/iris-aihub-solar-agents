/// Base of the text-to-SQL data agents (Telemetry, Weather, Maintenance).
/// <pre>
///   retrieve ──► sql ──┬─► execute ──┬─► analyze ──► END
///                      │      ▲      └─► fix_sql (SQL error: the LLM corrects it once) ─┐
///                      │      └─────────────────────────────────────────────────────────┘
///                      └─► END   (SQL rejected by the guardrails: the reason goes back to the user)
/// </pre>
///   retrieve : RAG over the "schema" and "examples" collections (IRIS native vectors)
///   sql      : %AI.Provider writes the SELECT (offline mode: closest example with the filters filled in)
///   execute  : guarded execution (single SELECT, only the agent's tables)
///   fix_sql  : self-correction — the database error goes back to the LLM, which rewrites the query
///   analyze  : statistics + table in Embedded Python, narrative by the LLM (offline: highlights)
///
/// Usage:
///   Set result = ##class(SolarAgents.Agent.Telemetry).%New().Answer("What was the PR of Aurora in August 2026?")
Class SolarAgents.Agent.DataAgent Extends SolarAgents.Graph.GraphAgent [ Abstract ]
{

Parameter MODEL = "gpt-4o-mini";

/// SolarAgents.Data classes this agent may query (comma-separated).
Parameter TABLES;

/// One-line description of the data source (used in prompts and tool descriptions).
Parameter TOPIC;

XData Graph [ MimeType = application/json ]
{
{
  "start": "retrieve",
  "on_error": "END",
  "nodes": {
    "retrieve": "RetrieveNode",
    "sql":      "SqlNode",
    "execute":  "ExecuteNode",
    "fix_sql":  "FixSqlNode",
    "analyze":  "AnalyzeNode"
  },
  "edges": {
    "retrieve": "sql",
    "sql":      { "router": "RouteAfterSql", "map": { "ok": "execute", "reject": "END" } },
    "execute":  { "router": "RouteAfterExecute", "map": { "ok": "analyze", "retry": "fix_sql", "fail": "END" } },
    "fix_sql":  { "router": "RouteAfterSql", "map": { "ok": "execute", "reject": "END" } },
    "analyze":  "END"
  }
}
}

/// Answers one question. context (optional, from the router): {"plants": {...}, "period": {...}, "language": "en"}
Method Answer(question As %String, context As %DynamicObject = "") As %DynamicObject
{
    Set:'$IsObject(context) context = {}
    Set state = {"question": (question), "context": (context), "sql": "", "error": ""}
    Set state = ..RunGraph(state)
    Set payload = {
        "agent": (..AgentName()),
        "topic": (..#TOPIC),
        "question": (question),
        "sql": (state.%Get("sql")),
        "row_count": (+state.%Get("row_count")),
        "table_md": (state.%Get("table_md")),
        "highlights": ($Select($IsObject(state.%Get("highlights")):state.highlights, 1:[])),
        "stats": ($Select($IsObject(state.%Get("stats")):state.stats, 1:{})),
        "narrative": (state.%Get("narrative")),
        "error": (state.%Get("error")),
        "path": (state.%Get("_path"))
    }
    Quit payload
}

/// Interop payload: content is either a plain question or {"question", "context"} JSON from the router.
Method Respond(question As %String, sessionId As %String = "") As %String
{
    Set context = {}
    If $Extract($ZStrip(question, "<W"))="{" {
        Try {
            Set input = ##class(%DynamicObject).%FromJSON(question)
            Set question = input.question
            Set:$IsObject(input.%Get("context")) context = input.context
        } Catch {
        }
    }
    Quit ..Answer(question, context).%ToJSON()
}

// ---------------------------------------------------------------- nodes

Method RetrieveNode(state As %DynamicObject) As %Status
{
    Set ctx = state.context, question = state.question
    Set:'$IsObject(ctx.%Get("plants")) ctx.plants = ##class(SolarAgents.Core.QueryParser).Plants(question)
    Set:'$IsObject(ctx.%Get("period")) ctx.period = ##class(SolarAgents.Core.QueryParser).Period(question)
    // every plant when the question names none (e.g. "which plant had the worst PR?")
    If ctx.plants.codes.%Size()=0 {
        Set ctx.plants = ##class(SolarAgents.Core.QueryParser).Plants("all")
    }
    Set schema = [], examples = []
    Set hits = ##class(SolarAgents.RAG.VectorStore).SearchObj("schema", question, 6)
    Set iter = hits.%GetIterator()
    While iter.%GetNext(, .hit) {
        Do:(","_hit.metadata.agents_",")[(","_..AgentName()_",") schema.%Push(hit.content)
    }
    Set hits = ##class(SolarAgents.RAG.VectorStore).SearchObj("examples", question, 8)
    Set iter = hits.%GetIterator()
    While iter.%GetNext(, .hit) {
        Continue:hit.metadata.agent'=..AgentName()
        Do examples.%Push({"question": (hit.content), "sql": (hit.metadata.sql), "score": (hit.score)})
    }
    Set state.schema = schema, state.examples = examples
    Set state.step = "retrieved"
    Quit $$$OK
}

Method SqlNode(state As %DynamicObject) As %Status
{
    Set ctx = state.context, codes = ##class(SolarAgents.Core.QueryParser).CodesSQL(ctx.plants.codes)
    If ##class(SolarAgents.Core.LLM).IsMock() {
        // offline mode: the closest example, with the plants and the period of this question;
        // questions about trends or causes prefer a day-by-day example
        Set best = state.examples.%Get(0)
        If '$IsObject(best) {
            Set state.error = "No example query for this agent."
            Quit $$$OK
        }
        Set q = " "_##class(SolarAgents.Core.QueryParser).Normalize(state.question)_" "
        If (q["evolv")||(q["day by day")||(q["daily")||(q[" why ")||(q[" drop")||(q["trend") {
            Set iter = state.examples.%GetIterator()
            While iter.%GetNext(, .ex) {
                If ex.sql["AS Day" {
                    Set best = ex
                    Quit
                }
            }
        }
        Set state.sql = ..Fill(best.sql, codes, ctx.period)
    } Else {
        Set nl = $Char(10)
        Set prompt = "You write SQL for InterSystems IRIS over solar plant data ("_..#TOPIC_")."_nl_nl
        Set iter = state.schema.%GetIterator()
        While iter.%GetNext(, .chunk) {
            Set prompt = prompt_"- "_chunk_nl
        }
        Set prompt = prompt_nl_"Requested plants: "_codes_" ("_..JoinArray(ctx.plants.names)_")"_nl
        Set prompt = prompt_##class(SolarAgents.Core.QueryParser).DateContext(ctx.period)_nl_"Examples:"_nl
        Set iter = state.examples.%GetIterator()
        While iter.%GetNext(, .ex) {
            Set prompt = prompt_"Question: "_ex.question_nl_"SQL: "_..Fill(ex.sql, codes, ctx.period)_nl_nl
        }
        Set prompt = prompt_"Answer ONLY with the SQL query, no explanations and no markdown."
        Set state.sql = ..CleanSQL(..LLM(prompt, "Question: "_state.question, "", 0))
    }
    Set reason = ##class(SolarAgents.Core.SQL).Validate(state.sql, ..#TABLES)
    Set:reason'="" state.error = reason
    Set state.step = "sql_ready"
    Quit $$$OK
}

Method RouteAfterSql(state As %DynamicObject) As %String
{
    Quit $Select(state.error'="":"reject", 1:"ok")
}

Method ExecuteNode(state As %DynamicObject) As %Status
{
    Set state."sql_error" = ""
    Try {
        Set result = ##class(SolarAgents.Core.SQL).Run(state.sql)
        Set state.rows = result.rows, state.columns = result.columns
    } Catch ex {
        Set state."sql_error" = ex.DisplayString()
    }
    Set state.step = "executed"
    Quit $$$OK
}

/// ok = rows fetched; retry = one self-correction attempt; fail = give up with the database error.
Method RouteAfterExecute(state As %DynamicObject) As %String
{
    Quit:state."sql_error"="" "ok"
    If (+state.%Get("attempts") < 1) && '##class(SolarAgents.Core.LLM).IsMock() {
        Quit "retry"
    }
    Set state.error = "SQL execution error: "_state."sql_error"
    Quit "fail"
}

/// Sends the failing query and the IRIS error back to the LLM.
Method FixSqlNode(state As %DynamicObject) As %Status
{
    Set state.attempts = state.%Get("attempts") + 1
    Set nl = $Char(10)
    Set system = "You fix InterSystems IRIS SQL queries. Return ONLY the corrected query, no explanations. "_
                 "Remember: TOP n goes right after SELECT; there is no LIMIT; dates are 'YYYY-MM-DD' literals."
    Set state.sql = ..CleanSQL(..LLM(system, "Query:"_nl_state.sql_nl_nl_"IRIS error:"_nl_state."sql_error", "", 0))
    Set reason = ##class(SolarAgents.Core.SQL).Validate(state.sql, ..#TABLES)
    Set:reason'="" state.error = reason
    Set state.step = "sql_fixed"
    Quit $$$OK
}

Method AnalyzeNode(state As %DynamicObject) As %Status
{
    Set analysis = ##class(%DynamicObject).%FromJSON(##class(SolarAgents.Analysis.Analyzer).Describe(state.rows.%ToJSON()))
    Set state."row_count" = analysis."row_count", state.stats = analysis.stats
    Set state.highlights = analysis.highlights, state."table_md" = analysis."table_md"
    If ##class(SolarAgents.Core.LLM).IsMock() || (analysis."row_count"=0) {
        Set state.narrative = ..JoinArray(analysis.highlights, ". ")
    } Else {
        Set nl = $Char(10)
        Set system = "You are a solar plant performance engineer. Write 2 to 4 objective sentences in English "_
                     "about the data, quoting numbers. Never invent values that are not in the data."
        Set user = "Question: "_state.question_nl_"Source: "_..#TOPIC_nl_"Highlights: "_analysis.highlights.%ToJSON()_nl_
                   "Statistics: "_analysis.stats.%ToJSON()_nl_"First rows: "_$Extract(state.rows.%ToJSON(), 1, 6000)
        Set state.narrative = ..LLM(system, user, "strong", 0.2)
    }
    Set state.step = "analyzed"
    Quit $$$OK
}

// ---------------------------------------------------------------- helpers

/// Removes markdown fences and line breaks from an LLM answer.
ClassMethod CleanSQL(sql As %String) As %String
{
    Set sql = $Replace($Replace($Replace(sql, "```sql", ""), "```", ""), $Char(13), "")
    Quit $ZStrip($Translate(sql, $Char(10, 9), "  "), "<>=W")
}

/// Fills {PLANTS}, {START} and {END} of an example query.
ClassMethod Fill(sql As %String, codes As %String, period As %DynamicObject) As %String
{
    Quit $Replace($Replace($Replace(sql, "{PLANTS}", codes), "{START}", period.start), "{END}", period.end)
}

ClassMethod JoinArray(arr As %DynamicArray, sep As %String = ", ") As %String
{
    Set out = "", iter = arr.%GetIterator()
    While iter.%GetNext(, .v) {
        Set out = out_$Select(out="":"", 1:sep)_v
    }
    Quit out
}

}
