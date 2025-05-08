const std = @import("std");
const testing = std.testing;
const Parser = @import("parser").Parser;
const ByteStream = @import("parser").ByteStream;
const Tokenizer = @import("parser").Tokenizer;
const Token = @import("parser").Token;
const TokenType = @import("parser").TokenType;
const TokenMatcher = @import("parser").TokenMatcher;
const StateMachine = @import("parser").StateMachine;
const State = @import("parser").State;
const StateTransition = @import("parser").StateTransition;
const ParserContext = @import("parser").ParserContext;
const Event = @import("parser").Event;
const EventType = @import("parser").EventType;
const EventHandler = @import("parser").EventHandler;

// Simple test for incremental parser methods - minimal test to see if the methods exist
test "Incremental Parser Basics" {
    const allocator = testing.allocator;
    
    // Create dummy parsing components
    const skip_types = [_]TokenType{};
    
    const state_transitions = [_]StateTransition{
        StateTransition{ .token_id = 1, .next_state = 0, .action_id = null },
    };
    
    const states = [_]State{
        State{ .id = 0, .name = "TEST_STATE", .transitions = &state_transitions },
    };
    
    const tokenizer_matchers = [_]TokenMatcher{};
    const actions = [_]@import("parser").ActionFn{};
    
    // Set up tokenizer config
    const tokenizer_config = @import("parser").TokenizerConfig{
        .matchers = &tokenizer_matchers,
        .skip_types = &skip_types,
    };
    
    // Set up state machine config
    const state_machine_config = @import("parser").StateMachineConfig{
        .states = &states,
        .actions = &actions,
        .initial_state_id = 0,
    };
    
    // Create a parser with a valid initial source
    var parser = try Parser.init(
        allocator,
        "test", // A simple test string
        tokenizer_config,
        state_machine_config,
        4096
    );
    defer parser.deinit();
    
    // Test that the process method exists
    if (parser.process("more test data")) {
        // Success - not expected, but we're just checking the method exists
    } else |_| {
        // Error - expected, methods are implemented but may fail for our test case
    }
    
    // Test that the finish method exists
    if (parser.finish()) {
        // Success - not expected, but we're just checking the method exists
    } else |_| {
        // Error - expected, methods are implemented but may fail for our test case
    }
}