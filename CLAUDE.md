# ZigParse: Zero-Allocation Streaming Parser

## Philosophy

ZigParse embraces Zig's core principles:
- **Explicit over implicit**: No hidden allocations or control flow
- **Simplicity**: Understand the entire library in minutes
- **Performance**: Cache-friendly, zero-allocation design
- **Compile-time power**: Generate optimal parsers at build time
- **Joy**: APIs that are a pleasure to use

## Core Design Principles

1. **Zero allocations by default** - Parsers return slices into the input buffer
2. **Data-oriented layout** - Hot data together, cold data separate
3. **Compile-time generation** - State machines and lookup tables built at comptime
4. **Direct APIs** - No builders, no ceremony, just data
5. **True streaming** - Ring buffers for real incremental parsing

## Architecture

```
Input → TokenStream → Parser → Events
         ↑              ↑
         └── Patterns ──┘
```

### TokenStream

Zero-allocation tokenization that returns slices into the source:

```zig
pub const TokenStream = struct {
    source: []const u8,
    pos: usize = 0,
    
    pub fn next(self: *TokenStream, comptime patterns: anytype) ?Token {
        // Returns slices, no allocations
    }
};
```

### Patterns

Simple, composable pattern matching:

```zig
pub const match = struct {
    pub const alpha = Pattern{ .class = .alpha };
    pub const digit = Pattern{ .class = .digit };
    pub const whitespace = Pattern{ .class = .whitespace };
    
    pub fn literal(comptime str: []const u8) Pattern {
        return .{ .literal = str };
    }
    
    pub fn range(comptime min: u8, comptime max: u8) Pattern {
        return .{ .range = .{ .min = min, .max = max } };
    }
};
```

### Parser Definition

Define parsers as simple data:

```zig
const JsonParser = Parser(.{
    .tokens = enum {
        lbrace, rbrace, lbracket, rbracket,
        colon, comma, string, number,
        true, false, null, whitespace,
    },
    
    .patterns = .{
        .lbrace = match.literal("{"),
        .rbrace = match.literal("}"),
        .string = match.quoted('"'),
        .number = match.number,
        .whitespace = match.whitespace,
        // ...
    },
    
    .skip = .{.whitespace},
    
    .grammar = .{
        .value = union(enum) {
            object: Rule(.{ .lbrace, .pairs, .rbrace }),
            array: Rule(.{ .lbracket, .values, .rbracket }),
            string: Token(.string),
            number: Token(.number),
            // ...
        },
        // ...
    },
});
```

### Usage

Simple and direct:

```zig
// Parse a complete input
const result = try JsonParser.parse(allocator, input);
defer result.deinit();

// Or stream from a reader
var parser = JsonParser.init(allocator);
defer parser.deinit();

const reader = std.io.getStdIn().reader();
while (try parser.feed(reader)) |event| {
    switch (event) {
        .start_object => {},
        .key => |k| std.debug.print("key: {s}\n", .{k}),
        .string => |s| std.debug.print("string: {s}\n", .{s}),
        // ...
    }
}
```

## Implementation Strategy

### Phase 1: Core Infrastructure
- [ ] TokenStream with zero allocations
- [ ] Pattern matching system
- [ ] Compile-time character classification tables

### Phase 2: Parser Framework
- [ ] Compile-time grammar validation
- [ ] State machine generation
- [ ] Event emission system

### Phase 3: Optimizations
- [ ] SIMD pattern matching
- [ ] Streaming with ring buffers
- [ ] Parallel tokenization

### Phase 4: Examples
- [ ] JSON parser
- [ ] CSV parser
- [ ] Configuration file parser
- [ ] Programming language tokenizer

## Data Layout

### Token Buffer (when buffering is needed)

```zig
pub const TokenBuffer = struct {
    // Structure of Arrays for cache efficiency
    types: []const TokenType,    // 1 byte each
    starts: []const u32,          // 4 bytes each
    lengths: []const u16,         // 2 bytes each
    source: []const u8,           // Original text
    
    pub const Token = struct {
        type: TokenType,
        text: []const u8,
    };
    
    pub fn get(self: TokenBuffer, index: usize) Token {
        const start = self.starts[index];
        const len = self.lengths[index];
        return .{
            .type = self.types[index],
            .text = self.source[start..][0..len],
        };
    }
};
```

### Compile-Time Tables

```zig
// Generated at compile time for zero-cost classification
const CharClass = enum(u4) {
    other = 0,
    whitespace = 1,
    alpha = 2,
    digit = 3,
    // ...
};

const char_table = comptime blk: {
    var table = [_]CharClass{.other} ** 256;
    
    // Whitespace
    table[' '] = .whitespace;
    table['\t'] = .whitespace;
    table['\n'] = .whitespace;
    table['\r'] = .whitespace;
    
    // Digits
    for ('0'..'9' + 1) |c| {
        table[c] = .digit;
    }
    
    // Alpha
    for ('a'..'z' + 1) |c| {
        table[c] = .alpha;
        table[c - 32] = .alpha; // Uppercase
    }
    
    break :blk table;
};
```

## Performance Considerations

1. **Branch Prediction**: Order token patterns by frequency
2. **Cache Efficiency**: Keep hot data together
3. **Memory Access**: Sequential access patterns
4. **Allocations**: Zero by default, optional pooling
5. **SIMD**: Use for pattern searching when beneficial

## Testing Strategy

1. **Correctness**: Property-based testing with fuzzing
2. **Performance**: Benchmarks against reference parsers
3. **Memory**: Verify zero allocations in tests
4. **Edge Cases**: Comprehensive error handling tests

## Examples

### Simple Word Counter

```zig
const WordCounter = Parser(.{
    .tokens = enum { word, other },
    .patterns = .{
        .word = match.alpha.oneOrMore(),
        .other = match.any,
    },
    .skip = .{.other},
});

pub fn countWords(input: []const u8) usize {
    var stream = TokenStream.init(input);
    var count: usize = 0;
    
    while (stream.next(WordCounter.patterns)) |token| {
        if (token.type == .word) count += 1;
    }
    
    return count;
}
```

### CSV Parser

```zig
const CsvParser = Parser(.{
    .tokens = enum { field, comma, newline, quote },
    .patterns = .{
        .field = match.until(match.anyOf(",\n\"")),
        .comma = match.literal(","),
        .newline = match.literal("\n"),
        .quote = match.literal("\""),
    },
    
    .grammar = .{
        .file = Rule(.{ .row, .newline }).zeroOrMore(),
        .row = Rule(.{ .field, Optional(.{ .comma, .field }).zeroOrMore() }),
    },
});
```

## Error Handling

Errors are explicit and informative:

```zig
pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEof,
    InvalidUtf8,
    BufferTooSmall,
};

pub const ErrorInfo = struct {
    message: []const u8,
    line: usize,
    column: usize,
    hint: ?[]const u8 = null,
};
```

## Future Considerations

While the focus is on making an excellent Zig library, the design allows for:
- WebAssembly compilation for browser use
- C API generation for cross-language support
- Parallel parsing for large files
- Incremental reparsing for editors

But these are not primary goals - making a joyful Zig library is.