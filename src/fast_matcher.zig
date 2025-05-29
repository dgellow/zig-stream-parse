const std = @import("std");
const Pattern = @import("pattern.zig").Pattern;
const char_class = @import("char_class.zig");
const pattern_optimized = @import("pattern_optimized.zig");

/// Ultra-fast pattern matcher with specialized fast paths
/// This is a runtime-optimized version that avoids complex compile-time analysis
pub const FastMatcher = struct {
    /// Match result
    pub const MatchResult = struct {
        pattern_index: ?u32,
        length: usize,
    };
    
    /// Match patterns against input with maximum performance
    pub fn match(comptime patterns: anytype, input: []const u8, start_pos: usize) MatchResult {
        if (start_pos >= input.len) return .{ .pattern_index = null, .length = 0 };
        
        // Try each pattern in order using optimized matching
        inline for (@typeInfo(@TypeOf(patterns)).@"struct".fields, 0..) |field, i| {
            const pattern = @field(patterns, field.name);
            
            // Use highly optimized pattern matching
            const result = pattern_optimized.matchPatternOptimized(pattern, input, start_pos);
            
            if (result.matched and result.len > 0) {
                return .{ .pattern_index = i, .length = result.len };
            }
        }
        
        return .{ .pattern_index = null, .length = 0 };
    }
    
    /// Specialized single character matching for ultra performance
    pub fn matchSingleChar(input: []const u8, pos: usize, expected: u8) bool {
        return pos < input.len and input[pos] == expected;
    }
    
    /// Specialized literal matching with length-based optimization
    pub fn matchLiteral(input: []const u8, pos: usize, literal: []const u8) bool {
        if (pos + literal.len > input.len) return false;
        
        return switch (literal.len) {
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
            8 => blk: {
                // Use 64-bit comparison for 8-byte literals
                const input_word = std.mem.readInt(u64, input[pos..][0..8], .little);
                const literal_word = std.mem.readInt(u64, literal[0..8], .little);
                break :blk input_word == literal_word;
            },
            else => std.mem.eql(u8, input[pos..pos + literal.len], literal),
        };
    }
    
    /// Specialized character class matching using lookup table
    pub fn matchCharClass(input: []const u8, pos: usize, class: char_class.CharClass) bool {
        return pos < input.len and char_class.char_table[input[pos]] == class;
    }
    
    /// Specialized repeated character class matching (for one_or_more patterns)
    pub fn matchCharClassRepeated(input: []const u8, pos: usize, class: char_class.CharClass) usize {
        var end_pos = pos;
        while (end_pos < input.len and char_class.char_table[input[end_pos]] == class) {
            end_pos += 1;
        }
        return end_pos - pos;
    }
    
    /// Specialized any-of matching with unrolled loops for small sets
    pub fn matchAnyOf(input: []const u8, pos: usize, chars: []const u8) bool {
        if (pos >= input.len) return false;
        
        const c = input[pos];
        
        return switch (chars.len) {
            0 => false,
            1 => c == chars[0],
            2 => c == chars[0] or c == chars[1],
            3 => c == chars[0] or c == chars[1] or c == chars[2],
            4 => c == chars[0] or c == chars[1] or c == chars[2] or c == chars[3],
            5 => c == chars[0] or c == chars[1] or c == chars[2] or c == chars[3] or c == chars[4],
            6 => c == chars[0] or c == chars[1] or c == chars[2] or c == chars[3] or c == chars[4] or c == chars[5],
            else => blk: {
                // Linear search for larger sets (could be optimized with lookup table)
                for (chars) |char| {
                    if (c == char) break :blk true;
                }
                break :blk false;
            },
        };
    }
};

/// Ultra-fast tokenizer using the fast matcher
pub fn UltraFastTokenizer(comptime TokenType: type, comptime patterns: anytype) type {
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
                const result = FastMatcher.match(patterns, self.input, start_pos);
                
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

test "fast matcher literal tests" {
    const patterns = .{
        .hello = Pattern{ .literal = "hello" },
        .world = Pattern{ .literal = "world" },
        .space = Pattern{ .literal = " " },
    };
    
    // Test "hello"
    const result1 = FastMatcher.match(patterns, "hello world", 0);
    try std.testing.expect(result1.pattern_index != null);
    try std.testing.expectEqual(@as(u32, 0), result1.pattern_index.?);
    try std.testing.expectEqual(@as(usize, 5), result1.length);
    
    // Test "world"
    const result2 = FastMatcher.match(patterns, "hello world", 6);
    try std.testing.expect(result2.pattern_index != null);
    try std.testing.expectEqual(@as(u32, 1), result2.pattern_index.?);
    try std.testing.expectEqual(@as(usize, 5), result2.length);
    
    // Test " " (space)
    const result3 = FastMatcher.match(patterns, "hello world", 5);
    try std.testing.expect(result3.pattern_index != null);
    try std.testing.expectEqual(@as(u32, 2), result3.pattern_index.?);
    try std.testing.expectEqual(@as(usize, 1), result3.length);
}

test "fast matcher character class tests" {
    const patterns = .{
        .digit = Pattern{ .char_class = .digit },
        .alpha = Pattern{ .char_class = .alpha_lower },
        .upper = Pattern{ .char_class = .alpha_upper },
    };
    
    // Test digit
    const result1 = FastMatcher.match(patterns, "123abc", 0);
    try std.testing.expect(result1.pattern_index != null);
    try std.testing.expectEqual(@as(u32, 0), result1.pattern_index.?);
    try std.testing.expectEqual(@as(usize, 1), result1.length);
    
    // Test lowercase alpha
    const result2 = FastMatcher.match(patterns, "abc123", 0);
    try std.testing.expect(result2.pattern_index != null);
    try std.testing.expectEqual(@as(u32, 1), result2.pattern_index.?);
    try std.testing.expectEqual(@as(usize, 1), result2.length);
    
    // Test uppercase alpha
    const result3 = FastMatcher.match(patterns, "ABC123", 0);
    try std.testing.expect(result3.pattern_index != null);
    try std.testing.expectEqual(@as(u32, 2), result3.pattern_index.?);
    try std.testing.expectEqual(@as(usize, 1), result3.length);
}

test "ultra fast tokenizer" {
    const TokenType = enum { word, number, space };
    const word_pattern = Pattern{ .char_class = .alpha_lower };
    const number_pattern = Pattern{ .char_class = .digit };
    const Tokenizer = UltraFastTokenizer(TokenType, .{
        .word = word_pattern.oneOrMore(),
        .number = number_pattern.oneOrMore(),
        .space = Pattern{ .literal = " " },
    });
    
    const input = "hello 123 world";
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
    
    // Should find space token
    const token4 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.space, token4.type);
    try std.testing.expectEqualStrings(" ", token4.text);
    
    // Should find word token
    const token5 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.word, token5.type);
    try std.testing.expectEqualStrings("world", token5.text);
    
    // Should be at end
    try std.testing.expect(tokenizer.next() == null);
}

test "specialized matching functions" {
    // Test single character matching
    try std.testing.expect(FastMatcher.matchSingleChar("hello", 0, 'h'));
    try std.testing.expect(!FastMatcher.matchSingleChar("hello", 0, 'x'));
    
    // Test literal matching
    try std.testing.expect(FastMatcher.matchLiteral("hello world", 0, "hello"));
    try std.testing.expect(FastMatcher.matchLiteral("hello world", 6, "world"));
    try std.testing.expect(!FastMatcher.matchLiteral("hello world", 0, "world"));
    
    // Test character class matching
    try std.testing.expect(FastMatcher.matchCharClass("123", 0, .digit));
    try std.testing.expect(FastMatcher.matchCharClass("abc", 0, .alpha_lower));
    try std.testing.expect(!FastMatcher.matchCharClass("123", 0, .alpha_lower));
    
    // Test repeated character class matching
    try std.testing.expectEqual(@as(usize, 3), FastMatcher.matchCharClassRepeated("123abc", 0, .digit));
    try std.testing.expectEqual(@as(usize, 3), FastMatcher.matchCharClassRepeated("abc123", 0, .alpha_lower));
    try std.testing.expectEqual(@as(usize, 0), FastMatcher.matchCharClassRepeated("123abc", 0, .alpha_lower));
    
    // Test any-of matching
    try std.testing.expect(FastMatcher.matchAnyOf("apple", 0, "aeiou")); // 'a' is in vowels
    try std.testing.expect(FastMatcher.matchAnyOf("world", 1, "aeiou")); // 'o' is in vowels
    try std.testing.expect(!FastMatcher.matchAnyOf("xyz", 0, "aeiou")); // 'x' is not in vowels
}