/// Base class of the demo agents: an IRIS AI Hub %AI.Agent that runs a declarative
/// state graph (nodes, conditional edges, END) defined in XData.
///
/// Subclasses declare the graph in XData Graph (JSON):
/// <example language="json">
/// {
///   "start": "triage",
///   "nodes": { "triage": "TriageNode", "knowledge": "KnowledgeNode", "finalize": "FinalizeNode" },
///   "edges": {
///     "triage":    { "router": "RouteByCategoria", "map": { "knowledge": "knowledge", "offtopic": "finalize" } },
///     "knowledge": "finalize",
///     "finalize":  "END"
///   }
/// }
/// </example>
///
/// - Every node is an instance method  Method XxxNode(state As %DynamicObject) As %Status
///   that reads and writes the shared state (%DynamicObject).
/// - A conditional edge names a router method  Method Xxx(state As %DynamicObject) As %String
///   whose return value is looked up in "map" (= add_conditional_edges).
/// - "END" finishes the run.
///
/// Each node execution is recorded in SolarAgents.Core.Trace (Kind="node"), and every LLM call
/// made through ..LLM() is recorded with the agent and node name.
Class SolarAgents.Graph.GraphAgent Extends %AI.Agent [ Abstract ]
{

Parameter PROVIDER = "openai";

/// Logical agent name used in traces and responses.
Parameter AGENTNAME;

/// Safety limit against cycles in the graph.
Parameter MAXSTEPS = 50;

/// Name of the node currently executing (for tracing).
Property CurrentNode As %String;

/// The graph only needs ..LLM(), which goes through SolarAgents.Core.LLM (one provider per process),
/// so no provider is attached here. Attaching that shared provider to every graph agent made the
/// %AI.Agent machinery hold extra references to it, and a graph run inside a tool call of another
/// %AI.Agent then re-entered the same provider (INVALID OREF in the Rust bridge). To use the
/// standard Chat() on a graph agent, pass a provider: ##class(...).%New(provider).
Method %OnNew(provider As %AI.Provider = "") As %Status
{
    Set sc = $$$OK
    Try {
        Set sc = ##super(provider)
        Set:..Model="" ..Model = ##class(SolarAgents.Core.LLM).ResolveModel(..#MODEL)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

ClassMethod AgentName() As %String
{
    Quit $Select(..#AGENTNAME'="":..#AGENTNAME, 1:$Piece($ClassName(), ".", *))
}

/// Interoperability entry point (SolarAgents.Interop.AgentProcess): question -> JSON payload
/// placed in SolarAgents.Interop.AgentResponse.Payload. Implemented by each agent family.
Method Respond(question As %String, sessionId As %String = "") As %String [ Abstract ]
{
}

/// Runs the graph from the start node with the given initial state. Returns the final state.
Method RunGraph(state As %DynamicObject) As %DynamicObject
{
    Set graph = ..GetGraph()
    Set node = graph.start, steps = 0
    Set:state.%Get("_path")="" state."_path" = []
    Set:##class(SolarAgents.Core.Trace).CurrentTraceId()="" state."trace_id" = ##class(SolarAgents.Core.Trace).StartTrace()
    While (node'="") && (node'="END") {
        Set steps = steps + 1
        If steps > ..#MAXSTEPS {
            Set state.error = "Graph exceeded "_..#MAXSTEPS_" steps (cycle?) at node "_node
            Quit
        }
        Set method = graph.nodes.%Get(node)
        If method="" {
            Set state.error = "Unknown graph node: "_node
            Quit
        }
        Set ..CurrentNode = node
        Set start = $ZHorolog, error = ""
        Try {
            Set sc = $Method($This, method, state)
            Set:$$$ISERR(sc) error = $System.Status.GetErrorText(sc)
        } Catch ex {
            Set error = ex.DisplayString()
        }
        Set ms = ($ZHorolog - start) * 1000 \ 1
        Do state."_path".%Push(node)
        Do ##class(SolarAgents.Core.Trace).Log(..AgentName()_"."_node, "node", "", "", ms, "", state.%Get("step"), "", error)
        If error'="" {
            Set state.error = error
            Set state.step = node_"_error"
            // optional "on_error" target in XData Graph (e.g. "END"); default: follow the normal edge
            If graph.%Get("on_error")'="" {
                Set node = graph."on_error"
                Continue
            }
        }
        Set node = ..NextNode(graph, node, state)
    }
    Quit state
}

Method NextNode(graph As %DynamicObject, node As %String, state As %DynamicObject) As %String
{
    Set edge = graph.edges.%Get(node)
    Quit:edge="" "END"
    Quit:'$IsObject(edge) edge
    Set route = $Method($This, edge.router, state)
    Set target = edge.map.%Get(route)
    Quit $Select(target'="":target, edge.%Get("default")'="":edge.default, 1:"END")
}

/// Reads XData Graph from the concrete class (cached per process).
Method GetGraph() As %DynamicObject
{
    Set cls = $ClassName()
    Quit:$IsObject($Get(%SolarGraph(cls))) %SolarGraph(cls)
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId(cls_"||Graph")
    If '$IsObject(xdata) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, cls_" has no XData Graph"))
    }
    Set %SolarGraph(cls) = ##class(%DynamicObject).%FromJSON(xdata.Data)
    Quit %SolarGraph(cls)
}

/// LLM call attributed to "<Agent>.<node>" in the trace. model: "" (fast) | "strong" | explicit id.
Method LLM(systemPrompt As %String, userMessage As %String, model As %String = "", temperature As %Float = 0) As %String
{
    Quit ##class(SolarAgents.Core.LLM).Complete(systemPrompt, userMessage, model, temperature, ..AgentName()_"."_..CurrentNode)
}

/// Mermaid flowchart of the graph (for docs / debugging).
ClassMethod Mermaid() As %String
{
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($ClassName()_"||Graph")
    Quit:'$IsObject(xdata) ""
    Set graph = ##class(%DynamicObject).%FromJSON(xdata.Data)
    Set nl = $Char(10), out = "flowchart TD"_nl_"  START((START)) --> "_graph.start_nl
    Set iter = graph.edges.%GetIterator()
    While iter.%GetNext(.from, .edge) {
        If '$IsObject(edge) {
            Set out = out_"  "_from_" --> "_$Select(edge="END":"END((END))", 1:edge)_nl
            Continue
        }
        Set mi = edge.map.%GetIterator()
        While mi.%GetNext(.label, .to) {
            Set out = out_"  "_from_" -- "_label_" --> "_$Select(to="END":"END((END))", 1:to)_nl
        }
    }
    Quit out
}

}
