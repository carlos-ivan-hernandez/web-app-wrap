using System.Globalization;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace WebAppWrap.Core;

/// <summary>
/// Reads JSON5 (https://spec.json5.org), and so also JSONC and plain JSON, by rewriting it as
/// strict JSON. Adds comments, trailing commas, unquoted keys, single-quoted and multi-line
/// strings, and hex, Infinity, NaN and +/-/. numbers. System.Text.Json has no JSON5 mode.
/// </summary>
internal static class Json5
{
    /// <exception cref="JsonException">The text isn't valid JSON5.</exception>
    public static JsonDocument Parse(string text)
    {
        var buffer = new MemoryStream();
        // Only read back by JsonDocument, so there's no need to escape HTML-sensitive or non-ASCII characters.
        using (var writer = new Utf8JsonWriter(buffer, new JsonWriterOptions { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping }))
        {
            var reader = new Reader(text);
            reader.SkipSpace();
            reader.Value(writer, depth: 0);
            reader.SkipSpace();
            if (!reader.AtEnd) throw reader.Error("unexpected text after the value");
        }
        return JsonDocument.Parse(buffer.ToArray());
    }

    private sealed class Reader(string text)
    {
        private const int MaxDepth = 64;
        private int _position;

        public bool AtEnd => _position >= text.Length;

        private char Peek(int offset = 0) => _position + offset < text.Length ? text[_position + offset] : '\0';

        public JsonException Error(string message) => new($"{message} at character {_position + 1}");

        /// <summary>Skips whitespace (any Unicode space, line breaks and the BOM) and comments.</summary>
        public void SkipSpace()
        {
            while (!AtEnd)
            {
                var c = Peek();
                if (char.IsWhiteSpace(c) || c == '\uFEFF')
                    _position++;
                else if (c == '/' && Peek(1) == '/')
                    while (!AtEnd && !IsLineBreak(Peek())) _position++;
                else if (c == '/' && Peek(1) == '*')
                {
                    var end = text.IndexOf("*/", _position + 2, StringComparison.Ordinal);
                    if (end < 0) throw Error("unclosed comment");
                    _position = end + 2;
                }
                else
                    return;
            }
        }

        public void Value(Utf8JsonWriter writer, int depth)
        {
            if (depth > MaxDepth) throw Error("too deeply nested");
            switch (Peek())
            {
                case '{': Object(writer, depth); break;
                case '[': Array(writer, depth); break;
                case '"' or '\'': writer.WriteStringValue(String()); break;
                default:
                    if (TryWord("true")) writer.WriteBooleanValue(true);
                    else if (TryWord("false")) writer.WriteBooleanValue(false);
                    else if (TryWord("null")) writer.WriteNullValue();
                    else Number(writer);
                    break;
            }
        }

        private void Object(Utf8JsonWriter writer, int depth)
        {
            _position++;
            writer.WriteStartObject();
            SkipSpace();
            while (Peek() != '}')
            {
                writer.WritePropertyName(Peek() is '"' or '\'' ? String() : Identifier());
                SkipSpace();
                Expect(':');
                SkipSpace();
                Value(writer, depth + 1);
                if (!CommaOr('}')) break;
            }
            Expect('}');
            writer.WriteEndObject();
        }

        private void Array(Utf8JsonWriter writer, int depth)
        {
            _position++;
            writer.WriteStartArray();
            SkipSpace();
            while (Peek() != ']')
            {
                Value(writer, depth + 1);
                if (!CommaOr(']')) break;
            }
            Expect(']');
            writer.WriteEndArray();
        }

        /// <summary>After a member: true if a comma follows (trailing commas allowed), false at the closing bracket.</summary>
        private bool CommaOr(char close)
        {
            SkipSpace();
            if (Peek() == close) return false;
            Expect(',');
            SkipSpace();
            return true;
        }

        private void Expect(char c)
        {
            if (Peek() != c) throw AtEnd ? Error("unexpected end of file") : Error($"expected “{c}”");
            _position++;
        }

        private bool TryWord(string word)
        {
            if (string.CompareOrdinal(text, _position, word, 0, word.Length) != 0 || IsIdentifierPart(Peek(word.Length))) return false;
            _position += word.Length;
            return true;
        }

        private string String()
        {
            var quote = text[_position++];
            var result = new StringBuilder();
            while (true)
            {
                if (AtEnd) throw Error("unclosed string");
                var c = text[_position++];
                if (c == quote) return result.ToString();
                if (c is '\n' or '\r') throw Error("line break in a string");
                if (c != '\\')
                {
                    result.Append(c);
                    continue;
                }

                if (AtEnd) throw Error("unclosed string");
                var escaped = text[_position++];
                switch (escaped)
                {
                    case 'b': result.Append('\b'); break;
                    case 'f': result.Append('\f'); break;
                    case 'n': result.Append('\n'); break;
                    case 'r': result.Append('\r'); break;
                    case 't': result.Append('\t'); break;
                    case 'v': result.Append('\v'); break;
                    case 'x': result.Append((char)Hex(2)); break;
                    case 'u': result.Append((char)Hex(4)); break;
                    case '0' when !char.IsAsciiDigit(Peek()): result.Append('\0'); break;
                    case >= '0' and <= '9': throw Error("number escapes aren’t allowed in strings");
                    // A backslash before a line break continues the string on the next line.
                    case '\r': if (Peek() == '\n') _position++; break;
                    case '\n' or '\u2028' or '\u2029': break;
                    default: result.Append(escaped); break;
                }
            }
        }

        private int Hex(int digits)
        {
            if (_position + digits > text.Length
                || !int.TryParse(text.AsSpan(_position, digits), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out var value))
                throw Error("bad escape in a string");
            _position += digits;
            return value;
        }

        private string Identifier()
        {
            var result = new StringBuilder();
            while (true)
            {
                var c = Peek();
                var length = 1;
                if (c == '\\' && Peek(1) == 'u' && _position + 6 <= text.Length
                    && int.TryParse(text.AsSpan(_position + 2, 4), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out var code))
                {
                    c = (char)code;
                    length = 6;
                }
                if (result.Length == 0 ? !IsIdentifierStart(c) : !IsIdentifierPart(c)) break;
                result.Append(c);
                _position += length;
            }
            if (result.Length == 0) throw AtEnd ? Error("unexpected end of file") : Error("expected a field name");
            return result.ToString();
        }

        private void Number(Utf8JsonWriter writer)
        {
            var negative = false;
            if (Peek() is '+' or '-')
            {
                negative = Peek() == '-';
                _position++;
            }

            // JSON has no Infinity or NaN, and no batch field accepts them, so they become strings
            // that fail the field checks like any other wrong type.
            if (TryWord("Infinity"))
            {
                writer.WriteStringValue(negative ? "-Infinity" : "Infinity");
                return;
            }
            if (TryWord("NaN"))
            {
                writer.WriteStringValue("NaN");
                return;
            }

            var start = _position;
            if (Peek() == '0' && Peek(1) is 'x' or 'X')
            {
                _position += 2;
                while (char.IsAsciiHexDigit(Peek())) _position++;
                if (!ulong.TryParse(text.AsSpan(start + 2, _position - start - 2), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out var hex))
                    throw Error("bad hex number");
                writer.WriteNumberValue(negative ? -(double)hex : hex);
            }
            else
            {
                var integerDigits = Digits();
                var fractionDigits = 0;
                if (Peek() == '.')
                {
                    _position++;
                    fractionDigits = Digits();
                }
                if (integerDigits == 0 && fractionDigits == 0)
                    throw AtEnd ? Error("unexpected end of file") : Error("unexpected character");
                if (Peek() is 'e' or 'E')
                {
                    _position++;
                    if (Peek() is '+' or '-') _position++;
                    if (Digits() == 0) throw Error("bad number");
                }
                if (integerDigits > 1 && text[start] == '0') throw Error("numbers can’t start with 0");
                if (!double.TryParse(text.AsSpan(start, _position - start), NumberStyles.Float, CultureInfo.InvariantCulture, out var number)
                    || !double.IsFinite(number))
                    throw Error("bad number");
                writer.WriteNumberValue(negative ? -number : number);
            }
            if (IsIdentifierPart(Peek())) throw Error("bad number");
        }

        private int Digits()
        {
            var start = _position;
            while (char.IsAsciiDigit(Peek())) _position++;
            return _position - start;
        }

        private static bool IsLineBreak(char c) => c is '\n' or '\r' or '\u2028' or '\u2029';

        private static bool IsIdentifierStart(char c) =>
            c is '$' or '_' || char.IsLetter(c) || char.GetUnicodeCategory(c) == UnicodeCategory.LetterNumber;

        private static bool IsIdentifierPart(char c) =>
            IsIdentifierStart(c) || char.IsAsciiDigit(c) || c is '\u200C' or '\u200D' || char.GetUnicodeCategory(c) is
                UnicodeCategory.NonSpacingMark or UnicodeCategory.SpacingCombiningMark
                or UnicodeCategory.DecimalDigitNumber or UnicodeCategory.ConnectorPunctuation;
    }
}
