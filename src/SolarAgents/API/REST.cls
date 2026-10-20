/// REST API and demo web page — web application /api/solar (password authentication).
///
///   GET  /ui              demo page (chat, graph with the executed path, trace, work orders)
///   POST /ask             {"question", "mode": "router|assistant|Telemetry|Weather|Maintenance", "session_id"}
///   GET  /health          provider, production, knowledge base
///   GET  /plants          fictional plants
///   GET  /graph/:agent    Mermaid diagram of an agent graph (Router, Telemetry, ...)
///   GET  /trace/:id       nodes, LLM calls and embeddings of one question
///   GET  /workorders      work orders opened by the assistant
Class SolarAgents.API.REST Extends %CSP.REST
{

Parameter CONTENTTYPE = "application/json";

Parameter CHARSET = "utf-8";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
  <Route Url="/" Method="GET" Call="UI"/>
  <Route Url="/ui" Method="GET" Call="UI"/>
  <Route Url="/health" Method="GET" Call="Health"/>
  <Route Url="/plants" Method="GET" Call="Plants"/>
  <Route Url="/ask" Method="POST" Call="Ask"/>
  <Route Url="/graph/:agent" Method="GET" Call="Graph"/>
  <Route Url="/trace/:id" Method="GET" Call="Trace"/>
  <Route Url="/workorders" Method="GET" Call="WorkOrders"/>
</Routes>
}

ClassMethod Health() As %Status
{
    Write {
        "status": "ok",
        "iris": ($ZVersion),
        "llm_provider": (##class(SolarAgents.Core.Config).Provider()),
        "offline": (##class(SolarAgents.Core.LLM).IsMock()),
        "production": (##class(SolarAgents.Core.Dispatch).ProductionRunning()),
        "knowledge": (##class(SolarAgents.RAG.VectorStore).Collections())
    }.%ToJSON()
    Quit $$$OK
}

ClassMethod Plants() As %Status
{
    Write ##class(SolarAgents.Tools.SolarToolSet).ListPlants()
    Quit $$$OK
}

ClassMethod Ask() As %Status
{
    // multi-agent answers and the assistant's tool loops can take longer than the default 60 s
    Set %response.Timeout = 900
    Try {
        Set body = ##class(%DynamicObject).%FromJSON(%request.Content)
        Set question = body.%Get("question"), mode = body.%Get("mode")
        Set:mode="" mode = "router"
        Set traceId = ##class(SolarAgents.Core.Trace).StartTrace()
        If mode="assistant" {
            Set out = ##class(SolarAgents.Agent.Assistant).Ask(question, body.%Get("session_id"))
            Set out.path = ["assistant"], out.category = "ASSISTANT"
        } ElseIf mode="router" {
            Set out = ##class(%DynamicObject).%FromJSON(##class(SolarAgents.Core.Dispatch).Call("Router", question))
        } ElseIf $ListFind($ListBuild("Telemetry", "Weather", "Maintenance"), mode) {
            Set payload = ##class(%DynamicObject).%FromJSON(##class(SolarAgents.Core.Dispatch).Call(mode, question))
            Set text = $Select(payload.%Get("error")'="":"⚠️ "_payload.error, 1:payload."table_md"_$Char(10)_"> "_payload.narrative)
            Set text = text_$Char(10,10)_"```sql"_$Char(10)_payload.sql_$Char(10)_"```"
            Set out = {"text": (text), "category": (mode), "path": (payload.path), "agents": [(mode)]}
        } Else {
            Set %response.Status = ..#HTTP400BADREQUEST
            Set out = {"error": "mode must be router, assistant, Telemetry, Weather or Maintenance"}
        }
        Set out."trace_id" = traceId
        Write out.%ToJSON()
    } Catch ex {
        Set %response.Status = ..#HTTP500INTERNALSERVERERROR
        Write {"error": (ex.DisplayString())}.%ToJSON()
    }
    Quit $$$OK
}

ClassMethod Graph(agent As %String) As %Status
{
    Set %response.ContentType = "text/plain"
    Set cls = "SolarAgents.Agent."_agent
    If ('##class(%Dictionary.CompiledClass).%ExistsId(cls)) || '$ClassMethod(cls, "%Extends", "SolarAgents.Graph.GraphAgent") {
        Set %response.Status = ..#HTTP404NOTFOUND
        Quit $$$OK
    }
    Write $ClassMethod(cls, "Mermaid")
    Quit $$$OK
}

ClassMethod Trace(id As %String) As %Status
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT CreatedAt, Agent, Kind, Model, DurationMs, PromptTokens, CompletionTokens, Error FROM SolarAgents_Core.Trace WHERE TraceId = ? ORDER BY ID", id)
    While rs.%Next() {
        Do out.%Push({"at": (rs.CreatedAt), "agent": (rs.Agent), "kind": (rs.Kind), "model": (rs.Model), "ms": (rs.DurationMs), "tokens_in": (rs.PromptTokens), "tokens_out": (rs.CompletionTokens), "error": (rs.Error)})
    }
    Write out.%ToJSON()
    Quit $$$OK
}

ClassMethod WorkOrders() As %Status
{
    Write ##class(SolarAgents.Tools.SolarToolSet).ListWorkOrders()
    Quit $$$OK
}

ClassMethod UI() As %Status
{
    Set %response.ContentType = "text/html"
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($ClassName()_"||Page")
    Do xdata.Data.Rewind()
    While 'xdata.Data.AtEnd {
        Write xdata.Data.Read(32000)
    }
    Quit $$$OK
}

XData Page [ MimeType = text/html ]
{
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>IRIS AI Hub · Solar Agents</title>
<script src="https://cdn.jsdelivr.net/npm/marked@12.0.2/marked.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js"></script>
<style>
  :root { --bg:#0f172a; --panel:#111c33; --card:#16233f; --text:#e5edf9; --muted:#93a4c3; --accent:#f59e0b; --accent2:#38bdf8; --ok:#22c55e; --border:#24365c; }
  * { box-sizing: border-box; }
  body { margin:0; font-family: "Segoe UI", system-ui, -apple-system, sans-serif; background:var(--bg); color:var(--text); }
  header { display:flex; align-items:center; gap:14px; padding:14px 22px; border-bottom:1px solid var(--border); background:#0b1324; }
  header h1 { font-size:18px; margin:0; font-weight:600; }
  header .sub { color:var(--muted); font-size:13px; }
  .badge { font-size:12px; padding:3px 9px; border-radius:999px; border:1px solid var(--border); color:var(--muted); }
  .badge.on { color:#0b1324; background:var(--ok); border-color:var(--ok); }
  .badge.warn { color:#0b1324; background:var(--accent); border-color:var(--accent); }
  main { display:grid; grid-template-columns: minmax(0, 1.25fr) minmax(0, 1fr); gap:16px; padding:16px 22px; height:calc(100vh - 62px); }
  .panel { background:var(--panel); border:1px solid var(--border); border-radius:12px; display:flex; flex-direction:column; min-height:0; }
  #chat { flex:1; overflow:auto; padding:16px; }
  .msg { margin-bottom:14px; padding:12px 14px; border-radius:10px; line-height:1.5; font-size:14px; overflow-x:auto; }
  .msg.user { background:#1d3157; margin-left:15%; }
  .msg.bot { background:var(--card); border:1px solid var(--border); }
  .msg .meta { font-size:11px; color:var(--muted); margin-top:8px; }
  .msg table { border-collapse:collapse; margin:8px 0; font-size:13px; }
  .msg th, .msg td { border:1px solid var(--border); padding:4px 8px; text-align:right; }
  .msg th { background:#1b2b4d; } .msg td:first-child, .msg th:first-child { text-align:left; }
  .msg blockquote { margin:8px 0; padding:6px 12px; border-left:3px solid var(--accent); color:#cbd6ea; background:#13203b; }
  .msg pre { background:#0b1324; padding:8px; border-radius:6px; font-size:12px; white-space:pre-wrap; }
  .chips { display:flex; flex-wrap:wrap; gap:6px; padding:10px 16px; border-top:1px solid var(--border); }
  .chip { font-size:12px; padding:5px 10px; border-radius:999px; background:#1b2b4d; border:1px solid var(--border); cursor:pointer; color:var(--text); }
  .chip:hover { border-color:var(--accent); }
  form { display:flex; gap:8px; padding:12px 16px; border-top:1px solid var(--border); }
  select, input, button { font:inherit; border-radius:8px; border:1px solid var(--border); background:#0b1324; color:var(--text); padding:9px 10px; }
  input { flex:1; } button { background:var(--accent); color:#111; font-weight:600; border:none; cursor:pointer; padding:9px 16px; }
  button:disabled { opacity:.5; cursor:wait; }
  .tabs { display:flex; border-bottom:1px solid var(--border); }
  .tab { padding:10px 16px; cursor:pointer; color:var(--muted); font-size:14px; border-bottom:2px solid transparent; }
  .tab.active { color:var(--text); border-color:var(--accent); }
  .view { display:none; flex:1; overflow:auto; padding:14px; } .view.active { display:block; }
  .trace { width:100%; border-collapse:collapse; font-size:12px; }
  .trace td, .trace th { padding:5px 6px; border-bottom:1px solid var(--border); text-align:left; }
  .kind-node { color:var(--accent2); } .kind-chat { color:var(--accent); } .kind-embedding { color:#a78bfa; }
  .hint { color:var(--muted); font-size:13px; }
  .mermaid svg { max-width:100%; }
  @media (max-width: 900px) { main { grid-template-columns: 1fr; height:auto; } .panel { min-height:420px; } }
</style>
</head>
<body>
<header>
  <div>
    <h1>☀️ Solar Plant Agents <span class="sub">· InterSystems IRIS AI Hub</span></h1>
    <div class="sub">%AI.Agent · %AI.ToolSet · %AI.Agent.Skill · %AI.MCP.Service · native vectors · Interoperability — fictional data</div>
  </div>
  <span style="flex:1"></span>
  <span id="b-llm" class="badge">LLM</span>
  <span id="b-prod" class="badge">Production</span>
</header>
<main>
  <section class="panel">
    <div id="chat"><div class="msg bot">Hi! Ask about the fictional solar plants <b>Aurora</b>, <b>Blue Ridge</b>, <b>Green Valley</b> and <b>Horizon</b> (data from June to September 2026). Pick a mode: the <b>multi-agent router</b> (deterministic graph), the <b>autonomous assistant</b> (the LLM picks the tools) or a single <b>data agent</b>.</div></div>
    <div class="chips" id="chips"></div>
    <form id="f">
      <select id="mode">
        <option value="router">Multi-agent router</option>
        <option value="assistant">Autonomous assistant</option>
        <option value="Telemetry">Agent: Telemetry</option>
        <option value="Weather">Agent: Weather</option>
        <option value="Maintenance">Agent: Maintenance</option>
      </select>
      <input id="q" placeholder="e.g. Why did the PR of Blue Ridge drop in August 2026?" autocomplete="off">
      <button id="send">Send</button>
    </form>
  </section>
  <section class="panel">
    <div class="tabs">
      <div class="tab active" data-v="graph">Graph</div>
      <div class="tab" data-v="trace">Trace</div>
      <div class="tab" data-v="orders">Work orders</div>
    </div>
    <div class="view active" id="v-graph"><div class="hint">Path executed by the router for the last question (nodes in orange).</div><div id="graph" class="mermaid"></div></div>
    <div class="view" id="v-trace"><div class="hint">Every graph node, LLM call (%AI.Provider) and embedding of the last question.</div><table class="trace" id="trace"></table></div>
    <div class="view" id="v-orders"><div class="hint">Work orders opened by the assistant through the production (Gateway → WorkOrders).</div><table class="trace" id="orders"></table></div>
  </section>
</main>
<script>
const chips = [
  ["router", "What was the energy and the PR of each plant in August 2026?"],
  ["router", "Why did the PR of Blue Ridge drop in August 2026?"],
  ["router", "How did the PR of Green Valley evolve day by day in September 2026?"],
  ["router", "What is Performance Ratio?"],
  ["router", "Which plant had the best performance ratio in July 2026?"],
  ["assistant", "Diagnose Blue Ridge in August 2026 and tell me whether it needs maintenance."],
  ["Maintenance", "Which alarms are still open?"]
];
const $ = id => document.getElementById(id);
mermaid.initialize({ startOnLoad:false, theme:"dark", flowchart:{ curve:"basis" } });
let sessionId = "", graphText = "";
chips.forEach(([m, q]) => { const c = document.createElement("span"); c.className = "chip"; c.textContent = q; c.title = m;
  c.onclick = () => { $("mode").value = m; $("q").value = q; $("f").requestSubmit(); }; $("chips").appendChild(c); });
document.querySelectorAll(".tab").forEach(t => t.onclick = () => {
  document.querySelectorAll(".tab").forEach(x => x.classList.remove("active")); t.classList.add("active");
  document.querySelectorAll(".view").forEach(v => v.classList.remove("active")); $("v-" + t.dataset.v).classList.add("active");
  if (t.dataset.v === "orders") loadOrders(); });
const api = (p, o) => fetch(p, Object.assign({ credentials:"same-origin", headers:{ "Content-Type":"application/json" } }, o)).then(r => r.json());
function add(cls, html) { const d = document.createElement("div"); d.className = "msg " + cls; d.innerHTML = html; $("chat").appendChild(d); $("chat").scrollTop = 1e9; return d; }
function esc(s) { return String(s ?? "").replace(/[&<>]/g, c => ({ "&":"&amp;", "<":"&lt;", ">":"&gt;" }[c])); }
async function drawGraph(path) {
  if (!graphText) graphText = await fetch("graph/Router", { credentials:"same-origin" }).then(r => r.text());
  let g = graphText + "\n  classDef done fill:#f59e0b,stroke:#f59e0b,color:#111;\n";
  const done = (path || []).filter(n => /^[a-z_]+$/.test(n));
  if (done.length) g += "  class " + [...new Set(done)].join(",") + " done;\n";
  $("graph").removeAttribute("data-processed"); $("graph").innerHTML = g; await mermaid.run({ nodes:[$("graph")] });
 }
async function loadTrace(id) {
  const rows = await api("trace/" + id);
  $("trace").innerHTML = "<tr><th>agent / node</th><th>kind</th><th>model</th><th>ms</th><th>tokens</th></tr>" + rows.map(r =>
    `<tr><td>${esc(r.agent)}</td><td class="kind-${r.kind}">${r.kind}</td><td>${esc(r.model)}</td><td>${r.ms ?? ""}</td><td>${r.tokens_in ? r.tokens_in + "/" + r.tokens_out : ""}</td></tr>` +
    (r.error ? `<tr><td colspan="5" style="color:#f87171">${esc(r.error)}</td></tr>` : "")).join("");
 }
async function loadOrders() {
  const rows = await api("workorders");
  $("orders").innerHTML = "<tr><th>order</th><th>plant</th><th>equip.</th><th>priority</th><th>description</th></tr>" +
    (rows.length ? rows.map(r => `<tr><td>${r.id}</td><td>${r.plant}</td><td>${esc(r.equipment)}</td><td>${r.priority}</td><td>${esc(r.description)}</td></tr>`).join("") : "<tr><td colspan='5'>No work orders yet.</td></tr>");
 }
$("f").onsubmit = async e => {
  e.preventDefault(); const q = $("q").value.trim(); if (!q) return;
  const mode = $("mode").value; add("user", esc(q)); $("q").value = ""; $("send").disabled = true;
  const wait = add("bot", "<span class='hint'>⏳ running " + esc($("mode").selectedOptions[0].text) + "…</span>");
  const t0 = performance.now();
  try {
    const r = await api("ask", { method:"POST", body:JSON.stringify({ question:q, mode, session_id: mode === "assistant" ? sessionId : "" }) });
    if (r.session_id) sessionId = r.session_id;
    const secs = ((performance.now() - t0) / 1000).toFixed(1);
    wait.innerHTML = r.error && !r.text ? "⚠️ " + esc(r.error) : marked.parse(r.text || "");
    wait.innerHTML += `<div class="meta">${esc(r.category || "")} · agents: ${esc((r.agents || []).join(", "))} · ${secs}s · trace ${esc((r.trace_id || "").slice(0, 8))}${r.session_id ? " · session " + r.session_id : ""}</div>`;
    if (mode === "router") drawGraph(r.path);
    if (r.trace_id) loadTrace(r.trace_id);
  } catch (err) { wait.innerHTML = "⚠️ " + esc(err); }
  $("send").disabled = false;
 };
api("health").then(h => {
  $("b-llm").textContent = h.offline ? "offline mode (no LLM)" : "LLM: OpenAI"; $("b-llm").className = "badge " + (h.offline ? "warn" : "on");
  $("b-prod").textContent = h.production ? "production running" : "production stopped"; $("b-prod").className = "badge " + (h.production ? "on" : "");
 });
drawGraph([]);
</script>
</body>
</html>
}

}
