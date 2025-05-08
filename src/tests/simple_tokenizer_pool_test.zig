const std = @import("std");
const testing = std.testing;
const ByteStream = @import("parser").ByteStream;
const TokenPool = @import("parser").TokenPool;
const Position = @import("parser").Position;

// Simplified Token implementation for testing
const TokenType = enum {
    WORD,
    NUMBER,
    WHITESPACE,
    ERROR,
};

const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    owned: bool, // Whether we own the memory
    
    fn deinit(self: Token, allocator: std.mem.Allocator) void {
        if (self.owned) {
            allocator.free(self.lexeme);
        }
    }
};

// Simplified tokenizer that uses a pool directly
const Tokenizer = struct {
    allocator: std.mem.Allocator,
    stream: *ByteStream,
    pool: ?*TokenPool,
    buffer: std.ArrayList(u8),
    
    pub fn init(allocator: std.mem.Allocator, stream: *ByteStream) Tokenizer {
        return .{
            .allocator = allocator,
            .stream = stream,
            .pool = null,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }
    
    pub fn initWithPool(allocator: std.mem.Allocator, stream: *ByteStream, pool: *TokenPool) Tokenizer {
        return .{
            .allocator = allocator,
            .stream = stream,
            .pool = pool,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *Tokenizer) void {
        self.buffer.deinit();
    }
    
    fn tokenizeWord(self: *Tokenizer) !?Token {
        // Clear the buffer
        self.buffer.clearRetainingCapacity();
        
        // Check first character is a letter
        const first = try self.stream.peek();
        if (first == null or !std.ascii.isAlphabetic(first.?)) {
            return null;
        }
        
        // Consume letters
        while (true) {
            const byte = try self.stream.peek();
            if (byte == null or !std.ascii.isAlphabetic(byte.?)) {
                break;
            }
            
            try self.buffer.append(byte.?);
            _ = try self.stream.consume();
        }
        
        // Copy the lexeme from buffer - either using pool or allocator
        if (self.pool) |pool| {
            const lexeme = try pool.dupe(self.buffer.items);
            return Token{
                .type = .WORD,
                .lexeme = lexeme,
                .owned = false, // Pool-allocated memory is not owned by token
            };
        } else {
            const lexeme = try self.allocator.dupe(u8, self.buffer.items);
            return Token{
                .type = .WORD,
                .lexeme = lexeme,
                .owned = true, // We own the memory and need to free it
            };
        }
    }
    
    fn tokenizeNumber(self: *Tokenizer) !?Token {
        // Clear the buffer
        self.buffer.clearRetainingCapacity();
        
        // Check first character is a digit
        const first = try self.stream.peek();
        if (first == null or !std.ascii.isDigit(first.?)) {
            return null;
        }
        
        // Consume digits
        while (true) {
            const byte = try self.stream.peek();
            if (byte == null or !std.ascii.isDigit(byte.?)) {
                break;
            }
            
            try self.buffer.append(byte.?);
            _ = try self.stream.consume();
        }
        
        // Copy the lexeme from buffer - either using pool or allocator
        if (self.pool) |pool| {
            const lexeme = try pool.dupe(self.buffer.items);
            return Token{
                .type = .NUMBER,
                .lexeme = lexeme,
                .owned = false, // Pool-allocated memory is not owned by token
            };
        } else {
            const lexeme = try self.allocator.dupe(u8, self.buffer.items);
            return Token{
                .type = .NUMBER,
                .lexeme = lexeme,
                .owned = true, // We own the memory and need to free it
            };
        }
    }
    
    fn tokenizeWhitespace(self: *Tokenizer) !?Token {
        // Clear the buffer
        self.buffer.clearRetainingCapacity();
        
        // Check first character is whitespace
        const first = try self.stream.peek();
        if (first == null or !std.ascii.isWhitespace(first.?)) {
            return null;
        }
        
        // Consume whitespace
        while (true) {
            const byte = try self.stream.peek();
            if (byte == null or !std.ascii.isWhitespace(byte.?)) {
                break;
            }
            
            try self.buffer.append(byte.?);
            _ = try self.stream.consume();
        }
        
        // Copy the lexeme from buffer - either using pool or allocator
        if (self.pool) |pool| {
            const lexeme = try pool.dupe(self.buffer.items);
            return Token{
                .type = .WHITESPACE,
                .lexeme = lexeme,
                .owned = false, // Pool-allocated memory is not owned by token
            };
        } else {
            const lexeme = try self.allocator.dupe(u8, self.buffer.items);
            return Token{
                .type = .WHITESPACE,
                .lexeme = lexeme,
                .owned = true, // We own the memory and need to free it
            };
        }
    }
    
    pub fn nextToken(self: *Tokenizer) !?Token {
        // Try to tokenize each token type
        if (try self.tokenizeWord()) |token| {
            return token;
        }
        
        if (try self.tokenizeNumber()) |token| {
            return token;
        }
        
        if (try self.tokenizeWhitespace()) |token| {
            return token;
        }
        
        // Check if at EOF
        const next_byte = try self.stream.peek();
        if (next_byte == null) {
            return null; // EOF
        }
        
        // Unknown character, treat as error
        _ = try self.stream.consume();
        self.buffer.clearRetainingCapacity();
        try self.buffer.append(next_byte.?);
        
        // Copy the error lexeme
        if (self.pool) |pool| {
            const lexeme = try pool.dupe(self.buffer.items);
            return Token{
                .type = .ERROR,
                .lexeme = lexeme,
                .owned = false, // Pool-allocated memory is not owned by token
            };
        } else {
            const lexeme = try self.allocator.dupe(u8, self.buffer.items);
            return Token{
                .type = .ERROR,
                .lexeme = lexeme,
                .owned = true, // We own the memory and need to free it
            };
        }
    }
};

test "Simple TokenPool with Tokenizer" {
    const allocator = testing.allocator;
    
    // Create a test input
    const input = "hello 123 world";
    var stream = try ByteStream.init(allocator, input, 1024);
    defer stream.deinit();
    
    // Create a token pool
    var pool = try TokenPool.init(allocator, 256);
    defer pool.deinit();
    
    // Create a tokenizer with the pool
    var tokenizer = Tokenizer.initWithPool(allocator, &stream, &pool);
    defer tokenizer.deinit();
    
    // Parse all tokens
    {
        const token1 = try tokenizer.nextToken();
        try testing.expect(token1 != null);
        try testing.expectEqual(TokenType.WORD, token1.?.type);
        try testing.expectEqualStrings("hello", token1.?.lexeme);
        
        const token2 = try tokenizer.nextToken();
        try testing.expect(token2 != null);
        try testing.expectEqual(TokenType.WHITESPACE, token2.?.type);
        try testing.expectEqualStrings(" ", token2.?.lexeme);
        
        const token3 = try tokenizer.nextToken();
        try testing.expect(token3 != null);
        try testing.expectEqual(TokenType.NUMBER, token3.?.type);
        try testing.expectEqualStrings("123", token3.?.lexeme);
        
        const token4 = try tokenizer.nextToken();
        try testing.expect(token4 != null);
        try testing.expectEqual(TokenType.WHITESPACE, token4.?.type);
        try testing.expectEqualStrings(" ", token4.?.lexeme);
        
        const token5 = try tokenizer.nextToken();
        try testing.expect(token5 != null);
        try testing.expectEqual(TokenType.WORD, token5.?.type);
        try testing.expectEqualStrings("world", token5.?.lexeme);
        
        const token6 = try tokenizer.nextToken();
        try testing.expect(token6 == null); // EOF
    }
    
    // Check pool usage
    try testing.expect(pool.used() > 0);
    try testing.expect(pool.used() <= 256);
}

test "Simple Tokenizer with and without pool - comparison" {
    const allocator = testing.allocator;
    
    // Create sample input
    const input = "hello 123 world 456 test 789";
    
    // First try without pool
    {
        var stream = try ByteStream.init(allocator, input, 1024);
        defer stream.deinit();
        
        var tokenizer = Tokenizer.init(allocator, &stream);
        defer tokenizer.deinit();
        
        var token_count: usize = 0;
        while (true) {
            const token_opt = try tokenizer.nextToken();
            if (token_opt == null) break;
            
            var token = token_opt.?;
            defer token.deinit(allocator); // Clean up token memory
            
            token_count += 1;
        }
        
        try testing.expectEqual(@as(usize, 11), token_count); // 6 tokens + 5 whitespace
    }
    
    // Now with pool
    {
        var stream = try ByteStream.init(allocator, input, 1024);
        defer stream.deinit();
        
        var pool = try TokenPool.init(allocator, 256);
        defer pool.deinit();
        
        var tokenizer = Tokenizer.initWithPool(allocator, &stream, &pool);
        defer tokenizer.deinit();
        
        var token_count: usize = 0;
        while (true) {
            const token_opt = try tokenizer.nextToken();
            if (token_opt == null) break;
            
            var token = token_opt.?;
            defer token.deinit(allocator); // Clean up token memory if needed
            
            token_count += 1;
        }
        
        try testing.expectEqual(@as(usize, 11), token_count); // 6 tokens + 5 whitespace
        
        // Check pool usage
        try testing.expect(pool.used() > 0);
        try testing.expect(pool.used() <= 256);
    }
}