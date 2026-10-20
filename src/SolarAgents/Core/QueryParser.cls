/// Deterministic understanding of a question: which plants, which period, which language.
/// Used by the router (no LLM needed for these facts) and by offline mode.
Class SolarAgents.Core.QueryParser Extends %RegisteredObject
{

/// Lower case without accents.
ClassMethod Normalize(text As %String) As %String
{
    Quit $ZConvert($Translate(text, "ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇçÑñ", "AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNn"), "L")
}

/// Plant codes mentioned in the question ("all plants" / "which plant" / "ranking" -> every plant).
/// Returns {"codes": [...], "names": [...], "all": 0|1}
ClassMethod Plants(question As %String) As %DynamicObject
{
    Set q = " "_$Translate(..Normalize(question), "?!.,;:", "      ")_" ", out = {"codes": [], "names": [], "all": 0}
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Code, Name FROM SolarAgents_Data.Plant ORDER BY Code")
    While rs.%Next() {
        Set short = $ZStrip(..Normalize($Replace(rs.Name, " Solar Plant", "")), "<>W")
        If (q[(" "_short_" ")) || (q[(" "_short_"'")) || (q[(" "_$ZConvert(rs.Code, "L")_" ")) {
            Do out.codes.%Push(rs.Code), out.names.%Push(rs.Name)
        }
    }
    Set wantsAll = 0
    For kw=" all "," every "," each "," ranking "," best "," worst "," which plant"," which plants"," plants "," todas"," cada "," qual usina"," quais usinas"," usinas " {
        If q[kw {
            Set wantsAll = 1
            Quit
        }
    }
    If (out.codes.%Size()=0) && wantsAll {
        Set out.all = 1
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Code, Name FROM SolarAgents_Data.Plant ORDER BY Code")
        While rs.%Next() {
            Do out.codes.%Push(rs.Code), out.names.%Push(rs.Name)
        }
    }
    Quit out
}

/// Period of the question. Returns {"start":"YYYY-MM-DD","end":"YYYY-MM-DD","label":"...","explicit":0|1}.
/// Without a period: the whole data range.
ClassMethod Period(question As %String) As %DynamicObject
{
    Set q = ..Normalize(question)
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MIN(Day) AS F, MAX(Day) AS L FROM SolarAgents_Data.Generation")
    Do rs.%Next()
    Set first = rs.F, last = rs.L
    Set:last="" last = +$Horolog, first = last - 30
    Set year = +$Piece($ZDate(last, 3), "-", 1)
    For i=1:1:$Length(q) {
        If $Extract(q, i, i + 3)?1"20"2N {
            Set year = +$Extract(q, i, i + 3)
            Quit
        }
    }
    // explicit dates: ISO (2026-08-10) or US (08/10/2026)
    Set dates = ""
    For i=1:1:$Length(q) {
        Set piece = $Extract(q, i, i + 9)
        Set:piece?4N1"-"2N1"-"2N dates = dates_$ListBuild($ZDateH(piece, 3))
        Set:piece?2N1"/"2N1"/"4N dates = dates_$ListBuild($ZDateH(piece, 1))
    }
    If $ListLength(dates) >= 1 {
        Set s = $List(dates, 1), e = $Select($ListLength(dates)>1:$List(dates, 2), 1:s)
        Quit {"start": ($ZDate(s, 3)), "end": ($ZDate(e, 3)), "label": (..Label(s)_" to "_..Label(e)), "explicit": 1}
    }
    // last N days (relative to the latest data)
    Set p = $Find(q, "last ")
    Set:p=0 p = $Find(q, "ultimos ")
    If p, +$Extract(q, p, p + 3) {
        Set n = +$Extract(q, p, p + 3)
        Quit {"start": ($ZDate(last - n + 1, 3)), "end": ($ZDate(last, 3)), "label": ("last "_n_" days"), "explicit": 1}
    }
    // month names (en / pt)
    Set months = $ListBuild("january|janeiro", "february|fevereiro", "march|marco", "april|abril", "may|maio", "june|junho", "july|julho", "august|agosto", "september|setembro", "october|outubro", "november|novembro", "december|dezembro")
    Set found = ""
    For m=1:1:12 {
        Set names = $List(months, m)
        For k=1:1:2 {
            Set:(" "_$Translate(q, "?!.,;:", "      ")_" ")[(" "_$Piece(names, "|", k)_" ") found = found_$ListBuild(m)
        }
    }
    If found'="" {
        Set m1 = $List(found, 1), m2 = $List(found, $ListLength(found))
        Set:m2<m1 tmp = m1, m1 = m2, m2 = tmp
        Set s = $ZDateH(year_"-"_$Translate($Justify(m1, 2), " ", "0")_"-01", 3)
        Set nextMonth = $Select(m2=12:(year + 1)_"-01-01", 1:year_"-"_$Translate($Justify(m2 + 1, 2), " ", "0")_"-01")
        Set e = $ZDateH(nextMonth, 3) - 1
        Set label = $ZConvert($Piece($List(months, m1), "|", 1), "W")_$Select(m2'=m1:" to "_$ZConvert($Piece($List(months, m2), "|", 1), "W"), 1:"")_" "_year
        Quit {"start": ($ZDate(s, 3)), "end": ($ZDate(e, 3)), "label": (label), "explicit": 1}
    }
    Quit {"start": ($ZDate(first, 3)), "end": ($ZDate(last, 3)), "label": ("entire period ("_..Label(first)_" to "_..Label(last)_")"), "explicit": 0}
}

/// "Aug 10, 2026"
ClassMethod Label(h As %Integer) As %String
{
    Quit $ZDate(h, 2)
}

/// "pt" when the question looks Portuguese, otherwise "en".
ClassMethod Language(question As %String) As %String
{
    Set q = " "_$Translate(..Normalize(question), "?!.,;:", "      ")_" ", hits = 0
    For w=" qual "," quais "," como "," usina "," usinas "," geracao "," por que "," porque "," da "," do "," em "," de "," foi "," teve "," mes " {
        Set:q[w hits = hits + 1
    }
    Quit $Select(hits>=2:"pt", 1:"en")
}

/// SQL list literal of plant codes: 'AUR', 'BLR'
ClassMethod CodesSQL(codes As %DynamicArray) As %String
{
    Set out = "", iter = codes.%GetIterator()
    While iter.%GetNext(, .code) {
        Set out = out_$Select(out="":"", 1:", ")_"'"_$Replace(code, "'", "''")_"'"
    }
    Quit out
}

/// Exact calendar for the SQL prompt so the LLM never computes dates by itself.
ClassMethod DateContext(period As %DynamicObject) As %String
{
    Set nl = $Char(10)
    Quit "DATE CONTEXT (use exactly):"_nl_"- Today: "_$ZDate(+$Horolog, 3)_nl_"- Requested period: "_period.label_" => '"_period.start_"' to '"_period.end_"'"_nl
}

}
