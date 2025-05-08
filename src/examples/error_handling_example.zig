const std = @import("std");
const lib = @import("zig_stream_parse_lib");

// Import our parser components
const ByteStream = lib.ByteStream;
const Position = lib.Position;
const Tokenizer = lib.Tokenizer;
const Token = lib.Token;
const TokenType = lib.TokenType;
const TokenMatcher = lib.TokenMatcher;
const StateTransition = lib.StateTransition;
const State = lib.State;
const EventEmitter = lib.EventEmitter;
const Event = lib.Event;
const EventType = lib.EventType;
const EventHandler = lib.EventHandler;
const ParserContext = lib.ParserContext;

// Import the enhanced error handling components
const ErrorContext = lib.ErrorContext;
const ErrorCode = lib.ErrorCode;
const ErrorSeverity = lib.ErrorSeverity;
const ErrorCategory = lib.ErrorCategory;
const ErrorReporter = lib.ErrorReporter;
const ErrorRecoveryStrategy = lib.ErrorRecoveryStrategy;
const StateMachine = lib.StateMachine;
const Parser = lib.Parser;

// ActionFn type
const ActionFn = *const fn(ctx: *ParserContext, token: Token) anyerror!void;

// Token types for a simple math expression grammar
const TOKEN_NUMBER = 1;
const TOKEN_PLUS = 2;
const TOKEN_MINUS = 3;
const TOKEN_MULTIPLY = 4;
const TOKEN_DIVIDE = 5;
const TOKEN_LPAREN = 6;
const TOKEN_RPAREN = 7;
const TOKEN_WHITESPACE = 8;

// Token matcher functions
fn numberTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Peek at the first character
    const first_char = try stream.peek();
    if (first_char == null) return null;
    
    // Check if it's a digit
    if (!isDigit(first_char.?)) return null;
    
    // Start of a number, consume it
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    
    // Consume the first character
    _ = try stream.consume();
    try token_bytes.append(first_char.?);
    
    // Continue consuming until we hit a non-digit character
    while (true) {
        const next_char = try stream.peek();
        if (next_char == null or !isDigit(next_char.?)) break;
        
        _ = try stream.consume();
        try token_bytes.append(next_char.?);
    }
    
    // Create the token
    const lexeme = try allocator.dupe(u8, token_bytes.items);
    return Token.init(
        .{ .id = TOKEN_NUMBER, .name = "NUMBER" },
        start_pos,
        lexeme
    );
}

fn operatorTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Peek at the first character
    const first_char = try stream.peek();
    if (first_char == null) return null;
    
    var token_type: TokenType = undefined;
    var token_name: []const u8 = undefined;
    
    // Check for operators
    switch (first_char.?) {
        '+' => {
            token_type = .{ .id = TOKEN_PLUS, .name = "PLUS" };
            token_name = "PLUS";
        },
        '-' => {
            token_type = .{ .id = TOKEN_MINUS, .name = "MINUS" };
            token_name = "MINUS";
        },
        '*' => {
            token_type = .{ .id = TOKEN_MULTIPLY, .name = "MULTIPLY" };
            token_name = "MULTIPLY";
        },
        '/' => {
            token_type = .{ .id = TOKEN_DIVIDE, .name = "DIVIDE" };
            token_name = "DIVIDE";
        },
        '(' => {
            token_type = .{ .id = TOKEN_LPAREN, .name = "LPAREN" };
            token_name = "LPAREN";
        },
        ')' => {
            token_type = .{ .id = TOKEN_RPAREN, .name = "RPAREN" };
            token_name = "RPAREN";
        },
        else => return null,
    }
    
    // Consume the operator
    _ = try stream.consume();
    
    // Create a byte array for the lexeme
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    try token_bytes.append(first_char.?);
    
    // Create the token
    const lexeme = try allocator.dupe(u8, token_bytes.items);
    return Token.init(token_type, start_pos, lexeme);
}

fn whitespaceTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Peek at the first character
    const first_char = try stream.peek();
    if (first_char == null) return null;
    
    // Check if it's whitespace
    if (!isWhitespace(first_char.?)) return null;
    
    // Start of whitespace, consume it
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    
    // Consume the first character
    _ = try stream.consume();
    try token_bytes.append(first_char.?);
    
    // Continue consuming until we hit a non-whitespace character
    while (true) {
        const next_char = try stream.peek();
        if (next_char == null or !isWhitespace(next_char.?)) break;
        
        _ = try stream.consume();
        try token_bytes.append(next_char.?);
    }
    
    // Create the token
    const lexeme = try allocator.dupe(u8, token_bytes.items);
    return Token.init(
        .{ .id = TOKEN_WHITESPACE, .name = "WHITESPACE" },
        start_pos,
        lexeme
    );
}

// Helper functions for character classification
fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

// Action functions for the state machine
fn emitNumber(ctx: *ParserContext, token: Token) !void {
    try ctx.pushValue(token.lexeme);
    std.debug.print("Number: {s}\n", .{token.lexeme});
}

fn emitOperator(ctx: *ParserContext, token: Token) !void {
    try ctx.pushValue(token.lexeme);
    std.debug.print("Operator: {s}\n", .{token.lexeme});
}

// Event handler that includes error events
fn handleEvent(event: Event, ctx: ?*anyopaque) !void {
    _ = ctx;
    switch (event.type) {
        .START_DOCUMENT => std.debug.print("Start Document\n", .{}),
        .END_DOCUMENT => std.debug.print("End Document\n", .{}),
        .VALUE => std.debug.print("Value: {s}\n", .{event.data.string_value}),
        .ERROR => std.debug.print("Error Event: {s}\n", .{event.data.error_info.message}),
        else => {},
    }
}

pub fn main() !void {
    // Setup allocator
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = general_purpose_allocator.allocator();
    defer _ = general_purpose_allocator.deinit();

    // Print welcome message
    std.debug.print("ZigParse: Error Handling Example\n", .{});

    // Create token matchers
    const number_matcher = TokenMatcher.init(numberTokenMatcher);
    const operator_matcher = TokenMatcher.init(operatorTokenMatcher);
    const whitespace_matcher = TokenMatcher.init(whitespaceTokenMatcher);

    // Create tokenizer configuration
    const matchers = [_]TokenMatcher{
        number_matcher,
        operator_matcher,
        whitespace_matcher,
    };
    
    const skip_types = [_]TokenType{
        .{ .id = TOKEN_WHITESPACE, .name = "WHITESPACE" },
    };

    // Create state machine configuration - simple expression grammar
    const action_fns = [_]ActionFn{
        emitNumber,
        emitOperator,
    };

    // Define a simple grammar for expressions
    // State 0: Expect number or lparen
    // State 1: Expect operator or rparen
    const transitions_state0 = [_]StateTransition{
        .{ .token_id = TOKEN_NUMBER, .next_state = 1, .action_id = 0 },  // NUMBER -> STATE_1 w/ emitNumber
        .{ .token_id = TOKEN_LPAREN, .next_state = 0, .action_id = 1 },  // LPAREN -> STATE_0 w/ emitOperator
    };
    
    const transitions_state1 = [_]StateTransition{
        .{ .token_id = TOKEN_PLUS, .next_state = 0, .action_id = 1 },    // PLUS -> STATE_0 w/ emitOperator
        .{ .token_id = TOKEN_MINUS, .next_state = 0, .action_id = 1 },   // MINUS -> STATE_0 w/ emitOperator
        .{ .token_id = TOKEN_MULTIPLY, .next_state = 0, .action_id = 1 }, // MULTIPLY -> STATE_0 w/ emitOperator
        .{ .token_id = TOKEN_DIVIDE, .next_state = 0, .action_id = 1 },  // DIVIDE -> STATE_0 w/ emitOperator
        .{ .token_id = TOKEN_RPAREN, .next_state = 1, .action_id = 1 },  // RPAREN -> STATE_1 w/ emitOperator
    };

    const states = [_]State{
        .{ .id = 0, .name = "EXPECT_NUMBER_OR_LPAREN", .transitions = &transitions_state0 },
        .{ .id = 1, .name = "EXPECT_OPERATOR_OR_RPAREN", .transitions = &transitions_state1 },
    };
    
    // Define synchronization tokens for error recovery
    const sync_token_types = [_]u32{
        TOKEN_NUMBER,
        TOKEN_PLUS,
        TOKEN_MINUS,
    };
    
    // Configure error recovery
    const recovery_config = .{
        .strategy = .synchronize, // Try to recover from errors
        .sync_token_types = &sync_token_types,
        .max_errors = 10, // Allow up to 10 errors before giving up
    };

    // Set up tokenizer config and state machine config
    const token_config = lib.TokenizerConfig{
        .matchers = &matchers,
        .skip_types = &skip_types,
    };

    const state_config = lib.StateMachineConfig{
        .states = &states,
        .actions = &action_fns,
        .initial_state_id = 0,  // Start expecting a number or lparen
        .recovery_config = recovery_config,
    };

    // Create example inputs - one correct, one with errors
    const correct_input = "123 + (45 * 67)";
    const error_input = "123 + ) * 45";  // Missing opening parenthesis

    // First parse the correct input
    std.debug.print("\n=== Parsing correct input: \"{s}\" ===\n", .{correct_input});
    
    var parser1 = try Parser.init(
        allocator,
        correct_input,
        token_config,
        state_config,
        1024, // buffer size
        .normal // Normal parsing mode
    );
    defer parser1.deinit();

    // Set event handler
    parser1.setEventHandler(EventHandler.init(handleEvent, null));

    // Parse the input
    parser1.parse() catch |err| {
        std.debug.print("\nError parsing correct input: {any}\n", .{err});
        try parser1.printErrors(); // Print all collected errors
    };
    
    // Now parse the input with errors
    std.debug.print("\n=== Parsing input with errors: \"{s}\" ===\n", .{error_input});
    
    var parser2 = try Parser.init(
        allocator,
        error_input,
        token_config,
        state_config,
        1024, // buffer size
        .normal // Normal parsing mode
    );
    defer parser2.deinit();

    // Set event handler
    parser2.setEventHandler(EventHandler.init(handleEvent, null));

    // Parse the input
    parser2.parse() catch |err| {
        std.debug.print("\nParsing failed with error: {any}\n", .{err});
        try parser2.printErrors(); // Print all collected errors
    };
    
    // Demonstrate strict parsing mode
    std.debug.print("\n=== Parsing with strict mode: \"{s}\" ===\n", .{error_input});
    
    var parser3 = try Parser.init(
        allocator,
        error_input,
        token_config,
        state_config,
        1024, // buffer size
        .strict // Strict parsing mode - stops on first error
    );
    defer parser3.deinit();

    // Set event handler
    parser3.setEventHandler(EventHandler.init(handleEvent, null));

    // Parse the input
    parser3.parse() catch |err| {
        std.debug.print("\nStrict parsing failed with error: {any}\n", .{err});
        try parser3.printErrors(); // Print all collected errors
    };
    
    // Demonstrate validation mode - collect all errors without recovery
    std.debug.print("\n=== Validation mode (collect all errors without recovery): \"{s}\" ===\n", .{error_input});
    
    var parser4 = try Parser.init(
        allocator,
        error_input,
        token_config,
        state_config,
        1024, // buffer size
        .validation // Validation mode - collect all errors without recovery
    );
    defer parser4.deinit();

    // Parse the input
    parser4.parse() catch |err| {
        std.debug.print("\nValidation found errors: {any}\n", .{err});
        try parser4.printErrors(); // Print all collected errors
    };
    
    // Demonstrate lenient mode - try hard to recover
    std.debug.print("\n=== Lenient mode (aggressive recovery): \"{s}\" ===\n", .{error_input});
    
    var parser5 = try Parser.init(
        allocator,
        error_input,
        token_config,
        state_config,
        1024, // buffer size
        .lenient // Lenient mode - aggressive recovery
    );
    defer parser5.deinit();

    // Parse the input
    parser5.parse() catch |err| {
        std.debug.print("\nLenient parsing failed with error: {any}\n", .{err});
        try parser5.printErrors(); // Print all collected errors
    };

    // Successfully completed the examples
    std.debug.print("\nAll examples completed\n", .{});
}