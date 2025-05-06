const std = @import("std");
const lib = @import("zig_stream_parse_lib");

// Import our parser components
const ByteStream = lib.ByteStream;
const Position = lib.Position;
const Tokenizer = lib.Tokenizer;
const Token = lib.Token;
const TokenType = lib.TokenType;
const TokenMatcher = lib.TokenMatcher;
const StateMachine = lib.StateMachine;
const State = lib.State;
const StateTransition = lib.StateTransition;
const EventEmitter = lib.EventEmitter;
const Event = lib.Event;
const EventType = lib.EventType;
const EventHandler = lib.EventHandler;
const Parser = lib.Parser;
const ParserContext = lib.ParserContext;
const Grammar = lib.Grammar;

// ActionFn type
const ActionFn = *const fn(ctx: *ParserContext, token: Token) anyerror!void;

// Simple benchmarking tools
fn measureTime(comptime func: anytype, args: anytype) !u64 {
    const start = try std.time.Instant.now();
    try @call(.auto, func, args);
    const end = try std.time.Instant.now();
    return end.since(start);
}

// Helper functions for memory usage
fn getCurrentMemoryUsage(allocator: std.mem.Allocator) !usize {
    _ = allocator;
    // In a real implementation this would use operating system APIs
    // or memory trackers to get actual memory usage
    return 0;
}

// Benchmark JSON-like parser
fn runJsonBenchmark(allocator: std.mem.Allocator, input: []const u8) !void {
    const start_mem = try getCurrentMemoryUsage(allocator);
    
    // Create token matchers
    const string_matcher = TokenMatcher.init(stringTokenMatcher);
    const number_matcher = TokenMatcher.init(numberTokenMatcher);
    const punctuation_matcher = TokenMatcher.init(punctuationTokenMatcher);
    const whitespace_matcher = TokenMatcher.init(whitespaceTokenMatcher);

    // Create tokenizer configuration
    const matchers = [_]TokenMatcher{
        string_matcher,
        number_matcher,
        punctuation_matcher,
        whitespace_matcher,
    };
    
    const skip_types = [_]TokenType{
        .{ .id = 9, .name = "WHITESPACE" },
    };

    // Create state machine configuration
    const action_fns = [_]ActionFn{
        handleString,
        handleNumber,
        handleOpenBrace,
        handleCloseBrace,
        handleOpenBracket,
        handleCloseBracket,
        handleColon,
        handleComma,
    };

    // Define some basic JSON-like state transitions (simplified)
    const transitions_value = [_]StateTransition{
        .{ .token_id = 1, .next_state = 0, .action_id = 0 }, // STRING -> VALUE w/ handleString
        .{ .token_id = 2, .next_state = 0, .action_id = 1 }, // NUMBER -> VALUE w/ handleNumber
        .{ .token_id = 3, .next_state = 1, .action_id = 2 }, // { -> OBJECT w/ handleOpenBrace
        .{ .token_id = 5, .next_state = 2, .action_id = 4 }, // [ -> ARRAY w/ handleOpenBracket
    };

    const transitions_object = [_]StateTransition{
        .{ .token_id = 1, .next_state = 3, .action_id = 0 }, // STRING -> OBJECT_KEY w/ handleString 
        .{ .token_id = 4, .next_state = 0, .action_id = 3 }, // } -> VALUE w/ handleCloseBrace
    };

    const transitions_array = [_]StateTransition{
        .{ .token_id = 1, .next_state = 0, .action_id = 0 }, // STRING -> VALUE w/ handleString
        .{ .token_id = 2, .next_state = 0, .action_id = 1 }, // NUMBER -> VALUE w/ handleNumber
        .{ .token_id = 3, .next_state = 1, .action_id = 2 }, // { -> OBJECT w/ handleOpenBrace
        .{ .token_id = 5, .next_state = 2, .action_id = 4 }, // [ -> ARRAY w/ handleOpenBracket
        .{ .token_id = 6, .next_state = 0, .action_id = 5 }, // ] -> VALUE w/ handleCloseBracket
    };

    const transitions_object_key = [_]StateTransition{
        .{ .token_id = 7, .next_state = 4, .action_id = 6 }, // : -> OBJECT_VALUE w/ handleColon
    };

    const transitions_object_value = [_]StateTransition{
        .{ .token_id = 1, .next_state = 5, .action_id = 0 }, // STRING -> OBJECT_NEXT w/ handleString
        .{ .token_id = 2, .next_state = 5, .action_id = 1 }, // NUMBER -> OBJECT_NEXT w/ handleNumber
        .{ .token_id = 3, .next_state = 1, .action_id = 2 }, // { -> OBJECT w/ handleOpenBrace
        .{ .token_id = 5, .next_state = 2, .action_id = 4 }, // [ -> ARRAY w/ handleOpenBracket
    };

    const transitions_object_next = [_]StateTransition{
        .{ .token_id = 4, .next_state = 0, .action_id = 3 }, // } -> VALUE w/ handleCloseBrace
        .{ .token_id = 8, .next_state = 3, .action_id = 7 }, // , -> OBJECT_KEY w/ handleComma
    };

    const states = [_]State{
        .{ .id = 0, .name = "VALUE", .transitions = &transitions_value },
        .{ .id = 1, .name = "OBJECT", .transitions = &transitions_object },
        .{ .id = 2, .name = "ARRAY", .transitions = &transitions_array },
        .{ .id = 3, .name = "OBJECT_KEY", .transitions = &transitions_object_key },
        .{ .id = 4, .name = "OBJECT_VALUE", .transitions = &transitions_object_value },
        .{ .id = 5, .name = "OBJECT_NEXT", .transitions = &transitions_object_next },
    };

    // Set up tokenizer config and state machine config
    const token_config = lib.TokenizerConfig{
        .matchers = &matchers,
        .skip_types = &skip_types,
    };

    const state_config = lib.StateMachineConfig{
        .states = &states,
        .actions = &action_fns,
        .initial_state_id = 0,
    };

    // Create a parser
    var parser = try Parser.init(
        allocator,
        input,
        token_config,
        state_config,
        4096 // buffer size
    );
    defer parser.deinit();

    // Set event handler
    parser.setEventHandler(EventHandler.init(silentEventHandler, null));

    // Parse the input
    try parser.parse();
    
    const end_mem = try getCurrentMemoryUsage(allocator);
    const mem_used = if (end_mem > start_mem) end_mem - start_mem else 0;
    
    std.debug.print("Memory used: {d} bytes\n", .{mem_used});
}

// Token matchers for JSON-like format
fn stringTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Check for quote to start string
    const first_char = try stream.peek();
    if (first_char == null or first_char.? != '"') return null;
    
    _ = try stream.consume(); // Skip opening quote
    
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    
    // Consume until closing quote or EOF
    while (true) {
        const next_char = try stream.peek();
        if (next_char == null) break; // Unexpected EOF
        
        _ = try stream.consume();
        
        if (next_char.? == '"') {
            // End of string
            const lexeme = try allocator.dupe(u8, token_bytes.items);
            return Token.init(
                .{ .id = 1, .name = "STRING" },
                start_pos,
                lexeme
            );
        }
        
        if (next_char.? == '\\') {
            // Handle escape sequence
            const esc_char = try stream.peek();
            if (esc_char != null) {
                _ = try stream.consume();
                switch (esc_char.?) {
                    '"', '\\', '/' => try token_bytes.append(esc_char.?),
                    'b' => try token_bytes.append(8), // backspace
                    'f' => try token_bytes.append(12), // form feed
                    'n' => try token_bytes.append('\n'),
                    'r' => try token_bytes.append('\r'),
                    't' => try token_bytes.append('\t'),
                    else => {}, // Ignore invalid escapes
                }
            }
            continue;
        }
        
        try token_bytes.append(next_char.?);
    }
    
    // No closing quote found - invalid, but we'll be lenient
    if (token_bytes.items.len > 0) {
        const lexeme = try allocator.dupe(u8, token_bytes.items);
        return Token.init(
            .{ .id = 1, .name = "STRING" },
            start_pos,
            lexeme
        );
    }
    
    return null;
}

fn numberTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Check first char is digit or minus
    const first_char = try stream.peek();
    if (first_char == null or (first_char.? != '-' and !isDigit(first_char.?))) 
        return null;
    
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    
    // Consume the first character
    _ = try stream.consume();
    try token_bytes.append(first_char.?);
    
    // Simple number parsing (not fully JSON compliant, but enough for benchmark)
    var has_decimal = false;
    
    while (true) {
        const next_char = try stream.peek();
        if (next_char == null) break;
        
        if (isDigit(next_char.?)) {
            _ = try stream.consume();
            try token_bytes.append(next_char.?);
        } else if (next_char.? == '.' and !has_decimal) {
            has_decimal = true;
            _ = try stream.consume();
            try token_bytes.append(next_char.?);
        } else {
            break;
        }
    }
    
    const lexeme = try allocator.dupe(u8, token_bytes.items);
    return Token.init(
        .{ .id = 2, .name = "NUMBER" },
        start_pos,
        lexeme
    );
}

fn punctuationTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    _ = allocator;
    const start_pos = stream.getPosition();
    
    const char = try stream.peek();
    if (char == null) return null;
    
    // Handle different punctuation characters in JSON
    const token_info: ?struct { id: u32, name: []const u8 } = switch (char.?) {
        '{' => .{ .id = 3, .name = "OPEN_BRACE" },
        '}' => .{ .id = 4, .name = "CLOSE_BRACE" },
        '[' => .{ .id = 5, .name = "OPEN_BRACKET" },
        ']' => .{ .id = 6, .name = "CLOSE_BRACKET" },
        ':' => .{ .id = 7, .name = "COLON" },
        ',' => .{ .id = 8, .name = "COMMA" },
        else => null,
    };
    
    if (token_info) |info| {
        _ = try stream.consume();
        return Token.init(
            .{ .id = info.id, .name = info.name },
            start_pos,
            &[_]u8{char.?}
        );
    }
    
    return null;
}

fn whitespaceTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    _ = allocator;
    const start_pos = stream.getPosition();
    
    const char = try stream.peek();
    if (char == null or !isWhitespace(char.?)) return null;
    
    var count: usize = 0;
    while (true) {
        const next_char = try stream.peek();
        if (next_char == null or !isWhitespace(next_char.?)) break;
        
        _ = try stream.consume();
        count += 1;
    }
    
    return Token.init(
        .{ .id = 9, .name = "WHITESPACE" },
        start_pos,
        "" // Don't need to store actual whitespace
    );
}

// Helper functions for character classification
fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

// State machine actions
fn handleString(ctx: *ParserContext, token: Token) !void {
    _ = ctx;
    _ = token;
    // In real parser would store the string value
}

fn handleNumber(ctx: *ParserContext, token: Token) !void {
    _ = ctx;
    _ = token;
    // In real parser would convert and store the number value
}

fn handleOpenBrace(ctx: *ParserContext, token: Token) !void {
    _ = ctx;
    _ = token;
    // In real parser would start a new object context
}

fn handleCloseBrace(ctx: *ParserContext, token: Token) !void {
    _ = ctx;
    _ = token;
    // In real parser would close an object context
}

fn handleOpenBracket(ctx: *ParserContext, token: Token) !void {
    _ = ctx;
    _ = token;
    // In real parser would start a new array context
}

fn handleCloseBracket(ctx: *ParserContext, token: Token) !void {
    _ = ctx;
    _ = token;
    // In real parser would close an array context
}

fn handleColon(ctx: *ParserContext, token: Token) !void {
    _ = ctx;
    _ = token;
    // In real parser would mark next value as associated with key
}

fn handleComma(ctx: *ParserContext, token: Token) !void {
    _ = ctx;
    _ = token;
    // In real parser would prepare for next key-value pair
}

// Silent event handler for benchmarking
fn silentEventHandler(event: Event, ctx: ?*anyopaque) !void {
    _ = event;
    _ = ctx;
    // Do nothing, just consume events silently
}

// Generate test data
fn generateJsonTestData(allocator: std.mem.Allocator, size: usize) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    // Create a deeply nested structure to test parser robustness
    try result.appendSlice("{\n");
    try result.appendSlice("  \"array\": [\n");
    
    var i: usize = 0;
    while (i < size) : (i += 1) {
        try result.appendSlice("    {\n");
        try result.appendSlice("      \"id\": ");
        try result.writer().print("{d}", .{i});
        try result.appendSlice(",\n");
        try result.appendSlice("      \"name\": \"item");
        try result.writer().print("{d}", .{i});
        try result.appendSlice("\",\n");
        try result.appendSlice("      \"value\": ");
        try result.writer().print("{d}.{d}", .{ i, i * 10 });
        try result.appendSlice("\n");
        try result.appendSlice("    }");
        
        if (i < size - 1) {
            try result.appendSlice(",");
        }
        try result.appendSlice("\n");
    }
    
    try result.appendSlice("  ]\n");
    try result.appendSlice("}\n");
    
    return result.toOwnedSlice();
}

pub fn main() !void {
    // Setup allocator
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = general_purpose_allocator.allocator();
    defer _ = general_purpose_allocator.deinit();

    std.debug.print("ZigParse Benchmarks\n", .{});
    std.debug.print("==================\n\n", .{});
    
    // Define benchmark sizes
    const sizes = [_]usize{10, 100, 1000, 10000};
    
    for (sizes) |size| {
        std.debug.print("Running benchmark with {d} items...\n", .{size});
        const test_data = try generateJsonTestData(allocator, size);
        defer allocator.free(test_data);
        
        const elapsed_ns = try measureTime(runJsonBenchmark, .{allocator, test_data});
        const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
        
        std.debug.print("  Time: {d:.2} ms\n", .{elapsed_ms});
        std.debug.print("  Input size: {d} bytes\n", .{test_data.len});
        std.debug.print("  Throughput: {d:.2} MB/s\n\n", .{
            @as(f64, @floatFromInt(test_data.len)) / 1_000_000.0 / (elapsed_ms / 1000.0)
        });
    }
    
    std.debug.print("Benchmarks completed successfully!\n", .{});
}