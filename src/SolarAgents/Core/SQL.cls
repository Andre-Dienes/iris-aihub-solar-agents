/// Guarded SQL execution for LLM-generated queries.
Class SolarAgents.Core.SQL Extends %RegisteredObject
{

/// "" when the SQL is a single read-only SELECT over the allowed tables, otherwise the reason.
/// allowedTables: comma-separated class names of SolarAgents.Data (e.g. "Generation,Plant").
ClassMethod Validate(sql As %String, allowedTables As %String = "") As %String
{
    Set s = $ZConvert($ZStrip(sql, "<>W"), "U")
    Quit:($Extract(s, 1, 6)'="SELECT")&&($Extract(s, 1, 4)'="WITH") "Only SELECT queries are allowed."
    Quit:$Length($ZStrip(s, ">", ";"), ";")>1 "Only one SQL statement is allowed."
    For kw="INSERT ","UPDATE ","DELETE ","DROP ","ALTER ","CREATE ","TRUNCATE ","GRANT ","CALL " {
        Return:s[kw "Command not allowed: "_$ZStrip(kw, ">W")
    }
    Quit:allowedTables="" ""
    Set allowed = $ListFromString($ZConvert(allowedTables, "U"), ",")
    Set p = 0
    For {
        Set p = $Find(s, "SOLARAGENTS_DATA.", p)
        Quit:p=0
        Set table = ""
        For i=p:1:$Length(s) {
            Quit:$Extract(s, i)'?1(1AN,1"_")
            Set table = table_$Extract(s, i)
        }
        Return:'$ListFind(allowed, table) "Table outside this agent's scope: "_table
    }
    Quit ""
}

/// Runs a SELECT (ODBC display mode) and returns {"columns": [...], "rows": [{...}], "truncated": 0|1}.
ClassMethod Run(sql As %String, maxRows As %Integer = 500) As %DynamicObject
{
    Set stmt = ##class(%SQL.Statement).%New()
    Set stmt.%SelectMode = 1
    $$$ThrowOnError(stmt.%Prepare(sql))
    Set rs = stmt.%Execute()
    If rs.%SQLCODE < 0 {
        $$$ThrowStatus($$$ERROR($$$SQLError, rs.%SQLCODE, rs.%Message))
    }
    Set meta = rs.%GetMetadata(), cols = meta.columns.Count(), columns = []
    For c=1:1:cols {
        Do columns.%Push(meta.columns.GetAt(c).colName)
    }
    Set rows = [], n = 0, truncated = 0
    While rs.%Next() {
        Set n = n + 1
        If n > maxRows {
            Set truncated = 1
            Quit
        }
        Set row = {}
        For c=1:1:cols {
            Set value = rs.%GetData(c), col = meta.columns.GetAt(c)
            If (value'="") && $IsValidNum(value) && ($ListFind($ListBuild(2, 3, 4, 5, 14, 15, 16, 18), col.clientType)) {
                Do row.%Set(col.colName, +value, "number")
            } Else {
                Do row.%Set(col.colName, value)
            }
        }
        Do rows.%Push(row)
    }
    Quit {"columns": (columns), "rows": (rows), "truncated": (truncated)}
}

}
