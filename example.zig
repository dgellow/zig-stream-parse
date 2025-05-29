const std = @import("std");
const zigparse = @import("src/root.zig");

pub fn main() !void {
    // Define token types
    const Token = enum { word, number, punctuation };
    
    // Define patterns
    const patterns = comptime .{
        .word = zigparse.match.alpha.oneOrMore(),
        .number = zigparse.match.digit.oneOrMore(),
        .punctuation = zigparse.match.anyOf(".,!?;:"),
    };
    
    // Input to parse
    const input = "Hello, world! 42 is the answer.";
    
    // Create zero-allocation token stream
    var stream = zigparse.TokenStream.init(input);
    
    // Parse tokens
    std.debug.print("Parsing: '{s}'\n\n", .{input});
    while (stream.next(Token, patterns)) |token| {
        std.debug.print("{s}: '{s}'\n", .{ @tagName(token.type), token.text });
    }
    
    std.debug.print("\nDone! Zero allocations used.\n", .{});
}

// Example showing how to count words without allocations
pub fn countWords(input: []const u8) usize {
    const Token = enum { word, other };
    const patterns = comptime .{
        .word = zigparse.match.alpha.oneOrMore(),
        .other = zigparse.match.any,
    };
    
    var stream = zigparse.TokenStream.init(input);
    var count: usize = 0;
    
    while (stream.next(Token, patterns)) |token| {
        if (token.type == .word) count += 1;
    }
    
    return count;
}

test "word counting" {
    const count = countWords("Hello beautiful world");
    try std.testing.expectEqual(@as(usize, 3), count);
}