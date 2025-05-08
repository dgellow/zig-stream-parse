# ZigParse Error Handling Guide

This document describes the error handling capabilities in ZigParse and provides best practices for handling errors in your parsers.

## Table of Contents

1. [Introduction](#introduction)
2. [Error Types and Categories](#error-types-and-categories)
3. [Error Context and Reporting](#error-context-and-reporting)
4. [Error Recovery Strategies](#error-recovery-strategies)
5. [Error Aggregation](#error-aggregation)
6. [Error Visualization](#error-visualization)
7. [Parser Modes](#parser-modes)
8. [Best Practices](#best-practices)
9. [Examples](#examples)

## Introduction

ZigParse provides a comprehensive error handling system that allows you to:

- Detect and report detailed errors with context
- Recover from errors and continue parsing
- Customize error handling behavior with different parsing modes
- Collect and format rich error information

The error system is designed to be flexible, allowing everything from strict parsing (stop on first error) to lenient parsing (try hard to recover from errors) depending on your use case.

## Error Types and Categories

Errors in ZigParse are organized into categories and specific error codes:

### Error Categories

- **Lexical**: Issues with character recognition and tokenization
- **Syntax**: Issues with grammar structure and token sequence
- **Semantic**: Issues with the meaning of correctly structured input
- **Internal**: Parser implementation errors
- **IO**: Input/output related errors

### Error Codes

Each error has a specific error code that identifies the exact issue:

```zig
pub const ErrorCode = enum(u32) {
    // Lexical errors (100-199)
    unknown_character = 100,
    invalid_escape_sequence = 101,
    unterminated_string = 102,
    // ...

    // Syntax errors (200-299)
    unexpected_token = 200,
    unexpected_end_of_input = 201,
    missing_token = 202,
    // ...

    // Semantic errors (300-399)
    duplicate_identifier = 300,
    undeclared_identifier = 301,
    type_mismatch = 302,
    // ...

    // Internal errors (900-999)
    internal_error = 900,
    state_machine_error = 901,
    memory_error = 902,
    // ...
};
```

### Error Severity

Each error also has an associated severity level:

- **Warning**: Non-fatal issues that don't stop parsing
- **Error**: Issues that may be recoverable but indicate a problem
- **Fatal**: Critical issues that require stopping the parse

## Error Context and Reporting

ZigParse provides rich error context through the `ErrorContext` struct:

```zig
pub const ErrorContext = struct {
    // Error identification
    code: ErrorCode,
    severity: ErrorSeverity,
    
    // Location information
    position: Position,  // line, column, and offset
    
    // Error message
    message: []const u8,
    
    // Additional context
    token: ?Token,
    expected_token_types: ?[]const u32,
    state_id: ?u32,
    state_name: ?[]const u8,
    
    // Recovery help
    recovery_hint: ?[]const u8,
    
    // ...
};
```

This context can be used to generate detailed error messages showing:

- Error type and location
- The problematic token
- Expected valid tokens
- Current parser state
- Suggestions for recovery

### Error Reporter

The `ErrorReporter` interface collects errors and warnings during parsing:

```zig
var reporter = ErrorReporter.init(allocator);
defer reporter.deinit();

// Report an error
try reporter.reportError(
    ErrorCode.unexpected_token,
    position,
    "Unexpected token '+', expected number"
);

// Check for errors
if (reporter.hasErrors()) {
    // Handle errors
}

// Print all errors
try reporter.printAll();
```

## Error Recovery Strategies

ZigParse offers multiple strategies for recovering from errors:

1. **Stop on First Error**: Parsing stops immediately when the first error is encountered
2. **Continue After Error**: Report the error but continue from the next token
3. **Synchronize**: Skip tokens until a synchronization point (e.g., statement terminator) is found
4. **Repair and Continue**: Attempt to fix the error by inserting or modifying tokens

```zig
// Configure error recovery
const recovery_config = ErrorRecoveryConfig{
    .strategy = .synchronize,
    .sync_token_types = &[_]u32{ TOKEN_SEMICOLON, TOKEN_RBRACE },
    .max_errors = 10,
};
```

## Error Aggregation

ZigParse provides an error aggregation system that intelligently groups related errors to help users identify root causes and reduce error noise. This is especially useful for complex inputs where a single mistake can cascade into multiple errors.

### Error Groups

The system uses an `ErrorGroup` structure to organize related errors:

```zig
pub const ErrorGroup = struct {
    // Primary error that likely caused other errors
    primary_error: ErrorContext,
    
    // Related errors that are likely consequences of the primary error
    related_errors: std.ArrayList(ErrorContext),
    
    // ...
};
```

### How Errors Are Related

The `ErrorAggregator` determines if errors are related based on several factors:

1. **Proximity**: Errors on the same line or nearby lines
2. **Error Category**: Errors of the same category are often related
3. **Error Code Patterns**: Certain combinations of error codes are frequently related
   - Missing tokens and unexpected tokens
   - Unterminated strings and subsequent syntax errors
   - Unbalanced delimiters and related syntax issues

### Using the Error Aggregator

```zig
// Create an error aggregator
var aggregator = ErrorAggregator.init(allocator);
defer aggregator.deinit();

// Collect errors from parsing
parser.parse() catch |err| {
    // Get all errors from the parser
    const errors = parser.getErrors();
    
    // Report each error to the aggregator
    for (errors) |error_ctx| {
        try aggregator.report(error_ctx);
    }
    
    // Print aggregated errors with intelligent grouping
    try aggregator.printAll();
};
```

### Configuration

You can configure the error aggregator to adjust how errors are grouped:

```zig
const aggregation_config = ErrorAggregationConfig{
    .enabled = true,
    .max_token_distance = 5,
    .max_line_distance = 3,
};
```

### Benefits

The error aggregation system provides several benefits:

1. **Reduced Noise**: Users aren't overwhelmed with cascading errors
2. **Root Cause Identification**: Primary errors are distinguished from their consequences
3. **Cleaner Error Reports**: Grouped errors are easier to understand and fix
4. **Better User Experience**: Helps users focus on fixing the most important issues first

## Error Visualization

ZigParse provides an error visualization system that displays source code snippets with highlighted error positions. This makes it easier for users to locate and understand errors in their input.

### Visualizer Configuration

```zig
pub const VisualizerConfig = struct {
    /// Number of context lines to show before and after error
    context_lines: usize = 2,
    
    /// Maximum line length to display
    max_line_length: usize = 120,
    
    /// Character to use for error position marker
    marker_char: u8 = '^',
    
    /// Color mode for terminal output
    use_colors: bool = true,
};
```

### Creating and Using a Visualizer

```zig
// Create a visualizer with the source code and configuration
var visualizer = try ErrorVisualizer.init(
    allocator,
    source_code,
    .{
        .use_colors = true,
        .context_lines = 2,
        .marker_char = '^'
    }
);
defer visualizer.deinit();

// Visualize a single error
try visualizer.visualizeError(error_ctx, std.io.getStdOut().writer());

// Visualize all errors
try visualizer.visualizeAllErrors(errors, std.io.getStdOut().writer());

// Visualize error groups with primary and related errors
try visualizer.visualizeAllErrorGroups(groups, std.io.getStdOut().writer());
```

### Visualization Features

1. **Source Context**: Shows the error location within the source code
2. **Position Highlighting**: Points to the exact column where the error occurred
3. **Configurable Context**: Control how many surrounding lines to display
4. **Color Support**: Optional ANSI color formatting for terminal output
5. **Error Metadata**: Displays error code, message, and recovery hints

### Sample Output

```
error at line 3, column 19:
missing_token: Missing semicolon at end of statement

 1 | function example() {
 2 |     let x = 10;
 3 |     let y = "hello"
                      ^
 4 |     return x + y;
 5 | }

 Hint: Add a semicolon after the string literal
```

### Integration with Error Aggregation

The visualizer can display error groups to show primary errors and their related errors:

```zig
// Create an aggregator
var aggregator = ErrorAggregator.init(allocator);
defer aggregator.deinit();

// Collect and aggregate errors
// ...

// Visualize error groups
try visualizer.visualizeAllErrorGroups(
    aggregator.getErrorGroups(),
    std.io.getStdOut().writer()
);
```

## Parser Modes

The enhanced parser supports different parsing modes to control error handling behavior:

1. **Normal**: Collect syntax errors and try to recover
2. **Strict**: Stop on first error
3. **Lenient**: Try hard to recover from errors
4. **Validation**: Collect all errors without recovery attempts

```zig
// Create a parser with a specific mode
var parser = try Parser.init(
    allocator,
    input,
    tokenizer_config,
    state_machine_config,
    buffer_size,
    .strict  // Use strict mode
);
```

## Best Practices

### When to Use Each Parsing Mode

- **Normal Mode**: Use for typical parsing scenarios where you want to catch and report multiple errors but also recover where possible
- **Strict Mode**: Use when parsing security-critical input or when you want to fail fast
- **Lenient Mode**: Use for user-authored input where recovery is more important than correctness
- **Validation Mode**: Use for linting or checking valid syntax without actually processing the input

### Synchronization Point Selection

Good synchronization points for error recovery are tokens that clearly indicate the start of a new syntactic unit:

- Statement terminators (semicolons, newlines)
- Block delimiters (braces, brackets)
- Keywords that begin statements or blocks

### Error Reporting Practices

- Include line and column information for user-facing errors
- Use clear, human-readable error messages that suggest how to fix the problem
- For syntax errors, show the expected token types
- Group related errors to avoid overwhelming users
- Consider including a snippet of the source with error location highlighted

### Memory Management

Always ensure proper memory management when handling errors:

```zig
// Create an error context
var error_ctx = try ErrorContext.init(
    allocator,
    ErrorCode.unexpected_token,
    position,
    "Unexpected token"
);
defer error_ctx.deinit();

// Add additional information
try error_ctx.setTokenText(token.lexeme);
try error_ctx.setRecoveryHint("Try inserting a semicolon");
```

## Examples

### Basic Error Handling

```zig
// Create a parser
var parser = try Parser.init(
    allocator,
    input,
    tokenizer_config,
    state_machine_config,
    buffer_size,
    .normal
);
defer parser.deinit();

// Set event handler for errors
parser.setEventHandler(EventHandler.init(handleEvent, context));

// Try to parse, handle errors
parser.parse() catch |err| {
    std.debug.print("Parsing failed: {any}\n", .{err});
    
    // Print detailed error information
    try parser.printErrors();
    
    // Handle specific errors
    if (parser.hasErrors()) {
        for (parser.getErrors()) |error_ctx| {
            switch (error_ctx.code) {
                .unexpected_token => {
                    // Handle unexpected token errors
                },
                .missing_token => {
                    // Handle missing token errors
                },
                else => {
                    // Handle other errors
                },
            }
        }
    }
};
```

### Custom Error Recovery

```zig
// Define synchronization tokens
const sync_tokens = [_]u32{
    TOKEN_SEMICOLON,
    TOKEN_RBRACE,
    TOKEN_EOF,
};

// Configure recovery
const recovery_config = .{
    .strategy = .synchronize,
    .sync_token_types = &sync_tokens,
    .max_errors = 10,
};

// Create state machine with recovery config
const state_machine_config = StateMachineConfig{
    .states = &states,
    .actions = &actions,
    .initial_state_id = 0,
    .recovery_config = recovery_config,
};

// Use the parser
var parser = try Parser.init(
    allocator,
    input,
    tokenizer_config,
    state_machine_config,
    buffer_size,
    .normal
);
defer parser.deinit();

try parser.parse();
```

### Validation Mode for Linting

```zig
// Create a validator parser
var validator = try Parser.init(
    allocator,
    input,
    tokenizer_config,
    state_machine_config,
    buffer_size,
    .validation
);
defer validator.deinit();

// Parse in validation mode
validator.parse() catch |_| {
    // Validation mode will collect all errors but not attempt recovery
};

// Print all errors and warnings as lint feedback
try validator.printErrors();

// Get counts
const error_count = validator.getErrors().len;
const warning_count = validator.getWarnings().len;

std.debug.print("{d} errors, {d} warnings found\n", .{
    error_count, warning_count
});
```

### Error Visualization Example

```zig
// Source code with errors
const source_with_errors = 
    \\function example() {
    \\    let x = 10
    \\    let y = "hello;
    \\    return x + y;
    \\}
;

// Parse and collect errors
parser.parse() catch |err| {
    const errors = parser.getErrors();
    
    // Create a visualizer
    var visualizer = try ErrorVisualizer.init(
        allocator, 
        source_with_errors,
        .{ .use_colors = true }
    );
    defer visualizer.deinit();
    
    // Visualize the errors with source context
    try visualizer.visualizeAllErrors(errors, std.io.getStdOut().writer());
};
```

### Error Aggregation Example

```zig
// Parse JSON with multiple related errors
const json_with_errors = 
    \\{
    \\  "name": "John Doe",
    \\  "age": 30,
    \\  "address": {
    \\    "street": "123 Main St"
    \\    "city": "Anytown", // Missing comma after street
    \\    "state": "CA"
    \\  },
    \\  "phone_numbers": [
    \\    "555-1234",
    \\    "555-5678"
    \\  ]
    \\  "email": "john@example.com" // Missing comma after array
    \\}
;

// Create an error aggregator
var aggregator = ErrorAggregator.init(allocator);
defer aggregator.deinit();

// Parse input and collect errors
const errors = parser.getErrors();
for (errors) |error_ctx| {
    try aggregator.report(error_ctx);
}

// Print aggregated errors
try aggregator.printAll();

// Output might look like:
// === 2 Error Group(s) ===
//
// --- Group 1: missing_token at line 5, column 30 ---
// * PRIMARY: [error] missing_token (202): Expected token not found at line 5, column 30
//   - token: "city"
//   - state: OBJECT_VALUE
//   Related errors that may be consequences:
//   * 1. [error] unexpected_token (200): Unexpected token encountered at line 6, column 5
//
// --- Group 2: missing_token at line 11, column 4 ---
// * PRIMARY: [error] missing_token (202): Expected token not found at line 11, column 4
//   - token: "email"
//   - state: OBJECT_KEY
```

## Conclusion

The ZigParse error handling system provides a flexible foundation for building parsers with robust error detection, reporting, and recovery capabilities. By understanding the different error handling modes and strategies, you can create parsers that balance correctness and user experience for your specific use case.

Whether you need strict validation for security-critical applications or lenient parsing for user-authored content, ZigParse gives you the tools to implement appropriate error handling behavior. The error aggregation system takes this a step further by helping users identify root causes and reducing error noise, especially in complex documents.