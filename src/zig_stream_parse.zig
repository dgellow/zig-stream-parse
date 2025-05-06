// This is the main API entry point for the ZigParse library
pub const ByteStream = @import("byte_stream.zig").ByteStream;
pub const Position = @import("common.zig").Position;
pub const Tokenizer = @import("tokenizer.zig").Tokenizer;
pub const Token = @import("tokenizer.zig").Token;
pub const TokenType = @import("tokenizer.zig").TokenType;
pub const TokenMatcher = @import("tokenizer.zig").TokenMatcher;
pub const StateMachine = @import("state_machine.zig").StateMachine;
pub const State = @import("state_machine.zig").State;
pub const StateTransition = @import("state_machine.zig").StateTransition;
pub const ActionFn = @import("state_machine.zig").ActionFn;
pub const EventEmitter = @import("event_emitter.zig").EventEmitter;
pub const Event = @import("event_emitter.zig").Event;
pub const EventType = @import("event_emitter.zig").EventType;
pub const EventHandler = @import("event_emitter.zig").EventHandler;
pub const Parser = @import("parser.zig").Parser;
pub const ParserContext = @import("parser.zig").ParserContext;
pub const TokenizerConfig = @import("parser.zig").TokenizerConfig;
pub const StateMachineConfig = @import("parser.zig").StateMachineConfig;
pub const Grammar = @import("grammar.zig").Grammar;

// Export the add function for backward compatibility
pub export fn add(a: i32, b: i32) i32 {
    return a + b;
}