const std = @import("std");
const testing = std.testing;
const lib = @import("../zig_stream_parse.zig");

const error_mod = @import("../error.zig");
const error_aggregator_mod = @import("../error_aggregator.zig");

const Position = lib.Position;
const ErrorContext = error_mod.ErrorContext;
const ErrorCode = error_mod.ErrorCode;
const ErrorSeverity = error_mod.ErrorSeverity;
const ErrorCategory = error_mod.ErrorCategory;
const ErrorAggregator = error_aggregator_mod.ErrorAggregator;
const ErrorGroup = error_aggregator_mod.ErrorGroup;

test "ErrorAggregator initialization" {
    const allocator = testing.allocator;
    
    var aggregator = ErrorAggregator.init(allocator);
    defer aggregator.deinit();
    
    try testing.expect(!aggregator.hasErrors());
    try testing.expect(!aggregator.hasFatalErrors());
    try testing.expectEqual(@as(usize, 0), aggregator.getErrors().len);
    try testing.expectEqual(@as(usize, 0), aggregator.getWarnings().len);
    try testing.expectEqual(@as(usize, 0), aggregator.getErrorGroups().len);
}

test "ErrorAggregator basic error reporting" {
    const allocator = testing.allocator;
    
    var aggregator = ErrorAggregator.init(allocator);
    defer aggregator.deinit();
    
    // Report a simple error
    try aggregator.reportError(
        ErrorCode.unexpected_token,
        Position{ .offset = 10, .line = 1, .column = 10 },
        "Unexpected token '+'"
    );
    
    try testing.expect(aggregator.hasErrors());
    try testing.expectEqual(@as(usize, 1), aggregator.getErrors().len);
    try testing.expectEqual(@as(usize, 1), aggregator.getErrorGroups().len);
    
    // Report a warning
    var warning_ctx = try ErrorContext.init(
        allocator,
        ErrorCode.type_mismatch,
        Position{ .offset = 20, .line = 2, .column = 5 },
        "Type mismatch warning"
    );
    warning_ctx.severity = .warning;
    
    try aggregator.report(warning_ctx);
    
    try testing.expectEqual(@as(usize, 1), aggregator.getErrors().len);
    try testing.expectEqual(@as(usize, 1), aggregator.getWarnings().len);
}

test "ErrorAggregator related errors" {
    const allocator = testing.allocator;
    
    var aggregator = ErrorAggregator.init(allocator);
    defer aggregator.deinit();
    
    // Report a primary error
    try aggregator.reportError(
        ErrorCode.unexpected_token,
        Position{ .offset = 10, .line = 1, .column = 10 },
        "Unexpected token '+'"
    );
    
    // Report a related error on the same line
    try aggregator.reportError(
        ErrorCode.missing_token,
        Position{ .offset = 12, .line = 1, .column = 12 },
        "Missing token ';'"
    );
    
    // Report an unrelated error on a distant line
    try aggregator.reportError(
        ErrorCode.invalid_number_format,
        Position{ .offset = 50, .line = 10, .column = 5 },
        "Invalid number format"
    );
    
    try testing.expectEqual(@as(usize, 3), aggregator.getErrors().len);
    try testing.expectEqual(@as(usize, 2), aggregator.getErrorGroups().len);
    
    // Check that the group contains the related error
    const groups = aggregator.getErrorGroups();
    try testing.expectEqual(@as(usize, 1), groups[0].related_errors.items.len);
}

test "ErrorAggregator complex error relationships" {
    const allocator = testing.allocator;
    
    var aggregator = ErrorAggregator.init(allocator);
    defer aggregator.deinit();
    
    // Report an unterminated string error
    try aggregator.reportError(
        ErrorCode.unterminated_string,
        Position{ .offset = 10, .line = 1, .column = 10 },
        "Unterminated string literal"
    );
    
    // Report a subsequent unexpected token error that's likely related
    try aggregator.reportError(
        ErrorCode.unexpected_token,
        Position{ .offset = 20, .line = 1, .column = 20 },
        "Unexpected token ','"
    );
    
    // Report another likely related error
    try aggregator.reportError(
        ErrorCode.unexpected_token,
        Position{ .offset = 25, .line = 2, .column = 5 },
        "Unexpected token ')'"
    );
    
    // Report an unrelated error
    try aggregator.reportError(
        ErrorCode.duplicate_identifier,
        Position{ .offset = 100, .line = 10, .column = 10 },
        "Duplicate identifier 'foo'"
    );
    
    try testing.expectEqual(@as(usize, 4), aggregator.getErrors().len);
    try testing.expectEqual(@as(usize, 2), aggregator.getErrorGroups().len);
    
    // Check that the first group contains the related errors
    const groups = aggregator.getErrorGroups();
    try testing.expectEqual(@as(usize, 2), groups[0].related_errors.items.len);
}

test "ErrorAggregator fatal errors" {
    const allocator = testing.allocator;
    
    var aggregator = ErrorAggregator.init(allocator);
    defer aggregator.deinit();
    
    // Report a normal error
    try aggregator.reportError(
        ErrorCode.unexpected_token,
        Position{ .offset = 10, .line = 1, .column = 10 },
        "Unexpected token '+'"
    );
    
    // Report a fatal error
    var fatal_ctx = try ErrorContext.init(
        allocator,
        ErrorCode.memory_error,
        Position{ .offset = 20, .line = 2, .column = 5 },
        "Memory allocation error"
    );
    fatal_ctx.severity = .fatal;
    
    try aggregator.report(fatal_ctx);
    
    try testing.expect(aggregator.hasErrors());
    try testing.expect(aggregator.hasFatalErrors());
    try testing.expectEqual(@as(usize, 2), aggregator.getErrors().len);
    try testing.expectEqual(@as(usize, 2), aggregator.getErrorGroups().len);
}

test "ErrorAggregator throwIfErrors" {
    const allocator = testing.allocator;
    
    var aggregator = ErrorAggregator.init(allocator);
    defer aggregator.deinit();
    
    // Should not throw with no errors
    try aggregator.throwIfErrors();
    
    // Report an error
    try aggregator.reportError(
        ErrorCode.unexpected_token,
        Position{ .offset = 10, .line = 1, .column = 10 },
        "Unexpected token '+'"
    );
    
    // Should throw now
    try testing.expectError(error.ParserError, aggregator.throwIfErrors());
}

test "ErrorGroup functionality" {
    const allocator = testing.allocator;
    
    // Create a primary error
    var primary = try ErrorContext.init(
        allocator,
        ErrorCode.unexpected_token,
        Position{ .offset = 10, .line = 1, .column = 10 },
        "Unexpected token '+'"
    );
    
    // Create a group
    var group = ErrorGroup.init(primary, allocator);
    defer group.deinit();
    
    // Create and add a related error
    var related = try ErrorContext.init(
        allocator,
        ErrorCode.missing_token,
        Position{ .offset = 12, .line = 1, .column = 12 },
        "Missing token ';'"
    );
    
    try group.addRelatedError(related);
    
    // Check group contents
    try testing.expectEqual(primary.code, group.primary_error.code);
    try testing.expectEqual(@as(usize, 1), group.related_errors.items.len);
    try testing.expectEqual(related.code, group.related_errors.items[0].code);
}