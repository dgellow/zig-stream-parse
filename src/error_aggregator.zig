const std = @import("std");
const error_mod = @import("error.zig");
const ErrorContext = error_mod.ErrorContext;
const ErrorCode = error_mod.ErrorCode;
const ErrorSeverity = error_mod.ErrorSeverity;
const ErrorCategory = error_mod.ErrorCategory;
const Position = error_mod.Position;

/// Represents a group of related errors that likely stem from the same root cause
pub const ErrorGroup = struct {
    /// Primary error that likely caused other errors
    primary_error: ErrorContext,
    
    /// Related errors that are likely consequences of the primary error
    related_errors: std.ArrayList(ErrorContext),
    
    /// Creates a new error group with a primary error
    pub fn init(primary: ErrorContext, allocator: std.mem.Allocator) ErrorGroup {
        return .{
            .primary_error = primary,
            .related_errors = std.ArrayList(ErrorContext).init(allocator),
        };
    }
    
    /// Add a related error to this group
    pub fn addRelatedError(self: *ErrorGroup, error_ctx: ErrorContext) !void {
        try self.related_errors.append(error_ctx);
    }
    
    /// Free resources
    pub fn deinit(self: *ErrorGroup) void {
        self.related_errors.deinit();
    }
};

/// Enhanced error reporter with error aggregation capabilities
pub const ErrorAggregator = struct {
    allocator: std.mem.Allocator,
    errors: std.ArrayList(ErrorContext),
    warnings: std.ArrayList(ErrorContext),
    error_groups: std.ArrayList(ErrorGroup),
    has_fatal: bool,
    
    /// Distance in tokens to consider errors potentially related
    max_token_distance: usize = 5,
    
    /// Maximum line distance to consider errors potentially related
    max_line_distance: usize = 3,
    
    /// Initialize a new error aggregator
    pub fn init(allocator: std.mem.Allocator) ErrorAggregator {
        return .{
            .allocator = allocator,
            .errors = std.ArrayList(ErrorContext).init(allocator),
            .warnings = std.ArrayList(ErrorContext).init(allocator),
            .error_groups = std.ArrayList(ErrorGroup).init(allocator),
            .has_fatal = false,
        };
    }
    
    /// Free all resources
    pub fn deinit(self: *ErrorAggregator) void {
        // Free individual errors
        for (self.errors.items) |*err| {
            err.deinit(self.allocator);
        }
        self.errors.deinit();
        
        // Free warnings
        for (self.warnings.items) |*warn| {
            warn.deinit(self.allocator);
        }
        self.warnings.deinit();
        
        // Free error groups
        for (self.error_groups.items) |*group| {
            group.deinit();
        }
        self.error_groups.deinit();
    }
    
    /// Report an error and attempt to aggregate it if related to existing errors
    pub fn report(self: *ErrorAggregator, error_context: ErrorContext) !void {
        switch (error_context.severity) {
            .warning => {
                try self.warnings.append(error_context);
            },
            .error_level => {
                try self.errors.append(error_context);
                if (try self.tryAggregateError(error_context)) {
                    // Error was aggregated into a group
                } else {
                    // Error was not related to any existing groups
                    // Consider it as a potential new primary error
                    const new_group = ErrorGroup.init(error_context, self.allocator);
                    try self.error_groups.append(new_group);
                }
            },
            .fatal => {
                try self.errors.append(error_context);
                self.has_fatal = true;
                if (try self.tryAggregateError(error_context)) {
                    // Fatal error was aggregated into a group
                } else {
                    // Create a new group with this fatal error as primary
                    const new_group = ErrorGroup.init(error_context, self.allocator);
                    try self.error_groups.append(new_group);
                }
            },
        }
    }
    
    /// Create an error context and report it in one step
    pub fn reportError(
        self: *ErrorAggregator,
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
    
    /// Check if an error is potentially related to any existing error groups
    fn tryAggregateError(self: *ErrorAggregator, error_ctx: ErrorContext) !bool {
        if (self.error_groups.items.len == 0) {
            return false;
        }
        
        // Determine if this error is likely related to an existing primary error
        for (self.error_groups.items) |*group| {
            if (self.areErrorsRelated(group.primary_error, error_ctx)) {
                try group.addRelatedError(error_ctx);
                return true;
            }
        }
        
        return false;
    }
    
    /// Determine if two errors are likely related (one caused by the other)
    fn areErrorsRelated(self: ErrorAggregator, primary: ErrorContext, secondary: ErrorContext) bool {
        // Errors in the same line or nearby lines are likely related
        const line_diff = if (primary.position.line > secondary.position.line)
            primary.position.line - secondary.position.line
        else
            secondary.position.line - primary.position.line;
            
        if (line_diff > self.max_line_distance) {
            return false;
        }
        
        // We consider errors related if they:
        
        // 1. Have the same category (e.g., syntax errors are often related)
        if (primary.code.category() == secondary.code.category()) {
            return true;
        }
        
        // 2. Secondary error is of a different category but close in position
        if (line_diff <= 1) {
            return true;
        }
        
        // 3. Secondary is a missing token and primary is an unexpected token
        if ((primary.code == .unexpected_token and secondary.code == .missing_token) or
            (primary.code == .missing_token and secondary.code == .unexpected_token)) {
            return true;
        }
        
        // 4. Certain error code combinations are likely related
        const is_related_combo = 
            (primary.code == .unterminated_string and secondary.code == .unexpected_token) or
            (primary.code == .unbalanced_delimiter and secondary.code == .unexpected_token) or
            (primary.code == .unbalanced_delimiter and secondary.code == .missing_token);
            
        if (is_related_combo) {
            return true;
        }
        
        return false;
    }
    
    /// Check if there are any errors (excluding warnings)
    pub fn hasErrors(self: ErrorAggregator) bool {
        return self.errors.items.len > 0;
    }
    
    /// Check if there are any fatal errors
    pub fn hasFatalErrors(self: ErrorAggregator) bool {
        return self.has_fatal;
    }
    
    /// Get all errors
    pub fn getErrors(self: ErrorAggregator) []ErrorContext {
        return self.errors.items;
    }
    
    /// Get all warnings
    pub fn getWarnings(self: ErrorAggregator) []ErrorContext {
        return self.warnings.items;
    }
    
    /// Get all error groups
    pub fn getErrorGroups(self: ErrorAggregator) []ErrorGroup {
        return self.error_groups.items;
    }
    
    /// Print all errors and warnings with intelligent grouping
    pub fn printAll(self: ErrorAggregator) !void {
        const stderr = std.io.getStdErr().writer();
        
        // Print grouped errors
        if (self.error_groups.items.len > 0) {
            try stderr.print("\n=== {d} Error Group(s) ===\n", .{self.error_groups.items.len});
            
            for (self.error_groups.items, 0..) |group, i| {
                try stderr.print("\n--- Group {d}: {s} at line {d}, column {d} ---\n", .{
                    i + 1,
                    @tagName(group.primary_error.code),
                    group.primary_error.position.line,
                    group.primary_error.position.column,
                });
                
                // Print primary error
                try stderr.print("* PRIMARY: {}\n", .{group.primary_error});
                
                // Print related errors if any
                if (group.related_errors.items.len > 0) {
                    try stderr.print("  Related errors that may be consequences:\n", .{});
                    for (group.related_errors.items, 0..) |related, j| {
                        try stderr.print("  * {d}. {}\n", .{j + 1, related});
                    }
                }
            }
        }
        
        // Print ungrouped errors
        const ungrouped_errors = self.getUngroupedErrors();
        if (ungrouped_errors.len > 0) {
            try stderr.print("\n=== {d} Ungrouped Error(s) ===\n", .{ungrouped_errors.len});
            for (ungrouped_errors, 0..) |err, i| {
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
    
    /// Get errors that aren't part of any group (rare cases or isolated errors)
    fn getUngroupedErrors(self: ErrorAggregator) []ErrorContext {
        var result = std.ArrayList(ErrorContext).init(self.allocator);
        defer result.deinit();
        
        // This is inefficient for large error sets but suitable for typical usage
        outer: for (self.errors.items) |err| {
            // Skip errors that are in any group
            for (self.error_groups.items) |group| {
                if (std.meta.eql(err, group.primary_error)) {
                    continue :outer;
                }
                
                for (group.related_errors.items) |related| {
                    if (std.meta.eql(err, related)) {
                        continue :outer;
                    }
                }
            }
            
            // This error isn't in any group
            result.append(err) catch continue;
        }
        
        return result.toOwnedSlice() catch &[_]ErrorContext{};
    }
    
    /// Throw a Parser error if there are any errors
    pub fn throwIfErrors(self: ErrorAggregator) !void {
        if (self.hasErrors()) {
            return error.ParserError;
        }
    }
};

/// Configuration for error aggregation
pub const ErrorAggregationConfig = struct {
    /// Enable error aggregation
    enabled: bool = true,
    
    /// Distance in tokens to consider errors potentially related
    max_token_distance: usize = 5,
    
    /// Maximum line distance to consider errors potentially related
    max_line_distance: usize = 3,
};