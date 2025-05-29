const std = @import("std");
const zigparse = @import("src/zigparse.zig");

/// Simple fuzzing test for robustness
pub fn fuzzBasicParsing(allocator: std.mem.Allocator, iterations: usize) !void {
    var rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    var successes: usize = 0;
    
    std.debug.print("🧪 Running {d} fuzzing iterations...\n", .{iterations});
    
    for (0..iterations) |i| {
        // Generate random input
        const input_len = rng.random().intRangeAtMost(usize, 0, 100);
        const input = try allocator.alloc(u8, input_len);
        defer allocator.free(input);
        
        // Fill with random ASCII characters
        for (input) |*byte| {
            byte.* = @intCast(rng.random().intRangeAtMost(u8, 32, 126));
        }
        
        // Test basic tokenization doesn't crash
        const TestToken = enum { word, number, space, other };
        
        var stream = zigparse.TokenStream.init(input);
        var token_count: usize = 0;
        
        // Test tokenization
        while (stream.next(TestToken, .{
            .word = zigparse.match.alpha.oneOrMore(),
            .number = zigparse.match.digit.oneOrMore(),
            .space = zigparse.match.literal(" "),
            .other = zigparse.match.any,
        })) |_| {
            token_count += 1;
            if (token_count > 1000) break; // Prevent infinite loops
        }
        
        // Test SIMD functions
        if (input.len > 0) {
            _ = zigparse.simd.findNextNonWhitespace(input, 0);
            _ = zigparse.simd.findEndOfAlphaSequence(input, 0);
            _ = zigparse.simd.findEndOfDigitSequence(input, 0);
        }
        
        successes += 1;
        
        if (i % 100 == 0) {
            std.debug.print("Progress: {d}/{d}\n", .{ i, iterations });
        }
    }
    
    const success_rate = @as(f64, @floatFromInt(successes)) / @as(f64, @floatFromInt(iterations)) * 100.0;
    std.debug.print("✅ Fuzzing complete: {d}/{d} ({d:.1}%) successful\n", .{ successes, iterations, success_rate });
}

/// Test with edge cases
pub fn testEdgeCases() !void {
    std.debug.print("🔬 Testing edge cases...\n", .{});
    
    const edge_cases = [_][]const u8{
        "",                    // Empty
        "\x00",               // Null byte
        "\x00\x00\x00",       // Multiple null bytes
        "\xFF\xFF\xFF",       // High bytes
        " \t\n\r",            // Whitespace only
        "aaaaaaaaaa" ** 100,  // Very long
        "123456789" ** 100,   // Long numbers
        "\n\n\n\n\n",         // Many newlines
        "\"\"\"\"\"\"",        // Many quotes
        "{}{}{}{}{}", // JSON-like
    };
    
    const TestToken = enum { word, number, space, any_char };
    
    for (edge_cases, 0..) |input, i| {
        std.debug.print("  Testing edge case {d}: {d} bytes\n", .{ i + 1, input.len });
        
        // Test tokenization
        var stream = zigparse.TokenStream.init(input);
        var token_count: usize = 0;
        
        while (stream.next(TestToken, .{
            .word = zigparse.match.alpha.oneOrMore(),
            .number = zigparse.match.digit.oneOrMore(),
            .space = zigparse.match.whitespace.oneOrMore(),
            .any_char = zigparse.match.any,
        })) |_| {
            token_count += 1;
            if (token_count > 10000) break;
        }
        
        // Test SIMD functions
        if (input.len > 0) {
            _ = zigparse.simd.findNextNonWhitespace(input, 0);
            _ = zigparse.simd.findEndOfAlphaSequence(input, 0);
            
            // Test at different positions
            for (0..@min(input.len, 10)) |pos| {
                _ = zigparse.simd.findNextNonWhitespace(input, pos);
            }
        }
        
        // Test JSON tokenizer
        var json_tokenizer = zigparse.json.JsonTokenizer.init(input);
        var json_tokens: usize = 0;
        while (json_tokenizer.next()) |_| {
            json_tokens += 1;
            if (json_tokens > 1000) break;
        }
        
        std.debug.print("    Tokens: {d}, JSON tokens: {d}\n", .{ token_count, json_tokens });
    }
    
    std.debug.print("✅ All edge cases handled safely\n", .{});
}

test "basic fuzzing" {
    try fuzzBasicParsing(std.testing.allocator, 1000);
}

test "edge case testing" {
    try testEdgeCases();
}

test "memory stress test" {
    std.debug.print("💾 Memory stress test...\n", .{});
    
    // Test with large inputs
    const large_input = try std.testing.allocator.alloc(u8, 1_000_000);
    defer std.testing.allocator.free(large_input);
    
    // Fill with pattern
    for (large_input, 0..) |*byte, i| {
        byte.* = switch (i % 4) {
            0 => 'a',
            1 => 'b',
            2 => ' ',
            3 => '1',
            else => unreachable,
        };
    }
    
    const TestToken = enum { word, number, space };
    
    const start = std.time.nanoTimestamp();
    
    var stream = zigparse.TokenStream.init(large_input);
    var token_count: usize = 0;
    
    while (stream.next(TestToken, .{
        .word = zigparse.match.alpha.oneOrMore(),
        .number = zigparse.match.digit.oneOrMore(),
        .space = zigparse.match.whitespace.oneOrMore(),
    })) |_| {
        token_count += 1;
    }
    
    const end = std.time.nanoTimestamp();
    const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    
    std.debug.print("Processed {d} MB in {d:.2}ms, found {d} tokens\n", .{ 
        large_input.len / (1024 * 1024), elapsed_ms, token_count 
    });
    
    try std.testing.expect(token_count > 0);
    std.debug.print("✅ Memory stress test passed\n", .{});
}

test "performance regression" {
    std.debug.print("🏎️  Performance regression test...\n", .{});
    
    const test_inputs = [_][]const u8{
        "hello world 123 test",
        "function main() { return 42; }",
        "name,age,city\nJohn,25,NYC\nJane,30,LA",
        "{\"key\": \"value\", \"number\": 123}",
        "a b c d e f g h i j k l m n o p q r s t u v w x y z",
        "1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0",
    };
    
    const TestToken = enum { word, number, space, punct, other };
    
    for (test_inputs, 0..) |input, i| {
        const iterations = 10000;
        const start = std.time.nanoTimestamp();
        
        for (0..iterations) |_| {
            var stream = zigparse.TokenStream.init(input);
            while (stream.next(TestToken, .{
                .word = zigparse.match.alpha.oneOrMore(),
                .number = zigparse.match.digit.oneOrMore(),
                .space = zigparse.match.whitespace.oneOrMore(),
                .punct = zigparse.match.anyOf("(){}[].,;:"),
                .other = zigparse.match.any,
            })) |token| {
                std.mem.doNotOptimizeAway(token.text.ptr);
            }
        }
        
        const end = std.time.nanoTimestamp();
        const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
        const per_iteration = elapsed_ms / @as(f64, @floatFromInt(iterations));
        
        std.debug.print("Input {d}: {d:.3}ms per iteration ({d} iterations)\n", .{ 
            i + 1, per_iteration, iterations 
        });
        
        // Basic performance check - should be very fast
        try std.testing.expect(per_iteration < 1.0); // Less than 1ms per iteration
    }
    
    std.debug.print("✅ Performance regression test passed\n", .{});
}