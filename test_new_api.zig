const std = @import("std");
const zigparse = @import("src/zigparse.zig");

test "comprehensive new API test" {
    // Test 1: Basic tokenization
    {
        const Token = enum { word, number, punct, whitespace };
        const patterns = comptime .{
            .word = zigparse.match.alpha.oneOrMore(),
            .number = zigparse.match.digit.oneOrMore(),
            .punct = zigparse.match.anyOf(".,!?"),
            .whitespace = zigparse.match.whitespace.oneOrMore(),
        };
        
        const input = "Hello 123 world!";
        var stream = zigparse.TokenStream.init(input);
        
        var tokens = std.ArrayList(struct {
            type: Token,
            text: []const u8,
        }).init(std.testing.allocator);
        defer tokens.deinit();
        
        while (stream.next(Token, patterns)) |token| {
            try tokens.append(.{ .type = token.type, .text = token.text });
        }
        
        try std.testing.expectEqual(@as(usize, 4), tokens.items.len);
        try std.testing.expectEqual(Token.word, tokens.items[0].type);
        try std.testing.expectEqualStrings("Hello", tokens.items[0].text);
        try std.testing.expectEqual(Token.number, tokens.items[1].type);
        try std.testing.expectEqualStrings("123", tokens.items[1].text);
    }
    
    // Test 2: JSON tokenization
    {
        const json_input = "{\"name\": \"test\", \"value\": 42}";
        var json_tokenizer = zigparse.json.JsonTokenizer.init(json_input);
        
        var token_count: usize = 0;
        while (json_tokenizer.next()) |token| {
            token_count += 1;
            std.testing.expect(token.text.len > 0) catch unreachable;
        }
        
        try std.testing.expect(token_count > 5); // Should have multiple tokens
    }
    
    // Test 3: SIMD functions
    {
        const input = "   hello world   ";
        const pos = zigparse.simd.findNextNonWhitespace(input, 0);
        try std.testing.expectEqual(@as(usize, 3), pos);
        try std.testing.expectEqual(@as(u8, 'h'), input[pos]);
    }
    
    // Test 4: Streaming with ring buffer
    {
        const Token = enum { word, number };
        const patterns = comptime .{
            .word = zigparse.match.alpha.oneOrMore(),
            .number = zigparse.match.digit.oneOrMore(),
        };
        
        const input = "word1 word2 123 456";
        var stream_source = std.io.fixedBufferStream(input);
        var tokenizer = try zigparse.StreamingTokenizer.init(std.testing.allocator, 8); // Small buffer
        defer tokenizer.deinit();
        
        var count: usize = 0;
        while (try tokenizer.next(stream_source.reader(), Token, patterns)) |_| {
            count += 1;
        }
        
        try std.testing.expect(count > 0);
    }
    
    std.debug.print("✅ All new API tests passed!\n", .{});
}