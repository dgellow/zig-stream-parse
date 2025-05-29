const std = @import("std");
const zigparse = @import("../zigparse.zig");

/// High-performance, zero-allocation JSON tokenizer
/// Returns slices into the original input - no copies!
pub const JsonTokenizer = struct {
    pub const TokenType = enum {
        lbrace,     // {
        rbrace,     // }
        lbracket,   // [
        rbracket,   // ]
        comma,      // ,
        colon,      // :
        string,     // "..."
        number,     // 123, -45.67, 1.23e-4
        true_lit,   // true
        false_lit,  // false
        null_lit,   // null
        whitespace, // spaces, tabs, newlines
        error_token,
    };
    
    pub const patterns = .{
        .lbrace = zigparse.match.literal("{"),
        .rbrace = zigparse.match.literal("}"),
        .lbracket = zigparse.match.literal("["),
        .rbracket = zigparse.match.literal("]"),
        .comma = zigparse.match.literal(","),
        .colon = zigparse.match.literal(":"),
        .string = jsonStringPattern(),
        .number = jsonNumberPattern(),
        .true_lit = zigparse.match.literal("true"),
        .false_lit = zigparse.match.literal("false"),
        .null_lit = zigparse.match.literal("null"),
        .whitespace = zigparse.match.whitespace.oneOrMore(),
    };
    
    stream: zigparse.TokenStream,
    
    pub fn init(input: []const u8) JsonTokenizer {
        return .{
            .stream = zigparse.TokenStream.init(input),
        };
    }
    
    pub const Token = struct {
        type: TokenType,
        text: []const u8,
        line: usize,
        column: usize,
    };
    
    pub fn next(self: *JsonTokenizer) ?Token {
        const token = self.stream.next(TokenType, patterns) orelse return null;
        return Token{
            .type = token.type,
            .text = token.text,
            .line = token.line,
            .column = token.column,
        };
    }
    
    pub fn remaining(self: *const JsonTokenizer) []const u8 {
        return self.stream.remaining();
    }
    
    pub fn isAtEnd(self: *const JsonTokenizer) bool {
        return self.stream.isAtEnd();
    }
};

// JSON string pattern: "..." with escape handling
fn jsonStringPattern() zigparse.Pattern {
    // This is a simplified version - a full implementation would handle all JSON escapes
    return .{
        .sequence = &[_]zigparse.Pattern{
            zigparse.match.literal("\""),
            .{
                .until = &zigparse.match.literal("\""),
            },
            zigparse.match.literal("\""),
        },
    };
}

// JSON number pattern: -?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?
fn jsonNumberPattern() zigparse.Pattern {
    // Handle all JSON number characters including exponents
    const number_chars = zigparse.Pattern{ .any_of = "0123456789.-+eE" };
    return number_chars.oneOrMore();
}

/// Zero-allocation JSON parser that emits events
pub const JsonParser = struct {
    pub const Event = union(enum) {
        object_start,
        object_end,
        array_start,
        array_end,
        key: []const u8,
        string: []const u8,
        number: []const u8,
        boolean: bool,
        null,
        error_event: []const u8,
    };
    
    tokenizer: JsonTokenizer,
    
    pub fn init(input: []const u8) JsonParser {
        return .{
            .tokenizer = JsonTokenizer.init(input),
        };
    }
    
    pub fn parseValue(self: *JsonParser) !?Event {
        const token = self.tokenizer.next() orelse return null;
        
        return switch (token.type) {
            .lbrace => .object_start,
            .rbrace => .object_end,
            .lbracket => .array_start,
            .rbracket => .array_end,
            .string => .{ .string = unescapeJsonString(token.text) },
            .number => .{ .number = token.text },
            .true_lit => .{ .boolean = true },
            .false_lit => .{ .boolean = false },
            .null_lit => .null,
            else => .{ .error_event = token.text },
        };
    }
    
    /// Parse complete JSON and emit all events
    pub fn parseAll(self: *JsonParser, allocator: std.mem.Allocator) !std.ArrayList(Event) {
        var events = std.ArrayList(Event).init(allocator);
        
        while (try self.parseValue()) |event| {
            try events.append(event);
        }
        
        return events;
    }
};

// Helper function to unescape JSON strings (simplified)
fn unescapeJsonString(text: []const u8) []const u8 {
    // Remove surrounding quotes
    if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') {
        return text[1 .. text.len - 1];
    }
    return text;
}

/// High-level JSON value type for complete parsing
pub const JsonValue = union(enum) {
    object: std.StringHashMap(JsonValue),
    array: std.ArrayList(JsonValue),
    string: []const u8,
    number: f64,
    boolean: bool,
    null,
    
    pub fn deinit(self: *JsonValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .object => |*obj| {
                var it = obj.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    entry.value_ptr.deinit(allocator);
                }
                obj.deinit();
            },
            .array => |*arr| {
                for (arr.items) |*item| {
                    item.deinit(allocator);
                }
                arr.deinit();
            },
            else => {},
        }
    }
};

/// Parse JSON into structured data (this does allocate for the structure)
pub fn parseJsonValue(allocator: std.mem.Allocator, input: []const u8) !JsonValue {
    var parser = JsonParser.init(input);
    
    // This is a simplified parser - a full implementation would handle the complete JSON grammar
    const first_event = try parser.parseValue() orelse return error.EmptyInput;
    
    return switch (first_event) {
        .string => |s| .{ .string = s },
        .number => |n| .{ .number = std.fmt.parseFloat(f64, n) catch return error.InvalidNumber },
        .boolean => |b| .{ .boolean = b },
        .null => .null,
        .object_start => {
            const obj = std.StringHashMap(JsonValue).init(allocator);
            // Parse object contents...
            return .{ .object = obj };
        },
        .array_start => {
            const arr = std.ArrayList(JsonValue).init(allocator);
            // Parse array contents...
            return .{ .array = arr };
        },
        else => error.InvalidJson,
    };
}

test "JSON tokenizer" {
    const input = 
        \\{"name": "John", "age": 30, "active": true, "scores": [85.5, 92.0], "meta": null}
    ;
    
    var tokenizer = JsonTokenizer.init(input);
    
    // Should find opening brace
    const token1 = tokenizer.next().?;
    try std.testing.expectEqual(JsonTokenizer.TokenType.lbrace, token1.type);
    try std.testing.expectEqualStrings("{", token1.text);
    
    // Should find string key
    const token2 = tokenizer.next().?;
    try std.testing.expectEqual(JsonTokenizer.TokenType.string, token2.type);
    try std.testing.expectEqualStrings("\"name\"", token2.text);
    
    // Should find colon
    const token3 = tokenizer.next().?;
    try std.testing.expectEqual(JsonTokenizer.TokenType.colon, token3.type);
    
    // Continue through the JSON...
    var token_count: usize = 3;
    while (tokenizer.next()) |_| {
        token_count += 1;
    }
    
    try std.testing.expect(token_count > 10); // Should have many tokens
}

test "JSON number parsing" {
    const numbers = [_][]const u8{
        "42",
        "-17",
        "3.14159",
        "-2.5",
        "1.23e4",
        "1.23E-4",
        "-1.23e+4",
    };
    
    for (numbers) |num_str| {
        var tokenizer = JsonTokenizer.init(num_str);
        const token = tokenizer.next().?;
        try std.testing.expectEqual(JsonTokenizer.TokenType.number, token.type);
        try std.testing.expectEqualStrings(num_str, token.text);
    }
}

test "JSON string parsing" {
    const strings = [_][]const u8{
        "\"hello\"",
        "\"world\"",
        "\"\"",
        "\"with spaces\"",
    };
    
    for (strings) |str| {
        var tokenizer = JsonTokenizer.init(str);
        const token = tokenizer.next().?;
        try std.testing.expectEqual(JsonTokenizer.TokenType.string, token.type);
        try std.testing.expectEqualStrings(str, token.text);
    }
}

test "JSON performance" {
    // Large JSON-like input
    const input = 
        \\{"users": [{"id": 1, "name": "Alice", "active": true}, {"id": 2, "name": "Bob", "active": false}], "count": 2, "version": "1.0"}
    ;
    
    const iterations = 1000;
    const start_time = std.time.nanoTimestamp();
    
    for (0..iterations) |_| {
        var tokenizer = JsonTokenizer.init(input);
        var token_count: usize = 0;
        while (tokenizer.next()) |token| {
            token_count += 1;
            // Prevent optimization
            std.mem.doNotOptimizeAway(token.text.ptr);
        }
        std.mem.doNotOptimizeAway(token_count);
    }
    
    const end_time = std.time.nanoTimestamp();
    const elapsed_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    
    std.debug.print("JSON tokenized {d}x in {d:.2}ms (avg: {d:.3}ms per iteration)\n", .{
        iterations,
        elapsed_ms,
        elapsed_ms / @as(f64, @floatFromInt(iterations)),
    });
}