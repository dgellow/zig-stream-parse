#ifndef ZIGPARSE_H
#define ZIGPARSE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Error codes for ZigParse operations.
 */
typedef enum {
    // Success (no error)
    ZP_OK = 0,
    
    // Generic errors
    ZP_ERROR_UNKNOWN = 1,
    ZP_ERROR_OUT_OF_MEMORY = 2,
    
    // Input/output errors
    ZP_ERROR_IO = 10,
    ZP_ERROR_EOF = 11,
    
    // Parser errors
    ZP_ERROR_INVALID_HANDLE = 20,
    ZP_ERROR_INVALID_ARGUMENT = 21,
    ZP_ERROR_INVALID_STATE = 22,
    ZP_ERROR_UNEXPECTED_TOKEN = 23,
    ZP_ERROR_PARSER_CONFIG = 24,
    
    // Implementation errors
    ZP_ERROR_NOT_IMPLEMENTED = 30,
} ZP_ErrorCode;

/**
 * Result structure for C API functions.
 */
typedef struct {
    ZP_ErrorCode code;
    void* data;
} ZP_Result;

/**
 * Opaque handle for a parser instance.
 */
typedef struct ZP_Parser_s ZP_Parser;

/**
 * Event types emitted by the parser.
 */
typedef enum {
    ZP_EVENT_START_DOCUMENT = 0,
    ZP_EVENT_END_DOCUMENT = 1,
    ZP_EVENT_START_ELEMENT = 2,
    ZP_EVENT_END_ELEMENT = 3,
    ZP_EVENT_VALUE = 4,
    ZP_EVENT_ERROR = 5,
} ZP_EventType;

/**
 * Callback function type for handling parser events.
 *
 * @param event_type The type of event that occurred.
 * @param data Pointer to event data (varies by event type).
 * @param data_len Length of event data.
 * @param user_data User-provided context pointer.
 */
typedef void (*ZP_EventCallback)(
    int event_type,
    const char* data,
    size_t data_len,
    void* user_data
);

/**
 * Initialize the ZigParse library.
 * This must be called before using any other functions.
 *
 * @return ZP_Result with ZP_OK on success.
 */
ZP_Result zp_init(void);

/**
 * Shutdown the ZigParse library.
 * This should be called when you're done using ZigParse to free resources.
 *
 * @return ZP_Result with ZP_OK on success.
 */
ZP_Result zp_shutdown(void);

/**
 * Create a parser from a JSON grammar definition.
 *
 * @param grammar_json JSON string containing the grammar definition.
 * @param len Length of the JSON string.
 * @return ZP_Result with parser handle in data field on success.
 */
ZP_Result zp_create_parser_from_json(const char* grammar_json, size_t len);

/**
 * Create a parser with direct configuration.
 *
 * @param token_matchers Array of token matcher definitions.
 * @param token_matcher_count Number of token matchers.
 * @param skip_types Array of token type IDs to skip.
 * @param skip_type_count Number of token types to skip.
 * @param states Array of state definitions.
 * @param state_count Number of states.
 * @param initial_state ID of the initial state.
 * @return ZP_Result with parser handle in data field on success.
 */
ZP_Result zp_create_parser(
    const char* token_matchers,
    size_t token_matcher_count,
    const uint32_t* skip_types,
    size_t skip_type_count,
    const char* states,
    size_t state_count,
    uint32_t initial_state
);

/**
 * Create a parser for a specific predefined format.
 *
 * @param format_name Name of the format (e.g., "json", "csv", "xml").
 * @return ZP_Result with parser handle in data field on success.
 */
ZP_Result zp_create_format_parser(const char* format_name);

/**
 * Destroy a parser and free associated resources.
 *
 * @param parser Parser handle to destroy.
 * @return ZP_Result with ZP_OK on success.
 */
ZP_Result zp_destroy_parser(ZP_Parser* parser);

/**
 * Set an event handler for parser events.
 *
 * @param parser Parser handle.
 * @param callback Function to call when events occur.
 * @param user_data User context pointer passed to the callback.
 * @return ZP_Result with ZP_OK on success.
 */
ZP_Result zp_set_event_handler(
    ZP_Parser* parser,
    ZP_EventCallback callback,
    void* user_data
);

/**
 * Parse a chunk of data incrementally.
 * Call zp_finish_parsing() when done with all chunks.
 *
 * @param parser Parser handle.
 * @param data Pointer to data chunk.
 * @param len Length of data chunk.
 * @return ZP_Result with ZP_OK on success.
 */
ZP_Result zp_parse_chunk(ZP_Parser* parser, const char* data, size_t len);

/**
 * Finish incremental parsing.
 *
 * @param parser Parser handle.
 * @return ZP_Result with ZP_OK on success.
 */
ZP_Result zp_finish_parsing(ZP_Parser* parser);

/**
 * Parse a complete string in one call.
 *
 * @param parser Parser handle.
 * @param data String to parse.
 * @param len Length of string.
 * @return ZP_Result with ZP_OK on success.
 */
ZP_Result zp_parse_string(ZP_Parser* parser, const char* data, size_t len);

/**
 * Get the last error message.
 *
 * @param parser Parser handle.
 * @return Error message string or NULL if no error.
 */
const char* zp_get_error(ZP_Parser* parser);

/**
 * Get the last error code.
 *
 * @param parser Parser handle.
 * @return Error code.
 */
int zp_get_error_code(ZP_Parser* parser);

/**
 * Test function to verify the C API is working.
 *
 * @return 42 if the library is working.
 */
int zp_test(void);

#ifdef __cplusplus
}
#endif

#endif /* ZIGPARSE_H */