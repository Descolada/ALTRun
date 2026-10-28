; Deterministic ranking compatibility and large-index timing, without windows or user data.
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => (FileAppend("FAIL SEARCH_RANKING " err.Message "`n" err.Stack "`n", "**"), ExitApp(1)))
SetTimer(() => ExitApp(2), -30000)
SearchRanking.Run()

class SearchRanking {
    static FixtureResults := []

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static LegacyTop(scores, limit) {
        if !scores.Count
            return []
        lines := ""
        for index, score in scores
            lines .= Format("{:09.4f}", score) "`t" Format("{:07}", 9999999 - index) "`n"
        result := []
        for line in StrSplit(Sort(RTrim(lines, "`n"), "R"), "`n") {
            result.Push(9999999 - Integer(StrSplit(line, "`t")[2]))
            if (result.Length >= limit)
                break
        }
        return result
    }

    static LegacySort(items) {
        if (items.Length < 2)
            return items
        lines := ""
        for index, item in items
            lines .= Format("{:.6f}", item.Score - index * 0.00001) "`t" index "`n"
        result := []
        for line in StrSplit(RTrim(Sort(lines, "N R"), "`n"), "`n")
            result.Push(items[Integer(StrSplit(line, "`t")[2])])
        return result
    }

    static Order(items) {
        result := []
        for item in items
            result.Push(item.Uid)
        return JSON.Stringify(result)
    }

    static Run() {
        Logger.Enabled := false
        AppSettings.Data := AppSettings.Defaults()
        SearchRanking.OptionalInit()
        scores := Map(500, 90, 3, 90, 20, 80.000049, 21, 80.000041, 22, 80.000051
            , 1, 1.23445, 2, 1.2344499999, 4, 0, 6, -0.1, 7, 10000.5)
        Loop 200
            scores[1000 + A_Index] := Mod(A_Index * 7919, 997) / 7
        for limit in [0, 1, 3, 50, 1000]
            SearchRanking.Assert(JSON.Stringify(FuzzyMatcher.TopIndexes(scores, limit)) == JSON.Stringify(SearchRanking.LegacyTop(scores, limit)), "Top-k changed score precision or tie ordering, limit " limit)
        SearchRanking.Assert(FuzzyMatcher.TopIndexes(Map(), 50).Length = 0, "An empty score map returned indexes.")
        tied := FuzzyMatcher.TopIndexes(Map(4, 90, 2, 90, 3, 20), 2)
        SearchRanking.Assert(tied.Length = 2 && tied[1] = 2 && tied[2] = 4, "Equal scores must prefer lower candidate indexes.")

        items := []
        for index, score in [10, 90, 50, 50, 50.000009, 50.00002, -1, 0, 0.1234565, 0.12345649999]
            items.Push(ResultItem("Fixture", "", {Uid: "rank:" index, Score: score}))
        expected := SearchRanking.Order(SearchRanking.LegacySort(items))
        SearchRanking.Assert(SearchRanking.Order(ProviderRegistry.SortByScore(items)) == expected, "Registry ranking changed its F6 precision, index adjustment or stable ordering.")
        SearchRanking.Assert(items[1].Score = 10 && items[2].Score = 90, "Ranking mutated source scores.")

        ProviderRegistry.Providers := [SearchRankingProvider]
        Loop 80
            SearchRanking.FixtureResults.Push(ResultItem("Fixture", "", {Uid: "fixture:" A_Index, Score: 100 - A_Index}))
        SearchRanking.FixtureResults.Push(ResultItem("Duplicate", "", {Uid: "fixture:1", Score: 200}))
        found := ProviderRegistry.Search("fixture")
        SearchRanking.Assert(found.Length = ProviderRegistry.MaxResults && found[1].Title == "Duplicate" && found[2].Uid == "fixture:2", "Search must deduplicate the best result before enforcing MaxResults.")

        large := Map()
        Loop 10000
            large[A_Index] := 80 + Mod(A_Index, 100) * 0.1
        started := Platform.Milliseconds()
        expected := SearchRanking.LegacyTop(large, 50)
        legacyMs := Platform.Milliseconds() - started
        started := Platform.Milliseconds()
        actual := FuzzyMatcher.TopIndexes(large, 50)
        fastMs := Platform.Milliseconds() - started
        SearchRanking.Assert(JSON.Stringify(actual) == JSON.Stringify(expected), "Large-index top-k ordering changed.")
        SearchRanking.Assert(fastMs < legacyMs * 0.5, "Top-k still scales like the growing-string implementation: " Round(fastMs, 2) " ms versus " Round(legacyMs, 2) " ms.")
        FileAppend("PASS SEARCH_RANKING precision, ties, sparse indexes, result limits; 10000 candidates " Round(legacyMs, 2) " -> " Round(fastMs, 2) " ms`n", "*")
        ExitApp(0)
    }

    static OptionalInit() {
        saved := Logger.GetOwnPropDesc("Error"), state := {Errors: 0}
        AppSettings.Feature("Clipboard")["Enabled"] := 0
        ProviderRegistry.Providers := [SearchRankingInitProvider, SearchRankingProvider, SearchRankingDisabledProvider]
        Logger.DefineProp("Error", {Call: (self, message) => state.Errors += 1})
        try {
            ProviderRegistry.InitAll()
            SearchRanking.Assert(SearchRankingInitProvider.Calls = 1 && SearchRankingDisabledProvider.Calls = 0 && state.Errors = 0
                , "Provider startup must initialize enabled providers, allow an absent Init and skip disabled providers.")
        } finally Logger.DefineProp("Error", saved)
    }
}

class SearchRankingProvider {
    static Id := "Applications"
    static Search(query) => SearchRanking.FixtureResults
}

class SearchRankingInitProvider {
    static Id := "Applications", Calls := 0
    static Init() => SearchRankingInitProvider.Calls += 1
}

class SearchRankingDisabledProvider {
    static Id := "Clipboard", Calls := 0
    static Init() => SearchRankingDisabledProvider.Calls += 1
}
