const std = @import("std");
const parser_mod = @import("parser.zig");
const Parser = parser_mod.Parser;
const TokenizerConfig = parser_mod.TokenizerConfig;
const StateMachineConfig = parser_mod.StateMachineConfig;
const ByteStream = @import("byte_stream.zig").ByteStream;
const TokenType = @import("tokenizer.zig").TokenType;
const TokenMatcher = @import("tokenizer.zig").TokenMatcher;
const State = @import("state_machine.zig").State;
const StateTransition = @import("state_machine.zig").StateTransition;
const EventType = @import("event_emitter.zig").EventType;
const EventHandler = @import("event_emitter.zig").EventHandler;
const Event = @import("event_emitter.zig").Event;
const ParserContext = @import("types.zig").ParserContext;
const ActionFn = @import("types.zig").ActionFn;

// C compatible error code enum
pub const ZP_ErrorCode = enum(c_int) {
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
};

// Result type for C API functions
pub const ZP_Result = extern struct {
    code: ZP_ErrorCode,
    data: ?*anyopaque,
};

// Opaque parser handle for C
pub const ZP_Parser = opaque {};

// Event callback type
// Event callback type - pointer to function
pub const ZP_EventCallback = *const fn (
    event_type: c_int,
    data: [*c]const u8,
    data_len: usize,
    user_data: ?*anyopaque,
) callconv(.C) void;

// Global allocator for C API
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const global_allocator = gpa.allocator();

// Internal parser registry to track handles
const ParserRegistry = struct {
    mutex: std.Thread.Mutex,
    parsers: std.AutoHashMap(u64, *Parser),
    
    fn init() ParserRegistry {
        return .{
            .mutex = .{},
            .parsers = std.AutoHashMap(u64, *Parser).init(global_allocator),
        };
    }
    
    fn deinit(self: *ParserRegistry) void {
        var it = self.parsers.iterator();
        while (it.next()) |entry| {
            const parser_ptr = entry.value_ptr.*;
            parser_ptr.deinit();
            global_allocator.destroy(parser_ptr);
        }
        self.parsers.deinit();
    }
    
    fn register(self: *ParserRegistry, parser: *Parser) u64 {
        const id = parser.handle.id;
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.parsers.put(id, parser) catch {
            // If put fails, we just return the ID anyway since the parser is valid
            // but won't be in our registry
        };
        return id;
    }
    
    fn get(self: *ParserRegistry, id: u64) ?*Parser {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        return self.parsers.get(id);
    }
    
    fn remove(self: *ParserRegistry, id: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        _ = self.parsers.remove(id);
    }
};

// Initialize the global parser registry
var parser_registry = ParserRegistry.init();

// Convert Zig error to ZP_ErrorCode
fn errorToCode(err: anyerror) ZP_ErrorCode {
    return switch (err) {
        error.OutOfMemory => .ZP_ERROR_OUT_OF_MEMORY,
        error.EndOfStream => .ZP_ERROR_EOF,
        error.UnexpectedToken => .ZP_ERROR_UNEXPECTED_TOKEN,
        error.NotImplemented => .ZP_ERROR_NOT_IMPLEMENTED,
        // Map other errors as needed
        else => .ZP_ERROR_UNKNOWN,
    };
}

// Cleanup function to be called at program exit
pub fn cleanup() void {
    parser_registry.deinit();
    _ = gpa.deinit();
}

// Helper for error handling
fn makeError(code: ZP_ErrorCode) ZP_Result {
    return .{
        .code = code,
        .data = null,
    };
}

// Helper for success with data
fn makeSuccess(data: ?*anyopaque) ZP_Result {
    return .{
        .code = .ZP_OK,
        .data = data,
    };
}

// A null event handler for when we're clearing the handler
fn nullHandler(event: Event, ctx: ?*anyopaque) !void {
    _ = event;
    _ = ctx;
    // Do nothing
}

//
// C API Functions
//

// Creates a parser from a JSON grammar definition
export fn zp_create_parser_from_json(grammar_json: [*c]const u8, len: usize) callconv(.C) ZP_Result {
    _ = grammar_json;
    _ = len;
    // Not implemented yet - this would parse a JSON grammar definition
    return makeError(.ZP_ERROR_NOT_IMPLEMENTED);
}

// Creates a parser with direct configuration
export fn zp_create_parser(
    token_matchers: [*c]const u8,
    token_matcher_count: usize,
    skip_types: [*c]const u32,
    skip_type_count: usize,
    states: [*c]const u8,
    state_count: usize,
    initial_state: u32,
) callconv(.C) ZP_Result {
    // This is a stub implementation. A real implementation would:
    // 1. Parse the C structures into Zig structures
    // 2. Create a parser with the parsed configuration
    _ = token_matchers;
    _ = token_matcher_count;
    _ = skip_types;
    _ = skip_type_count;
    _ = states;
    _ = state_count;
    _ = initial_state;
    
    return makeError(.ZP_ERROR_NOT_IMPLEMENTED);
}

// Creates a simple parser for a specific format (e.g., JSON, CSV)
export fn zp_create_format_parser(format_name: [*c]const u8) callconv(.C) ZP_Result {
    if (format_name == null) {
        return makeError(.ZP_ERROR_INVALID_ARGUMENT);
    }
    
    const name = std.mem.span(format_name);
    
    // This would create a parser for a specific format
    if (std.mem.eql(u8, name, "json") or 
        std.mem.eql(u8, name, "csv") or
        std.mem.eql(u8, name, "xml")) {
        // Not implemented yet
        return makeError(.ZP_ERROR_NOT_IMPLEMENTED);
    }
    
    return makeError(.ZP_ERROR_INVALID_ARGUMENT);
}

// Destroys a parser
export fn zp_destroy_parser(parser_ptr: *ZP_Parser) callconv(.C) ZP_Result {
    const id = @intFromPtr(parser_ptr);
    
    if (parser_registry.get(id)) |parser| {
        parser_registry.remove(id);
        parser.deinit();
        global_allocator.destroy(parser);
        return makeSuccess(null);
    }
    
    return makeError(.ZP_ERROR_INVALID_HANDLE);
}

// Sets an event handler on the parser
export fn zp_set_event_handler(
    parser_ptr: *ZP_Parser,
    callback: ?ZP_EventCallback,
    user_data: ?*anyopaque,
) callconv(.C) ZP_Result {
    const id = @intFromPtr(parser_ptr);
    
    if (parser_registry.get(id)) |parser| {
        if (callback) |cb| {
            // Create a context struct to hold both the callback and user data
            const CallbackContext = struct {
                callback: ZP_EventCallback,
                user_data: ?*anyopaque,
            };
            
            const ctx = global_allocator.create(CallbackContext) catch {
                return makeError(.ZP_ERROR_OUT_OF_MEMORY);
            };
            ctx.* = .{
                .callback = cb,
                .user_data = user_data,
            };
            
            // Create a wrapper function that calls the C callback
            const wrapper = struct {
                fn handler(event: Event, context: ?*anyopaque) !void {
                    if (context) |ctx_ptr| {
                        const cb_ctx = @as(*CallbackContext, @ptrCast(@alignCast(ctx_ptr)));
                        
                        // Convert event data to C format
                        const event_type = @intFromEnum(event.type);
                        
                        // Get data from event - this is simplified
                        var data_ptr: [*c]const u8 = null;
                        var data_len: usize = 0;
                        
                        switch (event.type) {
                            .VALUE => {
                                data_ptr = event.data.string_value.ptr;
                                data_len = event.data.string_value.len;
                            },
                            .ERROR => {
                                data_ptr = event.data.error_info.message.ptr;
                                data_len = event.data.error_info.message.len;
                            },
                            else => {
                                // Other event types may need special handling
                            },
                        }
                        
                        // Call the C callback
                        cb_ctx.callback(event_type, data_ptr, data_len, cb_ctx.user_data);
                    }
                }
            }.handler;
            
            // Set the event handler on the parser
            parser.setEventHandler(EventHandler.init(wrapper, ctx));
            return makeSuccess(null);
        } else {
            // Clear the event handler
            // Note: Would need to free the context here in a real implementation
            parser.setEventHandler(EventHandler{.handle_fn = nullHandler, .context = null});
            return makeSuccess(null);
        }
    }
    
    return makeError(.ZP_ERROR_INVALID_HANDLE);
}

// Parses a chunk of data
export fn zp_parse_chunk(
    parser_ptr: *ZP_Parser,
    data: [*c]const u8,
    len: usize,
) callconv(.C) ZP_Result {
    const id = @intFromPtr(parser_ptr);
    
    if (parser_registry.get(id)) |parser| {
        // The current parser doesn't support incremental parsing
        // Return not implemented
        _ = parser;
        _ = data;
        _ = len;
        return makeError(.ZP_ERROR_NOT_IMPLEMENTED);
    }
    
    return makeError(.ZP_ERROR_INVALID_HANDLE);
}

// Finishes parsing
export fn zp_finish_parsing(parser_ptr: *ZP_Parser) callconv(.C) ZP_Result {
    const id = @intFromPtr(parser_ptr);
    
    if (parser_registry.get(id)) |parser| {
        // The current parser doesn't support incremental parsing
        // Return not implemented
        _ = parser;
        return makeError(.ZP_ERROR_NOT_IMPLEMENTED);
    }
    
    return makeError(.ZP_ERROR_INVALID_HANDLE);
}

// Parses a complete string
export fn zp_parse_string(
    parser_ptr: *ZP_Parser,
    data: [*c]const u8,
    len: usize,
) callconv(.C) ZP_Result {
    const id = @intFromPtr(parser_ptr);
    
    if (parser_registry.get(id)) |parser| {
        if (data == null) {
            return makeError(.ZP_ERROR_INVALID_ARGUMENT);
        }
        
        // Create a slice from the C string
        _ = data[0..len]; // Verify the input range is valid
        
        // Parse the input
        parser.parse() catch |err| {
            return makeError(errorToCode(err));
        };
        
        return makeSuccess(null);
    }
    
    return makeError(.ZP_ERROR_INVALID_HANDLE);
}

// Gets the last error message
export fn zp_get_error(parser_ptr: *ZP_Parser) callconv(.C) [*c]const u8 {
    const id = @intFromPtr(parser_ptr);
    
    if (parser_registry.get(id)) |parser| {
        if (parser.handle.data.error_message) |msg| {
            return msg.ptr;
        }
        return "No error";
    }
    
    return "Invalid parser handle";
}

// Gets the last error code
export fn zp_get_error_code(parser_ptr: *ZP_Parser) callconv(.C) c_int {
    const id = @intFromPtr(parser_ptr);
    
    if (parser_registry.get(id)) |parser| {
        return @intCast(parser.handle.data.error_code);
    }
    
    return @intFromEnum(ZP_ErrorCode.ZP_ERROR_INVALID_HANDLE);
}

// Initialize the ZigParse library
export fn zp_init() callconv(.C) ZP_Result {
    // Nothing to do here yet
    return makeSuccess(null);
}

// Shutdown the ZigParse library
export fn zp_shutdown() callconv(.C) ZP_Result {
    cleanup();
    return makeSuccess(null);
}

// Test function to verify the C API is working
export fn zp_test() callconv(.C) c_int {
    return 42;
}