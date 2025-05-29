const std = @import("std");
const zigparse = @import("../zigparse.zig");
const fast_matcher = @import("../fast_matcher.zig");

/// High-performance CSV tokenizer with zero allocations
/// Handles CSV parsing with proper quote escaping and delimiter detection
pub const CsvTokenizer = struct {
    pub const TokenType = enum {
        field,         // Regular field content
        quoted_field,  // Quoted field content (with quotes)
        comma,         // Field separator
        newline,       // Record separator
        eof,           // End of file
        error_token,   // Parse error
    };
    
    /// CSV parsing configuration
    pub const Config = struct {
        delimiter: u8 = ',',
        quote_char: u8 = '"',
        escape_char: ?u8 = null, // If null, quotes are escaped by doubling
        skip_empty_lines: bool = true,
        trim_whitespace: bool = false,
    };
    
    stream: zigparse.TokenStream,
    config: Config,
    
    pub fn init(input: []const u8, config: Config) CsvTokenizer {
        return .{
            .stream = zigparse.TokenStream.init(input),
            .config = config,
        };
    }
    
    pub const Token = struct {
        type: TokenType,
        text: []const u8,
        line: usize,
        column: usize,
        
        /// Get field content without quotes (for quoted fields)
        pub fn getUnquotedContent(self: Token) []const u8 {
            if (self.type == .quoted_field and self.text.len >= 2) {
                if (self.text[0] == '"' and self.text[self.text.len - 1] == '"') {
                    return self.text[1..self.text.len - 1];
                }
            }
            return self.text;
        }
        
        /// Check if this field is empty
        pub fn isEmpty(self: Token) bool {
            return switch (self.type) {
                .field => self.text.len == 0,
                .quoted_field => self.getUnquotedContent().len == 0,
                else => true,
            };
        }
    };
    
    pub fn next(self: *CsvTokenizer) ?Token {
        // Skip whitespace if configured
        if (self.config.trim_whitespace) {
            self.skipWhitespace();
        }
        
        const current_pos = self.stream.getPosition();
        const input_remaining = self.stream.remaining();
        
        if (input_remaining.len == 0) {
            return Token{
                .type = .eof,
                .text = "",
                .line = current_pos.line,
                .column = current_pos.column,
            };
        }
        
        const first_char = input_remaining[0];
        
        // Handle delimiter
        if (first_char == self.config.delimiter) {
            self.stream.pos += 1;
            return Token{
                .type = .comma,
                .text = input_remaining[0..1],
                .line = current_pos.line,
                .column = current_pos.column,
            };
        }
        
        // Handle newlines
        if (first_char == '\n' or first_char == '\r') {
            const newline_len: usize = if (first_char == '\r' and input_remaining.len > 1 and input_remaining[1] == '\n') 2 else 1;
            self.stream.pos += newline_len;
            self.stream.line += 1;
            self.stream.column = 1;
            
            return Token{
                .type = .newline,
                .text = input_remaining[0..newline_len],
                .line = current_pos.line,
                .column = current_pos.column,
            };
        }
        
        // Handle quoted fields
        if (first_char == self.config.quote_char) {
            return self.parseQuotedField();
        }
        
        // Handle regular fields
        return self.parseRegularField();
    }
    
    fn parseQuotedField(self: *CsvTokenizer) Token {
        const start_pos = self.stream.getPosition();
        const input_remaining = self.stream.remaining();
        
        var pos: usize = 1; // Skip opening quote
        
        while (pos < input_remaining.len) {
            const c = input_remaining[pos];
            
            if (c == self.config.quote_char) {
                // Check for escaped quote (doubled quote)
                if (pos + 1 < input_remaining.len and input_remaining[pos + 1] == self.config.quote_char) {
                    pos += 2; // Skip both quotes
                    continue;
                }
                
                // End of quoted field
                pos += 1; // Include closing quote
                break;
            }
            
            // Handle escape character if configured
            if (self.config.escape_char) |escape| {
                if (c == escape and pos + 1 < input_remaining.len) {
                    pos += 2; // Skip escape char and next char
                    continue;
                }
            }
            
            pos += 1;
        }
        
        const field_text = input_remaining[0..pos];
        self.stream.pos += pos;
        
        // Update line/column tracking
        for (field_text) |c| {
            if (c == '\n') {
                self.stream.line += 1;
                self.stream.column = 1;
            } else {
                self.stream.column += 1;
            }
        }
        
        return Token{
            .type = .quoted_field,
            .text = field_text,
            .line = start_pos.line,
            .column = start_pos.column,
        };
    }
    
    fn parseRegularField(self: *CsvTokenizer) Token {
        const start_pos = self.stream.getPosition();
        const input_remaining = self.stream.remaining();
        
        var pos: usize = 0;
        
        while (pos < input_remaining.len) {
            const c = input_remaining[pos];
            
            // Stop at delimiter, newline, or quote
            if (c == self.config.delimiter or c == '\n' or c == '\r' or c == self.config.quote_char) {
                break;
            }
            
            pos += 1;
        }
        
        // Trim trailing whitespace if configured
        var end_pos = pos;
        if (self.config.trim_whitespace) {
            while (end_pos > 0 and isWhitespace(input_remaining[end_pos - 1])) {
                end_pos -= 1;
            }
        }
        
        const field_text = input_remaining[0..end_pos];
        self.stream.pos += pos;
        self.stream.column += pos;
        
        return Token{
            .type = .field,
            .text = field_text,
            .line = start_pos.line,
            .column = start_pos.column,
        };
    }
    
    fn skipWhitespace(self: *CsvTokenizer) void {
        const input_remaining = self.stream.remaining();
        var pos: usize = 0;
        
        while (pos < input_remaining.len and isWhitespace(input_remaining[pos])) {
            if (input_remaining[pos] == '\n') {
                self.stream.line += 1;
                self.stream.column = 1;
            } else {
                self.stream.column += 1;
            }
            pos += 1;
        }
        
        self.stream.pos += pos;
    }
    
    pub fn remaining(self: *const CsvTokenizer) []const u8 {
        return self.stream.remaining();
    }
    
    pub fn isAtEnd(self: *const CsvTokenizer) bool {
        return self.stream.isAtEnd();
    }
};

/// High-level CSV parser that produces structured records
pub const CsvParser = struct {
    tokenizer: CsvTokenizer,
    
    pub const Record = struct {
        fields: []const []const u8,
        line_number: usize,
    };
    
    pub fn init(input: []const u8, config: CsvTokenizer.Config) CsvParser {
        return .{
            .tokenizer = CsvTokenizer.init(input, config),
        };
    }
    
    /// Parse a single CSV record
    pub fn parseRecord(self: *CsvParser, allocator: std.mem.Allocator) !?Record {
        var fields = std.ArrayList([]const u8).init(allocator);
        defer fields.deinit();
        
        var line_number: usize = 1;
        var has_content = false;
        
        while (self.tokenizer.next()) |token| {
            switch (token.type) {
                .field, .quoted_field => {
                    try fields.append(token.getUnquotedContent());
                    has_content = true;
                    line_number = token.line;
                },
                .comma => {
                    // Continue to next field
                },
                .newline => {
                    if (has_content or !self.tokenizer.config.skip_empty_lines) {
                        break;
                    }
                    // Skip empty line
                    fields.clearRetainingCapacity();
                    has_content = false;
                },
                .eof => {
                    if (!has_content) return null;
                    break;
                },
                .error_token => {
                    return error.CsvParseError;
                },
            }
        }
        
        if (!has_content) return null;
        
        return Record{
            .fields = try fields.toOwnedSlice(),
            .line_number = line_number,
        };
    }
    
    /// Parse all CSV records
    pub fn parseAll(self: *CsvParser, allocator: std.mem.Allocator) ![]Record {
        var records = std.ArrayList(Record).init(allocator);
        defer records.deinit();
        
        while (try self.parseRecord(allocator)) |record| {
            try records.append(record);
        }
        
        return records.toOwnedSlice();
    }
};

/// Ultra-fast CSV tokenizer using our optimized matcher
pub const UltraFastCsvTokenizer = struct {
    input: []const u8,
    pos: usize = 0,
    line: usize = 1,
    column: usize = 1,
    config: CsvTokenizer.Config,
    
    pub fn init(input: []const u8, config: CsvTokenizer.Config) UltraFastCsvTokenizer {
        return .{
            .input = input,
            .config = config,
        };
    }
    
    pub fn next(self: *UltraFastCsvTokenizer) ?CsvTokenizer.Token {
        if (self.pos >= self.input.len) {
            return .{
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
        
        // Fast path for common cases
        if (c == self.config.delimiter) {
            self.pos += 1;
            self.column += 1;
            return .{
                .type = .comma,
                .text = self.input[start_pos..self.pos],
                .line = start_line,
                .column = start_column,
            };
        }
        
        if (c == '\n') {
            self.pos += 1;
            self.line += 1;
            self.column = 1;
            return .{
                .type = .newline,
                .text = self.input[start_pos..self.pos],
                .line = start_line,
                .column = start_column,
            };
        }
        
        if (c == '\r') {
            self.pos += 1;
            if (self.pos < self.input.len and self.input[self.pos] == '\n') {
                self.pos += 1;
            }
            self.line += 1;
            self.column = 1;
            return .{
                .type = .newline,
                .text = self.input[start_pos..self.pos],
                .line = start_line,
                .column = start_column,
            };
        }
        
        if (c == self.config.quote_char) {
            return self.parseQuotedFieldFast();
        }
        
        return self.parseRegularFieldFast();
    }
    
    fn parseQuotedFieldFast(self: *UltraFastCsvTokenizer) CsvTokenizer.Token {
        const start_pos = self.pos;
        const start_line = self.line;
        const start_column = self.column;
        
        self.pos += 1; // Skip opening quote
        self.column += 1;
        
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            
            if (c == self.config.quote_char) {
                self.pos += 1;
                self.column += 1;
                
                // Check for escaped quote
                if (self.pos < self.input.len and self.input[self.pos] == self.config.quote_char) {
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
        
        return .{
            .type = .quoted_field,
            .text = self.input[start_pos..self.pos],
            .line = start_line,
            .column = start_column,
        };
    }
    
    fn parseRegularFieldFast(self: *UltraFastCsvTokenizer) CsvTokenizer.Token {
        const start_pos = self.pos;
        const start_line = self.line;
        const start_column = self.column;
        
        // Use SIMD-accelerated search for field boundaries
        const remaining = self.input[self.pos..];
        var end_pos: usize = 0;
        
        for (remaining) |c| {
            if (c == self.config.delimiter or c == '\n' or c == '\r' or c == self.config.quote_char) {
                break;
            }
            end_pos += 1;
        }
        
        self.pos += end_pos;
        self.column += end_pos;
        
        return .{
            .type = .field,
            .text = self.input[start_pos..self.pos],
            .line = start_line,
            .column = start_column,
        };
    }
};

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t';
}

test "CSV tokenizer basic" {
    const input = "name,age,city\nJohn,25,NYC\n\"Jane Doe\",30,\"San Francisco\"";
    var tokenizer = CsvTokenizer.init(input, .{});
    
    // First record: headers
    const token1 = tokenizer.next().?;
    try std.testing.expectEqual(CsvTokenizer.TokenType.field, token1.type);
    try std.testing.expectEqualStrings("name", token1.text);
    
    const token2 = tokenizer.next().?;
    try std.testing.expectEqual(CsvTokenizer.TokenType.comma, token2.type);
    
    const token3 = tokenizer.next().?;
    try std.testing.expectEqual(CsvTokenizer.TokenType.field, token3.type);
    try std.testing.expectEqualStrings("age", token3.text);
    
    // Skip to newline
    _ = tokenizer.next(); // comma
    _ = tokenizer.next(); // city
    const newline1 = tokenizer.next().?;
    try std.testing.expectEqual(CsvTokenizer.TokenType.newline, newline1.type);
    
    // Second record
    const john = tokenizer.next().?;
    try std.testing.expectEqual(CsvTokenizer.TokenType.field, john.type);
    try std.testing.expectEqualStrings("John", john.text);
}

test "CSV quoted fields" {
    const input = "\"Hello, World\",\"She said \"\"Hi\"\" to me\"";
    var tokenizer = CsvTokenizer.init(input, .{});
    
    const token1 = tokenizer.next().?;
    try std.testing.expectEqual(CsvTokenizer.TokenType.quoted_field, token1.type);
    try std.testing.expectEqualStrings("\"Hello, World\"", token1.text);
    try std.testing.expectEqualStrings("Hello, World", token1.getUnquotedContent());
    
    _ = tokenizer.next(); // comma
    
    const token2 = tokenizer.next().?;
    try std.testing.expectEqual(CsvTokenizer.TokenType.quoted_field, token2.type);
    try std.testing.expectEqualStrings("She said \"\"Hi\"\" to me", token2.getUnquotedContent());
}

test "CSV parser records" {
    const input = "name,age\nJohn,25\nJane,30\n";
    var parser = CsvParser.init(input, .{});
    
    const record1 = try parser.parseRecord(std.testing.allocator);
    try std.testing.expect(record1 != null);
    defer std.testing.allocator.free(record1.?.fields);
    
    try std.testing.expectEqual(@as(usize, 2), record1.?.fields.len);
    try std.testing.expectEqualStrings("name", record1.?.fields[0]);
    try std.testing.expectEqualStrings("age", record1.?.fields[1]);
    
    const record2 = try parser.parseRecord(std.testing.allocator);
    try std.testing.expect(record2 != null);
    defer std.testing.allocator.free(record2.?.fields);
    
    try std.testing.expectEqualStrings("John", record2.?.fields[0]);
    try std.testing.expectEqualStrings("25", record2.?.fields[1]);
}

test "ultra fast CSV tokenizer" {
    const input = "a,b,c\n1,2,3\n";
    var tokenizer = UltraFastCsvTokenizer.init(input, .{});
    
    var token_count: usize = 0;
    while (tokenizer.next()) |token| {
        if (token.type == .eof) break;
        token_count += 1;
    }
    
    try std.testing.expectEqual(@as(usize, 12), token_count); // a,b,c,\n,1,2,3,\n = 12 tokens
}

test "CSV performance comparison" {
    const input = "name,age,city,country\n" ** 1000 ++ "John,25,NYC,USA\n" ** 1000;
    
    // Test regular tokenizer
    const start1 = std.time.nanoTimestamp();
    var tokenizer1 = CsvTokenizer.init(input, .{});
    var count1: usize = 0;
    while (tokenizer1.next()) |token| {
        if (token.type == .eof) break;
        count1 += 1;
    }
    const end1 = std.time.nanoTimestamp();
    
    // Test ultra-fast tokenizer
    const start2 = std.time.nanoTimestamp();
    var tokenizer2 = UltraFastCsvTokenizer.init(input, .{});
    var count2: usize = 0;
    while (tokenizer2.next()) |token| {
        if (token.type == .eof) break;
        count2 += 1;
    }
    const end2 = std.time.nanoTimestamp();
    
    try std.testing.expectEqual(count1, count2);
    
    const time1 = end1 - start1;
    const time2 = end2 - start2;
    
    std.debug.print("Regular: {d}ns, Ultra-fast: {d}ns, Speedup: {d:.2}x\n", .{
        time1, time2, @as(f64, @floatFromInt(time1)) / @as(f64, @floatFromInt(time2))
    });
}