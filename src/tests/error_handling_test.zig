const std = @import("std");
const lib = @import("../zig_stream_parse.zig");

const testing = std.testing;
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

// Token types for testing
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
}

fn emitOperator(ctx: *ParserContext, token: Token) !void {
    try ctx.pushValue(token.lexeme);
}

// Event capture for testing
const TestEventCapture = struct {
    events: std.ArrayList(Event),
    error_events: std.ArrayList(Event),
    
    fn init(allocator: std.mem.Allocator) TestEventCapture {
        return .{
            .events = std.ArrayList(Event).init(allocator),
            .error_events = std.ArrayList(Event).init(allocator),
        };
    }
    
    fn deinit(self: *TestEventCapture) void {
        self.events.deinit();
        self.error_events.deinit();
    }
    
    fn captureEvent(event: Event, ctx: ?*anyopaque) !void {
        const self = @ptrCast(*TestEventCapture, @alignCast(@alignOf(TestEventCapture), ctx.?));
        
        // Clone event to avoid invalidation
        var cloned_event = event;
        
        if (event.type == .ERROR) {
            // For error events, we need to copy the message
            const message = event.data.error_info.message;
            const allocator = self.error_events.allocator;
            const message_copy = try allocator.dupe(u8, message);
            cloned_event.data.error_info.message = message_copy;
            
            try self.error_events.append(cloned_event);
        } else {
            try self.events.append(cloned_event);
        }
    }
    
    fn getErrorCount(self: TestEventCapture) usize {
        return self.error_events.items.len;
    }
};

// Setup test parser configuration
fn createTestParser(
    allocator: std.mem.Allocator,
    input: []const u8,
    parse_mode: lib.ParseMode,
) !Parser {
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
    const action_fns = [_]ParserContext.ActionFn{
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

    return Parser.init(
        allocator,
        input,
        token_config,
        state_config,
        1024, // buffer size
        parse_mode
    );
}

// Test cases
test "ErrorContext initialization and format" {
    const allocator = testing.allocator;
    
    var error_ctx = try ErrorContext.init(
        allocator,
        ErrorCode.unexpected_token,
        .{ .offset = 10, .line = 2, .column = 5 },
        "Unexpected token: {s}", .{"+"} 
    );
    defer error_ctx.deinit();
    
    // Check basic properties
    try testing.expectEqual(ErrorCode.unexpected_token, error_ctx.code);
    try testing.expectEqual(@as(usize, 10), error_ctx.position.offset);
    try testing.expectEqual(@as(usize, 2), error_ctx.position.line);
    try testing.expectEqual(@as(usize, 5), error_ctx.position.column);
    try testing.expectEqual(ErrorSeverity.error, error_ctx.severity);
    
    // Add token info
    try error_ctx.setTokenText("+");
    
    // Add expected tokens
    try error_ctx.addExpectedToken("NUMBER");
    try error_ctx.addExpectedToken("LPAREN");
    
    // Add state info
    try error_ctx.setStateName("EXPECT_NUMBER_OR_LPAREN");
    
    // Add recovery hint
    try error_ctx.setRecoveryHint("Try inserting a number or '(' before this token");
    
    // Format the error to a string and check it contains the key information
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    try std.fmt.format(buffer.writer(), "{}", .{error_ctx});
    
    const formatted = buffer.items;
    
    try testing.expect(std.mem.indexOf(u8, formatted, "error at line 2, column 5") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "unexpected_token") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "Unexpected token: +") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "Token: '+'") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "In state: EXPECT_NUMBER_OR_LPAREN") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "Expected: 'NUMBER', 'LPAREN'") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "Hint: Try inserting a number or '(' before this token") != null);
}

test "ErrorReporter basic functionality" {
    const allocator = testing.allocator;
    
    var reporter = ErrorReporter.init(allocator);
    defer reporter.deinit();
    
    try testing.expect(!reporter.hasErrors());
    
    // Create and report an error
    var error_ctx1 = try ErrorContext.init(
        allocator,
        ErrorCode.unexpected_token,
        .{ .offset = 10, .line = 2, .column = 5 },
        "Unexpected token" 
    );
    
    try reporter.report(error_ctx1);
    
    try testing.expect(reporter.hasErrors());
    try testing.expectEqual(@as(usize, 1), reporter.getErrors().len);
    try testing.expectEqual(@as(usize, 0), reporter.getWarnings().len);
    
    // Create and report a warning
    var error_ctx2 = try ErrorContext.init(
        allocator,
        ErrorCode.type_mismatch,
        .{ .offset = 20, .line = 3, .column = 8 },
        "Type mismatch" 
    );
    error_ctx2.severity = .warning;
    
    try reporter.report(error_ctx2);
    
    try testing.expectEqual(@as(usize, 1), reporter.getErrors().len);
    try testing.expectEqual(@as(usize, 1), reporter.getWarnings().len);
    
    // Create and report a fatal error
    var error_ctx3 = try ErrorContext.init(
        allocator,
        ErrorCode.internal_error,
        .{ .offset = 30, .line = 4, .column = 12 },
        "Internal error" 
    );
    error_ctx3.severity = .fatal;
    
    try reporter.report(error_ctx3);
    
    try testing.expectEqual(@as(usize, 2), reporter.getErrors().len);
    try testing.expectEqual(@as(usize, 1), reporter.getWarnings().len);
    try testing.expect(reporter.hasFatalErrors());
}

test "Parser in normal mode recovers from errors" {
    const allocator = testing.allocator;
    
    // Input with a syntax error (missing opening parenthesis)
    const input = "123 + ) * 45";
    
    // Create parser in normal mode
    var parser = try createTestParser(allocator, input, .normal);
    defer parser.deinit();
    
    // Create event capture
    var event_capture = TestEventCapture.init(allocator);
    defer event_capture.deinit();
    
    // Set event handler
    parser.setEventHandler(EventHandler.init(TestEventCapture.captureEvent, &event_capture));
    
    // Parse the input - should not error out in normal mode
    parser.parse() catch |err| {
        try testing.expect(false); // Should not reach here
        return err;
    };
    
    // Check that we have errors but continued parsing
    try testing.expect(parser.hasErrors());
    try testing.expect(event_capture.getErrorCount() > 0);
    
    // Verify we got at least some events despite the error
    try testing.expect(event_capture.events.items.len > 0);
}

test "Parser in strict mode stops on first error" {
    const allocator = testing.allocator;
    
    // Input with a syntax error (missing opening parenthesis)
    const input = "123 + ) * 45";
    
    // Create parser in strict mode
    var parser = try createTestParser(allocator, input, .strict);
    defer parser.deinit();
    
    // Create event capture
    var event_capture = TestEventCapture.init(allocator);
    defer event_capture.deinit();
    
    // Set event handler
    parser.setEventHandler(EventHandler.init(TestEventCapture.captureEvent, &event_capture));
    
    // Parse the input - should error out in strict mode
    parser.parse() catch |err| {
        // This is expected
        try testing.expect(parser.hasErrors());
        try testing.expectEqual(@as(usize, 1), parser.getErrors().len); // Should have exactly one error
        return;
    };
    
    try testing.expect(false); // Should not reach here
}

test "Parser in validation mode collects all errors" {
    const allocator = testing.allocator;
    
    // Input with multiple syntax errors
    const input = "123 + ) * (45 ]";
    
    // Create parser in validation mode
    var parser = try createTestParser(allocator, input, .validation);
    defer parser.deinit();
    
    // Create event capture
    var event_capture = TestEventCapture.init(allocator);
    defer event_capture.deinit();
    
    // Set event handler
    parser.setEventHandler(EventHandler.init(TestEventCapture.captureEvent, &event_capture));
    
    // Parse the input - should error out in validation mode but collect all errors
    parser.parse() catch |err| {
        // This is expected
        try testing.expect(parser.hasErrors());
        try testing.expect(parser.getErrors().len >= 2); // Should have at least two errors
        return;
    };
    
    try testing.expect(false); // Should not reach here
}

test "Parser in lenient mode recovers aggressively" {
    const allocator = testing.allocator;
    
    // Input with a syntax error (missing opening parenthesis)
    const input = "123 + ) * 45";
    
    // Create parser in lenient mode
    var parser = try createTestParser(allocator, input, .lenient);
    defer parser.deinit();
    
    // Create event capture
    var event_capture = TestEventCapture.init(allocator);
    defer event_capture.deinit();
    
    // Set event handler
    parser.setEventHandler(EventHandler.init(TestEventCapture.captureEvent, &event_capture));
    
    // Parse the input - should not error out in lenient mode
    parser.parse() catch |err| {
        try testing.expect(false); // Should not reach here
        return err;
    };
    
    // Check that we have errors but continued parsing
    try testing.expect(parser.hasErrors());
    
    // Verify we got substantial events despite the errors
    try testing.expect(event_capture.events.items.len >= 5); // Should have processed most of the input
}

test "Error contains detailed position information" {
    const allocator = testing.allocator;
    
    // Input with carefully positioned error
    const input = "123 +\n   )";
    
    // Create parser in strict mode to catch the first error
    var parser = try createTestParser(allocator, input, .strict);
    defer parser.deinit();
    
    // Parse the input - should error out
    parser.parse() catch |err| {
        _ = err;
        try testing.expect(parser.hasErrors());
        
        // Check error details
        const errors = parser.getErrors();
        try testing.expectEqual(@as(usize, 1), errors.len);
        
        const err_ctx = errors[0];
        try testing.expectEqual(@as(usize, 2), err_ctx.position.line); // Error on line 2
        try testing.expectEqual(@as(usize, 4), err_ctx.position.column); // Error at column 4
        
        return;
    };
    
    try testing.expect(false); // Should not reach here
}

test "Error emits appropriate events" {
    const allocator = testing.allocator;
    
    // Input with syntax error
    const input = "123 + )";
    
    // Create parser in normal mode
    var parser = try createTestParser(allocator, input, .normal);
    defer parser.deinit();
    
    // Create event capture
    var event_capture = TestEventCapture.init(allocator);
    defer event_capture.deinit();
    
    // Set event handler
    parser.setEventHandler(EventHandler.init(TestEventCapture.captureEvent, &event_capture));
    
    // Parse the input
    _ = parser.parse() catch |_| {}; // Ignore parsing errors
    
    // Check that we got the right events
    try testing.expect(event_capture.getErrorCount() > 0);
    
    // Check that we got a start document event
    var found_start = false;
    for (event_capture.events.items) |event| {
        if (event.type == .START_DOCUMENT) {
            found_start = true;
            break;
        }
    }
    try testing.expect(found_start);
    
    // Check that the error event contains the right information
    const error_events = event_capture.error_events.items;
    try testing.expect(error_events.len > 0);
    try testing.expect(error_events[0].type == .ERROR);
    try testing.expect(std.mem.indexOf(u8, error_events[0].data.error_info.message, "Unexpected token") != null);
}

test "Maximum error limit works" {
    const allocator = testing.allocator;
    
    // Input with many errors (intentionally malformed)
    const input = "123 + ) * ] { @ # $ 789 + @ ? > < 456"; 
    
    // Create parser with low error limit (2 errors max)
    // We'll use a custom recovery config
    
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

    // Create state machine configuration
    const action_fns = [_]ParserContext.ActionFn{
        emitNumber,
        emitOperator,
    };

    // Define states
    const transitions_state0 = [_]StateTransition{
        .{ .token_id = TOKEN_NUMBER, .next_state = 1, .action_id = 0 },
        .{ .token_id = TOKEN_LPAREN, .next_state = 0, .action_id = 1 },
    };
    
    const transitions_state1 = [_]StateTransition{
        .{ .token_id = TOKEN_PLUS, .next_state = 0, .action_id = 1 },
        .{ .token_id = TOKEN_MINUS, .next_state = 0, .action_id = 1 },
        .{ .token_id = TOKEN_MULTIPLY, .next_state = 0, .action_id = 1 },
        .{ .token_id = TOKEN_DIVIDE, .next_state = 0, .action_id = 1 },
        .{ .token_id = TOKEN_RPAREN, .next_state = 1, .action_id = 1 },
    };

    const states = [_]State{
        .{ .id = 0, .name = "EXPECT_NUMBER_OR_LPAREN", .transitions = &transitions_state0 },
        .{ .id = 1, .name = "EXPECT_OPERATOR_OR_RPAREN", .transitions = &transitions_state1 },
    };
    
    // Define synchronization tokens but with a low error limit
    const sync_token_types = [_]u32{
        TOKEN_NUMBER,
        TOKEN_PLUS,
        TOKEN_MINUS,
    };
    
    // Configure error recovery with low limit
    const recovery_config = .{
        .strategy = .synchronize, 
        .sync_token_types = &sync_token_types,
        .max_errors = 2, // Only allow 2 errors before giving up
    };

    const token_config = lib.TokenizerConfig{
        .matchers = &matchers,
        .skip_types = &skip_types,
    };

    const state_config = lib.StateMachineConfig{
        .states = &states,
        .actions = &action_fns,
        .initial_state_id = 0,
        .recovery_config = recovery_config,
    };

    var parser = try Parser.init(
        allocator,
        input,
        token_config,
        state_config,
        1024,
        .normal
    );
    defer parser.deinit();
    
    // Parse should fail with too many errors
    parser.parse() catch |err| {
        try testing.expect(parser.getErrors().len <= 3); // Should not exceed max+1 errors
        
        // Should fail with TooManyErrors
        try testing.expectEqual(err, error.TooManyErrors);
        return;
    };
    
    try testing.expect(false); // Should not reach here
}