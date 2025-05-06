const std = @import("std");

// Re-export everything from the zig_stream_parse.zig file
pub usingnamespace @import("zig_stream_parse.zig");

// Simple test for backward compatibility
test "basic add functionality" {
    try std.testing.expect(@import("zig_stream_parse.zig").add(3, 7) == 10);
}