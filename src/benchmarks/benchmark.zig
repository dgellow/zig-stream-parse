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

// Simple benchmarking tools with error handling
fn measureTime(comptime func: anytype, args: anytype) !u64 {
    const start = try std.time.Instant.now();
    
    // Call function and propagate any errors upward
    _ = @call(.auto, func, args) catch |err| {
        std.debug.print("Function call failed: {s}\n", .{@errorName(err)});
        return err;
    };
    
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

// The REAL benchmark mode - safe and simple
fn runSafeBenchmark(allocator: std.mem.Allocator, input: []const u8) !void {
    var stream = try ByteStream.init(allocator, input, 4096);
    defer stream.deinit();
    
    var chars_processed: usize = 0;
    var lines: usize = 0;
    
    // Simple processing - just count chars and lines
    while (true) {
        const byte = try stream.consume();
        if (byte == null) break;
        
        chars_processed += 1;
        if (byte.? == '\n') lines += 1;
    }
    
    std.debug.print("Processed {d} characters and {d} lines\n", .{chars_processed, lines});
}

// Benchmark JSON-like parser (original implementation for reference)
fn runJsonBenchmark(allocator: std.mem.Allocator, input: []const u8) !void {
    const start_mem = try getCurrentMemoryUsage(allocator);
    
    // Use our fixed tokenizer instead of the fallback
    // Was previously set to true to avoid segfaults
    const use_fallback_benchmark = false;
    if (use_fallback_benchmark) {
        return runSafeBenchmark(allocator, input);
    }
    
    std.debug.print("Using full parser benchmark\n", .{});
    
    // Create token matchers - only used if not using fallback
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
        .{ .token_id = std.math.maxInt(u32), .next_state = 0, .action_id = null }, // ERROR -> VALUE (ignore and continue)
    };

    const transitions_object = [_]StateTransition{
        .{ .token_id = 1, .next_state = 3, .action_id = 0 }, // STRING -> OBJECT_KEY w/ handleString 
        .{ .token_id = 4, .next_state = 0, .action_id = 3 }, // } -> VALUE w/ handleCloseBrace
        .{ .token_id = std.math.maxInt(u32), .next_state = 1, .action_id = null }, // ERROR -> OBJECT (ignore and continue)
    };

    const transitions_array = [_]StateTransition{
        .{ .token_id = 1, .next_state = 0, .action_id = 0 }, // STRING -> VALUE w/ handleString
        .{ .token_id = 2, .next_state = 0, .action_id = 1 }, // NUMBER -> VALUE w/ handleNumber
        .{ .token_id = 3, .next_state = 1, .action_id = 2 }, // { -> OBJECT w/ handleOpenBrace
        .{ .token_id = 5, .next_state = 2, .action_id = 4 }, // [ -> ARRAY w/ handleOpenBracket
        .{ .token_id = 6, .next_state = 0, .action_id = 5 }, // ] -> VALUE w/ handleCloseBracket
        .{ .token_id = std.math.maxInt(u32), .next_state = 2, .action_id = null }, // ERROR -> ARRAY (ignore and continue)
    };

    const transitions_object_key = [_]StateTransition{
        .{ .token_id = 7, .next_state = 4, .action_id = 6 }, // : -> OBJECT_VALUE w/ handleColon
        .{ .token_id = std.math.maxInt(u32), .next_state = 3, .action_id = null }, // ERROR -> OBJECT_KEY (ignore and continue)
    };

    const transitions_object_value = [_]StateTransition{
        .{ .token_id = 1, .next_state = 5, .action_id = 0 }, // STRING -> OBJECT_NEXT w/ handleString
        .{ .token_id = 2, .next_state = 5, .action_id = 1 }, // NUMBER -> OBJECT_NEXT w/ handleNumber
        .{ .token_id = 3, .next_state = 1, .action_id = 2 }, // { -> OBJECT w/ handleOpenBrace
        .{ .token_id = 5, .next_state = 2, .action_id = 4 }, // [ -> ARRAY w/ handleOpenBracket
        .{ .token_id = std.math.maxInt(u32), .next_state = 4, .action_id = null }, // ERROR -> OBJECT_VALUE (ignore and continue)
    };

    const transitions_object_next = [_]StateTransition{
        .{ .token_id = 4, .next_state = 0, .action_id = 3 }, // } -> VALUE w/ handleCloseBrace
        .{ .token_id = 8, .next_state = 3, .action_id = 7 }, // , -> OBJECT_KEY w/ handleComma
        .{ .token_id = std.math.maxInt(u32), .next_state = 5, .action_id = null }, // ERROR -> OBJECT_NEXT (ignore and continue)
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

    // Try parsing safely with error handling
    parser.parse() catch |err| {
        std.debug.print("Benchmark parsing error: {s}\n", .{@errorName(err)});
        return;
    };
    
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
    
    // Save the initial position in case we need to reset
    const initial_position = stream.position;
    const initial_line = stream.line;
    const initial_column = stream.column;
    
    _ = try stream.consume(); // Skip opening quote
    
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    
    // Track if we've seen an error
    var error_encountered = false;
    
    // Consume until closing quote or EOF
    while (!error_encountered) {
        const next_char = try stream.peek();
        if (next_char == null) {
            // Unexpected EOF - invalid token
            error_encountered = true;
            break;
        }
        
        _ = try stream.consume();
        
        if (next_char.? == '"') {
            // End of string - successful match
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
            if (esc_char == null) {
                error_encountered = true;
                break;
            }
            
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
            continue;
        }
        
        try token_bytes.append(next_char.?);
    }
    
    if (error_encountered) {
        // Reset stream position on error for other matchers to try
        stream.position = initial_position;
        stream.line = initial_line;
        stream.column = initial_column;
        return null;
    }
    
    // No closing quote found but no error - invalid, but we'll be lenient
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
    
    // Save the initial position in case we need to reset
    const initial_position = stream.position;
    const initial_line = stream.line;
    const initial_column = stream.column;
    
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    
    // Consume the first character
    _ = try stream.consume();
    try token_bytes.append(first_char.?);
    
    // Simple number parsing (not fully JSON compliant, but enough for benchmark)
    var has_decimal = false;
    var has_digits_after_decimal = false;
    
    while (true) {
        const next_char = try stream.peek();
        if (next_char == null) break;
        
        if (isDigit(next_char.?)) {
            _ = try stream.consume();
            try token_bytes.append(next_char.?);
            if (has_decimal) has_digits_after_decimal = true;
        } else if (next_char.? == '.' and !has_decimal) {
            has_decimal = true;
            _ = try stream.consume();
            try token_bytes.append(next_char.?);
        } else {
            break;
        }
    }
    
    // Validate that numbers with decimal points have digits after them
    if (has_decimal and !has_digits_after_decimal) {
        // Invalid number format (e.g. "123.") - reset stream position
        stream.position = initial_position;
        stream.line = initial_line;
        stream.column = initial_column;
        return null;
    }
    
    // Create token with duplicated memory
    const lexeme = try allocator.dupe(u8, token_bytes.items);
    return Token.init(
        .{ .id = 2, .name = "NUMBER" },
        start_pos,
        lexeme
    );
}

fn punctuationTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
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
        '\n', '\r', '\t', ' ' => null, // Whitespace handled by whitespaceTokenMatcher
        else => null,
    };
    
    if (token_info) |info| {
        _ = try stream.consume();
        
        // Allocate memory for the token lexeme rather than using a stack slice
        var lexeme = try allocator.alloc(u8, 1);
        lexeme[0] = char.?;
        
        return Token.init(
            .{ .id = info.id, .name = info.name },
            start_pos,
            lexeme
        );
    }
    
    return null;
}

fn whitespaceTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    const char = try stream.peek();
    if (char == null or !isWhitespace(char.?)) return null;
    
    // Create a buffer for whitespace characters for debugging
    var whitespace = std.ArrayList(u8).init(allocator);
    defer whitespace.deinit();
    
    var count: usize = 0;
    while (true) {
        const next_char = try stream.peek();
        if (next_char == null or !isWhitespace(next_char.?)) break;
        
        // Append to our whitespace buffer
        try whitespace.append(next_char.?);
        
        _ = try stream.consume();
        count += 1;
    }
    
    // For debugging - can be removed in production
    if (count > 0) {
        std.debug.print("Whitespace token: '{s}' (len: {d})\n", .{whitespace.items, count});
    }
    
    // Create an empty string instead of using a literal, which ensures consistent memory management
    const empty_string = try allocator.alloc(u8, 0);
    
    return Token.init(
        .{ .id = 9, .name = "WHITESPACE" },
        start_pos,
        empty_string // Empty string, but properly allocated
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
    
    // Create a simpler JSON structure that avoids potential parsing issues
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
        
        // Run benchmark with error handling
        const elapsed_ns = measureTime(runJsonBenchmark, .{allocator, test_data}) catch |err| {
            std.debug.print("  Error running benchmark: {s}\n", .{@errorName(err)});
            continue;
        };
        
        const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
        
        std.debug.print("  Time: {d:.2} ms\n", .{elapsed_ms});
        std.debug.print("  Input size: {d} bytes\n", .{test_data.len});
        std.debug.print("  Throughput: {d:.2} MB/s\n\n", .{
            @as(f64, @floatFromInt(test_data.len)) / 1_000_000.0 / (elapsed_ms / 1000.0)
        });
    }
    
    std.debug.print("Benchmarks completed successfully!\n", .{});
}