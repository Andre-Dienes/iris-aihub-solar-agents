/// Central configuration of the demo.
///
/// Resolution order for every setting:
///   1. ^SolarAgents.Config(key)   (##class(SolarAgents.Core.Config).Set(key, value))
///   2. OS environment variable     (SOLAR_* / OPENAI_API_KEY, from docker/.env)
///   3. Built-in default
///
/// Without an OpenAI key the demo runs in **offline mode** (provider "mock"): every graph,
/// tool and screen still works, with retrieval-based SQL and template narratives instead of
/// LLM text. Set OPENAI_API_KEY to switch to the real %AI.Provider.
Class SolarAgents.Core.Config Extends %RegisteredObject
{

Parameter DEFAULTMODEL = "gpt-4o-mini";

Parameter DEFAULTSTRONGMODEL = "gpt-4o";

Parameter DEFAULTEMBEDDINGMODEL = "text-embedding-3-small";

Parameter EMBEDDINGDIMENSIONS = 1536;

ClassMethod Get(key As %String, default As %String = "") As %String
{
    Set value = $Get(^SolarAgents.Config(key))
    Quit:value'="" value
    Set env = $System.Util.GetEnviron(key)
    Quit:env'="" env
    Quit default
}

ClassMethod Set(key As %String, value As %String) As %Status
{
    Set ^SolarAgents.Config(key) = value
    Quit $$$OK
}

/// "openai" when a key is configured, otherwise "mock" (offline demo). Override with SOLAR_LLM_PROVIDER.
ClassMethod Provider() As %String
{
    Quit ..Get("SOLAR_LLM_PROVIDER", $Select(..ApiKey()'="":"openai", 1:"mock"))
}

/// Fast chat model (classification, SQL generation, translation).
ClassMethod Model() As %String
{
    Quit ..Get("SOLAR_LLM_MODEL", ..#DEFAULTMODEL)
}

/// Strong chat model (analysis narratives, the autonomous assistant).
ClassMethod StrongModel() As %String
{
    Quit ..Get("SOLAR_LLM_MODEL_STRONG", ..#DEFAULTSTRONGMODEL)
}

ClassMethod EmbeddingModel() As %String
{
    Quit ..Get("SOLAR_EMBEDDING_MODEL", ..#DEFAULTEMBEDDINGMODEL)
}

ClassMethod ApiKey() As %String
{
    Quit ..Get("OPENAI_API_KEY")
}

/// Provider settings for %AI.Provider.Create().
ClassMethod ProviderSettings() As %DynamicObject
{
    Set settings = {}
    Do settings.%Set("api_key", ..ApiKey())
    Set baseUrl = ..Get("SOLAR_LLM_BASE_URL")
    Do:baseUrl'="" settings.%Set("base_url", baseUrl)
    Quit settings
}

}
