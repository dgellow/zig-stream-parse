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

// Import the error aggregation components
const ErrorAggregator = lib.ErrorAggregator;
const ErrorGroup = lib.ErrorGroup;
const ErrorAggregationConfig = lib.ErrorAggregationConfig;

// ActionFn type
const ActionFn = *const fn(ctx: *ParserContext, token: Token) anyerror!void;

// Token types for a simple JSON-like grammar
const TOKEN_STRING = 1;
const TOKEN_NUMBER = 2;
const TOKEN_TRUE = 3;
const TOKEN_FALSE = 4;
const TOKEN_NULL = 5;
const TOKEN_LBRACE = 6;
const TOKEN_RBRACE = 7;
const TOKEN_LBRACKET = 8;
const TOKEN_RBRACKET = 9;
const TOKEN_COLON = 10;
const TOKEN_COMMA = 11;
const TOKEN_WHITESPACE = 12;

// Token matcher functions
fn stringTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Peek at the first character
    const first_char = try stream.peek();
    if (first_char == null or first_char.? != '"') return null;
    
    // Start of a string, consume it
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    
    // Consume the opening quote
    _ = try stream.consume();
    try token_bytes.append('"');
    
    // State to track if we're in an escape sequence
    var in_escape = false;
    
    // Continue consuming until the closing quote or EOF
    while (true) {
        const next_char = try stream.peek();
        if (next_char == null) {
            // Unterminated string - this will be caught as an error later
            break;
        }
        
        _ = try stream.consume();
        try token_bytes.append(next_char.?);
        
        if (in_escape) {
            in_escape = false;
        } else if (next_char.? == '\\') {
            in_escape = true;
        } else if (next_char.? == '"') {
            // End of string
            break;
        }
    }
    
    // Create the token
    const lexeme = try allocator.dupe(u8, token_bytes.items);
    return Token.init(
        .{ .id = TOKEN_STRING, .name = "STRING" },
        start_pos,
        lexeme
    );
}

fn numberTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Peek at the first character
    const first_char = try stream.peek();
    if (first_char == null) return null;
    
    // Check if it's a digit or minus sign
    if (!isDigit(first_char.?) and first_char.? != '-') return null;
    
    // Start of a number, consume it
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    
    // Consume the first character
    _ = try stream.consume();
    try token_bytes.append(first_char.?);
    
    // State to track parts of the number
    var seen_dot = false;
    var seen_e = false;
    
    // Continue consuming until we hit a non-number character
    while (true) {
        const next_char = try stream.peek();
        if (next_char == null) break;
        
        if (isDigit(next_char.?)) {
            _ = try stream.consume();
            try token_bytes.append(next_char.?);
        } else if (next_char.? == '.' and !seen_dot and !seen_e) {
            _ = try stream.consume();
            try token_bytes.append(next_char.?);
            seen_dot = true;
        } else if ((next_char.? == 'e' or next_char.? == 'E') and !seen_e) {
            _ = try stream.consume();
            try token_bytes.append(next_char.?);
            seen_e = true;
            
            // Check for sign after e
            const sign_char = try stream.peek();
            if (sign_char != null and (sign_char.? == '+' or sign_char.? == '-')) {
                _ = try stream.consume();
                try token_bytes.append(sign_char.?);
            }
        } else {
            break;
        }
    }
    
    // Create the token
    const lexeme = try allocator.dupe(u8, token_bytes.items);
    return Token.init(
        .{ .id = TOKEN_NUMBER, .name = "NUMBER" },
        start_pos,
        lexeme
    );
}

fn keywordOrPunctuationTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Peek at the first character
    const first_char = try stream.peek();
    if (first_char == null) return null;
    
    var token_type: TokenType = undefined;
    var token_name: []const u8 = undefined;
    var lexeme_len: usize = 1;
    
    // Check for keywords and punctuation
    switch (first_char.?) {
        '{' => {
            token_type = .{ .id = TOKEN_LBRACE, .name = "LBRACE" };
            token_name = "LBRACE";
        },
        '}' => {
            token_type = .{ .id = TOKEN_RBRACE, .name = "RBRACE" };
            token_name = "RBRACE";
        },
        '[' => {
            token_type = .{ .id = TOKEN_LBRACKET, .name = "LBRACKET" };
            token_name = "LBRACKET";
        },
        ']' => {
            token_type = .{ .id = TOKEN_RBRACKET, .name = "RBRACKET" };
            token_name = "RBRACKET";
        },
        ':' => {
            token_type = .{ .id = TOKEN_COLON, .name = "COLON" };
            token_name = "COLON";
        },
        ',' => {
            token_type = .{ .id = TOKEN_COMMA, .name = "COMMA" };
            token_name = "COMMA";
        },
        't' => {
            // Check if it's 'true'
            if (isKeyword(stream, "true")) {
                token_type = .{ .id = TOKEN_TRUE, .name = "TRUE" };
                token_name = "TRUE";
                lexeme_len = 4;
            } else {
                return null;
            }
        },
        'f' => {
            // Check if it's 'false'
            if (isKeyword(stream, "false")) {
                token_type = .{ .id = TOKEN_FALSE, .name = "FALSE" };
                token_name = "FALSE";
                lexeme_len = 5;
            } else {
                return null;
            }
        },
        'n' => {
            // Check if it's 'null'
            if (isKeyword(stream, "null")) {
                token_type = .{ .id = TOKEN_NULL, .name = "NULL" };
                token_name = "NULL";
                lexeme_len = 4;
            } else {
                return null;
            }
        },
        else => return null,
    }
    
    // Consume the token
    var i: usize = 0;
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    
    while (i < lexeme_len) : (i += 1) {
        const char = try stream.consume();
        if (char) |c| {
            try token_bytes.append(c);
        } else {
            // Unexpected EOF
            break;
        }
    }
    
    // Create the token
    const lexeme = try allocator.dupe(u8, token_bytes.items);
    return Token.init(token_type, start_pos, lexeme);
}

fn whitespaceTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Peek at the first character
    const first_char = try stream.peek();
    if (first_char == null or !isWhitespace(first_char.?)) return null;
    
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

fn isKeyword(stream: *ByteStream, keyword: []const u8) bool {
    // Save the current position
    const start_pos = stream.getPosition();
    
    // Try to match the keyword
    for (keyword) |expected_char| {
        const actual_char = stream.peek() catch return false;
        if (actual_char == null or actual_char.? != expected_char) {
            // Reset the stream position and return false
            stream.setPosition(start_pos) catch {};
            return false;
        }
        
        // Consume the character
        _ = stream.consume() catch return false;
    }
    
    // Reset the stream position since this is just a check
    stream.setPosition(start_pos) catch {};
    return true;
}

// Action functions for the state machine
fn emitValue(ctx: *ParserContext, token: Token) !void {
    try ctx.pushValue(token.lexeme);
    std.debug.print("Value: {s}\n", .{token.lexeme});
}

fn emitObjectStart(ctx: *ParserContext, token: Token) !void {
    _ = ctx;
    _ = token;
    std.debug.print("Object Start\n", .{});
}

fn emitObjectEnd(ctx: *ParserContext, token: Token) !void {
    _ = ctx;
    _ = token;
    std.debug.print("Object End\n", .{});
}

fn emitArrayStart(ctx: *ParserContext, token: Token) !void {
    _ = ctx;
    _ = token;
    std.debug.print("Array Start\n", .{});
}

fn emitArrayEnd(ctx: *ParserContext, token: Token) !void {
    _ = ctx;
    _ = token;
    std.debug.print("Array End\n", .{});
}

fn emitColon(ctx: *ParserContext, token: Token) !void {
    _ = ctx;
    _ = token;
    std.debug.print("Colon\n", .{});
}

fn emitComma(ctx: *ParserContext, token: Token) !void {
    _ = ctx;
    _ = token;
    std.debug.print("Comma\n", .{});
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
    std.debug.print("ZigParse: Error Aggregation Example\n", .{});

    // Create token matchers
    const string_matcher = TokenMatcher.init(stringTokenMatcher);
    const number_matcher = TokenMatcher.init(numberTokenMatcher);
    const keyword_punct_matcher = TokenMatcher.init(keywordOrPunctuationTokenMatcher);
    const whitespace_matcher = TokenMatcher.init(whitespaceTokenMatcher);

    // Create tokenizer configuration
    const matchers = [_]TokenMatcher{
        string_matcher,
        number_matcher,
        keyword_punct_matcher,
        whitespace_matcher,
    };
    
    const skip_types = [_]TokenType{
        .{ .id = TOKEN_WHITESPACE, .name = "WHITESPACE" },
    };

    // Create state machine configuration - JSON-like grammar
    const action_fns = [_]ActionFn{
        emitValue,        // 0: Value action
        emitObjectStart,  // 1: Object start action
        emitObjectEnd,    // 2: Object end action
        emitArrayStart,   // 3: Array start action
        emitArrayEnd,     // 4: Array end action
        emitColon,        // 5: Colon action
        emitComma,        // 6: Comma action
    };

    // Define a grammar for JSON-like structures
    // State 0: Value (start state)
    // State 1: After value
    // State 2: Object key
    // State 3: After key
    // State 4: Object value
    // State 5: After object value
    // State 6: Array value
    // State 7: After array value
    
    const transitions_state0 = [_]StateTransition{
        .{ .token_id = TOKEN_STRING, .next_state = 1, .action_id = 0 },    // STRING -> STATE_1 w/ emitValue
        .{ .token_id = TOKEN_NUMBER, .next_state = 1, .action_id = 0 },    // NUMBER -> STATE_1 w/ emitValue
        .{ .token_id = TOKEN_TRUE, .next_state = 1, .action_id = 0 },      // TRUE -> STATE_1 w/ emitValue
        .{ .token_id = TOKEN_FALSE, .next_state = 1, .action_id = 0 },     // FALSE -> STATE_1 w/ emitValue
        .{ .token_id = TOKEN_NULL, .next_state = 1, .action_id = 0 },      // NULL -> STATE_1 w/ emitValue
        .{ .token_id = TOKEN_LBRACE, .next_state = 2, .action_id = 1 },    // LBRACE -> STATE_2 w/ emitObjectStart
        .{ .token_id = TOKEN_LBRACKET, .next_state = 6, .action_id = 3 },  // LBRACKET -> STATE_6 w/ emitArrayStart
    };
    
    const transitions_state1 = [_]StateTransition{
        // Terminal state - no transitions
    };
    
    const transitions_state2 = [_]StateTransition{
        .{ .token_id = TOKEN_STRING, .next_state = 3, .action_id = 0 },    // STRING -> STATE_3 w/ emitValue
        .{ .token_id = TOKEN_RBRACE, .next_state = 1, .action_id = 2 },    // RBRACE -> STATE_1 w/ emitObjectEnd
    };
    
    const transitions_state3 = [_]StateTransition{
        .{ .token_id = TOKEN_COLON, .next_state = 4, .action_id = 5 },     // COLON -> STATE_4 w/ emitColon
    };
    
    const transitions_state4 = [_]StateTransition{
        .{ .token_id = TOKEN_STRING, .next_state = 5, .action_id = 0 },    // STRING -> STATE_5 w/ emitValue
        .{ .token_id = TOKEN_NUMBER, .next_state = 5, .action_id = 0 },    // NUMBER -> STATE_5 w/ emitValue
        .{ .token_id = TOKEN_TRUE, .next_state = 5, .action_id = 0 },      // TRUE -> STATE_5 w/ emitValue
        .{ .token_id = TOKEN_FALSE, .next_state = 5, .action_id = 0 },     // FALSE -> STATE_5 w/ emitValue
        .{ .token_id = TOKEN_NULL, .next_state = 5, .action_id = 0 },      // NULL -> STATE_5 w/ emitValue
        .{ .token_id = TOKEN_LBRACE, .next_state = 2, .action_id = 1 },    // LBRACE -> STATE_2 w/ emitObjectStart
        .{ .token_id = TOKEN_LBRACKET, .next_state = 6, .action_id = 3 },  // LBRACKET -> STATE_6 w/ emitArrayStart
    };
    
    const transitions_state5 = [_]StateTransition{
        .{ .token_id = TOKEN_COMMA, .next_state = 2, .action_id = 6 },     // COMMA -> STATE_2 w/ emitComma
        .{ .token_id = TOKEN_RBRACE, .next_state = 1, .action_id = 2 },    // RBRACE -> STATE_1 w/ emitObjectEnd
    };
    
    const transitions_state6 = [_]StateTransition{
        .{ .token_id = TOKEN_STRING, .next_state = 7, .action_id = 0 },    // STRING -> STATE_7 w/ emitValue
        .{ .token_id = TOKEN_NUMBER, .next_state = 7, .action_id = 0 },    // NUMBER -> STATE_7 w/ emitValue
        .{ .token_id = TOKEN_TRUE, .next_state = 7, .action_id = 0 },      // TRUE -> STATE_7 w/ emitValue
        .{ .token_id = TOKEN_FALSE, .next_state = 7, .action_id = 0 },     // FALSE -> STATE_7 w/ emitValue
        .{ .token_id = TOKEN_NULL, .next_state = 7, .action_id = 0 },      // NULL -> STATE_7 w/ emitValue
        .{ .token_id = TOKEN_LBRACE, .next_state = 2, .action_id = 1 },    // LBRACE -> STATE_2 w/ emitObjectStart
        .{ .token_id = TOKEN_LBRACKET, .next_state = 6, .action_id = 3 },  // LBRACKET -> STATE_6 w/ emitArrayStart
        .{ .token_id = TOKEN_RBRACKET, .next_state = 1, .action_id = 4 },  // RBRACKET -> STATE_1 w/ emitArrayEnd
    };
    
    const transitions_state7 = [_]StateTransition{
        .{ .token_id = TOKEN_COMMA, .next_state = 6, .action_id = 6 },     // COMMA -> STATE_6 w/ emitComma
        .{ .token_id = TOKEN_RBRACKET, .next_state = 1, .action_id = 4 },  // RBRACKET -> STATE_1 w/ emitArrayEnd
    };

    const states = [_]State{
        .{ .id = 0, .name = "VALUE", .transitions = &transitions_state0 },
        .{ .id = 1, .name = "AFTER_VALUE", .transitions = &transitions_state1 },
        .{ .id = 2, .name = "OBJECT_KEY", .transitions = &transitions_state2 },
        .{ .id = 3, .name = "AFTER_KEY", .transitions = &transitions_state3 },
        .{ .id = 4, .name = "OBJECT_VALUE", .transitions = &transitions_state4 },
        .{ .id = 5, .name = "AFTER_OBJECT_VALUE", .transitions = &transitions_state5 },
        .{ .id = 6, .name = "ARRAY_VALUE", .transitions = &transitions_state6 },
        .{ .id = 7, .name = "AFTER_ARRAY_VALUE", .transitions = &transitions_state7 },
    };
    
    // Define synchronization tokens for error recovery
    const sync_token_types = [_]u32{
        TOKEN_COMMA,
        TOKEN_RBRACE,
        TOKEN_RBRACKET,
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
        .initial_state_id = 0,
        .recovery_config = recovery_config,
    };

    // Create an example input with multiple related errors
    const error_input = 
        \\{
        \\  "name": "John Doe",
        \\  "age": 30,
        \\  "address": {
        \\    "street": "123 Main St"
        \\    "city": "Anytown",
        \\    "state": "CA"
        \\  },
        \\  "phone_numbers": [
        \\    "555-1234",
        \\    "555-5678"
        \\  ]
        \\  "email": "john@example.com"
        \\}
    ;
    
    std.debug.print("\n=== Parsing with standard error reporting ===\n", .{});
    
    // Parse with standard error reporting
    var parser1 = try lib.EnhancedParser.init(
        allocator,
        error_input,
        token_config,
        state_config,
        1024, // buffer size
        .normal // Normal parsing mode
    );
    defer parser1.deinit();
    
    // Set event handler
    parser1.setEventHandler(EventHandler.init(handleEvent, null));
    
    // Parse the input and collect errors
    parser1.parse() catch |err| {
        std.debug.print("\nParsing failed with error: {any}\n", .{err});
        
        // Show basic error list
        try parser1.printErrors();
    };
    
    // Now parse the same input with error aggregation
    std.debug.print("\n=== Parsing with error aggregation ===\n", .{});
    
    // Create an error aggregator
    var aggregator = ErrorAggregator.init(allocator);
    defer aggregator.deinit();
    
    // Create parser again
    var parser2 = try lib.EnhancedParser.init(
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
    
    // Parse the input and collect errors
    parser2.parse() catch |err| {
        std.debug.print("\nParsing failed with error: {any}\n", .{err});
        
        // Get all errors from the parser
        const errors = parser2.getErrors();
        
        // Report each error to the aggregator
        for (errors) |error_ctx| {
            // We need to clone the error context since it will be freed by the parser
            var cloned_ctx = try ErrorContext.init(
                allocator,
                error_ctx.code,
                error_ctx.position,
                error_ctx.message
            );
            cloned_ctx.severity = error_ctx.severity;
            
            if (error_ctx.token) |token| {
                cloned_ctx.setToken(token);
            }
            
            if (error_ctx.state_id != null and error_ctx.state_name != null) {
                try cloned_ctx.setStateContext(allocator, error_ctx.state_id.?, error_ctx.state_name.?);
            }
            
            if (error_ctx.recovery_hint) |hint| {
                try cloned_ctx.setRecoveryHint(allocator, hint);
            }
            
            try aggregator.report(cloned_ctx);
        }
        
        // Print aggregated errors
        try aggregator.printAll();
    };
    
    // Example successful parsing
    std.debug.print("\n=== Parsing a correct JSON ===\n", .{});
    
    // Create a correct JSON
    const correct_input = 
        \\{
        \\  "name": "John Doe",
        \\  "age": 30,
        \\  "address": {
        \\    "street": "123 Main St",
        \\    "city": "Anytown",
        \\    "state": "CA"
        \\  },
        \\  "phone_numbers": [
        \\    "555-1234",
        \\    "555-5678"
        \\  ],
        \\  "email": "john@example.com"
        \\}
    ;
    
    // Create parser for correct input
    var parser3 = try lib.EnhancedParser.init(
        allocator,
        correct_input,
        token_config,
        state_config,
        1024, // buffer size
        .normal // Normal parsing mode
    );
    defer parser3.deinit();
    
    // Set event handler
    parser3.setEventHandler(EventHandler.init(handleEvent, null));
    
    // Parse the input
    parser3.parse() catch |err| {
        std.debug.print("\nParsing failed unexpectedly: {any}\n", .{err});
        try parser3.printErrors();
    };
    
    std.debug.print("\nExample completed\n", .{});
}