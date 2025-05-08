# ZigParse C Examples

This directory contains examples of using the ZigParse library from C code.

## Building and Running

To build all examples:

```
zig build
```

To run the basic example:

```
zig build run-c-example
```

## Available Examples

### Basic Example (`example.c`)

Demonstrates initializing the library, creating a parser, setting an event handler, and processing some input.

Key concepts demonstrated:
- Library initialization and shutdown
- Error handling
- Event callbacks
- Basic JSON parsing

## Adding New Examples

When adding new C examples:

1. Create a new `.c` file in this directory
2. Update `build.zig` to compile and link the new example
3. Add a run step for the new example
4. Update this README to document the new example

## C API Reference

For detailed documentation on the ZigParse C API, see the main [C API documentation](/docs/c_api.md).