# Zig Stream Parse: Streaming Parser Framework

> Note: this is a work in progress, everythis likely to be broken.

A streaming parser framework implemented in Zig that enables efficient processing of structured data. It's designed to handle incremental parsing without building complete intermediate trees, making it memory-efficient and suitable for processing large files or streams.

## Features

- **Memory Efficient**: Process data incrementally without building complete intermediate trees
- **Streaming Input**: Parse data as it arrives from various sources
- **Compile-Time Optimization**: Leverages Zig's compile-time features
- **Clean API**: Consistent interface for defining and using parsers
- **State Machine Based**: Precise control over parsing logic
- **Event-Driven Architecture**: Generate events during parsing for reactive applications

## Components

ZigParse consists of five main components:

1. **ByteStream**: Manages input from various sources with position tracking
2. **Tokenizer**: Converts raw bytes into meaningful tokens
3. **StateMachine**: Tracks parsing context and handles transitions
4. **EventEmitter**: Generates events based on parsed content
5. **Parser**: Orchestrates the entire parsing process

## Usage

### Basic Example

```zig
const std = @import("std");
const lib = @import("zig_stream_parse_lib");

// Define token matchers for your grammar
fn wordTokenMatcher(stream: *lib.ByteStream, allocator: std.mem.Allocator) !?lib.Token {
    // Implementation to match word tokens
}

fn numberTokenMatcher(stream: *lib.ByteStream, allocator: std.mem.Allocator) !?lib.Token {
    // Implementation to match number tokens
}

// Define state machine actions
fn emitWord(ctx: *lib.ParserContext, token: lib.Token) !void {
    std.debug.print("Word: {s}\n", .{token.lexeme});
}

fn emitNumber(ctx: *lib.ParserContext, token: lib.Token) !void {
    std.debug.print("Number: {s}\n", .{token.lexeme});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Set up tokenizer and state machine configuration
    const matchers = [_]lib.TokenMatcher{
        lib.TokenMatcher.init(wordTokenMatcher),
        lib.TokenMatcher.init(numberTokenMatcher),
    };

    const token_config = lib.TokenizerConfig{
        .matchers = &matchers,
        .skip_types = &[_]lib.TokenType{},
    };

    const actions = [_]*const fn (*lib.ParserContext, lib.Token) anyerror!void{
        emitWord,
        emitNumber,
    };

    const transitions = [_]lib.StateTransition{
        .{ .token_id = 1, .next_state = 0, .action_id = 0 },
        .{ .token_id = 2, .next_state = 0, .action_id = 1 },
    };

    const states = [_]lib.State{
        .{ .id = 0, .name = "INITIAL", .transitions = &transitions },
    };

    const state_config = lib.StateMachineConfig{
        .states = &states,
        .actions = &actions,
        .initial_state_id = 0,
    };

    // Create and use the parser
    const input = "hello 123 world 456";
    var parser = try lib.Parser.init(
        allocator,
        input,
        token_config,
        state_config,
        1024 // buffer size
    );
    defer parser.deinit();

    try parser.parse();
}
```

### Grammar Builder API

The library also provides a builder pattern for defining grammars:

```zig
var grammar_builder = lib.Grammar.init();
defer grammar_builder.deinit();

try grammar_builder.token("WORD", lib.TokenMatcher.init(wordTokenMatcher));
try grammar_builder.token("NUMBER", lib.TokenMatcher.init(numberTokenMatcher));
try grammar_builder.token("WHITESPACE", lib.TokenMatcher.init(whitespaceTokenMatcher));
try grammar_builder.skipToken("WHITESPACE");

try grammar_builder.action("emitWord", emitWord);
try grammar_builder.action("emitNumber", emitNumber);

try grammar_builder.initialState("INITIAL");

var state_builder = try grammar_builder.state("INITIAL");
try (try state_builder.on("WORD")).to("INITIAL").action("emitWord");
try (try state_builder.on("NUMBER")).to("INITIAL").action("emitNumber");

const parser_config = try grammar_builder.build();
```

## Examples

The repository includes the following examples:

1. **Simple Example**: A basic word and number tokenizer
2. **CSV Parser**: A more complex example for parsing CSV data

To run the examples:

```bash
# Run the simple example
zig build run-simple

# Run the CSV parser example
zig build run-csv
```

## Benchmarks

The library includes a benchmark suite to measure parsing performance with different input sizes:

```bash
# Run the benchmarks
zig build benchmark
```

The benchmark simulates parsing JSON-like data with varying complexities to evaluate:

1. **Throughput**: How fast the parser processes data (MB/s)
2. **Memory Usage**: How efficiently memory is used during parsing
3. **Scalability**: How performance scales with input size

## Design Philosophy

ZigParse follows these design principles:

1. **Memory Efficiency**: Minimize allocation and buffer copying
2. **Simple Interfaces**: Clear component boundaries with well-defined responsibilities
3. **Incremental Processing**: Handle data as it arrives without requiring the full input
4. **Zig Zen**: Adhere to Zig's philosophy and idiomatic patterns
5. **Performance Focus**: Optimize for speed while maintaining memory safety
