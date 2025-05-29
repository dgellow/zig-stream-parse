const std = @import("std");

/// Simple high-performance CSV tokenizer for testing
pub const SimpleCsvTokenizer = struct {
    pub const TokenType = enum {
        field,
        quoted_field,
        comma,
        newline,
        eof,
    };
    
    input: []const u8,
    pos: usize = 0,
    line: usize = 1,
    column: usize = 1,
    
    pub fn init(input: []const u8) SimpleCsvTokenizer {
        return .{ .input = input };
    }
    
    pub const Token = struct {
        type: TokenType,
        text: []const u8,
        line: usize,
        column: usize,
    };
    
    pub fn next(self: *SimpleCsvTokenizer) ?Token {
        if (self.pos >= self.input.len) {
            return Token{
                .type = .eof,
                .text = "",
                .line = self.line,
                .column = self.column,
            };
        }
        
        const start_line = self.line;
        const start_column = self.column;
        const start_pos = self.pos;
        
        const c = self.input[self.pos];
        
        // Handle comma
        if (c == ',') {
            self.pos += 1;
            self.column += 1;
            return Token{
                .type = .comma,
                .text = self.input[start_pos..self.pos],
                .line = start_line,
                .column = start_column,
            };
        }
        
        // Handle newline
        if (c == '\n') {
            self.pos += 1;
            self.line += 1;
            self.column = 1;
            return Token{
                .type = .newline,
                .text = self.input[start_pos..self.pos],
                .line = start_line,
                .column = start_column,
            };
        }
        
        // Handle quoted field
        if (c == '"') {
            return self.parseQuoted();
        }
        
        // Handle regular field
        return self.parseField();
    }
    
    fn parseQuoted(self: *SimpleCsvTokenizer) Token {
        const start_pos = self.pos;
        const start_line = self.line;
        const start_column = self.column;
        
        self.pos += 1; // Skip opening quote
        self.column += 1;
        
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            
            if (c == '"') {
                self.pos += 1;
                self.column += 1;
                
                // Check for escaped quote
                if (self.pos < self.input.len and self.input[self.pos] == '"') {
                    self.pos += 1;
                    self.column += 1;
                    continue;
                }
                break;
            }
            
            if (c == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            self.pos += 1;
        }
        
        return Token{
            .type = .quoted_field,
            .text = self.input[start_pos..self.pos],
            .line = start_line,
            .column = start_column,
        };
    }
    
    fn parseField(self: *SimpleCsvTokenizer) Token {
        const start_pos = self.pos;
        const start_line = self.line;
        const start_column = self.column;
        
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            
            if (c == ',' or c == '\n' or c == '"') {
                break;
            }
            
            self.pos += 1;
            self.column += 1;
        }
        
        return Token{
            .type = .field,
            .text = self.input[start_pos..self.pos],
            .line = start_line,
            .column = start_column,
        };
    }
};

test "simple CSV tokenizer" {
    const input = "name,age\nJohn,25\n\"Jane Doe\",30";
    var tokenizer = SimpleCsvTokenizer.init(input);
    
    var tokens = std.ArrayList(SimpleCsvTokenizer.Token).init(std.testing.allocator);
    defer tokens.deinit();
    
    while (tokenizer.next()) |token| {
        if (token.type == .eof) break;
        try tokens.append(token);
    }
    
    try std.testing.expect(tokens.items.len > 5); // Should have multiple tokens
    
    // Verify first row
    try std.testing.expectEqual(SimpleCsvTokenizer.TokenType.field, tokens.items[0].type);
    try std.testing.expectEqualStrings("name", tokens.items[0].text);
    
    try std.testing.expectEqual(SimpleCsvTokenizer.TokenType.comma, tokens.items[1].type);
    
    try std.testing.expectEqual(SimpleCsvTokenizer.TokenType.field, tokens.items[2].type);
    try std.testing.expectEqualStrings("age", tokens.items[2].text);
    
    try std.testing.expectEqual(SimpleCsvTokenizer.TokenType.newline, tokens.items[3].type);
}

test "CSV quoted fields" {
    const input = "\"Hello, World\",\"Quote: \"\"Hi\"\"\"";
    var tokenizer = SimpleCsvTokenizer.init(input);
    
    const token1 = tokenizer.next().?;
    try std.testing.expectEqual(SimpleCsvTokenizer.TokenType.quoted_field, token1.type);
    try std.testing.expectEqualStrings("\"Hello, World\"", token1.text);
    
    _ = tokenizer.next(); // comma
    
    const token2 = tokenizer.next().?;
    try std.testing.expectEqual(SimpleCsvTokenizer.TokenType.quoted_field, token2.type);
    try std.testing.expectEqualStrings("\"Quote: \"\"Hi\"\"\"", token2.text);
}

test "CSV performance" {
    const input = "a,b,c\n" ** 10000;
    
    const start = std.time.nanoTimestamp();
    var tokenizer = SimpleCsvTokenizer.init(input);
    var count: usize = 0;
    
    while (tokenizer.next()) |token| {
        if (token.type == .eof) break;
        count += 1;
    }
    
    const end = std.time.nanoTimestamp();
    const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    
    std.debug.print("Parsed {d} CSV tokens in {d:.2}ms\n", .{ count, elapsed_ms });
    try std.testing.expect(count > 0);
}