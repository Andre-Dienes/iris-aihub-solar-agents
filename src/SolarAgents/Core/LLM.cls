/// LLM gateway of the demo, built on the IRIS AI Hub (%AI.Provider).
/// 
///   Complete(system, user, model, temperature, agent)  -> %AI.Provider.ChatComplete (traced)
///   Embed(text) / EmbedBatch(texts)                    -> OpenAI-compatible /v1/embeddings
/// 
/// From embedded Python:
///   iris.cls("SolarAgents.Core.LLM").Complete(system_prompt, user_msg, "strong", 0.2, "Analyzer")
/// 
/// Provider "mock" (offline mode) answers ^SolarAgents.Mock(agent) when set, otherwise an echo;
/// the agents detect offline mode and use deterministic fallbacks instead of LLM text.
Class SolarAgents.Core.LLM Extends %RegisteredObject
{

/// Cached %AI.Provider for this process.
ClassMethod GetProvider() As %AI.Provider
{
    Set name = ##class(SolarAgents.Core.Config).Provider()
    If $IsObject($Get(%SolarProvider)), $Get(%SolarProviderName)=name {
        Quit %SolarProvider
    }
    Set settings = ##class(SolarAgents.Core.Config).ProviderSettings()
    If (name="openai") && (settings.%Get("api_key")="") {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "OpenAI API key not configured. Set OPENAI_API_KEY or ^SolarAgents.Config(""OPENAI_API_KEY"")"))
    }
    Set %SolarProvider = ##class(%AI.Provider).Create(name, settings)
    Set %SolarProviderName = name
    Quit %SolarProvider
}

ClassMethod IsMock() As %Boolean
{
    Quit ##class(SolarAgents.Core.Config).Provider()="mock"
}

/// Single-shot completion: system prompt + user message -> text.
/// model "" = Config.Model(); model "strong" = Config.StrongModel().
ClassMethod Complete(systemPrompt As %String, userMessage As %String, model As %String = "", temperature As %Float = 0, agent As %String = "Demo") As %String
{
    Set messages = []
    Do:systemPrompt'="" messages.%Push({"role":"system","content":(systemPrompt)})
    Do messages.%Push({"role":"user","content":(userMessage)})
    Quit ..Chat(messages, model, temperature, agent)
}

/// Multi-message completion. messages = [{"role":"system|user|assistant","content":"..."}]
ClassMethod Chat(messages As %DynamicArray, model As %String = "", temperature As %Float = 0, agent As %String = "Demo") As %String
{
    Set model = ..ResolveModel(model)
    Set providerName = ##class(SolarAgents.Core.Config).Provider()
    Set start = $ZHorolog, content = "", usage = "", error = ""
    Try {
        If ..IsMock() {
            Set content = ..MockAnswer(agent, messages)
        } Else {
            Set response = ..GetProvider().ChatComplete(model, messages, temperature)
            Set content = response.Content
            Set usage = response.Usage
        }
    } Catch ex {
        Set error = ex.DisplayString()
    }
    Set elapsed = ($ZHorolog - start) * 1000 \ 1
    Do ##class(SolarAgents.Core.Trace).Log(agent, "chat", providerName, model, elapsed, messages.%ToJSON(), content, usage, error)
    If error'="" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, agent_": LLM call failed: "_error))
    }
    Quit content
}

/// Same as Complete() but never throws: returns fallback on any error.
ClassMethod CompleteSafe(systemPrompt As %String, userMessage As %String, model As %String = "", temperature As %Float = 0, agent As %String = "Demo", fallback As %String = "") As %String
{
    Try {
        Set out = ..Complete(systemPrompt, userMessage, model, temperature, agent)
    } Catch {
        Set out = fallback
    }
    Quit out
}

/// Extracts the first JSON object from a model answer (strips ```json fences).
ClassMethod ParseJSON(text As %String) As %DynamicObject
{
    Set clean = $Replace($Replace(text, "```json", ""), "```", "")
    Set start = $Find(clean, "{") - 1
    Set end = $Length(clean) - $Find($Reverse(clean), "}") + 2
    Quit:(start<1)||(end<=start) {}
    Try {
        Set obj = ##class(%DynamicObject).%FromJSON($Extract(clean, start, end))
    } Catch {
        Set obj = {}
    }
    Quit obj
}

ClassMethod ResolveModel(model As %String) As %String
{
    Quit:model="" ##class(SolarAgents.Core.Config).Model()
    Quit:$ZConvert(model,"L")="strong" ##class(SolarAgents.Core.Config).StrongModel()
    Quit model
}

ClassMethod MockAnswer(agent As %String, messages As %DynamicArray) As %String
{
    Set answer = $Get(^SolarAgents.Mock(agent))
    Set:answer="" answer = $Get(^SolarAgents.Mock($Piece(agent, ".", 2)))
    Set:answer="" answer = $Get(^SolarAgents.Mock("default"))
    Quit:answer'="" answer
    Set last = messages.%Get(messages.%Size() - 1)
    Quit "[mock "_agent_"] "_$Extract(last.content, 1, 300)
}

/// Embedding vector for text, as a comma-separated string ready for TO_VECTOR(?, DOUBLE).
ClassMethod Embed(text As %String, agent As %String = "Demo.Embed") As %String
{
    Set batch = ..EmbedBatch([(text)], agent)
    Quit batch.%Get(0)
}

/// Embeds several texts in one call. Returns a %DynamicArray of comma-separated vectors.
/// The %AI.RAG embedding classes only run inside the KnowledgeBase Rust bridge, so this
/// calls the OpenAI-compatible /v1/embeddings endpoint directly (same as iris-ai-examples).
ClassMethod EmbedBatch(texts As %DynamicArray, agent As %String = "Demo.Embed") As %DynamicArray
{
    Set model = ##class(SolarAgents.Core.Config).EmbeddingModel()
    Set start = $ZHorolog, out = [], error = ""
    Try {
        If ..IsMock() {
            Set iter = texts.%GetIterator()
            While iter.%GetNext(, .txt) {
                Do out.%Push(..HashEmbedding(txt))
            }
            Quit
        }
        Set apiKey = ##class(SolarAgents.Core.Config).ApiKey()
        If apiKey="" {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "OpenAI API key not configured"))
        }
        Set inputs = []
        Set iter = texts.%GetIterator()
        While iter.%GetNext(, .txt) {
            Do inputs.%Push($Extract(txt, 1, 24000))
        }
        Set req = ##class(%Net.HttpRequest).%New()
        Set baseUrl = ##class(SolarAgents.Core.Config).Get("SOLAR_EMBEDDING_URL", "https://api.openai.com/v1/embeddings")
        Do ##class(%Net.URLParser).Decompose(baseUrl, .url)
        Set req.Server = url("host")
        Set req.Https = (url("scheme")="https")
        Set req.Port = $Select($Get(url("port"))'="":url("port"), req.Https:443, 1:80)
        Set:req.Https req.SSLConfiguration = ..SSLConfig()
        Set req.Timeout = 60
        Do req.SetHeader("Authorization", "Bearer "_apiKey)
        Set req.ContentType = "application/json; charset=utf-8"
        // chunk texts carry accents, emojis and symbols: the body must go out as UTF-8 bytes
        Do req.EntityBody.Write($ZConvert({"model":(model),"input":(inputs)}.%ToJSON(), "O", "UTF8"))
        $$$ThrowOnError(req.Post(url("path")))
        Set resp = ##class(%DynamicObject).%FromJSON(req.HttpResponse.Data)
        If req.HttpResponse.StatusCode'=200 {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "Embeddings HTTP "_req.HttpResponse.StatusCode_": "_resp.%ToJSON()))
        }
        Set iter = resp.data.%GetIterator()
        While iter.%GetNext(, .item) {
            Do out.%Push(..VectorToString(item.embedding))
        }
    } Catch ex {
        Set error = ex.DisplayString()
    }
    Set elapsed = ($ZHorolog - start) * 1000 \ 1
    Do ##class(SolarAgents.Core.Trace).Log(agent, "embedding", ##class(SolarAgents.Core.Config).Provider(), model, elapsed, "["_texts.%Size()_" texts]", "["_out.%Size()_" vectors]", "", error)
    If error'="" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "Embedding failed: "_error))
    }
    Quit out
}

ClassMethod VectorToString(vec As %DynamicArray) As %String
{
    Set parts = "", iter = vec.%GetIterator()
    While iter.%GetNext(, .v) {
        Set parts = parts_$Select(parts="":"", 1:",")_v
    }
    Quit parts
}

/// Offline deterministic embedding (hashed bag of words, L2-normalised).
/// Lets RAG work in mock mode with lexical similarity.
ClassMethod HashEmbedding(text As %String) As %String
{
    Set dims = ##class(SolarAgents.Core.Config).#EMBEDDINGDIMENSIONS
    Set clean = $ZConvert($Translate(text, ".,;:!?()[]{}""'`*#|\/-_=+<>", "                                "), "L")
    Set clean = $ZStrip(clean, "=W")
    For i=1:1:$Length(clean, " ") {
        Set word = $Piece(clean, " ", i)
        Continue:$Length(word)<2
        Set idx = $ZCRC(word, 7) # dims + 1
        Set bucket(idx) = $Get(bucket(idx)) + 1
    }
    Set norm = 0, idx = ""
    For {
        Set idx = $Order(bucket(idx), 1, cnt)
        Quit:idx=""
        Set norm = norm + (cnt * cnt)
    }
    Set norm = $Select(norm>0:$ZSqr(norm), 1:1)
    Set out = ""
    For i=1:1:dims {
        Set out = out_$Select(i=1:"", 1:",")_($Get(bucket(i), 0) / norm)
    }
    Quit out
}

ClassMethod SSLConfig() As %String
{
    Set name = "SOLAR_TLS"
    New $Namespace
    Set $Namespace = "%SYS"
    If '##class(Security.SSLConfigs).Exists(name) {
        Do ##class(Security.SSLConfigs).Create(name)
    }
    Quit name
}

}
