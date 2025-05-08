// This is the main API entry point for the ZigParse library
pub const ByteStream = @import("byte_stream.zig").ByteStream;
pub const Position = @import("common.zig").Position;
pub const Tokenizer = @import("tokenizer.zig").Tokenizer;
pub const Token = @import("tokenizer.zig").Token;
pub const TokenType = @import("tokenizer.zig").TokenType;
pub const TokenMatcher = @import("tokenizer.zig").TokenMatcher;
pub const TokenPool = @import("token_pool.zig").TokenPool;
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

// Error handling
pub const ErrorCode = @import("error.zig").ErrorCode;
pub const ErrorSeverity = @import("error.zig").ErrorSeverity;
pub const ErrorCategory = @import("error.zig").ErrorCategory;
pub const ErrorContext = @import("error.zig").ErrorContext;
pub const ErrorReporter = @import("error.zig").ErrorReporter;
pub const ErrorRecoveryStrategy = @import("error.zig").ErrorRecoveryStrategy;
pub const ParseError = @import("error.zig").ParseError;

// Enhanced parser with error handling
pub const ParseMode = @import("parser_enhanced.zig").ParseMode;
pub const EnhancedParser = @import("parser_enhanced.zig").Parser;

// Enhanced state machine with error recovery
pub const EnhancedStateMachine = @import("state_machine_enhanced.zig").StateMachine;
pub const ErrorRecoveryConfig = @import("state_machine_enhanced.zig").ErrorRecoveryConfig;

// Error aggregation
pub const ErrorAggregator = @import("error_aggregator.zig").ErrorAggregator;
pub const ErrorGroup = @import("error_aggregator.zig").ErrorGroup;
pub const ErrorAggregationConfig = @import("error_aggregator.zig").ErrorAggregationConfig;

// Error visualization
pub const ErrorVisualizer = @import("error_visualizer.zig").ErrorVisualizer;
pub const VisualizerConfig = @import("error_visualizer.zig").VisualizerConfig;
pub const AnsiColor = @import("error_visualizer.zig").AnsiColor;

// Export the add function for backward compatibility
pub export fn add(a: i32, b: i32) i32 {
    return a + b;
}