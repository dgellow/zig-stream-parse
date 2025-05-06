const std = @import("std");
const lib = @import("zig_stream_parse_lib");

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

// Token types for CSV parsing
const TOKEN_STRING = 0;
const TOKEN_COMMA = 1;
const TOKEN_NEWLINE = 2;
const TOKEN_EOF = 3;

// State machine states
const STATE_FIELD = 0;
const STATE_DELIMITER = 1;
const STATE_ROW_END = 2;

// Simple CSV tokenizers
fn stringTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    const start_pos = stream.getPosition();
    
    // Build the string
    // Check for tokens first, since tokens might be empty strings
    // Check if the next character is a comma or newline
    const peek_char = try stream.peek();
    if (peek_char != null) {
        if (peek_char.? == ',') {
            return null; // Let the comma matcher handle it
        } else if (peek_char.? == '\n' or peek_char.? == '\r') {
            return null; // Let the newline matcher handle it
        }
    }
    
    var token_bytes = std.ArrayList(u8).init(allocator);
    defer token_bytes.deinit();
    
    var quoted = false;
    const first_char = try stream.peek();
    if (first_char != null and first_char.? == '"') {
        quoted = true;
        _ = try stream.consume(); // Consume the opening quote
    }
    
    while (true) {
        const next_char = try stream.peek();
        if (next_char == null) break;
        
        if (quoted) {
            if (next_char.? == '"') {
                _ = try stream.consume();
                const lookahead = try stream.peek();
                if (lookahead == null or lookahead.? != '"') {
                    break; // End of quoted string
                }
                // Double quote inside quoted string, treat as single quote
                _ = try stream.consume();
                try token_bytes.append('"');
                continue;
            }
        } else {
            if (next_char.? == ',' or next_char.? == '\n' or next_char.? == '\r') {
                break;
            }
        }
        
        _ = try stream.consume();
        try token_bytes.append(next_char.?);
    }
    
    // Create the token
    const lexeme = try allocator.dupe(u8, token_bytes.items);
    return Token.init(
        .{ .id = TOKEN_STRING, .name = "STRING" },
        start_pos,
        lexeme
    );
}

fn commaTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    _ = allocator;
    const start_pos = stream.getPosition();
    
    const next_char = try stream.peek();
    if (next_char == null or next_char.? != ',') return null;
    
    _ = try stream.consume();
    
    return Token.init(
        .{ .id = TOKEN_COMMA, .name = "COMMA" },
        start_pos,
        ","
    );
}

fn newlineTokenMatcher(stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
    _ = allocator;
    const start_pos = stream.getPosition();
    
    const next_char = try stream.peek();
    if (next_char == null) return null;
    
    if (next_char.? == '\n') {
        _ = try stream.consume();
        return Token.init(
            .{ .id = TOKEN_NEWLINE, .name = "NEWLINE" },
            start_pos,
            "\n"
        );
    }
    
    if (next_char.? == '\r') {
        _ = try stream.consume();
        const lookahead = try stream.peek();
        if (lookahead != null and lookahead.? == '\n') {
            _ = try stream.consume();
            return Token.init(
                .{ .id = TOKEN_NEWLINE, .name = "NEWLINE" },
                start_pos,
                "\r\n"
            );
        }
        return Token.init(
            .{ .id = TOKEN_NEWLINE, .name = "NEWLINE" },
            start_pos,
            "\r"
        );
    }
    
    return null;
}

// State machine actions
fn emitField(ctx: *ParserContext, token: Token) !void {
    std.debug.print("Field: {s}\n", .{token.lexeme});
    try ctx.pushValue(token.lexeme);
}

fn endField(ctx: *ParserContext, token: Token) !void {
    _ = token;
    _ = ctx;
    std.debug.print("End of field\n", .{});
}

fn endRow(ctx: *ParserContext, token: Token) !void {
    _ = token;
    _ = ctx;
    std.debug.print("End of row\n", .{});
}

// Event handler
fn handleEvent(event: Event, ctx: ?*anyopaque) !void {
    _ = ctx;
    switch (event.type) {
        .START_DOCUMENT => std.debug.print("CSV Parsing Started\n", .{}),
        .END_DOCUMENT => std.debug.print("CSV Parsing Completed\n", .{}),
        else => {},
    }
}

pub fn main() !void {
    // Setup allocator
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = general_purpose_allocator.allocator();
    defer _ = general_purpose_allocator.deinit();

    // Print welcome message
    std.debug.print("ZigParse CSV Parser Example\n", .{});

    // Create token matchers
    const string_matcher = TokenMatcher.init(stringTokenMatcher);
    const comma_matcher = TokenMatcher.init(commaTokenMatcher);
    const newline_matcher = TokenMatcher.init(newlineTokenMatcher);

    // Create tokenizer configuration
    const matchers = [_]TokenMatcher{
        string_matcher,
        comma_matcher,
        newline_matcher,
    };
    
    const skip_types = [_]TokenType{};

    // Create state machine configuration
    const action_fns = [_]ActionFn{
        emitField,
        endField,
        endRow,
    };

    const transitions_field = [_]StateTransition{
        .{ .token_id = TOKEN_STRING, .next_state = STATE_DELIMITER, .action_id = 0 }, // STRING -> DELIMITER w/ emitField
        .{ .token_id = TOKEN_COMMA, .next_state = STATE_FIELD, .action_id = 1 },     // COMMA -> FIELD w/ endField (empty field)
        .{ .token_id = TOKEN_NEWLINE, .next_state = STATE_FIELD, .action_id = 2 },   // NEWLINE -> FIELD w/ endRow (empty field at end of row)
    };

    const transitions_delimiter = [_]StateTransition{
        .{ .token_id = TOKEN_COMMA, .next_state = STATE_FIELD, .action_id = 1 },     // COMMA -> FIELD w/ endField
        .{ .token_id = TOKEN_NEWLINE, .next_state = STATE_FIELD, .action_id = 2 },   // NEWLINE -> FIELD w/ endRow
    };

    const transitions_row_end = [_]StateTransition{
        .{ .token_id = TOKEN_STRING, .next_state = STATE_DELIMITER, .action_id = 0 }, // STRING -> DELIMITER w/ emitField
    };

    const states = [_]State{
        .{ .id = STATE_FIELD, .name = "FIELD", .transitions = &transitions_field },
        .{ .id = STATE_DELIMITER, .name = "DELIMITER", .transitions = &transitions_delimiter },
        .{ .id = STATE_ROW_END, .name = "ROW_END", .transitions = &transitions_row_end },
    };

    // Set up tokenizer config and state machine config
    const token_config = lib.TokenizerConfig{
        .matchers = &matchers,
        .skip_types = &skip_types,
    };

    const state_config = lib.StateMachineConfig{
        .states = &states,
        .actions = &action_fns,
        .initial_state_id = STATE_FIELD,
    };

    // Create example CSV input
    const input = 
        \\name,age,city
        \\John,25,New York
        \\Alice,30,San Francisco
        \\Bob,28,Chicago
        \\
    ;

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
    std.debug.print("\nCSV Parsing completed successfully!\n", .{});
}