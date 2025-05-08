const std = @import("std");
const error_mod = @import("error.zig");
const error_agg_mod = @import("error_aggregator.zig");

const ErrorContext = error_mod.ErrorContext;
const ErrorGroup = error_agg_mod.ErrorGroup;
const Position = error_mod.Position;

/// Configuration for error visualization
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

/// ANSI color codes for terminal output
pub const AnsiColor = struct {
    pub const reset = "\x1b[0m";
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const bold = "\x1b[1m";
    pub const underline = "\x1b[4m";
    
    /// Get color code for a specific error severity
    pub fn forSeverity(severity: error_mod.ErrorSeverity) []const u8 {
        return switch (severity) {
            .warning => yellow,
            .error_level => red,
            .fatal => bold ++ red,
        };
    }
};

/// Renders error context with source code snippet and position markers
pub const ErrorVisualizer = struct {
    allocator: std.mem.Allocator,
    config: VisualizerConfig,
    source_text: []const u8,
    line_starts: std.ArrayList(usize),
    
    /// Initialize a new error visualizer
    pub fn init(allocator: std.mem.Allocator, source_text: []const u8, config: VisualizerConfig) !ErrorVisualizer {
        var result = ErrorVisualizer{
            .allocator = allocator,
            .config = config,
            .source_text = source_text,
            .line_starts = std.ArrayList(usize).init(allocator),
        };
        
        // Find the start position of each line
        try result.line_starts.append(0); // First line starts at position 0
        
        for (source_text, 0..) |c, i| {
            if (c == '\n' and i + 1 < source_text.len) {
                try result.line_starts.append(i + 1);
            }
        }
        
        return result;
    }
    
    /// Free allocated resources
    pub fn deinit(self: *ErrorVisualizer) void {
        self.line_starts.deinit();
    }
    
    /// Render a visual representation of an error in its source context
    pub fn visualizeError(self: *ErrorVisualizer, error_ctx: ErrorContext, writer: anytype) !void {
        const pos = error_ctx.position;
        const line_idx = pos.line - 1; // Convert 1-based line number to 0-based index
        
        // Determine range of lines to show
        const start_line = if (line_idx >= self.config.context_lines) 
            line_idx - self.config.context_lines 
        else 
            0;
            
        const end_line = @min(line_idx + self.config.context_lines, self.line_starts.items.len - 1);
        
        // Header for error location
        if (self.config.use_colors) {
            try writer.print("{s}{s} at {s}line {d}, column {d}{s}:\n", .{
                AnsiColor.bold,
                @tagName(error_ctx.severity),
                AnsiColor.forSeverity(error_ctx.severity),
                pos.line,
                pos.column,
                AnsiColor.reset
            });
        } else {
            try writer.print("{s} at line {d}, column {d}:\n", .{
                @tagName(error_ctx.severity),
                pos.line,
                pos.column
            });
        }
        
        // Display error message
        if (self.config.use_colors) {
            try writer.print("{s}{s}:{s} {s}\n\n", .{
                AnsiColor.bold,
                @tagName(error_ctx.code),
                AnsiColor.reset,
                error_ctx.message
            });
        } else {
            try writer.print("{s}: {s}\n\n", .{
                @tagName(error_ctx.code),
                error_ctx.message
            });
        }
        
        // Display code snippet with context
        var i: usize = start_line;
        while (i <= end_line) : (i += 1) {
            const line_start = self.line_starts.items[i];
            const line_end = if (i + 1 < self.line_starts.items.len)
                self.line_starts.items[i + 1] - 1 // Exclude newline
            else
                self.source_text.len;
                
            // Print line number
            if (self.config.use_colors) {
                try writer.print(" {s}{d: >4}{s} | ", .{
                    if (i == line_idx) AnsiColor.bold else "",
                    i + 1, // 1-based line number
                    AnsiColor.reset
                });
            } else {
                try writer.print(" {d: >4} | ", .{i + 1});
            }
            
            // Print line content (truncate if too long)
            const line_content = self.source_text[line_start..@min(line_end, line_start + self.config.max_line_length)];
            try writer.print("{s}\n", .{line_content});
            
            // Print error marker arrow if this is the error line
            if (i == line_idx) {
                // Calculate padding for column position
                const padding = pos.column - 1; // Convert 1-based column to 0-based
                
                // Print marker arrow
                if (self.config.use_colors) {
                    try writer.print("      | {s}{s}{c}{s}\n", .{
                        AnsiColor.forSeverity(error_ctx.severity),
                        " " ** @min(padding, self.config.max_line_length),
                        self.config.marker_char,
                        AnsiColor.reset
                    });
                } else {
                    try writer.print("      | {s}{c}\n", .{
                        " " ** @min(padding, self.config.max_line_length),
                        self.config.marker_char
                    });
                }
            }
        }
        
        // Print any recovery hint
        if (error_ctx.recovery_hint) |hint| {
            try writer.print("\n");
            if (self.config.use_colors) {
                try writer.print(" {s}Hint:{s} {s}\n", .{
                    AnsiColor.green ++ AnsiColor.bold,
                    AnsiColor.reset,
                    hint
                });
            } else {
                try writer.print(" Hint: {s}\n", .{hint});
            }
        }
        
        try writer.print("\n");
    }
    
    /// Visualize an error group with primary and related errors
    pub fn visualizeErrorGroup(self: *ErrorVisualizer, group: ErrorGroup, writer: anytype) !void {
        // First visualize the primary error
        if (self.config.use_colors) {
            try writer.print("{s}Primary Error:{s}\n", .{AnsiColor.bold, AnsiColor.reset});
        } else {
            try writer.print("Primary Error:\n", .{});
        }
        
        try self.visualizeError(group.primary_error, writer);
        
        // Then visualize related errors
        if (group.related_errors.items.len > 0) {
            if (self.config.use_colors) {
                try writer.print("{s}Related Errors:{s}\n", .{AnsiColor.bold, AnsiColor.reset});
            } else {
                try writer.print("Related Errors:\n", .{});
            }
            
            for (group.related_errors.items, 0..) |related, i| {
                if (self.config.use_colors) {
                    try writer.print("{s}Related Error {d}:{s}\n", .{AnsiColor.bold, i + 1, AnsiColor.reset});
                } else {
                    try writer.print("Related Error {d}:\n", .{i + 1});
                }
                
                try self.visualizeError(related, writer);
            }
        }
    }
    
    /// Get line content for a specific line number
    pub fn getLine(self: ErrorVisualizer, line_number: usize) ?[]const u8 {
        if (line_number == 0 or line_number > self.line_starts.items.len) {
            return null;
        }
        
        const line_idx = line_number - 1;
        const line_start = self.line_starts.items[line_idx];
        const line_end = if (line_idx + 1 < self.line_starts.items.len)
            self.line_starts.items[line_idx + 1] - 1 // Exclude newline
        else
            self.source_text.len;
            
        return self.source_text[line_start..line_end];
    }
    
    /// Visualize all errors from an error reporter
    pub fn visualizeAllErrors(self: *ErrorVisualizer, errors: []const ErrorContext, writer: anytype) !void {
        if (errors.len == 0) {
            try writer.print("No errors found.\n", .{});
            return;
        }
        
        if (self.config.use_colors) {
            try writer.print("{s}=== {d} Error(s) ==={s}\n\n", .{AnsiColor.bold, errors.len, AnsiColor.reset});
        } else {
            try writer.print("=== {d} Error(s) ===\n\n", .{errors.len});
        }
        
        for (errors, 0..) |error_ctx, i| {
            if (self.config.use_colors) {
                try writer.print("{s}Error {d}/{d}:{s}\n", .{
                    AnsiColor.bold, 
                    i + 1, 
                    errors.len,
                    AnsiColor.reset
                });
            } else {
                try writer.print("Error {d}/{d}:\n", .{i + 1, errors.len});
            }
            
            try self.visualizeError(error_ctx, writer);
        }
    }
    
    /// Visualize all error groups from an error aggregator
    pub fn visualizeAllErrorGroups(self: *ErrorVisualizer, groups: []const ErrorGroup, writer: anytype) !void {
        if (groups.len == 0) {
            try writer.print("No error groups found.\n", .{});
            return;
        }
        
        if (self.config.use_colors) {
            try writer.print("{s}=== {d} Error Group(s) ==={s}\n\n", .{AnsiColor.bold, groups.len, AnsiColor.reset});
        } else {
            try writer.print("=== {d} Error Group(s) ===\n\n", .{groups.len});
        }
        
        for (groups, 0..) |group, i| {
            if (self.config.use_colors) {
                try writer.print("{s}Group {d}/{d}:{s}\n", .{
                    AnsiColor.bold, 
                    i + 1, 
                    groups.len,
                    AnsiColor.reset
                });
            } else {
                try writer.print("Group {d}/{d}:\n", .{i + 1, groups.len});
            }
            
            try self.visualizeErrorGroup(group, writer);
        }
    }
};