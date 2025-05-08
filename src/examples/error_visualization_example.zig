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

// Import the error visualization components
const error_visualizer_mod = @import("../error_visualizer.zig");
const ErrorVisualizer = error_visualizer_mod.ErrorVisualizer;
const VisualizerConfig = error_visualizer_mod.VisualizerConfig;

// Import the error aggregation components
const ErrorAggregator = lib.ErrorAggregator;
const ErrorGroup = lib.ErrorGroup;

// ActionFn type
const ActionFn = *const fn(ctx: *ParserContext, token: Token) anyerror!void;

// Token types for a simple Javascript-like language
const TOKEN_KEYWORD = 1;
const TOKEN_IDENTIFIER = 2;
const TOKEN_NUMBER = 3;
const TOKEN_STRING = 4;
const TOKEN_OPERATOR = 5;
const TOKEN_LPAREN = 6;
const TOKEN_RPAREN = 7;
const TOKEN_LBRACE = 8;
const TOKEN_RBRACE = 9;
const TOKEN_SEMICOLON = 10;
const TOKEN_COMMA = 11;
const TOKEN_WHITESPACE = 12;

// Token matcher functions
fn keywordTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Peek at the first character
    const first_char = try stream.peek();
    if (first_char == null) return null;
    
    // Check if it's a letter
    if (!isAlpha(first_char.?)) return null;
    
    // Save the starting position for rewinding
    const original_pos = stream.getPosition();
    
    // Start of a potential keyword, consume it
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    
    // Consume the first character
    _ = try stream.consume();
    try token_bytes.append(first_char.?);
    
    // Continue consuming until we hit a non-identifier character
    while (true) {
        const next_char = try stream.peek();
        if (next_char == null or (!isAlpha(next_char.?) and !isDigit(next_char.?))) break;
        
        _ = try stream.consume();
        try token_bytes.append(next_char.?);
    }
    
    // Check if it's a keyword
    const lexeme = token_bytes.items;
    const is_keyword = std.mem.eql(u8, lexeme, "function") or
                      std.mem.eql(u8, lexeme, "let") or
                      std.mem.eql(u8, lexeme, "return") or
                      std.mem.eql(u8, lexeme, "if") or
                      std.mem.eql(u8, lexeme, "else");
                      
    if (!is_keyword) {
        // Not a keyword, rewind the stream
        stream.setPosition(original_pos) catch {};
        return null;
    }
    
    // Create the token
    const lexeme_copy = try allocator.dupe(u8, lexeme);
    return Token.init(
        .{ .id = TOKEN_KEYWORD, .name = "KEYWORD" },
        start_pos,
        lexeme_copy
    );
}

fn identifierTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Peek at the first character
    const first_char = try stream.peek();
    if (first_char == null) return null;
    
    // Check if it's a letter or underscore
    if (!isAlpha(first_char.?) and first_char.? != '_') return null;
    
    // Start of an identifier, consume it
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    
    // Consume the first character
    _ = try stream.consume();
    try token_bytes.append(first_char.?);
    
    // Continue consuming until we hit a non-identifier character
    while (true) {
        const next_char = try stream.peek();
        if (next_char == null or (!isAlpha(next_char.?) and !isDigit(next_char.?) and next_char.? != '_')) break;
        
        _ = try stream.consume();
        try token_bytes.append(next_char.?);
    }
    
    // Create the token
    const lexeme = try allocator.dupe(u8, token_bytes.items);
    return Token.init(
        .{ .id = TOKEN_IDENTIFIER, .name = "IDENTIFIER" },
        start_pos,
        lexeme
    );
}

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
    var seen_dot = false;
    while (true) {
        const next_char = try stream.peek();
        if (next_char == null) break;
        
        if (isDigit(next_char.?)) {
            _ = try stream.consume();
            try token_bytes.append(next_char.?);
        } else if (next_char.? == '.' and !seen_dot) {
            _ = try stream.consume();
            try token_bytes.append(next_char.?);
            seen_dot = true;
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
    
    // Record if we're in an escape sequence
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

fn operatorTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Peek at the first character
    const first_char = try stream.peek();
    if (first_char == null) return null;
    
    // Check if it's an operator
    const is_operator = first_char.? == '+' or
                        first_char.? == '-' or
                        first_char.? == '*' or
                        first_char.? == '/' or
                        first_char.? == '=' or
                        first_char.? == '>' or
                        first_char.? == '<';
                        
    if (!is_operator) return null;
    
    // Consume the operator
    _ = try stream.consume();
    
    // Check for two-character operators
    var lexeme_len: usize = 1;
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    try token_bytes.append(first_char.?);
    
    const second_char = try stream.peek();
    if (second_char != null) {
        if ((first_char.? == '=' and second_char.? == '=') or
            (first_char.? == '!' and second_char.? == '=') or
            (first_char.? == '>' and second_char.? == '=') or
            (first_char.? == '<' and second_char.? == '=') or
            (first_char.? == '+' and second_char.? == '+') or
            (first_char.? == '-' and second_char.? == '-')) {
            _ = try stream.consume();
            try token_bytes.append(second_char.?);
        }
    }
    
    // Create the token
    const lexeme = try allocator.dupe(u8, token_bytes.items);
    return Token.init(
        .{ .id = TOKEN_OPERATOR, .name = "OPERATOR" },
        start_pos,
        lexeme
    );
}

fn punctuationTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Peek at the first character
    const first_char = try stream.peek();
    if (first_char == null) return null;
    
    var token_type: TokenType = undefined;
    var token_name: []const u8 = undefined;
    
    // Check for punctuation
    switch (first_char.?) {
        '(' => {
            token_type = .{ .id = TOKEN_LPAREN, .name = "LPAREN" };
            token_name = "LPAREN";
        },
        ')' => {
            token_type = .{ .id = TOKEN_RPAREN, .name = "RPAREN" };
            token_name = "RPAREN";
        },
        '{' => {
            token_type = .{ .id = TOKEN_LBRACE, .name = "LBRACE" };
            token_name = "LBRACE";
        },
        '}' => {
            token_type = .{ .id = TOKEN_RBRACE, .name = "RBRACE" };
            token_name = "RBRACE";
        },
        ';' => {
            token_type = .{ .id = TOKEN_SEMICOLON, .name = "SEMICOLON" };
            token_name = "SEMICOLON";
        },
        ',' => {
            token_type = .{ .id = TOKEN_COMMA, .name = "COMMA" };
            token_name = "COMMA";
        },
        else => return null,
    }
    
    // Consume the character
    _ = try stream.consume();
    
    // Create the token
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    try token_bytes.append(first_char.?);
    
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
fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

// Action functions for the state machine
fn emitKeyword(ctx: *ParserContext, token: Token) !void {
    try ctx.pushValue(token.lexeme);
    //std.debug.print("Keyword: {s}\n", .{token.lexeme});
}

fn emitIdentifier(ctx: *ParserContext, token: Token) !void {
    try ctx.pushValue(token.lexeme);
    //std.debug.print("Identifier: {s}\n", .{token.lexeme});
}

fn emitLiteral(ctx: *ParserContext, token: Token) !void {
    try ctx.pushValue(token.lexeme);
    //std.debug.print("Literal: {s}\n", .{token.lexeme});
}

fn emitOperator(ctx: *ParserContext, token: Token) !void {
    try ctx.pushValue(token.lexeme);
    //std.debug.print("Operator: {s}\n", .{token.lexeme});
}

fn emitPunctuation(ctx: *ParserContext, token: Token) !void {
    try ctx.pushValue(token.lexeme);
    //std.debug.print("Punctuation: {s}\n", .{token.lexeme});
}

// Event handler for errors
fn handleEvent(event: Event, ctx: ?*anyopaque) !void {
    _ = ctx;
    switch (event.type) {
        .ERROR => {
            std.debug.print("Error Event: {s}\n", .{event.data.error_info.message});
        },
        else => {},
    }
}

// Sample code with intentional errors
const sample_code =
    \\function example() {
    \\    let x = 10
    \\    let y = "hello;
    \\    return x + y;
    \\}
;

pub fn main() !void {
    // Setup allocator
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = general_purpose_allocator.allocator();
    defer _ = general_purpose_allocator.deinit();

    // Print welcome message
    std.debug.print("ZigParse: Error Visualization Example\n", .{});
    std.debug.print("\nSample code with errors:\n{s}\n", .{sample_code});

    // Create token matchers
    const keyword_matcher = TokenMatcher.init(keywordTokenMatcher);
    const identifier_matcher = TokenMatcher.init(identifierTokenMatcher);
    const number_matcher = TokenMatcher.init(numberTokenMatcher);
    const string_matcher = TokenMatcher.init(stringTokenMatcher);
    const operator_matcher = TokenMatcher.init(operatorTokenMatcher);
    const punctuation_matcher = TokenMatcher.init(punctuationTokenMatcher);
    const whitespace_matcher = TokenMatcher.init(whitespaceTokenMatcher);

    // Create tokenizer configuration
    const matchers = [_]TokenMatcher{
        keyword_matcher,
        identifier_matcher,
        number_matcher,
        string_matcher,
        operator_matcher,
        punctuation_matcher,
        whitespace_matcher,
    };
    
    const skip_types = [_]TokenType{
        .{ .id = TOKEN_WHITESPACE, .name = "WHITESPACE" },
    };

    // Create state machine configuration - simple JS-like grammar
    // This is a simplified grammar that's designed to catch the errors in the sample code
    const action_fns = [_]ActionFn{
        emitKeyword,
        emitIdentifier,
        emitLiteral,
        emitOperator,
        emitPunctuation,
    };

    // Define some states for a simple JavaScript-like language parser
    // State 0: Starting point, expect function declaration
    // State 1: After function keyword, expect function name
    // State 2: After function name, expect open paren
    // State 3: In parameter list, expect param or close paren
    // State 4: After close paren, expect open brace
    // State 5: Statement start, expect keyword or identifier
    // State 6: After let/var, expect identifier
    // State 7: After identifier in declaration, expect equals
    // State 8: After equals, expect expression
    // State 9: After expression, expect semicolon
    // State 10: After statement, back to statement start or close brace
    
    const transitions_state0 = [_]StateTransition{
        .{ .token_id = TOKEN_KEYWORD, .next_state = 1, .action_id = 0 },  // KEYWORD -> STATE_1 w/ emitKeyword
    };
    
    const transitions_state1 = [_]StateTransition{
        .{ .token_id = TOKEN_IDENTIFIER, .next_state = 2, .action_id = 1 },  // IDENTIFIER -> STATE_2 w/ emitIdentifier
    };
    
    const transitions_state2 = [_]StateTransition{
        .{ .token_id = TOKEN_LPAREN, .next_state = 3, .action_id = 4 },  // LPAREN -> STATE_3 w/ emitPunctuation
    };
    
    const transitions_state3 = [_]StateTransition{
        .{ .token_id = TOKEN_IDENTIFIER, .next_state = 3, .action_id = 1 },  // IDENTIFIER -> STATE_3 w/ emitIdentifier
        .{ .token_id = TOKEN_COMMA, .next_state = 3, .action_id = 4 },  // COMMA -> STATE_3 w/ emitPunctuation
        .{ .token_id = TOKEN_RPAREN, .next_state = 4, .action_id = 4 },  // RPAREN -> STATE_4 w/ emitPunctuation
    };
    
    const transitions_state4 = [_]StateTransition{
        .{ .token_id = TOKEN_LBRACE, .next_state = 5, .action_id = 4 },  // LBRACE -> STATE_5 w/ emitPunctuation
    };
    
    const transitions_state5 = [_]StateTransition{
        .{ .token_id = TOKEN_KEYWORD, .next_state = 6, .action_id = 0 },  // KEYWORD -> STATE_6 w/ emitKeyword
        .{ .token_id = TOKEN_IDENTIFIER, .next_state = 7, .action_id = 1 },  // IDENTIFIER -> STATE_7 w/ emitIdentifier
        .{ .token_id = TOKEN_RBRACE, .next_state = 10, .action_id = 4 },  // RBRACE -> STATE_10 w/ emitPunctuation
    };
    
    const transitions_state6 = [_]StateTransition{
        .{ .token_id = TOKEN_IDENTIFIER, .next_state = 7, .action_id = 1 },  // IDENTIFIER -> STATE_7 w/ emitIdentifier
    };
    
    const transitions_state7 = [_]StateTransition{
        .{ .token_id = TOKEN_OPERATOR, .next_state = 8, .action_id = 3 },  // OPERATOR -> STATE_8 w/ emitOperator
    };
    
    const transitions_state8 = [_]StateTransition{
        .{ .token_id = TOKEN_NUMBER, .next_state = 9, .action_id = 2 },  // NUMBER -> STATE_9 w/ emitLiteral
        .{ .token_id = TOKEN_STRING, .next_state = 9, .action_id = 2 },  // STRING -> STATE_9 w/ emitLiteral
        .{ .token_id = TOKEN_IDENTIFIER, .next_state = 9, .action_id = 1 },  // IDENTIFIER -> STATE_9 w/ emitIdentifier
    };
    
    const transitions_state9 = [_]StateTransition{
        .{ .token_id = TOKEN_SEMICOLON, .next_state = 5, .action_id = 4 },  // SEMICOLON -> STATE_5 w/ emitPunctuation
        .{ .token_id = TOKEN_OPERATOR, .next_state = 8, .action_id = 3 },  // OPERATOR -> STATE_8 w/ emitOperator
    };
    
    const transitions_state10 = [_]StateTransition{
        // Terminal state - no transitions
    };
    
    const states = [_]State{
        .{ .id = 0, .name = "START", .transitions = &transitions_state0 },
        .{ .id = 1, .name = "AFTER_FUNCTION", .transitions = &transitions_state1 },
        .{ .id = 2, .name = "AFTER_FUNC_NAME", .transitions = &transitions_state2 },
        .{ .id = 3, .name = "IN_PARAM_LIST", .transitions = &transitions_state3 },
        .{ .id = 4, .name = "AFTER_PARAMS", .transitions = &transitions_state4 },
        .{ .id = 5, .name = "STATEMENT_START", .transitions = &transitions_state5 },
        .{ .id = 6, .name = "AFTER_KEYWORD", .transitions = &transitions_state6 },
        .{ .id = 7, .name = "AFTER_IDENTIFIER", .transitions = &transitions_state7 },
        .{ .id = 8, .name = "AFTER_EQUALS", .transitions = &transitions_state8 },
        .{ .id = 9, .name = "AFTER_EXPRESSION", .transitions = &transitions_state9 },
        .{ .id = 10, .name = "END", .transitions = &transitions_state10 },
    };
    
    // Define synchronization tokens for error recovery
    const sync_token_types = [_]u32{
        TOKEN_SEMICOLON,
        TOKEN_RBRACE,
        TOKEN_KEYWORD,
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

    // Now parse with different visualization options
    std.debug.print("\n=== Basic Error Visualization (No Colors) ===\n", .{});
    
    // Create parser
    var parser1 = try lib.EnhancedParser.init(
        allocator,
        sample_code,
        token_config,
        state_config,
        1024, // buffer size
        .validation // Validation mode to collect all errors
    );
    defer parser1.deinit();
    
    // Set event handler
    parser1.setEventHandler(EventHandler.init(handleEvent, null));
    
    // Parse the input and collect errors
    parser1.parse() catch |err| {
        std.debug.print("\nParsing found errors: {any}\n", .{err});
        
        // Get all errors from the parser
        const errors = parser1.getErrors();
        
        // Create a visualizer
        var visualizer = try ErrorVisualizer.init(
            allocator,
            sample_code,
            .{ .use_colors = false } // No colors for terminal compatibility
        );
        defer visualizer.deinit();
        
        // Visualize each error
        try visualizer.visualizeAllErrors(errors, std.io.getStdOut().writer());
    };
    
    // Now parse and visualize with error aggregation
    std.debug.print("\n=== Error Visualization with Aggregation ===\n", .{});
    
    // Create parser
    var parser2 = try lib.EnhancedParser.init(
        allocator,
        sample_code,
        token_config,
        state_config,
        1024, // buffer size
        .validation // Validation mode to collect all errors
    );
    defer parser2.deinit();
    
    // Set event handler
    parser2.setEventHandler(EventHandler.init(handleEvent, null));
    
    // Create an error aggregator
    var aggregator = ErrorAggregator.init(allocator);
    defer aggregator.deinit();
    
    // Parse the input and collect errors
    parser2.parse() catch |err| {
        std.debug.print("\nParsing found errors: {any}\n", .{err});
        
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
            errdefer cloned_ctx.deinit(allocator);
            
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
        
        // Create a visualizer
        var visualizer = try ErrorVisualizer.init(
            allocator,
            sample_code,
            .{ 
                .use_colors = false, // No colors for terminal compatibility
                .context_lines = 1,  // Show less context to keep output compact
            }
        );
        defer visualizer.deinit();
        
        // Visualize the error groups
        try visualizer.visualizeAllErrorGroups(aggregator.getErrorGroups(), std.io.getStdOut().writer());
    };
    
    std.debug.print("\n=== Color Error Visualization (if supported by terminal) ===\n", .{});
    
    // Create parser with colors
    var parser3 = try lib.EnhancedParser.init(
        allocator,
        sample_code,
        token_config,
        state_config,
        1024, // buffer size
        .validation // Validation mode to collect all errors
    );
    defer parser3.deinit();
    
    // Set event handler
    parser3.setEventHandler(EventHandler.init(handleEvent, null));
    
    // Parse the input and collect errors
    parser3.parse() catch |err| {
        std.debug.print("\nParsing found errors: {any}\n", .{err});
        
        // Get all errors from the parser
        const errors = parser3.getErrors();
        
        // Create a visualizer with colors
        var visualizer = try ErrorVisualizer.init(
            allocator,
            sample_code,
            .{ 
                .use_colors = true, // Use colors
                .marker_char = '~',  // Use different marker
            }
        );
        defer visualizer.deinit();
        
        // Visualize each error
        try visualizer.visualizeAllErrors(errors, std.io.getStdOut().writer());
    };
    
    std.debug.print("\nExample completed\n", .{});
}