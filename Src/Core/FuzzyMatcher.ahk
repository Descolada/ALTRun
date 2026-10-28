;===============================================================================
; FuzzyMatcher.ahk - match scoring for search (AutoHotkey v2)
;-------------------------------------------------------------------------------
; Returns 0 (no match) ~ 100 (identical), following Alfred:
;   100  identical                     "notepad"  -> Notepad
;    90  same start                    "note"     -> Notepad
;    80  start of a word               "code"     -> Visual Studio Code
;    75  word initials                 "vsc"      -> Visual Studio Code
;    60  contains (higher nearer the start)  "pad"      -> Notepad
;    45  several words all match       "st co"    -> Visual Studio Code
;    30  letters in order (at least 3, same first letter)  "ntpd" -> Notepad
; Within a tier, shorter text scores higher (more exact). All case-insensitive.
;
; Performance: thousands of candidates are scored on each key press, so each candidate's SearchKey (lower case,
; word boundaries, initials) is computed in advance and scoring is just a few InStr calls, no regex. Candidates that don't match (most of them)
; are usually ruled out after two InStr calls.
;
; Usage:
;   key := FuzzyMatcher.Key("Visual Studio Code")          build once per candidate and cache it
;   FuzzyMatcher.ScoreKey("vsc", key)                      needle must already be lower case
;   FuzzyMatcher.BestKey("wx", [titleKey, pinyinKey])      the best score of several
;   FuzzyMatcher.Score("vsc", "Visual Studio Code")        one-off scoring (builds the key itself)
;   FuzzyMatcher.TopIndexes(scores, limit)                 scores -> the indexes of the limit best
;   FuzzyMatcher.MatchRanges("vsc", "Visual Studio Code")  the positions to highlight -> [[1, 1], [8, 1], [15, 1]]
;===============================================================================

class FuzzyMatcher {

    static Score(needle, text) {
        needle := StrLower(Trim(needle))
        if (needle = "")
            return 1
        return FuzzyMatcher.ScoreKey(needle, FuzzyMatcher.Key(text))
    }

    static Best(needle, candidates) {
        needle := StrLower(Trim(needle))
        best := 0
        for text in candidates {
            if (text = "")
                continue
            score := (needle = "") ? 1 : FuzzyMatcher.ScoreKey(needle, FuzzyMatcher.Key(text))
            if (score > best)
                best := score
        }
        return best
    }

    ; Precomputed candidate text: Lower = the text in lower case, Words = " " + the lower-case text with only spaces between words,
    ; Initials = the initials of the words (camel case counts as words)
    static Key(text) {
        lower := StrLower(text)
        words := " " RegExReplace(lower, "[\s\-_.\\/()\[\]]+", " ")
        return {Lower: lower, Words: words, Initials: FuzzyMatcher.Initials(text), Length: StrLen(lower)}
    }

    static BestKey(needle, keys) {
        best := 0
        for key in keys {
            if !IsObject(key)
                continue
            score := FuzzyMatcher.ScoreKey(needle, key)
            if (score > best)
                best := score
        }
        return best
    }

    ; needle: already trimmed and lower case
    static ScoreKey(needle, key) {
        if (needle = "")
            return 1
        h := key.Lower
        if (h = "")
            return 0
        needleLength := StrLen(needle)
        lengthPenalty := Min(Max(key.Length - needleLength, 0), 40) * 0.1  ; at most 4 points off

        if (pos := InStr(h, needle)) {
            if (key.Length = needleLength)
                return 100
            if (pos = 1)
                return 90 - lengthPenalty
            if (InStr(key.Words, " " needle) || InStr(" -_.\/()[]", SubStr(h, pos - 1, 1)))   ; second condition: when the needle itself contains separators
                return 80 - lengthPenalty
            return 60 - Min(pos, 20) * 0.25 - lengthPenalty
        }
        if (needleLength >= 2 && InStr(key.Initials, needle) = 1)
            return 75 - lengthPenalty

        if InStr(needle, " ") {                                             ; several words: each must match
            total := 0, count := 0
            for token in StrSplit(needle, " ") {
                if (token = "")
                    continue
                tokenScore := FuzzyMatcher.ScoreKey(token, key)
                if (tokenScore <= 1)
                    return 0
                total += tokenScore, count++
            }
            return count ? Min(total / count, 90) * 0.5 : 0
        }

        ; letters in order: at least 3 and the same first letter, otherwise too many unrelated items match
        if (needleLength >= 3 && SubStr(needle, 1, 1) = SubStr(h, 1, 1) && FuzzyMatcher.IsSubsequence(needle, h))
            return 30 - lengthPenalty
        return 0
    }

    ; The characters to highlight in a result: where needle hits text, as [[start, length], ...] (1-based, sorted by position, adjacent ones merged).
    ; Matches the way ScoreKey matches: a contiguous run (preferring word starts) / word initials / several words each found / letters in order;
    ; failing those, by pinyin initials (one letter per Chinese character, same positions). When several words don't match as a whole (e.g. "snip 报价",
    ; where the first is a keyword), the words that are found are marked on their own. [] if nothing is found
    static MatchRanges(needle, text) {
        needle := StrLower(Trim(RegExReplace(needle, "\s+", " ")))
        if (needle = "" || text = "")
            return []
        ranges := FuzzyMatcher._Ranges(needle, text, true)
        if (!ranges.Length && InStr(needle, " ")) {
            for token in StrSplit(needle, " ")
                if (token != "")
                    for range in FuzzyMatcher._Ranges(token, text, false)
                        ranges.Push(range)
        }
        if (!ranges.Length && RegExMatch(text, "[^\x{00}-\x{ff}]")) {
            initials := Pinyin.Initials(text)
            if (initials != text && StrLen(initials) = StrLen(text))
                ranges := FuzzyMatcher._Ranges(needle, initials, true)
        }
        return FuzzyMatcher._MergeRanges(ranges)
    }

    static _Ranges(needle, text, allowSubsequence) {
        h := StrLower(text)
        if (pos := InStr(h, needle)) {                                      ; contiguous: use one at a word start if there is one
            starts := FuzzyMatcher.WordStarts(text), found := pos
            while pos {
                if FuzzyMatcher._Has(starts, pos) {
                    found := pos
                    break
                }
                pos := InStr(h, needle, false, pos + 1)
            }
            return [[found, StrLen(needle)]]
        }
        needleLength := StrLen(needle)
        if (needleLength >= 2 && !InStr(needle, " ")) {                     ; word initials
            starts := FuzzyMatcher.WordStarts(text), initials := ""
            for start in starts
                initials .= SubStr(h, start, 1)
            if (InStr(initials, needle) = 1) {
                ranges := []
                Loop needleLength
                    ranges.Push([starts[A_Index], 1])
                return ranges
            }
        }
        if InStr(needle, " ") {                                             ; several words: each must be found
            ranges := []
            for token in StrSplit(needle, " ") {
                if (token = "")
                    continue
                found := FuzzyMatcher._Ranges(token, text, allowSubsequence)
                if !found.Length
                    return []
                for range in found
                    ranges.Push(range)
            }
            return ranges
        }
        if (allowSubsequence && needleLength >= 3 && SubStr(needle, 1, 1) = SubStr(h, 1, 1)) {   ; letters in order
            ranges := [], pos := 1
            Loop Parse needle {
                if !(pos := InStr(h, A_LoopField, false, pos))
                    return []
                ranges.Push([pos, 1]), pos++
            }
            return ranges
        }
        return []
    }

    ; Position of the first character of each word (split like Initials: characters other than letters and digits separate, camel case counts as words)
    static WordStarts(text) {
        starts := [], previousWord := false, previousLower := false
        Loop Parse text {
            code := Ord(A_LoopField)
            ; Parsing UTF-16 visits each surrogate separately; Unicode regex cannot accept a lone surrogate.
            isWord := (code < 0xD800 || code > 0xDFFF) && RegExMatch(A_LoopField, "^[\p{L}\p{N}]$")
            if (isWord && (!previousWord || (previousLower && code >= 65 && code <= 90)))
                starts.Push(A_Index)
            previousWord := isWord, previousLower := code >= 97 && code <= 122
        }
        return starts
    }

    static _Has(list, value) {
        for item in list
            if (item = value)
                return true
        return false
    }

    static _MergeRanges(ranges) {
        if (ranges.Length <= 1)
            return ranges
        lines := ""
        for range in ranges
            lines .= Format("{:06}", range[1]) "`t" range[2] "`n"
        merged := []
        for line in StrSplit(RTrim(Sort(lines), "`n"), "`n") {
            parts := StrSplit(line, "`t"), start := Integer(parts[1]), length := Integer(parts[2])
            if (merged.Length && start <= merged[merged.Length][1] + merged[merged.Length][2]) {
                last := merged[merged.Length]
                last[2] := Max(last[1] + last[2], start + length) - last[1]
            } else {
                merged.Push([start, length])
            }
        }
        return merged
    }

    ; Splits the text at the hits: [[text, highlighted], ...] (anything beyond the text's length is ignored)
    static Segments(text, ranges) {
        segments := [], pos := 1, textLength := StrLen(text)
        for range in ranges {
            start := range[1], stop := Min(range[1] + range[2], textLength + 1)
            if (start > textLength || stop <= pos)
                continue
            start := Max(start, pos)
            if (start > pos)
                segments.Push([SubStr(text, pos, start - pos), false])
            segments.Push([SubStr(text, start, stop - start), true])
            pos := stop
        }
        if (pos <= textLength)
            segments.Push([SubStr(text, pos), false])
        return segments
    }

    ; "Visual Studio Code" -> "vsc"; "my_file-name" -> "mfn"; "AutoHotkey" -> "ah" (camel case counts as words)
    static Initials(text) {
        text := RegExReplace(text, "([a-z])([A-Z])", "$1 $2")
        initials := ""
        for word in StrSplit(RegExReplace(text, "[^\p{L}\p{N}]+", " "), " ")
            if (word != "")
                initials .= SubStr(word, 1, 1)
        return StrLower(initials)
    }

    static IsSubsequence(needle, text) {
        pos := 1
        Loop Parse needle {
            pos := InStr(text, A_LoopField, false, pos)
            if !pos
                return false
            pos++
        }
        return true
    }

    ; scores: index -> score (Map); returns the indexes of the limit highest scores (on ties, lower indexes first)
    static TopIndexes(scores, limit) => ALTRunRankedIndexes(scores, limit, false)
}

#CSharp
private readonly record struct ALTRunSearchRank(long Index, string Key, double Number);

private sealed class ALTRunSearchRankComparer(bool numeric) : System.Collections.Generic.IComparer<ALTRunSearchRank>
{
    public int Compare(ALTRunSearchRank left, ALTRunSearchRank right)
    {
        int result = numeric ? left.Number.CompareTo(right.Number)
            : System.StringComparer.OrdinalIgnoreCase.Compare(left.Key, right.Key);
        return result != 0 ? result : right.Index.CompareTo(left.Index);
    }
}

public static Keysharp.Builtins.Array ALTRunRankedIndexes(Keysharp.Builtins.Map scores, long limit, bool numeric)
{
    var culture = System.Globalization.CultureInfo.InvariantCulture;
    int count = (int)scores.Count;
    int take = (int)System.Math.Min(count, System.Math.Max(1, limit));
    if (take == 0) return new Keysharp.Builtins.Array();
    var comparer = new ALTRunSearchRankComparer(numeric);
    var queue = take < count ? new System.Collections.Generic.PriorityQueue<ALTRunSearchRank, ALTRunSearchRank>(comparer) : null;
    var selected = new System.Collections.Generic.List<ALTRunSearchRank>(take);
    foreach (var (key, value) in scores)
    {
        long index = System.Convert.ToInt64(key, culture);
        double score;
        try { score = System.Convert.ToDouble(value, culture); }
        catch { score = 0; }
        // Retain the search model's F4/F6 precision and tie ordering without repeatedly copying a growing string.
        string text = score.ToString(numeric ? "F6" : "F4", culture);
        var rank = numeric
            ? new ALTRunSearchRank(index, "", double.Parse(text, culture))
            : new ALTRunSearchRank(index, text.PadLeft(9, '0') + "\t" + (9999999 - index).ToString("D7", culture), 0);
        if (queue == null) selected.Add(rank);
        else if (queue.Count < take) queue.Enqueue(rank, rank);
        else queue.EnqueueDequeue(rank, rank);
    }
    if (queue != null)
        foreach (var entry in queue.UnorderedItems) selected.Add(entry.Element);
    selected.Sort((left, right) => comparer.Compare(right, left));
    var result = new object[selected.Count];
    for (int index = 0; index < selected.Count; index++) result[index] = selected[index].Index;
    return new Keysharp.Builtins.Array(result);
}
#EndCSharp
