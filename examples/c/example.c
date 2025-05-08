#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../src/zigparse.h"

// Example event handler callback
void handle_event(
    int event_type,
    const char* data,
    size_t data_len,
    void* user_data
) {
    const char* event_name = "UNKNOWN";
    
    // Get the event name based on the type
    switch (event_type) {
        case ZP_EVENT_START_DOCUMENT:
            event_name = "START_DOCUMENT";
            break;
        case ZP_EVENT_END_DOCUMENT:
            event_name = "END_DOCUMENT";
            break;
        case ZP_EVENT_START_ELEMENT:
            event_name = "START_ELEMENT";
            break;
        case ZP_EVENT_END_ELEMENT:
            event_name = "END_ELEMENT";
            break;
        case ZP_EVENT_VALUE:
            event_name = "VALUE";
            break;
        case ZP_EVENT_ERROR:
            event_name = "ERROR";
            break;
    }
    
    // Print the event information
    printf("Event: %s\n", event_name);
    
    if (data && data_len > 0) {
        // Print the event data (safely handling non-null-terminated data)
        printf("  Data: %.*s\n", (int)data_len, data);
    }
    
    // Use the user data if provided
    if (user_data) {
        printf("  Context: %s\n", (const char*)user_data);
    }
}

int main() {
    // Initialize the library
    ZP_Result result = zp_init();
    if (result.code != ZP_OK) {
        fprintf(stderr, "Failed to initialize ZigParse\n");
        return 1;
    }
    
    // Test that the API is working
    int test_result = zp_test();
    printf("API test result: %d (should be 42)\n", test_result);
    
    // Create a parser for JSON format
    result = zp_create_format_parser("json");
    if (result.code != ZP_OK) {
        fprintf(stderr, "Failed to create JSON parser: %d\n", result.code);
        
        // This is expected to fail at this point since the implementation is not complete
        printf("Expected failure for zp_create_format_parser: %d (ZP_ERROR_NOT_IMPLEMENTED)\n", result.code);
    } else {
        ZP_Parser* parser = (ZP_Parser*)result.data;
        
        // Set an event handler
        const char* context = "Example context";
        result = zp_set_event_handler(parser, handle_event, (void*)context);
        if (result.code != ZP_OK) {
            fprintf(stderr, "Failed to set event handler: %d\n", result.code);
        }
        
        // Parse a JSON string
        const char* json = "{\"name\":\"John\",\"age\":30}";
        result = zp_parse_string(parser, json, strlen(json));
        if (result.code != ZP_OK) {
            fprintf(stderr, "Failed to parse JSON: %d\n", result.code);
            fprintf(stderr, "Error: %s\n", zp_get_error(parser));
        }
        
        // Destroy the parser
        result = zp_destroy_parser(parser);
        if (result.code != ZP_OK) {
            fprintf(stderr, "Failed to destroy parser: %d\n", result.code);
        }
    }
    
    // Shut down the library
    result = zp_shutdown();
    if (result.code != ZP_OK) {
        fprintf(stderr, "Failed to shut down ZigParse\n");
        return 1;
    }
    
    printf("C API example completed successfully!\n");
    return 0;
}