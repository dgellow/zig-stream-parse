# ZigParse C API Documentation

The ZigParse C API provides a cross-language interface to the ZigParse streaming parser framework. This document describes how to use the C API to create parsers, process data, and handle parsing events.

## Getting Started

### Building the C API

Build the C API library and examples:

```bash
zig build
```

This will create:
- A shared library (`libzigparse.so` on Linux, `zigparse.dll` on Windows, or `libzigparse.dylib` on macOS)
- A C header file (`include/zigparse.h`)
- C example executables in `zig-out/bin/`

### Running the C Example

```bash
zig build run-c-example
```

## Using the C API

### Basic Usage Pattern

```c
#include <zigparse.h>

// Initialize the library
zp_init();

// Create a parser
ZP_Result result = zp_create_format_parser("json");
if (result.code == ZP_OK) {
    ZP_Parser* parser = (ZP_Parser*)result.data;
    
    // Set up event handling
    zp_set_event_handler(parser, my_event_handler, my_context);
    
    // Parse data
    zp_parse_string(parser, json_string, strlen(json_string));
    
    // Clean up
    zp_destroy_parser(parser);
}

// Shut down the library
zp_shutdown();
```

### Event Handling

Define a callback function to handle parsing events:

```c
void my_event_handler(
    int event_type,
    const char* data,
    size_t data_len,
    void* user_data
) {
    switch (event_type) {
        case ZP_EVENT_START_DOCUMENT:
            // Handle document start
            break;
        case ZP_EVENT_END_DOCUMENT:
            // Handle document end
            break;
        case ZP_EVENT_VALUE:
            // Handle value event
            printf("Value: %.*s\n", (int)data_len, data);
            break;
        // Handle other event types...
    }
}
```

### Error Handling

Check return codes and retrieve error information:

```c
ZP_Result result = zp_parse_string(parser, data, data_len);
if (result.code != ZP_OK) {
    printf("Error %d: %s\n", zp_get_error_code(parser), zp_get_error(parser));
}
```

## API Reference

### Initialization and Shutdown

- `ZP_Result zp_init(void)`: Initialize the library
- `ZP_Result zp_shutdown(void)`: Clean up library resources

### Parser Creation and Destruction

- `ZP_Result zp_create_parser_from_json(const char* grammar_json, size_t len)`: Create a parser from a JSON grammar definition
- `ZP_Result zp_create_format_parser(const char* format_name)`: Create a parser for a specific format
- `ZP_Result zp_destroy_parser(ZP_Parser* parser)`: Destroy a parser

### Event Handling

- `ZP_Result zp_set_event_handler(ZP_Parser* parser, ZP_EventCallback callback, void* user_data)`: Set an event handler function

### Parsing

- `ZP_Result zp_parse_string(ZP_Parser* parser, const char* data, size_t len)`: Parse a complete string
- `ZP_Result zp_parse_chunk(ZP_Parser* parser, const char* data, size_t len)`: Parse a chunk of data incrementally
- `ZP_Result zp_finish_parsing(ZP_Parser* parser)`: Finish incremental parsing

### Error Handling

- `const char* zp_get_error(ZP_Parser* parser)`: Get the last error message
- `int zp_get_error_code(ZP_Parser* parser)`: Get the last error code

## Error Codes

- `ZP_OK`: No error (success)
- `ZP_ERROR_UNKNOWN`: Unknown error
- `ZP_ERROR_OUT_OF_MEMORY`: Memory allocation failed
- `ZP_ERROR_IO`: I/O error
- `ZP_ERROR_EOF`: Unexpected end of file
- `ZP_ERROR_INVALID_HANDLE`: Invalid parser handle
- `ZP_ERROR_INVALID_ARGUMENT`: Invalid argument
- `ZP_ERROR_INVALID_STATE`: Invalid parser state
- `ZP_ERROR_UNEXPECTED_TOKEN`: Unexpected token
- `ZP_ERROR_PARSER_CONFIG`: Parser configuration error
- `ZP_ERROR_NOT_IMPLEMENTED`: Feature not implemented

## Event Types

- `ZP_EVENT_START_DOCUMENT`: Start of the document
- `ZP_EVENT_END_DOCUMENT`: End of the document
- `ZP_EVENT_START_ELEMENT`: Start of an element
- `ZP_EVENT_END_ELEMENT`: End of an element
- `ZP_EVENT_VALUE`: Value
- `ZP_EVENT_ERROR`: Error

## Future Development

The ZigParse C API is still in development. Future versions will include:

1. Full support for incremental parsing
2. Additional predefined parsers for common formats
3. Grammar definition via JSON configuration
4. Memory usage control options
5. Additional performance optimizations

## Thread Safety

The current implementation is not thread-safe. Do not use the same parser from multiple threads simultaneously.

## Memory Management

The C API handles memory allocation and deallocation internally. Users should not attempt to free memory returned by API functions.

## Versioning

The C API follows semantic versioning. The current version is 0.1.0, indicating it is still in development and may change significantly.