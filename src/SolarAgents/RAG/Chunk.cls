/// A text chunk with its embedding, grouped by collection.
/// Native IRIS vector storage: VECTOR(DOUBLE, 1536) + VECTOR_COSINE, no external vector database.
Class SolarAgents.RAG.Chunk Extends %Persistent
{

Property Collection As %String(COLLATION = "EXACT", MAXLEN = 200) [ Required ];

Property Content As %String(MAXLEN = "");

/// JSON object with the chunk metadata (type, priority, "Resposta", "prompt", ...).
Property Metadata As %String(MAXLEN = "");

Property Embedding As %Vector(DATATYPE = "DOUBLE", LEN = 1536);

Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDateTime($ZTimeStamp, 3, 1)} ];

Index CollectionIdx On Collection;

}
