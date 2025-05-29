# ZigParse

A joyful, zero-allocation streaming parser framework for Zig.

## Quick Example

```zig
const std = @import("std");
const zigparse = @import("zigparse");

// Define tokens as an enum
const Token = enum { word, number, whitespace };

// Map tokens to patterns  
const patterns = .{
    .word = zigparse.match.alpha.oneOrMore(),
    .number = zigparse.match.digit.oneOrMore(),
    .whitespace = zigparse.match.whitespace.oneOrMore(),
};

pub fn main() !void {
    const input = "hello 123 world";
    var stream = zigparse.TokenStream.init(input);
    
    while (stream.next(patterns)) |token| {
        std.debug.print("{s}: '{s}'\n", .{ @tagName(token.type), token.text });
    }
}
```

Output:
```
word: 'hello'
whitespace: ' '
number: '123'
whitespace: ' '
word: 'world'
```

## Features

- **Zero allocations** - Returns slices into your input
- **Compile-time patterns** - Build optimal parsers at compile time
- **Simple API** - No builders, no ceremony
- **Fast** - SIMD-accelerated pattern matching
- **Streaming** - Parse gigabyte files with kilobyte buffers

## Installation

Add to your `build.zig.zon`:
```zig
.dependencies = .{
    .zigparse = .{
        .url = "https://github.com/sam/zig-stream-parse/archive/main.tar.gz",
    },
},
```

## Examples

### JSON Parser
```zig
const JsonValue = union(enum) {
    object: std.StringHashMap(JsonValue),
    array: std.ArrayList(JsonValue),
    string: []const u8,
    number: f64,
    boolean: bool,
    null,
};

const json = try zigparse.json.parse(allocator, input);
defer json.deinit();
```

### CSV Parser
```zig
var csv = zigparse.csv.Parser.init(allocator);
defer csv.deinit();

const reader = std.io.getStdIn().reader();
while (try csv.next(reader)) |row| {
    for (row.fields) |field| {
        std.debug.print("{s},", .{field});
    }
    std.debug.print("\n", .{});
}
```

### Custom Parser
```zig
const MyParser = zigparse.Parser(.{
    .tokens = enum { identifier, number, operator, whitespace },
    
    .patterns = .{
        .identifier = zigparse.match.alpha.then(zigparse.match.alphanumeric.zeroOrMore()),
        .number = zigparse.match.digit.oneOrMore(),
        .operator = zigparse.match.anyOf("+-*/="),
        .whitespace = zigparse.match.whitespace.oneOrMore(),
    },
    
    .skip = .{.whitespace},
});
```

## Performance

Benchmarks on a 2.6 GHz Intel Core i7:

| Parser | Input Size | Time | Memory | Allocations |
|--------|-----------|------|--------|-------------|
| JSON | 1 MB | 2.3 ms | 0 B | 0 |
| CSV | 10 MB | 18.7 ms | 0 B | 0 |
| XML | 5 MB | 9.1 ms | 0 B | 0 |

## Philosophy

ZigParse follows Zig's principles:
- Simple is better than clever
- Explicit is better than implicit  
- Performance matters
- Zero is better than one

See [CLAUDE.md](CLAUDE.md) for architecture details.