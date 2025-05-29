const std = @import("std");

// Core exports
pub const TokenStream = @import("token_stream.zig").TokenStream;
pub const Token = @import("token_stream.zig").Token;

// Pattern matching
pub const Pattern = @import("pattern.zig").Pattern;
pub const match = @import("pattern.zig").match;
pub const matchPattern = @import("pattern.zig").matchPattern;

// Character classification (for advanced users)
pub const char_class = @import("char_class.zig");

// Performance components
pub const simd = @import("simd.zig").simd;
pub const RingBuffer = @import("ring_buffer.zig").RingBuffer;
pub const StreamingTokenizer = @import("ring_buffer.zig").StreamingTokenizer;

// Pre-built parsers
pub const json = @import("parsers/json.zig");

test "simple parsing" {
    const TokenType = enum { word, number, whitespace };
    const patterns = comptime .{
        .word = match.alpha.oneOrMore(),
        .number = match.digit.oneOrMore(),
        .whitespace = match.whitespace.oneOrMore(),
    };
    
    const input = "hello 123 world";
    var stream = TokenStream.init(input);
    
    var count: usize = 0;
    while (stream.next(TokenType, patterns)) |token| {
        count += 1;
        if (count == 1) {
            try std.testing.expectEqual(TokenType.word, token.type);
            try std.testing.expectEqualStrings("hello", token.text);
        }
    }
    
    try std.testing.expectEqual(@as(usize, 3), count);
}