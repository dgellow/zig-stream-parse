const std = @import("std");
const zigparse = @import("zigparse");

pub fn main() !void {
    // Example 1: Basic tokenization
    {
        std.debug.print("=== Example 1: Basic Tokenization ===\n", .{});
        
        const Token = enum { word, number, whitespace };
        const patterns = .{
            .word = zigparse.match.alpha.oneOrMore(),
            .number = zigparse.match.digit.oneOrMore(),
            .whitespace = zigparse.match.whitespace.oneOrMore(),
        };
        
        const input = "hello 123 world 456";
        var stream = zigparse.TokenStream.init(input);
        
        while (stream.next(&patterns)) |token| {
            std.debug.print("{s}: '{s}'\n", .{ @tagName(token.type), token.text });
        }
    }
    
    std.debug.print("\n", .{});
    
    // Example 2: Using Parser helper
    {
        std.debug.print("=== Example 2: Parser Helper ===\n", .{});
        
        const MyParser = zigparse.Parser(.{
            .tokens = enum { identifier, number, operator, whitespace },
            .patterns = .{
                .identifier = zigparse.match.alpha.oneOrMore(),
                .number = zigparse.match.digit.oneOrMore(),
                .operator = zigparse.match.anyOf("+-*/="),
                .whitespace = zigparse.match.whitespace.oneOrMore(),
            },
            .skip = .{.whitespace},
        });
        
        const input = "x = 42 + y * 3";
        
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        
        var result = try MyParser.parse(gpa.allocator(), input);
        defer result.deinit();
        
        for (result.tokens.items) |token| {
            std.debug.print("{s}: '{s}'\n", .{ @tagName(token.type), token.text });
        }
    }
    
    std.debug.print("\n", .{});
    
    // Example 3: Custom patterns
    {
        std.debug.print("=== Example 3: Custom Patterns ===\n", .{});
        
        const Token = enum { string, number, boolean, null };
        const patterns = .{
            .string = zigparse.match.quoted('"'),
            .number = zigparse.match.digit.oneOrMore(),
            .boolean = zigparse.Pattern{ .any_of = "tf" },  // simplified
            .null = zigparse.match.literal("null"),
        };
        
        const input = "\"hello\" 123 true null";
        var stream = zigparse.TokenStreamWithWhitespace.init(input);
        
        while (!stream.isAtEnd()) {
            if (stream.next(&patterns)) |token| {
                if (token.type != .unknown) {
                    std.debug.print("{s}: '{s}'\n", .{ @tagName(token.type), token.text });
                }
            }
        }
    }
}