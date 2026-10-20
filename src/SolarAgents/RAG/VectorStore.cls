/// Vector store API over SolarAgents.RAG.Chunk (IRIS native VECTOR + VECTOR_COSINE).
/// 
///   AddDocuments(collection, docsJSON)   docs = [{"content": "...", "metadata": {...}}]
///   Search(collection, query, k)         -> JSON [{"content","metadata","score"}]
///   DeleteCollection / Count / Exists / Collections
/// 
/// Scores are cosine DISTANCE (1 - cosine similarity): lower = more similar.
Class SolarAgents.RAG.VectorStore Extends %RegisteredObject
{

Parameter BATCHSIZE = 64;

/// docsJSON: JSON array of {"content": "...", "metadata": {...}} (a %DynamicArray is also accepted).
/// Returns the number of chunks stored.
ClassMethod AddDocuments(collection As %String, docsJSON) As %Integer
{
    Set docs = $Select($IsObject(docsJSON):docsJSON, 1:##class(%DynamicArray).%FromJSON(docsJSON))
    Set total = docs.%Size(), stored = 0
    For offset=0:..#BATCHSIZE:(total - 1) {
        Set texts = []
        For i=offset:1:$Select(offset + ..#BATCHSIZE - 1 < (total - 1):offset + ..#BATCHSIZE - 1, 1:total - 1) {
            Do texts.%Push(docs.%Get(i).content)
        }
        Set vectors = ##class(SolarAgents.Core.LLM).EmbedBatch(texts, "VectorStore."_collection)
        For j=0:1:(texts.%Size() - 1) {
            Set doc = docs.%Get(offset + j)
            Set meta = doc.%Get("metadata")
            Set rs = ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO SolarAgents_RAG.Chunk (Collection, Content, Metadata, Embedding) VALUES (?, ?, ?, TO_VECTOR(?, DOUBLE))",
                collection, doc.content, $Select($IsObject(meta):meta.%ToJSON(), 1:"{}"), vectors.%Get(j))
            If rs.%SQLCODE < 0 {
                $$$ThrowStatus($$$ERROR($$$SQLError, rs.%SQLCODE, rs.%Message))
            }
            Set stored = stored + 1
        }
    }
    Quit stored
}

/// Similarity search. Returns a JSON array string of {"content","metadata","score"} ordered by score asc.
ClassMethod Search(collection As %String, query As %String, k As %Integer = 4) As %String
{
    Quit ..SearchObj(collection, query, k).%ToJSON()
}

ClassMethod SearchObj(collection As %String, query As %String, k As %Integer = 4) As %DynamicArray
{
    Set out = []
    Quit:..Count(collection)=0 out
    Set vec = ##class(SolarAgents.Core.LLM).Embed(query, "VectorStore."_collection)
    Set sql = "SELECT TOP ? Content, Metadata, (1 - VECTOR_COSINE(Embedding, TO_VECTOR(?, DOUBLE))) AS Score "_
              "FROM SolarAgents_RAG.Chunk WHERE Collection = ? ORDER BY Score"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, k, vec, collection)
    If rs.%SQLCODE < 0 {
        $$$ThrowStatus($$$ERROR($$$SQLError, rs.%SQLCODE, rs.%Message))
    }
    While rs.%Next() {
        Set meta = rs.Metadata
        Try {
            Set metaObj = ##class(%DynamicObject).%FromJSON($Select(meta="":"{}", 1:meta))
        } Catch {
            Set metaObj = {}
        }
        Do out.%Push({"content":(rs.Content), "metadata":(metaObj), "score":($Number(rs.Score, 6))})
    }
    Quit out
}

ClassMethod Count(collection As %String) As %Integer
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM SolarAgents_RAG.Chunk WHERE Collection = ?", collection)
    Quit:'rs.%Next() 0
    Quit +rs.N
}

ClassMethod Exists(collection As %String) As %Boolean
{
    Quit ..Count(collection) > 0
}

ClassMethod DeleteCollection(collection As %String) As %Integer
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM SolarAgents_RAG.Chunk WHERE Collection = ?", collection)
    Quit rs.%ROWCOUNT
}

/// Lists collections with chunk counts: [{"collection":..., "chunks":...}]
ClassMethod Collections() As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Collection, COUNT(*) AS N FROM SolarAgents_RAG.Chunk GROUP BY Collection ORDER BY Collection")
    While rs.%Next() {
        Do out.%Push({"collection":(rs.Collection), "chunks":(+rs.N)})
    }
    Quit out
}

}
