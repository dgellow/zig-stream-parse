const std = @import("std");

// Import our modules
const char_class = @import("src/char_class.zig");
const pattern = @import("src/pattern.zig");
const token_stream = @import("src/token_stream.zig");
const simd_mod = @import("src/simd.zig");
const json = @import("src/parsers/json.zig");
const csv = @import("src/parsers/csv.zig");
const pattern_optimized = @import("src/pattern_optimized.zig");
const token_stream_optimized = @import("src/token_stream_optimized.zig");
const fast_matcher = @import("src/fast_matcher.zig");
const fuzz_tests = @import("src/fuzzing/fuzz_tests.zig");

test "char class table" {
    // Test some basic classifications
    try std.testing.expectEqual(char_class.CharClass.alpha_lower, char_class.char_table['a']);
    try std.testing.expectEqual(char_class.CharClass.alpha_upper, char_class.char_table['A']);
    try std.testing.expectEqual(char_class.CharClass.digit, char_class.char_table['5']);
    try std.testing.expectEqual(char_class.CharClass.whitespace, char_class.char_table[' ']);
    try std.testing.expectEqual(char_class.CharClass.newline, char_class.char_table['\n']);
}

test "pattern matching basics" {
    // Test literal
    const hello = pattern.Pattern{ .literal = "hello" };
    const hello_result = pattern.matchPattern(hello, "hello world", 0);
    try std.testing.expect(hello_result.matched and hello_result.len == 5);
    const world_result = pattern.matchPattern(hello, "world", 0);
    try std.testing.expect(!world_result.matched);
    
    // Test character class
    const digit = pattern.Pattern{ .char_class = .digit };
    const digit_result = pattern.matchPattern(digit, "123", 0);
    try std.testing.expect(digit_result.matched and digit_result.len == 1);
    const no_digit = pattern.matchPattern(digit, "abc", 0);
    try std.testing.expect(!no_digit.matched);
    
    // Test any_of
    const vowel = pattern.Pattern{ .any_of = "aeiou" };
    const vowel_result = pattern.matchPattern(vowel, "apple", 0);
    try std.testing.expect(vowel_result.matched and vowel_result.len == 1);
    const no_vowel = pattern.matchPattern(vowel, "xyz", 0);
    try std.testing.expect(!no_vowel.matched);
}

test "pattern sequences" {
    const word = pattern.match.word;
    
    const result1 = pattern.matchPattern(word, "hello123", 0);
    try std.testing.expect(result1.matched and result1.len == 5);
    
    const result2 = pattern.matchPattern(word, "123hello", 0);
    try std.testing.expect(!result2.matched);
}

test "token stream basic" {
    const input = "hello 123 world";
    var stream = token_stream.TokenStream.init(input);
    
    const TokenType = enum { word, number, space };
    
    // Define patterns separately
    const alpha_pattern = pattern.match.word;
    const digit_pattern = pattern.match.number;
    const space_pattern = pattern.match.whitespaceOneOrMore();
    
    // First token: "hello"
    const token1 = stream.next(TokenType, .{
        .word = alpha_pattern,
        .number = digit_pattern,
        .space = space_pattern,
    });
    
    try std.testing.expect(token1 != null);
    try std.testing.expectEqual(TokenType.word, token1.?.type);
    try std.testing.expectEqualStrings("hello", token1.?.text);
    
    // Second token: " "
    const token2 = stream.next(TokenType, .{
        .word = alpha_pattern,
        .number = digit_pattern,
        .space = space_pattern,
    });
    
    try std.testing.expect(token2 != null);
    try std.testing.expectEqual(TokenType.space, token2.?.type);
    
    // Third token: "123"
    const token3 = stream.next(TokenType, .{
        .word = alpha_pattern,
        .number = digit_pattern,
        .space = space_pattern,
    });
    
    try std.testing.expect(token3 != null);
    try std.testing.expectEqual(TokenType.number, token3.?.type);
    try std.testing.expectEqualStrings("123", token3.?.text);
}

test "SIMD whitespace detection" {
    const input = "   \t\n  hello";
    const pos = simd_mod.simd.findNextNonWhitespace(input, 0);
    try std.testing.expectEqual(@as(usize, 7), pos);
}

test "JSON tokenizer" {
    const input = 
        \\{"name": "John", "age": 42}
    ;
    
    var tokenizer = json.JsonTokenizer.init(input);
    
    const token1 = tokenizer.next();
    try std.testing.expect(token1 != null);
    try std.testing.expectEqual(json.JsonTokenizer.TokenType.lbrace, token1.?.type);
    
    const token2 = tokenizer.next();
    try std.testing.expect(token2 != null);
    try std.testing.expectEqual(json.JsonTokenizer.TokenType.string, token2.?.type);
    try std.testing.expectEqualStrings("\"name\"", token2.?.text);
}

test "CSV tokenizer" {
    const input = "name,age\nJohn,25";
    var tokenizer = csv.UltraFastCsvTokenizer.init(input, .{});
    
    const token1 = tokenizer.next();
    try std.testing.expect(token1 != null);
    try std.testing.expectEqual(csv.CsvTokenizer.TokenType.field, token1.?.type);
    try std.testing.expectEqualStrings("name", token1.?.text);
    
    const token2 = tokenizer.next();
    try std.testing.expect(token2 != null);
    try std.testing.expectEqual(csv.CsvTokenizer.TokenType.comma, token2.?.type);
}

test "optimized pattern matching" {
    const hello_pattern = pattern.match.literal("hello");
    const result = pattern_optimized.matchPatternOptimized(hello_pattern, "hello world", 0);
    try std.testing.expect(result.matched and result.len == 5);
}

test "fast matcher" {
    // Test exact literal matching
    const literal_match = fast_matcher.FastMatcher.matchLiteral("hello world", 0, "hello");
    try std.testing.expect(literal_match);
    
    // Test pattern matching
    const result = fast_matcher.FastMatcher.match(.{
        .word = pattern.match.alpha.oneOrMore(),
        .number = pattern.match.digit.oneOrMore(),
    }, "hello123", 0);
    try std.testing.expectEqual(@as(?u32, 0), result.pattern_index);
    try std.testing.expectEqual(@as(usize, 5), result.length);
}

test "fuzzing basic" {
    var fuzzer = fuzz_tests.FuzzTester.init(std.testing.allocator, 42);
    const results = try fuzzer.fuzzPatternMatching(10);
    
    try std.testing.expect(results.pattern_tests == 10);
    try std.testing.expect(results.pattern_successes > 0);
}