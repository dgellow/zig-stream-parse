const std = @import("std");
const benchmarks = @import("src/benchmarks/comprehensive.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    try benchmarks.runBenchmarks(allocator);
}