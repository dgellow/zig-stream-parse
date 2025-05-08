const std = @import("std");
const testing = std.testing;
const ByteStream = @import("parser").ByteStream;
const Tokenizer = @import("parser").Tokenizer;
const Token = @import("parser").Token;
const TokenType = @import("parser").TokenType;
const TokenMatcher = @import("parser").TokenMatcher;
const Position = @import("parser").Position;
const TokenPool = @import("parser").TokenPool;

// Simple token matchers for testing
fn wordMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    var token_buf = std.ArrayList(u8).init(allocator);
    defer token_buf.deinit();
    
    // Check if first character is a letter
    const first = try stream.peek();
    if (first == null or !std.ascii.isAlphabetic(first.?)) {
        return null;
    }
    
    // Consume letters
    while (true) {
        const byte = try stream.peek();
        if (byte == null or !std.ascii.isAlphabetic(byte.?)) {
            break;
        }
        
        try token_buf.append(byte.?);
        _ = try stream.consume();
    }
    
    // Create token result
    const lexeme = try allocator.dupe(u8, token_buf.items);
    return Token.init(
        TokenType{ .id = 1, .name = "WORD" },
        start_pos,
        lexeme
    );
}

fn numberMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    var token_buf = std.ArrayList(u8).init(allocator);
    defer token_buf.deinit();
    
    // Check if first character is a digit
    const first = try stream.peek();
    if (first == null or !std.ascii.isDigit(first.?)) {
        return null;
    }
    
    // Consume digits
    while (true) {
        const byte = try stream.peek();
        if (byte == null or !std.ascii.isDigit(byte.?)) {
            break;
        }
        
        try token_buf.append(byte.?);
        _ = try stream.consume();
    }
    
    // Create token result
    const lexeme = try allocator.dupe(u8, token_buf.items);
    return Token.init(
        TokenType{ .id = 2, .name = "NUMBER" },
        start_pos,
        lexeme
    );
}

fn whitespaceMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    var token_buf = std.ArrayList(u8).init(allocator);
    defer token_buf.deinit();
    
    // Check if first character is whitespace
    const first = try stream.peek();
    if (first == null or !std.ascii.isWhitespace(first.?)) {
        return null;
    }
    
    // Consume whitespace
    while (true) {
        const byte = try stream.peek();
        if (byte == null or !std.ascii.isWhitespace(byte.?)) {
            break;
        }
        
        try token_buf.append(byte.?);
        _ = try stream.consume();
    }
    
    // Create token result
    const lexeme = try allocator.dupe(u8, token_buf.items);
    return Token.init(
        TokenType{ .id = 3, .name = "WHITESPACE" },
        start_pos,
        lexeme
    );
}

test "Tokenizer with TokenPool" {
    const allocator = testing.allocator;
    
    // Create a byte stream from a string
    const input = "abc 123 def";
    var stream = try ByteStream.init(allocator, input, 4096);
    defer stream.deinit();
    
    // Set up matchers and skip types
    const matchers = [_]TokenMatcher{
        TokenMatcher.init(wordMatcher),
        TokenMatcher.init(numberMatcher),
        TokenMatcher.init(whitespaceMatcher),
    };
    
    const skip_types = [_]TokenType{
        TokenType{ .id = 3, .name = "WHITESPACE" },
    };
    
    // Create a tokenizer with a token pool
    var tokenizer = try Tokenizer.initWithPool(
        allocator,
        &stream,
        &matchers,
        &skip_types,
        256 // Pool size
    );
    defer tokenizer.deinit();
    
    // Verify pool exists and is empty
    try testing.expect(tokenizer.token_pool != null);
    try testing.expect(tokenizer.use_pool);
    try testing.expectEqual(@as(usize, 0), tokenizer.poolUsage().?);
    try testing.expectEqual(@as(usize, 256), tokenizer.poolAvailable().?);
    
    // Parse tokens
    const expected_tokens = [_]struct { id: u32, lexeme: []const u8 }{
        .{ .id = 1, .lexeme = "abc" },
        .{ .id = 2, .lexeme = "123" },
        .{ .id = 1, .lexeme = "def" },
    };
    
    for (expected_tokens) |expected| {
        const token = try tokenizer.nextToken();
        try testing.expect(token != null);
        try testing.expectEqual(expected.id, token.?.type.id);
        try testing.expectEqualStrings(expected.lexeme, token.?.lexeme);
    }
    
    // Verify end of input
    const eof_token = try tokenizer.nextToken();
    try testing.expect(eof_token == null);
    
    // Verify pool has been used
    try testing.expect(tokenizer.poolUsage().? > 0);
    try testing.expect(tokenizer.poolAvailable().? < 256);
    
    // Reset pool
    tokenizer.resetPool();
    try testing.expectEqual(@as(usize, 0), tokenizer.poolUsage().?);
    try testing.expectEqual(@as(usize, 256), tokenizer.poolAvailable().?);
}

test "Tokenizer with and without TokenPool - comparison" {
    const allocator = testing.allocator;
    
    // Create sample input with predictable token count
    var input = std.ArrayList(u8).init(allocator);
    defer input.deinit();
    
    const sample_words = [_][]const u8{ "hello", "world", "testing", "tokens" };
    const sample_numbers = [_][]const u8{ "123", "456", "789", "999" };
    
    for (0..25) |i| {
        const word = sample_words[i % sample_words.len];
        const number = sample_numbers[i % sample_numbers.len];
        
        try input.appendSlice(word);
        try input.append(' ');
        try input.appendSlice(number);
        try input.append(' ');
    }
    
    const input_text = input.items;
    
    // Set up matchers and skip types
    const matchers = [_]TokenMatcher{
        TokenMatcher.init(wordMatcher),
        TokenMatcher.init(numberMatcher),
        TokenMatcher.init(whitespaceMatcher),
    };
    
    const skip_types = [_]TokenType{
        TokenType{ .id = 3, .name = "WHITESPACE" },
    };
    
    // First, use a tokenizer without a pool
    {
        var stream1 = try ByteStream.init(allocator, input_text, 4096);
        defer stream1.deinit();
        
        var tokenizer1 = try Tokenizer.init(
            allocator,
            &stream1,
            &matchers,
            &skip_types
        );
        defer tokenizer1.deinit();
        
        // Count tokens
        var token_count: usize = 0;
        while (try tokenizer1.nextToken()) |_| {
            token_count += 1;
        }
        
        try testing.expectEqual(@as(usize, 50), token_count); // Should be 25 words + 25 numbers
    }
    
    // Now use a tokenizer with a pool
    {
        var stream2 = try ByteStream.init(allocator, input_text, 4096);
        defer stream2.deinit();
        
        var tokenizer2 = try Tokenizer.initWithPool(
            allocator,
            &stream2,
            &matchers,
            &skip_types,
            2048 // Pool size
        );
        defer tokenizer2.deinit();
        
        // Count tokens
        var token_count: usize = 0;
        while (try tokenizer2.nextToken()) |_| {
            token_count += 1;
        }
        
        try testing.expectEqual(@as(usize, 50), token_count); // Should be 25 words + 25 numbers
        
        // Check pool usage
        const usage = tokenizer2.poolUsage().?;
        try testing.expect(usage > 0);
        try testing.expect(usage <= 2048);
    }
}