const std = @import("std");
const testing = std.testing;
const Parser = @import("parser").Parser;
const StateMachine = @import("parser").StateMachine;
const State = @import("parser").State;
const StateTransition = @import("parser").StateTransition;
const Token = @import("parser").Token;
const TokenType = @import("parser").TokenType;
const TokenMatcher = @import("parser").TokenMatcher;
const ParserContext = @import("parser").ParserContext;
const ActionFn = @import("parser").ActionFn;
const ByteStream = @import("parser").ByteStream;
const Event = @import("parser").Event;
const EventType = @import("parser").EventType;
const EventHandler = @import("parser").EventHandler;
const Position = @import("parser").Position;

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

// Test incremental parsing with a simple expression grammar
test "Incremental Parsing" {
    const allocator = testing.allocator;
    
    // Define token matchers
    const matchers = [_]TokenMatcher{
        TokenMatcher.init(numberMatcher),
        TokenMatcher.init(stringMatcher),
        TokenMatcher.init(plusMatcher),
        TokenMatcher.init(minusMatcher),
        TokenMatcher.init(whitespaceMatcher),
    };
    
    // Skip whitespace
    const skip_types = [_]TokenType{
        TokenType{ .id = TOKEN_WHITESPACE, .name = "WHITESPACE" },
    };
    
    // Define states
    const states = [_]State{
        // STATE_EXPRESSION - can take a number/string and go to operator state
        State{
            .id = STATE_EXPRESSION,
            .name = "EXPRESSION",
            .transitions = &[_]StateTransition{
                StateTransition{
                    .token_id = TOKEN_NUMBER,
                    .next_state = STATE_OPERATOR,
                    .action_id = 0, // emitNumberAction
                },
                StateTransition{
                    .token_id = TOKEN_STRING,
                    .next_state = STATE_OPERATOR,
                    .action_id = 1, // emitStringAction
                },
            },
        },
        // STATE_OPERATOR - can take an operator and go back to expression state
        State{
            .id = STATE_OPERATOR,
            .name = "OPERATOR",
            .transitions = &[_]StateTransition{
                StateTransition{
                    .token_id = TOKEN_PLUS,
                    .next_state = STATE_EXPRESSION,
                    .action_id = null, // No action yet
                },
                StateTransition{
                    .token_id = TOKEN_MINUS,
                    .next_state = STATE_EXPRESSION,
                    .action_id = null, // No action yet
                },
                StateTransition{
                    .token_id = TOKEN_NUMBER,
                    .next_state = STATE_EXPRESSION,
                    .action_id = 2, // emitAddAction or emitSubtractAction based on previous token
                },
                StateTransition{
                    .token_id = TOKEN_STRING,
                    .next_state = STATE_EXPRESSION,
                    .action_id = 3, // Same as above
                },
            },
        },
    };
    
    // Define actions
    const actions = [_]ActionFn{
        emitNumberAction,
        emitStringAction,
        emitAddAction,
        emitSubtractAction,
    };
    
    // Set up tokenizer config
    const tokenizer_config = @import("parser").TokenizerConfig{
        .matchers = &matchers,
        .skip_types = &skip_types,
    };
    
    // Set up state machine config
    const state_machine_config = @import("parser").StateMachineConfig{
        .states = &states,
        .actions = &actions,
        .initial_state_id = STATE_EXPRESSION,
    };
    
    // Create a parser with incremental parsing
    var events = std.ArrayList(Event).init(allocator);
    defer {
        for (events.items) |event| {
            if (event.type == .VALUE) {
                allocator.free(event.data.string_value);
            }
        }
        events.deinit();
    }
    
    // Create an event handler that records events
    const event_handler = EventHandler{
        .handle_fn = struct {
            fn handle(event: Event, ctx: ?*anyopaque) !void {
                const list = @as(*std.ArrayList(Event), @ptrCast(@alignCast(ctx)));
                
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
    
    // Create a parser with an initial source (not starting with process)
    var parser = try Parser.init(
        allocator,
        "0", // Initial content needs at least one character
        tokenizer_config,
        state_machine_config,
        4096
    );
    defer parser.deinit();
    
    parser.setEventHandler(event_handler);
    
    // Process chunks incrementally
    try parser.process("10 + ");
    try parser.process("20 - ");
    try parser.process("5");
    try parser.finish();
    
    // Check context
    const context = parser.handle.data.context;
    try testing.expectEqual(@as(usize, 1), context.value_stack.items.len);
    
    // Result should be 25
    const result = context.value_stack.items[0];
    try testing.expectEqualStrings("25", result);
    
    // Check events
    try testing.expectEqual(@as(usize, 2), events.items.len);
    try testing.expectEqual(EventType.START_DOCUMENT, events.items[0].type);
    try testing.expectEqual(EventType.END_DOCUMENT, events.items[1].type);
}

// Test error handling during incremental parsing
test "Incremental Parsing Errors" {
    const allocator = testing.allocator;
    
    // Define token matchers
    const matchers = [_]TokenMatcher{
        TokenMatcher.init(numberMatcher),
        TokenMatcher.init(stringMatcher),
        TokenMatcher.init(plusMatcher),
        TokenMatcher.init(minusMatcher),
        TokenMatcher.init(whitespaceMatcher),
    };
    
    // Skip whitespace
    const skip_types = [_]TokenType{
        TokenType{ .id = TOKEN_WHITESPACE, .name = "WHITESPACE" },
    };
    
    // Define states
    const states = [_]State{
        // STATE_EXPRESSION - can take a number/string and go to operator state
        State{
            .id = STATE_EXPRESSION,
            .name = "EXPRESSION",
            .transitions = &[_]StateTransition{
                StateTransition{
                    .token_id = TOKEN_NUMBER,
                    .next_state = STATE_OPERATOR,
                    .action_id = 0, // emitNumberAction
                },
                StateTransition{
                    .token_id = TOKEN_STRING,
                    .next_state = STATE_OPERATOR,
                    .action_id = 1, // emitStringAction
                },
            },
        },
        // STATE_OPERATOR - can take an operator and go back to expression state
        State{
            .id = STATE_OPERATOR,
            .name = "OPERATOR",
            .transitions = &[_]StateTransition{
                StateTransition{
                    .token_id = TOKEN_PLUS,
                    .next_state = STATE_EXPRESSION,
                    .action_id = null, // No action yet
                },
                StateTransition{
                    .token_id = TOKEN_MINUS,
                    .next_state = STATE_EXPRESSION,
                    .action_id = null, // No action yet
                },
                StateTransition{
                    .token_id = TOKEN_NUMBER,
                    .next_state = STATE_EXPRESSION,
                    .action_id = 2, // emitAddAction or emitSubtractAction based on previous token
                },
                StateTransition{
                    .token_id = TOKEN_STRING,
                    .next_state = STATE_EXPRESSION,
                    .action_id = 3, // Same as above
                },
            },
        },
    };
    
    // Define actions
    const actions = [_]ActionFn{
        emitNumberAction,
        emitStringAction,
        emitAddAction,
        emitSubtractAction,
    };
    
    // Set up tokenizer config
    const tokenizer_config = @import("parser").TokenizerConfig{
        .matchers = &matchers,
        .skip_types = &skip_types,
    };
    
    // Set up state machine config
    const state_machine_config = @import("parser").StateMachineConfig{
        .states = &states,
        .actions = &actions,
        .initial_state_id = STATE_EXPRESSION,
    };
    
    // Test calling finish() before process()
    {
        var parser = try Parser.init(
            allocator,
            "0",
            tokenizer_config,
            state_machine_config,
            4096
        );
        defer parser.deinit();
        
        const finish_result = parser.finish();
        try testing.expectError(error.ParsingNotStarted, finish_result);
    }
    
    // Test parsing invalid tokens (unterminated string)
    {
        var parser = try Parser.init(
            allocator,
            "0",
            tokenizer_config,
            state_machine_config,
            4096
        );
        defer parser.deinit();
        
        // Process valid chunk
        try parser.process("10 + ");
        
        // Process invalid chunk (unterminated string)
        const error_result = parser.process("\"this is an unterminated string");
        try testing.expectError(error.UnterminatedString, error_result);
    }
    
    // Test unexpected token
    {
        var parser = try Parser.init(
            allocator,
            "0",
            tokenizer_config,
            state_machine_config,
            4096
        );
        defer parser.deinit();
        
        // State machine doesn't expect a plus at the beginning
        const error_result = parser.process("+ 10");
        try testing.expectError(error.UnexpectedToken, error_result);
    }
}