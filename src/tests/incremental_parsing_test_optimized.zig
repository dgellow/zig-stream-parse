const std = @import("std");
const testing = std.testing;
const ByteStream = @import("byte_stream_optimized").ByteStream;
const Tokenizer = @import("tokenizer").Tokenizer;
const Token = @import("tokenizer").Token;
const TokenType = @import("tokenizer").TokenType;
const TokenMatcher = @import("tokenizer").TokenMatcher;
const Parser = @import("parser_optimized").Parser;
const IncrementalOptions = @import("parser_optimized").IncrementalOptions;
const ParseMode = @import("parser_optimized").ParseMode;
const StateMachine = @import("state_machine").StateMachine;
const State = @import("state_machine").State;
const StateTransition = @import("state_machine").StateTransition;
const types = @import("types");
const ParserContext = types.ParserContext;
const ActionFn = types.ActionFn;
const EventEmitter = @import("event_emitter").EventEmitter;
const Event = @import("event_emitter").Event;
const EventType = @import("event_emitter").EventType;
const EventHandler = @import("event_emitter").EventHandler;
const Position = @import("common").Position;

// Simple test grammar that recognizes numbers, strings, and operators
const TOKEN_NUMBER = 1;
const TOKEN_STRING = 2;
const TOKEN_PLUS = 3;
const TOKEN_MINUS = 4;
const TOKEN_WHITESPACE = 5;

const STATE_EXPRESSION = 0;
const STATE_OPERATOR = 1;

// Simple actions that just update the context
fn emitNumberAction(ctx: *ParserContext, token: Token) !void {
    try ctx.pushValue(token.lexeme);
}

fn emitStringAction(ctx: *ParserContext, token: Token) !void {
    try ctx.pushValue(token.lexeme);
}

fn emitAddAction(ctx: *ParserContext, token: Token) !void {
    _ = token;
    
    const b_str = ctx.popValue() orelse return error.InvalidExpression;
    const a_str = ctx.popValue() orelse return error.InvalidExpression;
    
    // Simple integer addition
    const a = try std.fmt.parseInt(i32, a_str, 10);
    const b = try std.fmt.parseInt(i32, b_str, 10);
    
    const result = a + b;
    var result_buf: [16]u8 = undefined;
    const result_str = try std.fmt.bufPrint(&result_buf, "{d}", .{result});
    
    try ctx.pushValue(result_str);
}

fn emitSubtractAction(ctx: *ParserContext, token: Token) !void {
    _ = token;
    
    const b_str = ctx.popValue() orelse return error.InvalidExpression;
    const a_str = ctx.popValue() orelse return error.InvalidExpression;
    
    // Simple integer subtraction
    const a = try std.fmt.parseInt(i32, a_str, 10);
    const b = try std.fmt.parseInt(i32, b_str, 10);
    
    const result = a - b;
    var result_buf: [16]u8 = undefined;
    const result_str = try std.fmt.bufPrint(&result_buf, "{d}", .{result});
    
    try ctx.pushValue(result_str);
}

// Function to match numbers
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
        TokenType{ .id = TOKEN_NUMBER, .name = "NUMBER" },
        start_pos,
        lexeme
    );
}

// Function to match strings
fn stringMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    var token_buf = std.ArrayList(u8).init(allocator);
    defer token_buf.deinit();
    
    // Check if first character is a quote
    const first = try stream.peek();
    if (first == null or first.? != '"') {
        return null;
    }
    
    // Consume opening quote
    _ = try stream.consume();
    try token_buf.append('"');
    
    // Consume characters until closing quote
    while (true) {
        const byte = try stream.peek();
        if (byte == null) {
            return error.UnterminatedString;
        }
        
        _ = try stream.consume();
        try token_buf.append(byte.?);
        
        if (byte.? == '"') {
            break;
        }
    }
    
    // Create token result
    const lexeme = try allocator.dupe(u8, token_buf.items);
    return Token.init(
        TokenType{ .id = TOKEN_STRING, .name = "STRING" },
        start_pos,
        lexeme
    );
}

// Function to match plus operator
fn plusMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    const byte = try stream.peek();
    if (byte == null or byte.? != '+') {
        return null;
    }
    
    _ = try stream.consume();
    
    const lexeme = try allocator.dupe(u8, "+");
    return Token.init(
        TokenType{ .id = TOKEN_PLUS, .name = "PLUS" },
        start_pos,
        lexeme
    );
}

// Function to match minus operator
fn minusMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    const byte = try stream.peek();
    if (byte == null or byte.? != '-') {
        return null;
    }
    
    _ = try stream.consume();
    
    const lexeme = try allocator.dupe(u8, "-");
    return Token.init(
        TokenType{ .id = TOKEN_MINUS, .name = "MINUS" },
        start_pos,
        lexeme
    );
}

// Function to match whitespace
fn whitespaceMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    var token_buf = std.ArrayList(u8).init(allocator);
    defer token_buf.deinit();
    
    // Consume whitespace
    var found = false;
    while (true) {
        const byte = try stream.peek();
        if (byte == null or !std.ascii.isWhitespace(byte.?)) {
            break;
        }
        
        found = true;
        try token_buf.append(byte.?);
        _ = try stream.consume();
    }
    
    if (!found) {
        return null;
    }
    
    // Create token result
    const lexeme = try allocator.dupe(u8, token_buf.items);
    return Token.init(
        TokenType{ .id = TOKEN_WHITESPACE, .name = "WHITESPACE" },
        start_pos,
        lexeme
    );
}

// Test using the optimized incremental parser
test "Optimized Incremental Parsing" {
    const allocator = testing.allocator;
    
    // Define token matchers
    var matchers = [_]TokenMatcher{
        TokenMatcher.init(numberMatcher),
        TokenMatcher.init(stringMatcher),
        TokenMatcher.init(plusMatcher),
        TokenMatcher.init(minusMatcher),
        TokenMatcher.init(whitespaceMatcher),
    };
    
    // Skip whitespace
    var skip_types = [_]TokenType{
        TokenType{ .id = TOKEN_WHITESPACE, .name = "WHITESPACE" },
    };
    
    // Define states
    var state0 = State.init(
        STATE_EXPRESSION,
        "EXPRESSION",
        &[_]StateTransition{
            StateTransition.init(TOKEN_NUMBER, STATE_OPERATOR, 0), // emitNumberAction
            StateTransition.init(TOKEN_STRING, STATE_OPERATOR, 1), // emitStringAction
        }
    );
    
    var state1 = State.init(
        STATE_OPERATOR,
        "OPERATOR",
        &[_]StateTransition{
            StateTransition.init(TOKEN_PLUS, STATE_EXPRESSION, null), // No action yet
            StateTransition.init(TOKEN_MINUS, STATE_EXPRESSION, null), // No action yet
            StateTransition.init(TOKEN_NUMBER, STATE_EXPRESSION, 2), // emitAddAction
            StateTransition.init(TOKEN_STRING, STATE_EXPRESSION, 3), // emitSubtractAction
        }
    );
    
    var states = [_]State{ state0, state1 };
    
    // Define actions
    var actions = [_]ActionFn{
        emitNumberAction,
        emitStringAction,
        emitAddAction,
        emitSubtractAction,
    };
    
    // Set up tokenizer config
    const tokenizer_config = .{
        .matchers = &matchers,
        .skip_types = &skip_types,
    };
    
    // Set up state machine config
    const state_machine_config = .{
        .states = &states,
        .actions = &actions,
        .initial_state_id = STATE_EXPRESSION,
    };
    
    // Create a parser with incremental parsing options
    const incremental_options = IncrementalOptions{
        .initial_buffer_size = 64,
        .max_buffer_size = 4096,
        .auto_compact = true,
        .compact_threshold = 0.25,
    };
    
    var parser = try Parser.initIncrementalParser(
        allocator,
        tokenizer_config,
        state_machine_config,
        incremental_options,
        .normal
    );
    defer parser.deinit();
    
    // Create an event handler that records events
    var events = std.ArrayList(Event).init(allocator);
    defer {
        for (events.items) |event| {
            if (event.type == .VALUE) {
                allocator.free(event.data.string_value);
            }
        }
        events.deinit();
    }
    
    const event_handler = EventHandler{
        .handle_fn = struct {
            fn handle(event: Event, ctx: ?*anyopaque) !void {
                const list = @as(*std.ArrayList(Event), @ptrCast(ctx.?));
                
                // Clone the event because it might be temporary
                var cloned_event = event;
                if (event.type == .VALUE) {
                    cloned_event.data.string_value = try list.allocator.dupe(u8, event.data.string_value);
                }
                
                try list.append(cloned_event);
            }
        }.handle,
        .context = &events,
    };
    
    parser.setEventHandler(event_handler);
    
    // Process chunks incrementally
    try parser.processChunk("10 + ");
    
    // Get buffer stats after first chunk
    const stats1 = parser.getBufferStats().?;
    try testing.expect(stats1.buffer_size >= 5); // "10 + " is 5 bytes
    try testing.expect(stats1.total_consumed > 0);
    
    try parser.processChunk("20 - ");
    
    // Get buffer stats after second chunk
    const stats2 = parser.getBufferStats().?;
    try testing.expect(stats2.total_consumed > stats1.total_consumed);
    
    try parser.processChunk("5");
    
    // Finish parsing
    try parser.finishChunks();
    
    // Check events
    try testing.expectEqual(@as(usize, 2), events.items.len);
    try testing.expectEqual(EventType.START_DOCUMENT, events.items[0].type);
    try testing.expectEqual(EventType.END_DOCUMENT, events.items[1].type);
    
    // Check the result
    const result = parser.handle.data.context.value_stack.items[0];
    try testing.expectEqualStrings("25", result);
}

// Test buffer management and performance with large data
test "Optimized Incremental Parsing With Large Data" {
    const allocator = testing.allocator;
    
    // Define token matchers
    var matchers = [_]TokenMatcher{
        TokenMatcher.init(numberMatcher),
        TokenMatcher.init(plusMatcher),
        TokenMatcher.init(whitespaceMatcher),
    };
    
    // Skip whitespace
    var skip_types = [_]TokenType{
        TokenType{ .id = TOKEN_WHITESPACE, .name = "WHITESPACE" },
    };
    
    // Define simplified states for performance testing
    var state0 = State.init(
        0,
        "NUMBER",
        &[_]StateTransition{
            StateTransition.init(TOKEN_NUMBER, 1, 0), // emitNumberAction
        }
    );
    
    var state1 = State.init(
        1,
        "OPERATOR",
        &[_]StateTransition{
            StateTransition.init(TOKEN_PLUS, 0, null),
            StateTransition.init(TOKEN_NUMBER, 1, 2), // emitAddAction
        }
    );
    
    var states = [_]State{ state0, state1 };
    
    // Define actions
    var actions = [_]ActionFn{
        emitNumberAction,
        emitStringAction,
        emitAddAction,
    };
    
    // Set up configs
    const tokenizer_config = .{
        .matchers = &matchers,
        .skip_types = &skip_types,
    };
    
    const state_machine_config = .{
        .states = &states,
        .actions = &actions,
        .initial_state_id = 0,
    };
    
    // Test with different buffer sizes
    const buffer_sizes = [_]usize{ 64, 256, 1024, 4096 };
    
    for (buffer_sizes) |buffer_size| {
        // Create incremental options with specific buffer size
        const incremental_options = IncrementalOptions{
            .initial_buffer_size = buffer_size,
            .max_buffer_size = 16 * 1024, // 16KB max
            .auto_compact = true,
            .compact_threshold = 0.25,
        };
        
        var parser = try Parser.initIncrementalParser(
            allocator,
            tokenizer_config,
            state_machine_config,
            incremental_options,
            .normal
        );
        defer parser.deinit();
        
        // Generate a large test string with numbers and plus signs
        var test_data = std.ArrayList(u8).init(allocator);
        defer test_data.deinit();
        
        const num_elements = 1000; // 1000 numbers to sum
        var expected_sum: i32 = 0;
        
        for (0..num_elements) |i| {
            // Each number is i*2
            const num = @as(i32, @intCast(i)) * 2;
            expected_sum += num;
            
            // Convert to string
            var num_buf: [16]u8 = undefined;
            const num_str = try std.fmt.bufPrint(&num_buf, "{d}", .{num});
            
            // Add to test data
            try test_data.appendSlice(num_str);
            
            // Add plus between numbers (except last one)
            if (i < num_elements - 1) {
                try test_data.append(' ');
                try test_data.append('+');
                try test_data.append(' ');
            }
        }
        
        // Process in chunks of various sizes
        const chunk_sizes = [_]usize{ 128, 512, 2048 };
        
        for (chunk_sizes) |chunk_size| {
            // Reset parser
            try parser.reset();
            
            // Parse in chunks
            var offset: usize = 0;
            while (offset < test_data.items.len) {
                const remaining = test_data.items.len - offset;
                const size = @min(chunk_size, remaining);
                const chunk = test_data.items[offset..offset+size];
                
                try parser.processChunk(chunk);
                offset += size;
                
                // Check buffer stats periodically
                if (offset % (chunk_size * 4) == 0) {
                    const stats = parser.getBufferStats().?;
                    try testing.expect(stats.buffer_size <= incremental_options.max_buffer_size);
                    try testing.expect(stats.total_consumed > 0);
                }
            }
            
            // Finish parsing
            try parser.finishChunks();
            
            // Check result
            const result = parser.handle.data.context.value_stack.items[0];
            const parsed_result = try std.fmt.parseInt(i32, result, 10);
            try testing.expectEqual(expected_sum, parsed_result);
            
            // Check final buffer stats
            const final_stats = parser.getBufferStats().?;
            try testing.expectEqual(@as(usize, test_data.items.len), final_stats.total_consumed);
        }
    }
}

// Test error recovery with the optimized parser
test "Optimized Incremental Parsing Error Recovery" {
    const allocator = testing.allocator;
    
    // Define token matchers
    var matchers = [_]TokenMatcher{
        TokenMatcher.init(numberMatcher),
        TokenMatcher.init(plusMatcher),
        TokenMatcher.init(minusMatcher),
        TokenMatcher.init(whitespaceMatcher),
    };
    
    // Skip whitespace
    var skip_types = [_]TokenType{
        TokenType{ .id = TOKEN_WHITESPACE, .name = "WHITESPACE" },
    };
    
    // Define states
    var state0 = State.init(
        0,
        "NUMBER",
        &[_]StateTransition{
            StateTransition.init(TOKEN_NUMBER, 1, 0), // emitNumberAction
        }
    );
    
    var state1 = State.init(
        1,
        "OPERATOR",
        &[_]StateTransition{
            StateTransition.init(TOKEN_PLUS, 0, null),
            StateTransition.init(TOKEN_MINUS, 0, null),
        }
    );
    
    var states = [_]State{ state0, state1 };
    
    // Define actions
    var actions = [_]ActionFn{
        emitNumberAction,
    };
    
    // Set up configs
    const tokenizer_config = .{
        .matchers = &matchers,
        .skip_types = &skip_types,
    };
    
    const state_machine_config = .{
        .states = &states,
        .actions = &actions,
        .initial_state_id = 0,
    };
    
    // Create a parser in lenient mode for error recovery
    const incremental_options = IncrementalOptions{
        .initial_buffer_size = 64,
        .max_buffer_size = 1024,
        .auto_compact = true,
        .compact_threshold = 0.25,
    };
    
    var parser = try Parser.initIncrementalParser(
        allocator,
        tokenizer_config,
        state_machine_config,
        incremental_options,
        .lenient // Use lenient mode
    );
    defer parser.deinit();
    
    // Valid chunk
    try parser.processChunk("10 + ");
    
    // Invalid chunk (operator after operator)
    try parser.processChunk("- ");
    
    // Valid chunk
    try parser.processChunk("20");
    
    // Finish parsing
    try parser.finishChunks();
    
    // Check that we have errors but parsing completed
    try testing.expect(parser.hasErrors());
    
    // Check that buffer was properly managed
    const stats = parser.getBufferStats().?;
    try testing.expect(stats.total_consumed > 0);
}

// Test the performance and memory usage of the optimized buffer management
test "Buffer Management Performance" {
    const allocator = testing.allocator;
    
    // Create a ByteStream with a small buffer
    var stream = try ByteStream.fromMemory(allocator, "", 64);
    defer stream.deinit();
    
    // Track initial memory state
    const initial_stats = stream.getStats();
    try testing.expectEqual(@as(usize, 0), initial_stats.used_space);
    try testing.expectEqual(@as(usize, 64), initial_stats.buffer_size);
    
    // Generate a large amount of data
    const total_data_size = 100 * 1024; // 100KB
    const chunk_size = 1024; // 1KB chunks
    var test_data = try allocator.alloc(u8, total_data_size);
    defer allocator.free(test_data);
    
    // Fill with test pattern
    for (0..total_data_size) |i| {
        test_data[i] = @as(u8, @truncate(i % 256));
    }
    
    // Process data in chunks
    var total_processed: usize = 0;
    var total_compacted: usize = 0;
    var total_grown: usize = 0;
    
    while (total_processed < total_data_size) {
        const remaining = total_data_size - total_processed;
        const size = @min(chunk_size, remaining);
        const chunk = test_data[total_processed..total_processed+size];
        
        // Append chunk
        try stream.append(chunk);
        total_processed += size;
        
        // Consume some data (75% of the chunk)
        const to_consume = (size * 3) / 4;
        var consumed: usize = 0;
        while (consumed < to_consume) {
            _ = try stream.consume();
            consumed += 1;
        }
        
        // Check stats
        const stats = stream.getStats();
        
        // We don't have access to compactions and growths counters directly in
        // the optimized ByteStream's getStats() method, so we'll track based on buffer changes
        
        // Check if buffer was likely compacted (buffer size is same but used_space changed)
        if (stats.used_space < stream.buffer_end) {
            total_compacted += 1;
        }
        
        // Check if buffer was grown (buffer size increased)
        if (stats.buffer_size > stream.buffer.len) {
            total_grown += 1;
        }
    }
    
    // Consume remaining data
    while (try stream.peek() != null) {
        _ = try stream.consume();
    }
    
    // Check final stats
    const final_stats = stream.getStats();
    try testing.expectEqual(@as(usize, total_data_size), final_stats.total_consumed);
    
    // Check that we had to grow the buffer at least once
    try testing.expect(final_stats.grow_count > 0);
    
    // Check that we've compacted the buffer at least once
    try testing.expect(final_stats.compact_count > 0);
    
    // Buffer should be larger than initial size
    try testing.expect(final_stats.buffer_size > 64);
    
    // Buffer should be smaller than total data size due to compaction
    try testing.expect(final_stats.buffer_size < total_data_size);
}

// Test handling of multiple reset operations
test "Multiple Reset Operations" {
    const allocator = testing.allocator;
    
    // Create a ByteStream for memory source
    var stream = try ByteStream.fromMemory(allocator, "Initial content", 64);
    defer stream.deinit();
    
    // Consume part of the initial content
    for (0..8) |_| {
        _ = try stream.consume();
    }
    
    // Append new data
    try stream.append(" Additional");
    
    // Reset the stream
    try stream.reset();
    
    // Position should be reset
    try testing.expectEqual(@as(usize, 0), stream.position);
    try testing.expectEqual(@as(usize, 1), stream.line);
    try testing.expectEqual(@as(usize, 1), stream.column);
    
    // First character should be 'I' again
    try testing.expectEqual(@as(u8, 'I'), (try stream.peek()).?);
    
    // Consume all data
    while (try stream.peek() != null) {
        _ = try stream.consume();
    }
    
    // Reset again
    try stream.reset();
    
    // Position should be reset again
    try testing.expectEqual(@as(usize, 0), stream.position);
    
    // First character should still be 'I'
    try testing.expectEqual(@as(u8, 'I'), (try stream.peek()).?);
}

// Test error handling with unterminated strings
test "Error Handling with Unterminated Strings" {
    const allocator = testing.allocator;
    
    // Define token matchers
    var matchers = [_]TokenMatcher{
        TokenMatcher.init(numberMatcher),
        TokenMatcher.init(stringMatcher),
        TokenMatcher.init(plusMatcher),
        TokenMatcher.init(whitespaceMatcher),
    };
    
    // Skip whitespace
    var skip_types = [_]TokenType{
        TokenType{ .id = TOKEN_WHITESPACE, .name = "WHITESPACE" },
    };
    
    // Define simple state
    var state0 = State.init(
        0,
        "ANY",
        &[_]StateTransition{
            StateTransition.init(TOKEN_NUMBER, 0, null),
            StateTransition.init(TOKEN_STRING, 0, null),
            StateTransition.init(TOKEN_PLUS, 0, null),
        }
    );
    
    var states = [_]State{state0};
    var actions = [_]ActionFn{};
    
    // Set up configs
    const tokenizer_config = .{
        .matchers = &matchers,
        .skip_types = &skip_types,
    };
    
    const state_machine_config = .{
        .states = &states,
        .actions = &actions,
        .initial_state_id = 0,
    };
    
    // Create a parser in validation mode to collect errors
    const incremental_options = IncrementalOptions{
        .initial_buffer_size = 64,
        .max_buffer_size = 1024,
    };
    
    var parser = try Parser.initIncrementalParser(
        allocator,
        tokenizer_config,
        state_machine_config,
        incremental_options,
        .validation // Use validation mode
    );
    defer parser.deinit();
    
    // Valid chunk
    try parser.processChunk("123 + ");
    
    // Start string in one chunk
    try parser.processChunk("\"This is the start of a string");
    
    // Try to finish parsing - should detect unterminated string
    const result = parser.finishChunks();
    try testing.expectError(error.UnterminatedString, result);
}

// Test compatibility with different optimized ByteStream sources
test "Different ByteStream Sources" {
    const allocator = testing.allocator;
    
    // Test with memory source
    {
        var stream = try ByteStream.fromMemory(allocator, "Memory source test", 64);
        defer stream.deinit();
        
        try testing.expectEqual(@as(u8, 'M'), (try stream.peek()).?);
        try stream.append(" - Appended");
        
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();
        
        while (try stream.peek()) |byte| {
            _ = try stream.consume();
            try result.append(byte);
        }
        
        try testing.expectEqualStrings("Memory source test - Appended", result.items);
    }
    
    // Test with buffer source
    {
        var buffer = try allocator.alloc(u8, 64);
        defer allocator.free(buffer);
        
        var stream = ByteStream.withBuffer(allocator, buffer);
        defer stream.deinit();
        
        try stream.append("Buffer source test");
        
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();
        
        while (try stream.peek()) |byte| {
            _ = try stream.consume();
            try result.append(byte);
        }
        
        try testing.expectEqualStrings("Buffer source test", result.items);
    }
}

// Test integration with error reporting
test "Error Reporting Integration" {
    const allocator = testing.allocator;
    
    // Define token matchers
    var matchers = [_]TokenMatcher{
        TokenMatcher.init(numberMatcher),
        TokenMatcher.init(plusMatcher),
        TokenMatcher.init(whitespaceMatcher),
    };
    
    // Skip whitespace
    var skip_types = [_]TokenType{
        TokenType{ .id = TOKEN_WHITESPACE, .name = "WHITESPACE" },
    };
    
    // Define states that will produce errors
    var state0 = State.init(
        0,
        "NUMBER",
        &[_]StateTransition{
            StateTransition.init(TOKEN_NUMBER, 1, 0), // emitNumberAction
        }
    );
    
    var state1 = State.init(
        1,
        "PLUS",
        &[_]StateTransition{
            StateTransition.init(TOKEN_PLUS, 0, null),
        }
    );
    
    var states = [_]State{ state0, state1 };
    var actions = [_]ActionFn{emitNumberAction};
    
    // Set up configs
    const tokenizer_config = .{
        .matchers = &matchers,
        .skip_types = &skip_types,
    };
    
    const state_machine_config = .{
        .states = &states,
        .actions = &actions,
        .initial_state_id = 0,
    };
    
    // Create a parser in validation mode
    const incremental_options = IncrementalOptions{
        .initial_buffer_size = 64,
        .max_buffer_size = 1024,
    };
    
    var parser = try Parser.initIncrementalParser(
        allocator,
        tokenizer_config,
        state_machine_config,
        incremental_options,
        .validation // Use validation mode
    );
    defer parser.deinit();
    
    // This should parse fine
    try parser.processChunk("123 + 456");
    
    // This should produce an error (number followed by number)
    // State machine expects PLUS after a number
    try parser.processChunk(" 789");
    
    // Finish parsing - in validation mode, it shouldn't fail
    try parser.finishChunks();
    
    // Check that errors were collected
    try testing.expect(parser.hasErrors());
    const errors = parser.getErrors();
    try testing.expect(errors.len > 0);
}

// Test with many small chunks (stress test)
test "Many Small Chunks Stress Test" {
    const allocator = testing.allocator;
    
    // Define a simple state machine that just consumes text
    var matcher = TokenMatcher.init(struct {
        fn match(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
            const start_pos = stream.getPosition();
            var token_buf = std.ArrayList(u8).init(allocator);
            defer token_buf.deinit();
            
            // Consume any character
            const byte = try stream.peek();
            if (byte == null) {
                return null;
            }
            
            _ = try stream.consume();
            try token_buf.append(byte.?);
            
            // Create token result
            const lexeme = try allocator.dupe(u8, token_buf.items);
            return Token.init(
                TokenType{ .id = 1, .name = "CHAR" },
                start_pos,
                lexeme
            );
        }
    }.match);
    
    var matchers = [_]TokenMatcher{matcher};
    var skip_types = [_]TokenType{};
    
    // State machine that accepts any token
    var state0 = State.init(
        0,
        "ANY",
        &[_]StateTransition{
            StateTransition.init(1, 0, null),
        }
    );
    
    var states = [_]State{state0};
    var actions = [_]ActionFn{};
    
    // Set up configs
    const tokenizer_config = .{
        .matchers = &matchers,
        .skip_types = &skip_types,
    };
    
    const state_machine_config = .{
        .states = &states,
        .actions = &actions,
        .initial_state_id = 0,
    };
    
    // Create a parser with a small buffer
    const incremental_options = IncrementalOptions{
        .initial_buffer_size = 16,
        .max_buffer_size = 1024,
        .auto_compact = true,
        .compact_threshold = 0.5,
    };
    
    var parser = try Parser.initIncrementalParser(
        allocator,
        tokenizer_config,
        state_machine_config,
        incremental_options,
        .normal
    );
    defer parser.deinit();
    
    // Process many tiny chunks (1-2 bytes each)
    const total_chunks = 1000;
    var total_bytes: usize = 0;
    
    for (0..total_chunks) |i| {
        // Create a tiny chunk
        var chunk_buf: [2]u8 = undefined;
        const chunk_len = (i % 2) + 1; // Either 1 or 2 bytes
        
        for (0..chunk_len) |j| {
            chunk_buf[j] = @as(u8, @truncate(65 + (i + j) % 26)); // A-Z
        }
        
        try parser.processChunk(chunk_buf[0..chunk_len]);
        total_bytes += chunk_len;
        
        // Every 100 chunks, check buffer stats
        if (i % 100 == 0) {
            const stats = parser.getBufferStats().?;
            try testing.expect(stats.buffer_size <= incremental_options.max_buffer_size);
        }
    }
    
    // Finish parsing
    try parser.finishChunks();
    
    // Check final buffer stats
    const final_stats = parser.getBufferStats().?;
    try testing.expectEqual(total_bytes, final_stats.total_consumed);
}