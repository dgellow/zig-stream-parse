const std = @import("std");
const Position = @import("common.zig").Position;
const Token = @import("tokenizer.zig").Token;

/// Error severity levels
pub const ErrorSeverity = enum {
    /// Warnings don't stop parsing but are reported to the user
    warning,
    
    /// Errors cause parsing to fail but may be recoverable
    error_level,
    
    /// Fatal errors cause parsing to immediately stop
    fatal,
};

/// Error categories to help clients group similar errors
pub const ErrorCategory = enum {
    /// Lexical errors related to tokenization (unknown characters, invalid literals)
    lexical,
    
    /// Syntax errors related to grammar rules (unexpected tokens)
    syntax,
    
    /// Semantic errors related to the meaning of the parsed content
    semantic,
    
    /// Internal errors related to the parser itself
    internal,
    
    /// I/O errors related to reading input
    io,
};

/// Enhanced error code enum with clear categorization
pub const ErrorCode = enum(u32) {
    // Lexical errors (100-199)
    unknown_character = 100,
    invalid_escape_sequence = 101,
    unterminated_string = 102,
    invalid_number_format = 103,
    
    // Syntax errors (200-299)
    unexpected_token = 200,
    unexpected_end_of_input = 201,
    missing_token = 202,
    invalid_syntax = 203,
    
    // Semantic errors (300-399)
    duplicate_identifier = 300,
    undeclared_identifier = 301,
    type_mismatch = 302,
    
    // Internal errors (900-999)
    internal_error = 900,
    state_machine_error = 901,
    memory_error = 902,
    
    // Helper function to get category from code
    pub fn category(self: ErrorCode) ErrorCategory {
        const code_num = @intFromEnum(self);
        return switch (code_num) {
            100...199 => .lexical,
            200...299 => .syntax,
            300...399 => .semantic,
            900...999 => .internal,
            else => .internal,
        };
    }
    
    // Helper function to get default severity from code
    pub fn defaultSeverity(self: ErrorCode) ErrorSeverity {
        const code_num = @intFromEnum(self);
        return switch (code_num) {
            100...199 => .error_level, // Most lexical errors are non-fatal
            200...299 => .error_level, // Most syntax errors are non-fatal
            300...399 => .warning, // Semantic errors are often warnings
            900...999 => .fatal, // Internal errors are typically fatal
            else => .error_level,
        };
    }
    
    // Helper function to get human-readable description
    pub fn description(self: ErrorCode) []const u8 {
        return switch (self) {
            .unknown_character => "Unknown character encountered",
            .invalid_escape_sequence => "Invalid escape sequence in string",
            .unterminated_string => "Unterminated string literal",
            .invalid_number_format => "Invalid number format",
            
            .unexpected_token => "Unexpected token encountered",
            .unexpected_end_of_input => "Unexpected end of input",
            .missing_token => "Expected token not found",
            .invalid_syntax => "Invalid syntax",
            
            .duplicate_identifier => "Duplicate identifier",
            .undeclared_identifier => "Undeclared identifier",
            .type_mismatch => "Type mismatch",
            
            .internal_error => "Internal parser error",
            .state_machine_error => "State machine error",
            .memory_error => "Memory allocation error",
        };
    }
};

/// Rich error context information
pub const ErrorContext = struct {
    /// The error code
    code: ErrorCode,
    
    /// The position where the error occurred
    position: Position,
    
    /// The severity of the error
    severity: ErrorSeverity,
    
    /// A detailed message describing the error
    message: []const u8,
    
    /// The token that caused the error, if applicable
    token: ?Token = null,
    
    /// Expected token types, if applicable (for unexpected token errors)
    expected_token_types: ?[]const u32 = null,
    
    /// State machine context, if applicable
    state_id: ?u32 = null,
    state_name: ?[]const u8 = null,
    
    /// Recovery suggestion
    recovery_hint: ?[]const u8 = null,
    
    /// Create a basic error with position and message
    pub fn init(
        allocator: std.mem.Allocator,
        code: ErrorCode,
        position: Position, 
        message: []const u8
    ) !ErrorContext {
        return ErrorContext{
            .code = code,
            .position = position,
            .severity = code.defaultSeverity(),
            .message = try allocator.dupe(u8, message),
        };
    }
    
    /// Free resources
    pub fn deinit(self: *ErrorContext, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        if (self.recovery_hint) |hint| {
            allocator.free(hint);
        }
    }
    
    /// Set the token that caused the error
    pub fn setToken(self: *ErrorContext, token: Token) void {
        self.token = token;
    }
    
    /// Set expected token types
    pub fn setExpectedTokenTypes(self: *ErrorContext, allocator: std.mem.Allocator, token_types: []const u32) !void {
        self.expected_token_types = try allocator.dupe(u32, token_types);
    }
    
    /// Set state machine context
    pub fn setStateContext(self: *ErrorContext, allocator: std.mem.Allocator, state_id: u32, state_name: []const u8) !void {
        self.state_id = state_id;
        self.state_name = try allocator.dupe(u8, state_name);
    }
    
    /// Set a recovery hint
    pub fn setRecoveryHint(self: *ErrorContext, allocator: std.mem.Allocator, hint: []const u8) !void {
        if (self.recovery_hint) |old_hint| {
            allocator.free(old_hint);
        }
        self.recovery_hint = try allocator.dupe(u8, hint);
    }
    
    /// Set severity 
    pub fn setSeverity(self: *ErrorContext, severity: ErrorSeverity) void {
        self.severity = severity;
    }
    
    /// Format the error for display
    pub fn format(
        self: ErrorContext,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        // Write error severity and code
        try writer.print("[{s}] {s} ({d}): ", .{
            @tagName(self.severity),
            @tagName(self.code),
            @intFromEnum(self.code),
        });
        
        // Write the message
        try writer.print("{s} at ", .{self.message});
        
        // Write the position
        try writer.print("{}", .{self.position});
        
        // Write token info if available
        if (self.token) |token| {
            try writer.print(" - token: {s} ({d})", .{token.lexeme, token.type.id});
        }
        
        // Write state machine context if available
        if (self.state_id != null and self.state_name != null) {
            try writer.print(" - state: {s} ({d})", .{self.state_name.?, self.state_id.?});
        }
        
        // Write expected tokens if available
        if (self.expected_token_types) |expected| {
            try writer.print("\nExpected token types: ", .{});
            for (expected, 0..) |token_type, i| {
                if (i > 0) try writer.print(", ", .{});
                try writer.print("{d}", .{token_type});
            }
        }
        
        // Write recovery hint if available
        if (self.recovery_hint) |hint| {
            try writer.print("\nRecovery suggestion: {s}", .{hint});
        }
    }
};

/// Error reporting interface
pub const ErrorReporter = struct {
    allocator: std.mem.Allocator,
    errors: std.ArrayList(ErrorContext),
    warnings: std.ArrayList(ErrorContext),
    has_fatal: bool,
    
    /// Initialize a new error reporter
    pub fn init(allocator: std.mem.Allocator) ErrorReporter {
        return .{
            .allocator = allocator,
            .errors = std.ArrayList(ErrorContext).init(allocator),
            .warnings = std.ArrayList(ErrorContext).init(allocator),
            .has_fatal = false,
        };
    }
    
    /// Free all resources
    pub fn deinit(self: *ErrorReporter) void {
        for (self.errors.items) |*err| {
            err.deinit(self.allocator);
        }
        self.errors.deinit();
        
        for (self.warnings.items) |*warn| {
            warn.deinit(self.allocator);
        }
        self.warnings.deinit();
    }
    
    /// Report an error
    pub fn report(self: *ErrorReporter, error_context: ErrorContext) !void {
        switch (error_context.severity) {
            .warning => {
                try self.warnings.append(error_context);
            },
            .error_level => {
                try self.errors.append(error_context);
            },
            .fatal => {
                try self.errors.append(error_context);
                self.has_fatal = true;
            },
        }
    }
    
    /// Create a error context and report it in one step
    pub fn reportError(
        self: *ErrorReporter,
        code: ErrorCode,
        position: Position,
        message: []const u8,
    ) !void {
        var error_context = try ErrorContext.init(
            self.allocator,
            code,
            position,
            message
        );
        try self.report(error_context);
    }
    
    /// Check if there are any errors (excluding warnings)
    pub fn hasErrors(self: ErrorReporter) bool {
        return self.errors.items.len > 0;
    }
    
    /// Check if there are any fatal errors
    pub fn hasFatalErrors(self: ErrorReporter) bool {
        return self.has_fatal;
    }
    
    /// Get all errors
    pub fn getErrors(self: ErrorReporter) []ErrorContext {
        return self.errors.items;
    }
    
    /// Get all warnings
    pub fn getWarnings(self: ErrorReporter) []ErrorContext {
        return self.warnings.items;
    }
    
    /// Print all errors and warnings
    pub fn printAll(self: ErrorReporter) !void {
        const stderr = std.io.getStdErr().writer();
        
        // Print errors
        if (self.errors.items.len > 0) {
            try stderr.print("\n=== {d} Error(s) ===\n", .{self.errors.items.len});
            for (self.errors.items, 0..) |err, i| {
                try stderr.print("\n{d}. {}\n", .{i + 1, err});
            }
        }
        
        // Print warnings
        if (self.warnings.items.len > 0) {
            try stderr.print("\n=== {d} Warning(s) ===\n", .{self.warnings.items.len});
            for (self.warnings.items, 0..) |warn, i| {
                try stderr.print("\n{d}. {}\n", .{i + 1, warn});
            }
        }
    }
    
    /// Throw a Parser error if there are any errors
    pub fn throwIfErrors(self: ErrorReporter) !void {
        if (self.hasErrors()) {
            return error.ParserError;
        }
    }
};

/// Error recovery strategy
pub const ErrorRecoveryStrategy = enum {
    /// Stop parsing immediately on any error
    stop_on_first_error,
    
    /// Continue parsing after errors to collect as many errors as possible
    continue_after_error,
    
    /// Attempt to synchronize after errors by skipping tokens until a synchronization point
    synchronize,
    
    /// Insert missing tokens and continue parsing
    repair_and_continue,
};

/// Error recovery helper functions
pub const ErrorRecovery = struct {
    /// Token types that are good synchronization points (e.g., statement terminators)
    sync_token_types: []const u32,
    
    /// Initialize with synchronization tokens
    pub fn init(sync_token_types: []const u32) ErrorRecovery {
        return .{
            .sync_token_types = sync_token_types,
        };
    }
    
    /// Check if a token is a synchronization point
    pub fn isSyncPoint(self: ErrorRecovery, token_type: u32) bool {
        for (self.sync_token_types) |sync_type| {
            if (token_type == sync_type) {
                return true;
            }
        }
        return false;
    }
    
    /// Generate a recovery hint based on the error
    pub fn generateHint(
        self: ErrorRecovery,
        allocator: std.mem.Allocator, 
        error_context: *ErrorContext
    ) !void {
        _ = self;
        
        var hint_buffer = std.ArrayList(u8).init(allocator);
        defer hint_buffer.deinit();
        
        const writer = hint_buffer.writer();
        
        switch (error_context.code) {
            .unexpected_token => {
                if (error_context.expected_token_types) |expected| {
                    try writer.print("Expected one of token types: ", .{});
                    for (expected, 0..) |token_type, i| {
                        if (i > 0) try writer.print(", ", .{});
                        try writer.print("{d}", .{token_type});
                    }
                    try writer.print(". Consider adding or replacing the current token.", .{});
                } else {
                    try writer.print("Replace or remove this token.", .{});
                }
            },
            .unexpected_end_of_input => {
                try writer.print("Add missing content or close any unclosed structures.", .{});
            },
            .missing_token => {
                if (error_context.expected_token_types) |expected| {
                    try writer.print("Insert ", .{});
                    for (expected, 0..) |token_type, i| {
                        if (i > 0) try writer.print(" or ", .{});
                        try writer.print("token type {d}", .{token_type});
                    }
                    try writer.print(" before continuing.", .{});
                } else {
                    try writer.print("Insert the missing token.", .{});
                }
            },
            .unknown_character => {
                try writer.print("Remove or replace this character.", .{});
            },
            .unterminated_string => {
                try writer.print("Add closing quote to complete the string.", .{});
            },
            else => {
                try writer.print("Check the documentation for this error type.", .{});
            },
        }
        
        try error_context.setRecoveryHint(allocator, hint_buffer.items);
    }
};