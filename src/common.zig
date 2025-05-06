const std = @import("std");

pub const Position = struct {
    offset: usize,
    line: usize,
    column: usize,

    pub fn init(offset: usize, line: usize, column: usize) Position {
        return .{
            .offset = offset,
            .line = line,
            .column = column,
        };
    }

    pub fn format(
        self: Position,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("line {d}, column {d} (offset {d})", .{
            self.line,
            self.column,
            self.offset,
        });
    }
};