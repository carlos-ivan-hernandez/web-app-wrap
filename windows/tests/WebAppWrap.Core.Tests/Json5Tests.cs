using System.Text.Json;
using WebAppWrap.Core;

namespace WebAppWrap.Core.Tests;

public class Json5Tests
{
    private static string Strict(string json5)
    {
        using var document = Json5.Parse(json5);
        return document.RootElement.GetRawText();
    }

    [Theory]
    [InlineData("""{"a": [1, true, null, "x"]}""", """{"a":[1,true,null,"x"]}""")]
    [InlineData("\uFEFF // top\n[1, /* two */ 2,] // end", "[1,2]")]
    [InlineData("{a: 1, $b_2: 2, ünï: 3, \\u0061b: 4,}", """{"a":1,"$b_2":2,"ünï":3,"ab":4}""")]
    [InlineData("""['it\'s', "say \"hi\"", 'tab\there']""", """["it's","say \"hi\"","tab\there"]""")]
    [InlineData("'\\x41\\u0042\\0\\q'", "\"AB\\u0000q\"")]
    [InlineData("'one \\\ntwo \\\r\nthree'", "\"one two three\"")]
    [InlineData("[0x1F, -0XfF, .5, 5., +1, -1.5e2, 0]", "[31,-255,0.5,5,1,-150,0]")]
    [InlineData("[Infinity, -Infinity, NaN]", """["Infinity","-Infinity","NaN"]""")]
    public void RewritesAsStrictJson(string json5, string expected) => Assert.Equal(expected, Strict(json5));

    [Theory]
    [InlineData("")]
    [InlineData("not json")]
    [InlineData("[1 2]")]
    [InlineData("[1,,]")]
    [InlineData("{a 1}")]
    [InlineData("{'a': }")]
    [InlineData("'unclosed")]
    [InlineData("'line\nbreak'")]
    [InlineData("/* unclosed")]
    [InlineData("[01]")]
    [InlineData("[1.2.3]")]
    [InlineData("[1e]")]
    [InlineData("[.]")]
    [InlineData("[0x]")]
    [InlineData("['\\1']")]
    [InlineData("['\\x4']")]
    [InlineData("[1] [2]")]
    [InlineData("[truex]")]
    [InlineData("{1: 2}")]
    public void RejectsInvalid(string json5) => Assert.ThrowsAny<JsonException>(() => Strict(json5));

    [Fact]
    public void RejectsDeepNesting() => Assert.ThrowsAny<JsonException>(() => Strict(new string('[', 1000) + new string(']', 1000)));
}
