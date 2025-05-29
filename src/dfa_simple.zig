const std = @import("std");
const Pattern = @import("pattern.zig").Pattern;
const char_class = @import("char_class.zig");

/// Simplified DFA-style fast pattern matcher
/// Uses lookup tables and specialized matchers for maximum performance
pub fn FastMatcher(comptime patterns: anytype) type {
    // Analyze patterns at compile time to generate optimized matchers
    const pattern_info = comptime analyzePatterns(patterns);
    
    return struct {
        pub const MatchResult = struct {
            pattern_index: ?u32,
            length: usize,
        };
        
        /// Ultra-fast pattern matching using specialized strategies
        pub fn match(input: []const u8, start_pos: usize) MatchResult {
            if (start_pos >= input.len) return .{ .pattern_index = null, .length = 0 };
            
            // Try each pattern in order with specialized matchers
            inline for (pattern_info, 0..) |info, i| {
                const result = switch (info.type) {
                    .single_char => matchSingleChar(input, start_pos, info.data.single_char),
                    .literal => matchLiteral(input, start_pos, info.data.literal),
                    .char_class => matchCharClass(input, start_pos, info.data.char_class),
                    .char_class_repeated => matchCharClassRepeated(input, start_pos, info.data.char_class_repeated),
                    .any_of => matchAnyOf(input, start_pos, info.data.any_of),
                };
                
                if (result.matched) {
                    return .{ .pattern_index = i, .length = result.length };
                }
            }
            
            return .{ .pattern_index = null, .length = 0 };
        }
    };
}

/// Pattern analysis result
const PatternInfo = struct {
    type: PatternType,
    data: PatternData,
};

const PatternType = enum {
    single_char,
    literal,
    char_class,
    char_class_repeated,
    any_of,
};

const PatternData = union(PatternType) {
    single_char: u8,
    literal: []const u8,
    char_class: char_class.CharClass,
    char_class_repeated: char_class.CharClass,
    any_of: []const u8,
};

/// Analyze patterns at compile time
fn analyzePatterns(comptime patterns: anytype) []const PatternInfo {
    const fields = @typeInfo(@TypeOf(patterns)).@"struct".fields;
    var pattern_infos: [fields.len]PatternInfo = undefined;
    
    inline for (fields, 0..) |field, i| {
        const pattern = @field(patterns, field.name);
        pattern_infos[i] = analyzePattern(pattern);
    }
    
    return &pattern_infos;
}

/// Analyze a single pattern
fn analyzePattern(comptime pattern: Pattern) PatternInfo {
    return switch (pattern) {
        .literal => |lit| blk: {
            if (lit.len == 1) {
                break :blk .{ .type = .single_char, .data = .{ .single_char = lit[0] } };
            } else {
                break :blk .{ .type = .literal, .data = .{ .literal = lit } };
            }
        },
        .char_class => |class| .{ .type = .char_class, .data = .{ .char_class = class } },
        .one_or_more => |sub| switch (sub.*) {
            .char_class => |class| .{ .type = .char_class_repeated, .data = .{ .char_class_repeated = class } },
            else => .{ .type = .char_class, .data = .{ .char_class = .other } }, // Fallback
        },
        .any_of => |chars| .{ .type = .any_of, .data = .{ .any_of = chars } },
        else => .{ .type = .char_class, .data = .{ .char_class = .other } }, // Fallback
    };
}

/// Match result for internal use
const InternalMatchResult = struct {
    matched: bool,
    length: usize,
};

/// Ultra-fast single character matching
fn matchSingleChar(input: []const u8, pos: usize, expected: u8) InternalMatchResult {
    if (pos >= input.len) return .{ .matched = false, .length = 0 };
    return .{ .matched = input[pos] == expected, .length = if (input[pos] == expected) 1 else 0 };
}

/// Optimized literal matching
fn matchLiteral(input: []const u8, pos: usize, literal: []const u8) InternalMatchResult {
    if (pos + literal.len > input.len) return .{ .matched = false, .length = 0 };
    
    // Use different strategies based on literal length
    const matched = switch (literal.len) {
        0 => true,
        1 => input[pos] == literal[0],
        2 => input[pos] == literal[0] and input[pos + 1] == literal[1],
        3 => input[pos] == literal[0] and input[pos + 1] == literal[1] and input[pos + 2] == literal[2],
        4 => blk: {
            // Use 32-bit comparison for 4-byte literals
            const input_word = std.mem.readInt(u32, input[pos..][0..4], .little);
            const literal_word = std.mem.readInt(u32, literal[0..4], .little);
            break :blk input_word == literal_word;
        },
        else => std.mem.eql(u8, input[pos..pos + literal.len], literal),
    };
    
    return .{ .matched = matched, .length = if (matched) literal.len else 0 };
}

/// Fast character class matching using lookup table
fn matchCharClass(input: []const u8, pos: usize, class: char_class.CharClass) InternalMatchResult {
    if (pos >= input.len) return .{ .matched = false, .length = 0 };
    
    const c = input[pos];
    const matched = char_class.char_table[c] == class;
    return .{ .matched = matched, .length = if (matched) 1 else 0 };
}

/// Fast repeated character class matching (one or more)
fn matchCharClassRepeated(input: []const u8, pos: usize, class: char_class.CharClass) InternalMatchResult {
    if (pos >= input.len) return .{ .matched = false, .length = 0 };
    
    var end_pos = pos;
    while (end_pos < input.len and char_class.char_table[input[end_pos]] == class) {
        end_pos += 1;
    }
    
    const length = end_pos - pos;
    return .{ .matched = length > 0, .length = length };
}

/// Fast any-of matching with different strategies
fn matchAnyOf(input: []const u8, pos: usize, chars: []const u8) InternalMatchResult {
    if (pos >= input.len) return .{ .matched = false, .length = 0 };
    
    const c = input[pos];
    
    // Use different strategies based on character set size
    const matched = switch (chars.len) {
        0 => false,
        1 => c == chars[0],
        2 => c == chars[0] or c == chars[1],
        3 => c == chars[0] or c == chars[1] or c == chars[2],
        4 => c == chars[0] or c == chars[1] or c == chars[2] or c == chars[3],
        else => blk: {
            // Use lookup table for larger sets
            for (chars) |char| {
                if (c == char) break :blk true;
            }
            break :blk false;
        },
    };
    
    return .{ .matched = matched, .length = if (matched) 1 else 0 };
}

/// Ultra-fast tokenizer using the fast matcher
pub fn FastTokenizer(comptime TokenType: type, comptime patterns: anytype) type {
    const Matcher = FastMatcher(patterns);
    
    return struct {
        input: []const u8,
        pos: usize = 0,
        line: usize = 1,
        column: usize = 1,
        
        const Self = @This();
        
        pub fn init(input: []const u8) Self {
            return .{ .input = input };
        }
        
        pub fn next(self: *Self) ?struct {
            type: TokenType,
            text: []const u8,
            line: usize,
            column: usize,
        } {
            while (self.pos < self.input.len) {
                const start_pos = self.pos;
                const start_line = self.line;
                const start_column = self.column;
                
                // Use fast matcher
                const result = Matcher.match(self.input, start_pos);
                
                if (result.pattern_index) |pattern_idx| {
                    const token_type = getTokenTypeFromIndex(TokenType, pattern_idx);
                    const token_text = self.input[start_pos..start_pos + result.length];
                    
                    self.pos = start_pos + result.length;
                    self.updatePosition(token_text);
                    
                    return .{
                        .type = token_type,
                        .text = token_text,
                        .line = start_line,
                        .column = start_column,
                    };
                }
                
                // No pattern matched - skip character
                self.pos += 1;
                if (self.input[start_pos] == '\n') {
                    self.line += 1;
                    self.column = 1;
                } else {
                    self.column += 1;
                }
            }
            
            return null;
        }
        
        fn updatePosition(self: *Self, text: []const u8) void {
            for (text) |c| {
                if (c == '\n') {
                    self.line += 1;
                    self.column = 1;
                } else {
                    self.column += 1;
                }
            }
        }
        
        pub fn remaining(self: *const Self) []const u8 {
            return self.input[self.pos..];
        }
        
        pub fn isAtEnd(self: *const Self) bool {
            return self.pos >= self.input.len;
        }
    };
}

/// Map pattern index to token type
fn getTokenTypeFromIndex(comptime TokenType: type, index: u32) TokenType {
    const fields = @typeInfo(TokenType).@"enum".fields;
    if (index < fields.len) {
        return @enumFromInt(index);
    }
    return @enumFromInt(0); // Default to first enum value
}

test "fast matcher literal" {
    const patterns = .{
        .hello = Pattern{ .literal = "hello" },
        .world = Pattern{ .literal = "world" },
    };
    
    const Matcher = FastMatcher(patterns);
    
    // Test "hello"
    const result1 = Matcher.match("hello world", 0);
    try std.testing.expect(result1.pattern_index != null);
    try std.testing.expectEqual(@as(u32, 0), result1.pattern_index.?);
    try std.testing.expectEqual(@as(usize, 5), result1.length);
    
    // Test "world"
    const result2 = Matcher.match("hello world", 6);
    try std.testing.expect(result2.pattern_index != null);
    try std.testing.expectEqual(@as(u32, 1), result2.pattern_index.?);
    try std.testing.expectEqual(@as(usize, 5), result2.length);
}

test "fast matcher character class" {
    const patterns = .{
        .digit = Pattern{ .char_class = .digit },
        .alpha = Pattern{ .char_class = .alpha_lower },
    };
    
    const Matcher = FastMatcher(patterns);
    
    // Test digit
    const result1 = Matcher.match("123", 0);
    try std.testing.expect(result1.pattern_index != null);
    try std.testing.expectEqual(@as(u32, 0), result1.pattern_index.?);
    try std.testing.expectEqual(@as(usize, 1), result1.length);
    
    // Test alpha
    const result2 = Matcher.match("abc", 0);
    try std.testing.expect(result2.pattern_index != null);
    try std.testing.expectEqual(@as(u32, 1), result2.pattern_index.?);
    try std.testing.expectEqual(@as(usize, 1), result2.length);
}

test "fast tokenizer" {
    const TokenType = enum { word, number, space };
    const word_pattern = Pattern{ .char_class = .alpha_lower };
    const number_pattern = Pattern{ .char_class = .digit };
    const patterns = .{
        .word = word_pattern.oneOrMore(),
        .number = number_pattern.oneOrMore(),
        .space = Pattern{ .literal = " " },
    };
    
    const Tokenizer = FastTokenizer(TokenType, patterns);
    
    const input = "hello 123";
    var tokenizer = Tokenizer.init(input);
    
    // Should find word token
    const token1 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.word, token1.type);
    try std.testing.expectEqualStrings("hello", token1.text);
    
    // Should find space token
    const token2 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.space, token2.type);
    try std.testing.expectEqualStrings(" ", token2.text);
    
    // Should find number token
    const token3 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.number, token3.type);
    try std.testing.expectEqualStrings("123", token3.text);
    
    // Should be at end
    try std.testing.expect(tokenizer.next() == null);
}

test "fast matcher performance patterns" {
    const digit_pattern = Pattern{ .char_class = .digit };
    const letter_pattern = Pattern{ .char_class = .alpha_lower };
    const patterns = .{
        .single = Pattern{ .literal = "a" },
        .double = Pattern{ .literal = "ab" },
        .triple = Pattern{ .literal = "abc" },
        .quad = Pattern{ .literal = "abcd" },
        .long = Pattern{ .literal = "abcdefgh" },
        .digits = digit_pattern.oneOrMore(),
        .letters = letter_pattern.oneOrMore(),
        .vowels = Pattern{ .any_of = "aeiou" },
    };
    
    const Matcher = FastMatcher(patterns);
    
    // Test various inputs
    const inputs = [_][]const u8{
        "a", "ab", "abc", "abcd", "abcdefgh",
        "123", "hello", "e",
    };
    
    for (inputs) |input| {
        const result = Matcher.match(input, 0);
        try std.testing.expect(result.pattern_index != null);
        try std.testing.expect(result.length > 0);
    }
}