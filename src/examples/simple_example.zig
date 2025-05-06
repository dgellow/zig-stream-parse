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

// Simple example that parses words and numbers
fn wordTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Peek at the first character
    const first_char = try stream.peek();
    if (first_char == null) return null;
    
    // Check if it's a letter
    if (!isAlpha(first_char.?)) return null;
    
    // Start of a word, consume it
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    
    // Consume the first character
    _ = try stream.consume();
    try token_bytes.append(first_char.?);
    
    // Continue consuming until we hit a non-alphabetic character
    while (true) {
        const next_char = try stream.peek();
        if (next_char == null or !isAlpha(next_char.?)) break;
        
        _ = try stream.consume();
        try token_bytes.append(next_char.?);
    }
    
    // Create the token
    const lexeme = try allocator.dupe(u8, token_bytes.items);
    return Token.init(
        .{ .id = 1, .name = "WORD" },
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
    while (true) {
        const next_char = try stream.peek();
        if (next_char == null or !isDigit(next_char.?)) break;
        
        _ = try stream.consume();
        try token_bytes.append(next_char.?);
    }
    
    // Create the token
    const lexeme = try allocator.dupe(u8, token_bytes.items);
    return Token.init(
        .{ .id = 2, .name = "NUMBER" },
        start_pos,
        lexeme
    );
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
        .{ .id = 3, .name = "WHITESPACE" },
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
fn emitWord(ctx: *ParserContext, token: Token) !void {
    try ctx.pushValue(token.lexeme);
    std.debug.print("Word: {s}\n", .{token.lexeme});
}

fn emitNumber(ctx: *ParserContext, token: Token) !void {
    try ctx.pushValue(token.lexeme);
    std.debug.print("Number: {s}\n", .{token.lexeme});
}

// Event handler
fn handleEvent(event: Event, ctx: ?*anyopaque) !void {
    _ = ctx;
    switch (event.type) {
        .START_DOCUMENT => std.debug.print("Start Document\n", .{}),
        .END_DOCUMENT => std.debug.print("End Document\n", .{}),
        .VALUE => std.debug.print("Value: {s}\n", .{event.data.string_value}),
        .ERROR => std.debug.print("Error: {s}\n", .{event.data.error_info.message}),
        else => {},
    }
}

pub fn main() !void {
    // Setup allocator
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = general_purpose_allocator.allocator();
    defer _ = general_purpose_allocator.deinit();

    // Print welcome message
    std.debug.print("ZigParse: Simple Parser Example\n", .{});

    // Create token matchers
    const word_matcher = TokenMatcher.init(wordTokenMatcher);
    const number_matcher = TokenMatcher.init(numberTokenMatcher);
    const whitespace_matcher = TokenMatcher.init(whitespaceTokenMatcher);

    // Create tokenizer configuration
    const matchers = [_]TokenMatcher{
        word_matcher,
        number_matcher,
        whitespace_matcher,
    };
    
    const skip_types = [_]TokenType{
        .{ .id = 3, .name = "WHITESPACE" },
    };

    // Create state machine configuration
    const action_fns = [_]ActionFn{
        emitWord,
        emitNumber,
    };

    const transitions = [_]StateTransition{
        .{ .token_id = 1, .next_state = 0, .action_id = 0 }, // WORD -> INITIAL w/ emitWord
        .{ .token_id = 2, .next_state = 0, .action_id = 1 }, // NUMBER -> INITIAL w/ emitNumber
    };

    const states = [_]State{
        .{ .id = 0, .name = "INITIAL", .transitions = &transitions },
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

    // Create example input
    const input = "hello 123 world 456";

    // Create a parser
    var parser = try Parser.init(
        allocator,
        input,
        token_config,
        state_config,
        1024 // buffer size
    );
    defer parser.deinit();

    // Set event handler
    parser.setEventHandler(EventHandler.init(handleEvent, null));

    // Parse the input
    try parser.parse();

    // Notify user about successful parsing
    std.debug.print("\nParsing completed successfully!\n", .{});
}