const std = @import("std");
const testing = std.testing;
const lib = @import("../zig_stream_parse.zig");
const error_mod = @import("../error.zig");
const error_visualizer_mod = @import("../error_visualizer.zig");

const Position = lib.Position;
const ErrorContext = error_mod.ErrorContext;
const ErrorCode = error_mod.ErrorCode;
const ErrorSeverity = error_mod.ErrorSeverity;
const ErrorVisualizer = error_visualizer_mod.ErrorVisualizer;
const VisualizerConfig = error_visualizer_mod.VisualizerConfig;

test "ErrorVisualizer initialization" {
    const allocator = testing.allocator;
    
    const source_text = 
        \\function example() {
        \\    let x = 10;
        \\    let y = "hello";
        \\    return x + y;
        \\}
    ;
    
    var visualizer = try ErrorVisualizer.init(allocator, source_text, .{});
    defer visualizer.deinit();
    
    // Test line starts calculation
    try testing.expectEqual(@as(usize, 5), visualizer.line_starts.items.len);
    try testing.expectEqual(@as(usize, 0), visualizer.line_starts.items[0]);
}

test "ErrorVisualizer getLine" {
    const allocator = testing.allocator;
    
    const source_text = 
        \\function example() {
        \\    let x = 10;
        \\    let y = "hello";
        \\    return x + y;
        \\}
    ;
    
    var visualizer = try ErrorVisualizer.init(allocator, source_text, .{});
    defer visualizer.deinit();
    
    // Test getting specific lines
    const line1 = visualizer.getLine(1);
    try testing.expect(line1 != null);
    try testing.expectEqualStrings("function example() {", line1.?);
    
    const line3 = visualizer.getLine(3);
    try testing.expect(line3 != null);
    try testing.expectEqualStrings("    let y = \"hello\";", line3.?);
    
    // Test out of bounds
    try testing.expect(visualizer.getLine(0) == null);
    try testing.expect(visualizer.getLine(6) == null);
}

test "ErrorVisualizer renderError" {
    const allocator = testing.allocator;
    
    const source_text = 
        \\function example() {
        \\    let x = 10;
        \\    let y = "hello";
        \\    return x + y;
        \\}
    ;
    
    var visualizer = try ErrorVisualizer.init(
        allocator, 
        source_text, 
        .{ .use_colors = false }
    );
    defer visualizer.deinit();
    
    // Create an error context
    var error_ctx = try ErrorContext.init(
        allocator,
        ErrorCode.type_mismatch,
        .{ .offset = 59, .line = 4, .column = 14 },
        "Cannot add number and string"
    );
    defer error_ctx.deinit(allocator);
    
    try error_ctx.setRecoveryHint(allocator, "Convert the string to a number or use string concatenation");
    
    // Render to a buffer
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try visualizer.visualizeError(error_ctx, buf.writer());
    
    // Check output contains key elements
    const output = buf.items;
    
    try testing.expect(std.mem.indexOf(u8, output, "error at line 4, column 14") != null);
    try testing.expect(std.mem.indexOf(u8, output, "type_mismatch: Cannot add number and string") != null);
    try testing.expect(std.mem.indexOf(u8, output, "return x + y;") != null);
    try testing.expect(std.mem.indexOf(u8, output, "             ^") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Hint: Convert the string to a number or use string concatenation") != null);
}

test "ErrorVisualizer with multiple errors" {
    const allocator = testing.allocator;
    
    const source_text = 
        \\function example() {
        \\    let x = 10;
        \\    let y = "hello"
        \\    return x + y;
        \\}
    ;
    
    var visualizer = try ErrorVisualizer.init(
        allocator, 
        source_text, 
        .{ .use_colors = false }
    );
    defer visualizer.deinit();
    
    // Create multiple error contexts
    var error_ctx1 = try ErrorContext.init(
        allocator,
        ErrorCode.missing_token,
        .{ .offset = 40, .line = 3, .column = 19 },
        "Missing semicolon at end of statement"
    );
    defer error_ctx1.deinit(allocator);
    
    var error_ctx2 = try ErrorContext.init(
        allocator,
        ErrorCode.type_mismatch,
        .{ .offset = 59, .line = 4, .column = 14 },
        "Cannot add number and string"
    );
    defer error_ctx2.deinit(allocator);
    
    // Create array of errors
    const errors = [_]ErrorContext{ error_ctx1, error_ctx2 };
    
    // Render all errors to a buffer
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try visualizer.visualizeAllErrors(&errors, buf.writer());
    
    // Check output contains key elements for both errors
    const output = buf.items;
    
    try testing.expect(std.mem.indexOf(u8, output, "=== 2 Error(s) ===") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Error 1/2:") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Error 2/2:") != null);
    try testing.expect(std.mem.indexOf(u8, output, "missing_token: Missing semicolon at end of statement") != null);
    try testing.expect(std.mem.indexOf(u8, output, "type_mismatch: Cannot add number and string") != null);
}

test "ErrorVisualizer config options" {
    const allocator = testing.allocator;
    
    const source_text = 
        \\function example() {
        \\    let x = 10;
        \\    let y = "hello";
        \\    return x + y;
        \\}
    ;
    
    // Test with custom configuration
    var visualizer = try ErrorVisualizer.init(
        allocator, 
        source_text, 
        .{ 
            .use_colors = false,
            .context_lines = 1,  // Show only 1 line of context
            .marker_char = '~'   // Use ~ for error marker
        }
    );
    defer visualizer.deinit();
    
    // Create an error context
    var error_ctx = try ErrorContext.init(
        allocator,
        ErrorCode.type_mismatch,
        .{ .offset = 59, .line = 4, .column = 14 },
        "Cannot add number and string"
    );
    defer error_ctx.deinit(allocator);
    
    // Render to a buffer
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try visualizer.visualizeError(error_ctx, buf.writer());
    
    // Check output
    const output = buf.items;
    
    // Should only show lines 3-5 (with 1 line of context)
    try testing.expect(std.mem.indexOf(u8, output, "    let x = 10;") == null); // Line 2 should not be shown
    try testing.expect(std.mem.indexOf(u8, output, "    let y = \"hello\";") != null); // Line 3 should be shown
    try testing.expect(std.mem.indexOf(u8, output, "    return x + y;") != null); // Line 4 should be shown
    try testing.expect(std.mem.indexOf(u8, output, "             ~") != null); // Using ~ as marker
}

test "ErrorVisualizer with really long lines" {
    const allocator = testing.allocator;
    
    // Source with a very long line
    const source_text = 
        \\function example() {
        \\    let reallyLongVariableName = "This is an extremely long string that exceeds the default max line length to test line truncation behavior in our error visualizer implementation which should gracefully handle overly verbose code lines without breaking the visualization";
        \\    return reallyLongVariableName;
        \\}
    ;
    
    var visualizer = try ErrorVisualizer.init(
        allocator, 
        source_text, 
        .{ 
            .use_colors = false,
            .max_line_length = 60  // Restrict line length to 60 chars
        }
    );
    defer visualizer.deinit();
    
    // Create an error in the middle of the long line
    var error_ctx = try ErrorContext.init(
        allocator,
        ErrorCode.syntax_error,
        .{ .offset = 50, .line = 2, .column = 50 },
        "Syntax error in string literal"
    );
    defer error_ctx.deinit(allocator);
    
    // Render to a buffer
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try visualizer.visualizeError(error_ctx, buf.writer());
    
    // The output line should be truncated
    const output = buf.items;
    const line_content = "    let reallyLongVariableName = \"This is an extremely long st";
    try testing.expect(std.mem.indexOf(u8, output, line_content) != null);
}

test "ErrorVisualizer for position at start of line" {
    const allocator = testing.allocator;
    
    const source_text = 
        \\function example() {
        \\let x = 10; // Missing indentation
        \\    return x;
        \\}
    ;
    
    var visualizer = try ErrorVisualizer.init(
        allocator, 
        source_text, 
        .{ .use_colors = false }
    );
    defer visualizer.deinit();
    
    // Create an error at the start of line 2
    var error_ctx = try ErrorContext.init(
        allocator,
        ErrorCode.style_error,
        .{ .offset = 20, .line = 2, .column = 1 },
        "Missing indentation"
    );
    defer error_ctx.deinit(allocator);
    
    // Render to a buffer
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try visualizer.visualizeError(error_ctx, buf.writer());
    
    // Check that the marker is at the beginning of the line
    const output = buf.items;
    try testing.expect(std.mem.indexOf(u8, output, "      | ^") != null);
}

test "ErrorVisualizer with multiple blank lines" {
    const allocator = testing.allocator;
    
    const source_text = 
        \\function example() {
        \\    let x = 10;
        \\
        \\
        \\    return x;
        \\}
    ;
    
    var visualizer = try ErrorVisualizer.init(
        allocator, 
        source_text, 
        .{ .use_colors = false }
    );
    defer visualizer.deinit();
    
    // Test handling of blank lines
    const line3 = visualizer.getLine(3);
    try testing.expect(line3 != null);
    try testing.expectEqualStrings("", line3.?);
    
    const line4 = visualizer.getLine(4);
    try testing.expect(line4 != null);
    try testing.expectEqualStrings("", line4.?);
}