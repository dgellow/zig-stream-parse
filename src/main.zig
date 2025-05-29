const std = @import("std");
const zigparse = @import("root.zig");

pub fn main() !void {
    std.debug.print("ZigParse: Zero-Allocation Streaming Parser\n\n", .{});
    
    // Define our token types
    const TokenType = enum { word, number, punct, whitespace };
    
    // Define patterns for each token type
    const patterns = comptime .{
        .word = zigparse.match.alpha.oneOrMore(),
        .number = zigparse.match.digit.oneOrMore(),
        .punct = zigparse.match.anyOf(".,!?;:"),
        .whitespace = zigparse.match.whitespace.oneOrMore(),
    };
    
    // Example input
    const input = "Hello, world! 123 testing: 456.";
    
    // Create a token stream
    var stream = zigparse.TokenStream.init(input);
    
    // Process tokens - zero allocations!
    std.debug.print("Tokens found:\n", .{});
    while (stream.next(TokenType, patterns)) |token| {
        std.debug.print("  {s}: '{s}' at line {d}, column {d}\n", .{
            @tagName(token.type),
            token.text,
            token.line,
            token.column,
        });
    }
    
    std.debug.print("\nParsing complete!\n", .{});
}