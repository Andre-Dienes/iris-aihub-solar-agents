/// Runs a class method in a separate IRIS process and waits for its (string) result.
///
/// Why: in this AI Hub build an LLM call made *inside* a tool call of a running %AI.Agent (e.g. the
/// Assistant calling AskSolar, which runs the Router graph and its own LLM calls) re-enters the
/// AI-Core Rust bridge and fails with <INVALID OREF> in %AI.LLM.Response / crashes the CSP process.
/// Running the tool body in another process keeps every LLM call at the top level of its process.
///
///   Set text = ##class(SolarAgents.Core.Isolate).Call("SolarAgents.Tools.SolarToolSet", "AskRouterRun", 600, question)
Class SolarAgents.Core.Isolate Extends %RegisteredObject
{

/// Calls class:method(args...) in a background job; returns its result or throws its error.
ClassMethod Call(class As %String, method As %String, timeoutSecs As %Integer = 600, args...) As %String
{
    Set key = $System.Util.CreateGUID()
    Set ^IRIS.Temp.SolarAgents(key, "class") = class
    Set ^IRIS.Temp.SolarAgents(key, "method") = method
    Set ^IRIS.Temp.SolarAgents(key, "trace") = ##class(SolarAgents.Core.Trace).CurrentTraceId()
    Set ^IRIS.Temp.SolarAgents(key, "args") = +$Get(args)
    For i=1:1:+$Get(args) {
        Set ^IRIS.Temp.SolarAgents(key, "args", i) = $Get(args(i))
    }
    Job ..Worker(key)::10
    If '$Test {
        Kill ^IRIS.Temp.SolarAgents(key)
        $$$ThrowStatus($$$ERROR($$$GeneralError, "Isolate: could not start worker job"))
    }
    Set deadline = $ZHorolog + timeoutSecs
    While '$Data(^IRIS.Temp.SolarAgents(key, "done")) {
        If $ZHorolog > deadline {
            Kill ^IRIS.Temp.SolarAgents(key)
            $$$ThrowStatus($$$ERROR($$$GeneralError, "Isolate: "_class_":"_method_" timed out after "_timeoutSecs_"s"))
        }
        Hang 0.2
    }
    Set error = $Get(^IRIS.Temp.SolarAgents(key, "error"))
    Set result = ""
    For i=1:1:+$Get(^IRIS.Temp.SolarAgents(key, "result")) {
        Set result = result_^IRIS.Temp.SolarAgents(key, "result", i)
    }
    Kill ^IRIS.Temp.SolarAgents(key)
    If error'="" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, error))
    }
    Quit result
}

/// Background entry point (runs in the caller's namespace).
ClassMethod Worker(key As %String)
{
    Try {
        Set class = ^IRIS.Temp.SolarAgents(key, "class"), method = ^IRIS.Temp.SolarAgents(key, "method")
        Do ##class(SolarAgents.Core.Trace).StartTrace($Get(^IRIS.Temp.SolarAgents(key, "trace")))
        Set n = +$Get(^IRIS.Temp.SolarAgents(key, "args"))
        For i=1:1:n {
            Set args(i) = $Get(^IRIS.Temp.SolarAgents(key, "args", i))
        }
        Set args = n
        Set result = $ClassMethod(class, method, args...)
        // store in 1 MB pieces (results can be large markdown tables)
        Set pieces = 0
        For p=1:1000000:$Length(result) {
            Set pieces = pieces + 1
            Set ^IRIS.Temp.SolarAgents(key, "result", pieces) = $Extract(result, p, p + 999999)
        }
        Set ^IRIS.Temp.SolarAgents(key, "result") = pieces
    } Catch ex {
        Set ^IRIS.Temp.SolarAgents(key, "error") = ex.DisplayString()
    }
    Set ^IRIS.Temp.SolarAgents(key, "done") = 1
}

}
