const std = @import("std");

// Core exports
pub const TokenStream = @import("token_stream.zig").TokenStream;

// Pattern matching
pub const Pattern = @import("pattern.zig").Pattern;
pub const match = @import("pattern.zig").match;
pub const matchPattern = @import("pattern.zig").matchPattern;

// Legacy compatibility - deprecated but kept for old examples
pub const TokenMatcher = struct {
    // Simplified for compatibility
    id: u32 = 0,
};
pub const TokenType = struct {
    id: u32,
    name: []const u8,
};
pub const Token = struct {
    type: TokenType,
    position: struct { offset: usize, line: usize, column: usize },
    lexeme: []const u8,
};

// Character classification (for advanced users)
pub const char_class = @import("char_class.zig");

// Performance components
pub const simd = @import("simd.zig").simd;
pub const RingBuffer = @import("ring_buffer.zig").RingBuffer;
pub const StreamingTokenizer = @import("ring_buffer.zig").StreamingTokenizer;

// Pre-built parsers
pub const json = @import("parsers/json.zig");
pub const csv = @import("parsers/csv.zig");

test "simple parsing" {
    const TestTokenType = enum { word, number, whitespace };
    const patterns = comptime .{
        .word = match.alpha.oneOrMore(),
        .number = match.digit.oneOrMore(),
        .whitespace = match.whitespace.oneOrMore(),
    };
    
    const input = "hello 123 world";
    var stream = TokenStream.init(input);
    
    var count: usize = 0;
    while (stream.next(TestTokenType, patterns)) |token| {
        count += 1;
        if (count == 1) {
            try std.testing.expectEqual(TestTokenType.word, token.type);
            try std.testing.expectEqualStrings("hello", token.text);
        }
    }
    
    try std.testing.expectEqual(@as(usize, 5), count); // hello, space, 123, space, world
}