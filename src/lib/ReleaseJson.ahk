#Requires AutoHotkey v2.0

; Strict, bounded JSON reader for release metadata. No script evaluation.
class ReleaseJson {
    static Parse(text) {
        if (Type(text) != "String" || StrLen(text) > 1048576)
            throw Error("Release JSON must be a string smaller than 1 MiB.")
        reader := this(text)
        value := reader.ReadValue(0)
        reader.SkipWhitespace()
        if (reader.Pos <= reader.Length)
            throw Error("Trailing data in release JSON.")
        return value
    }

    __New(text) {
        this.Text := text
        this.Length := StrLen(text)
        this.Pos := 1
    }

    SkipWhitespace() {
        while (this.Pos <= this.Length && InStr(" `t`r`n", SubStr(this.Text, this.Pos, 1)))
            this.Pos++
    }

    ReadValue(depth) {
        if (depth > 32)
            throw Error("Release JSON nesting is too deep.")
        this.SkipWhitespace()
        char := SubStr(this.Text, this.Pos, 1)
        if (char == "{")
            return this.ReadObject(depth + 1)
        if (char == "[")
            return this.ReadArray(depth + 1)
        if (char == '"')
            return this.ReadString()
        for literal, value in Map("true", 1, "false", 0, "null", {JsonNull: true}) {
            if (SubStr(this.Text, this.Pos, StrLen(literal)) == literal) {
                this.Pos += StrLen(literal)
                return value
            }
        }
        if !RegExMatch(SubStr(this.Text, this.Pos), '^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?', &match)
            throw Error("Invalid value in release JSON.")
        this.Pos += StrLen(match[0])
        return RegExMatch(match[0], '[.eE]') ? Float(match[0]) : Integer(match[0])
    }

    ReadObject(depth) {
        value := Map()
        value.CaseSense := "On"
        this.Pos++
        this.SkipWhitespace()
        if (SubStr(this.Text, this.Pos, 1) == "}") {
            this.Pos++
            return value
        }
        loop {
            this.SkipWhitespace()
            key := this.ReadString()
            if value.Has(key)
                throw Error("Duplicate key in release JSON.")
            this.SkipWhitespace()
            this.Consume(":")
            value[key] := this.ReadValue(depth)
            this.SkipWhitespace()
            if (SubStr(this.Text, this.Pos, 1) == "}") {
                this.Pos++
                return value
            }
            this.Consume(",")
        }
    }

    ReadArray(depth) {
        value := []
        this.Pos++
        this.SkipWhitespace()
        if (SubStr(this.Text, this.Pos, 1) == "]") {
            this.Pos++
            return value
        }
        loop {
            value.Push(this.ReadValue(depth))
            this.SkipWhitespace()
            if (SubStr(this.Text, this.Pos, 1) == "]") {
                this.Pos++
                return value
            }
            this.Consume(",")
        }
    }

    ReadString() {
        this.Consume('"')
        value := ""
        while (this.Pos <= this.Length) {
            char := SubStr(this.Text, this.Pos++, 1)
            if (char == '"')
                return value
            if (Ord(char) < 32)
                throw Error("Unescaped control character in release JSON.")
            if (char != "\") {
                value .= char
                continue
            }
            escaped := SubStr(this.Text, this.Pos++, 1)
            switch escaped, true {
                case '"', "\", "/": value .= escaped
                case "b": value .= Chr(8)
                case "f": value .= Chr(12)
                case "n": value .= "`n"
                case "r": value .= "`r"
                case "t": value .= "`t"
                case "u":
                    code := this.ReadUnicode()
                    if (code >= 0xD800 && code <= 0xDBFF) {
                        this.Consume("\u")
                        low := this.ReadUnicode()
                        if (low < 0xDC00 || low > 0xDFFF)
                            throw Error("Invalid Unicode surrogate pair in release JSON.")
                        value .= Chr(0x10000 + ((code - 0xD800) << 10) + low - 0xDC00)
                    } else if (code >= 0xDC00 && code <= 0xDFFF) {
                        throw Error("Unpaired Unicode surrogate in release JSON.")
                    } else {
                        if (code == 0)
                            throw Error("NUL escapes are unsupported in release JSON.")
                        value .= Chr(code)
                    }
                default: throw Error("Invalid escape in release JSON.")
            }
        }
        throw Error("Unterminated string in release JSON.")
    }

    ReadUnicode() {
        digits := SubStr(this.Text, this.Pos, 4)
        if !RegExMatch(digits, '^[0-9a-fA-F]{4}$')
            throw Error("Invalid Unicode escape in release JSON.")
        this.Pos += 4
        return Integer("0x" . digits)
    }

    Consume(expected) {
        if (SubStr(this.Text, this.Pos, StrLen(expected)) !== expected)
            throw Error("Invalid delimiter in release JSON.")
        this.Pos += StrLen(expected)
    }
}
