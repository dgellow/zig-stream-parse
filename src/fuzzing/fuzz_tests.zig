const std = @import("std");
const zigparse = @import("../zigparse.zig");
const fast_matcher = @import("../fast_matcher.zig");

/// Fuzzing test suite for robustness testing
/// Tests parser behavior with malformed, edge case, and random inputs
pub const FuzzTester = struct {
    allocator: std.mem.Allocator,
    rng: std.Random.DefaultPrng,
    
    pub fn init(allocator: std.mem.Allocator, seed: u64) FuzzTester {
        return .{
            .allocator = allocator,
            .rng = std.Random.DefaultPrng.init(seed),
        };
    }
    
    /// Generate random test input of given length
    pub fn generateRandomInput(self: *FuzzTester, length: usize) ![]u8 {
        const input = try self.allocator.alloc(u8, length);
        for (input) |*byte| {
            byte.* = @intCast(self.rng.random().intRangeAtMost(u8, 0, 255));
        }
        return input;
    }
    
    /// Generate random ASCII input
    pub fn generateRandomASCII(self: *FuzzTester, length: usize) ![]u8 {
        const input = try self.allocator.alloc(u8, length);
        for (input) |*byte| {
            byte.* = @intCast(self.rng.random().intRangeAtMost(u8, 32, 126)); // Printable ASCII
        }
        return input;
    }
    
    /// Generate input with specific character patterns
    pub fn generatePatternInput(self: *FuzzTester, length: usize, pattern: PatternType) ![]u8 {
        const input = try self.allocator.alloc(u8, length);
        
        switch (pattern) {
            .digits_only => {
                for (input) |*byte| {
                    byte.* = '0' + @as(u8, @intCast(self.rng.random().intRangeAtMost(u8, 0, 9)));
                }
            },
            .alpha_only => {
                for (input) |*byte| {
                    byte.* = 'a' + @as(u8, @intCast(self.rng.random().intRangeAtMost(u8, 0, 25)));
                }
            },
            .whitespace_heavy => {
                const whitespace = " \t\n\r";
                for (input) |*byte| {
                    if (self.rng.random().boolean()) {
                        byte.* = whitespace[self.rng.random().intRangeAtMost(usize, 0, whitespace.len - 1)];
                    } else {
                        byte.* = 'a' + @as(u8, @intCast(self.rng.random().intRangeAtMost(u8, 0, 25)));
                    }
                }
            },
            .mixed_unicode => {
                for (input) |*byte| {
                    // Generate bytes that might form UTF-8 sequences
                    byte.* = @intCast(self.rng.random().intRangeAtMost(u8, 128, 255));
                }
            },
            .control_chars => {
                for (input) |*byte| {
                    byte.* = @intCast(self.rng.random().intRangeAtMost(u8, 0, 31)); // Control characters
                }
            },
        }
        
        return input;
    }
    
    /// Generate edge case inputs
    pub fn generateEdgeCases(self: *FuzzTester) ![][]u8 {
        var cases = std.ArrayList([]u8).init(self.allocator);
        
        // Empty input
        try cases.append(try self.allocator.dupe(u8, ""));
        
        // Single characters
        for (0..256) |i| {
            const single = try self.allocator.alloc(u8, 1);
            single[0] = @intCast(i);
            try cases.append(single);
        }
        
        // Very long inputs
        const long_input = try self.allocator.alloc(u8, 100_000);
        @memset(long_input, 'a');
        try cases.append(long_input);
        
        // Null bytes
        const null_input = try self.allocator.alloc(u8, 100);
        @memset(null_input, 0);
        try cases.append(null_input);
        
        // Alternating patterns
        const alt_input = try self.allocator.alloc(u8, 1000);
        for (alt_input, 0..) |*byte, i| {
            byte.* = if (i % 2 == 0) 'a' else 'b';
        }
        try cases.append(alt_input);
        
        return try cases.toOwnedSlice();
    }
    
    /// Test pattern matching robustness
    pub fn fuzzPatternMatching(self: *FuzzTester, iterations: usize) !TestResults {
        var results = TestResults.init();
        
        for (0..iterations) |_| {
            // Generate random test case
            const input_len = self.rng.random().intRangeAtMost(usize, 0, 1000);
            const input = try self.generateRandomInput(input_len);
            defer self.allocator.free(input);
            
            // Test basic pattern matching - patterns must be comptime
            const test_patterns = comptime .{
                .word = zigparse.match.alpha.oneOrMore(),
                .number = zigparse.match.digit.oneOrMore(),
                .space = zigparse.match.literal(" "),
            };
            
            // Test that it doesn't crash
            var stream = zigparse.TokenStream.init(input);
            var token_count: usize = 0;
            
            while (stream.next(TestTokenType, test_patterns)) |_| {
                token_count += 1;
                if (token_count > 10000) break; // Prevent infinite loops
            }
            
            results.pattern_tests += 1;
            if (token_count < 10000) {
                results.pattern_successes += 1;
            }
        }
        
        return results;
    }
    
    /// Test JSON parsing robustness
    pub fn fuzzJsonParsing(self: *FuzzTester, iterations: usize) !TestResults {
        var results = TestResults.init();
        
        for (0..iterations) |_| {
            // Generate JSON-like input
            const input = try self.generateJsonLikeInput();
            defer self.allocator.free(input);
            
            // Test JSON tokenizer
            var json_tokenizer = zigparse.json.JsonTokenizer.init(input);
            var token_count: usize = 0;
            
            while (json_tokenizer.next()) |_| {
                token_count += 1;
                if (token_count > 10000) break; // Prevent infinite loops
            }
            
            results.json_tests += 1;
            if (token_count < 10000) {
                results.json_successes += 1;
            }
        }
        
        return results;
    }
    
    /// Test SIMD algorithms robustness
    pub fn fuzzSIMDAlgorithms(self: *FuzzTester, iterations: usize) !TestResults {
        var results = TestResults.init();
        
        for (0..iterations) |_| {
            const input_len = self.rng.random().intRangeAtMost(usize, 0, 1000);
            const input = try self.generateRandomInput(input_len);
            defer self.allocator.free(input);
            
            // Test SIMD functions don't crash
            if (input.len > 0) {
                _ = zigparse.simd.findNextNonWhitespace(input, 0);
                _ = zigparse.simd.findEndOfAlphaSequence(input, 0);
                _ = zigparse.simd.findEndOfDigitSequence(input, 0);
                
                // Test with different start positions
                const start_pos = if (input.len > 1) self.rng.random().intRangeAtMost(usize, 0, input.len - 1) else 0;
                _ = zigparse.simd.findNextNonWhitespace(input, start_pos);
            }
            
            results.simd_tests += 1;
            results.simd_successes += 1; // If we got here, it didn't crash
        }
        
        return results;
    }
    
    /// Test memory safety with edge cases
    pub fn fuzzMemorySafety(self: *FuzzTester) !TestResults {
        var results = TestResults.init();
        
        const edge_cases = try self.generateEdgeCases();
        defer {
            for (edge_cases) |case| {
                self.allocator.free(case);
            }
            self.allocator.free(edge_cases);
        }
        
        for (edge_cases) |input| {
            // Test TokenStream with edge case
            var stream = zigparse.TokenStream.init(input);
            
            const edge_patterns = comptime .{
                .any_char = zigparse.match.any,
                .alpha = zigparse.match.alpha,
                .digit = zigparse.match.digit,
            };
            
            var token_count: usize = 0;
            while (stream.next(TestTokenType, edge_patterns)) |_| {
                token_count += 1;
                if (token_count > 1000) break;
            }
            
            results.memory_tests += 1;
            results.memory_successes += 1; // If we got here, no memory issues
        }
        
        return results;
    }
    
    fn generateJsonLikeInput(self: *FuzzTester) ![]u8 {
        const templates = [_][]const u8{
            "{\"key\": \"value\"}",
            "[1, 2, 3]",
            "\"string\"",
            "123",
            "true",
            "false",
            "null",
            "{",
            "}",
            "[",
            "]",
            "\"",
            "\\",
            "{\"nested\": {\"deep\": [1, 2, {\"more\": true}]}}",
        };
        
        const template = templates[self.rng.random().intRangeAtMost(usize, 0, templates.len - 1)];
        
        // Sometimes corrupt the template
        if (self.rng.random().boolean()) {
            const corrupted = try self.allocator.dupe(u8, template);
            for (corrupted, 0..) |_, i| {
                if (self.rng.random().intRangeAtMost(u8, 0, 10) == 0) { // 10% chance
                    corrupted[i] = @intCast(self.rng.random().intRangeAtMost(u8, 0, 255));
                }
            }
            return corrupted;
        }
        
        return try self.allocator.dupe(u8, template);
    }
};

const PatternType = enum {
    digits_only,
    alpha_only,
    whitespace_heavy,
    mixed_unicode,
    control_chars,
};

const TestTokenType = enum { word, number, space, any_char, alpha, digit };

pub const TestResults = struct {
    pattern_tests: usize = 0,
    pattern_successes: usize = 0,
    json_tests: usize = 0,
    json_successes: usize = 0,
    simd_tests: usize = 0,
    simd_successes: usize = 0,
    memory_tests: usize = 0,
    memory_successes: usize = 0,
    
    pub fn init() TestResults {
        return .{};
    }
    
    pub fn combine(self: TestResults, other: TestResults) TestResults {
        return .{
            .pattern_tests = self.pattern_tests + other.pattern_tests,
            .pattern_successes = self.pattern_successes + other.pattern_successes,
            .json_tests = self.json_tests + other.json_tests,
            .json_successes = self.json_successes + other.json_successes,
            .simd_tests = self.simd_tests + other.simd_tests,
            .simd_successes = self.simd_successes + other.simd_successes,
            .memory_tests = self.memory_tests + other.memory_tests,
            .memory_successes = self.memory_successes + other.memory_successes,
        };
    }
    
    pub fn printSummary(self: TestResults) void {
        std.debug.print("\n🧪 Fuzzing Test Results:\n", .{});
        std.debug.print("========================\n", .{});
        
        if (self.pattern_tests > 0) {
            const pattern_rate = @as(f64, @floatFromInt(self.pattern_successes)) / @as(f64, @floatFromInt(self.pattern_tests)) * 100.0;
            std.debug.print("Pattern Matching: {d}/{d} ({d:.1}%)\n", .{ self.pattern_successes, self.pattern_tests, pattern_rate });
        }
        
        if (self.json_tests > 0) {
            const json_rate = @as(f64, @floatFromInt(self.json_successes)) / @as(f64, @floatFromInt(self.json_tests)) * 100.0;
            std.debug.print("JSON Parsing: {d}/{d} ({d:.1}%)\n", .{ self.json_successes, self.json_tests, json_rate });
        }
        
        if (self.simd_tests > 0) {
            const simd_rate = @as(f64, @floatFromInt(self.simd_successes)) / @as(f64, @floatFromInt(self.simd_tests)) * 100.0;
            std.debug.print("SIMD Algorithms: {d}/{d} ({d:.1}%)\n", .{ self.simd_successes, self.simd_tests, simd_rate });
        }
        
        if (self.memory_tests > 0) {
            const memory_rate = @as(f64, @floatFromInt(self.memory_successes)) / @as(f64, @floatFromInt(self.memory_tests)) * 100.0;
            std.debug.print("Memory Safety: {d}/{d} ({d:.1}%)\n", .{ self.memory_successes, self.memory_tests, memory_rate });
        }
        
        const total_tests = self.pattern_tests + self.json_tests + self.simd_tests + self.memory_tests;
        const total_successes = self.pattern_successes + self.json_successes + self.simd_successes + self.memory_successes;
        
        if (total_tests > 0) {
            const overall_rate = @as(f64, @floatFromInt(total_successes)) / @as(f64, @floatFromInt(total_tests)) * 100.0;
            std.debug.print("Overall: {d}/{d} ({d:.1}%)\n", .{ total_successes, total_tests, overall_rate });
        }
        
        std.debug.print("\n", .{});
    }
};

/// Run comprehensive fuzzing test suite
pub fn runFuzzingTests(allocator: std.mem.Allocator, iterations: usize) !TestResults {
    var fuzzer = FuzzTester.init(allocator, @intCast(std.time.timestamp()));
    
    std.debug.print("🔬 Running fuzzing tests with {d} iterations...\n", .{iterations});
    
    // Run different fuzzing test categories
    const pattern_results = try fuzzer.fuzzPatternMatching(iterations);
    const json_results = try fuzzer.fuzzJsonParsing(iterations);
    const simd_results = try fuzzer.fuzzSIMDAlgorithms(iterations);
    const memory_results = try fuzzer.fuzzMemorySafety();
    
    // Combine results
    const total_results = pattern_results
        .combine(json_results)
        .combine(simd_results)
        .combine(memory_results);
    
    return total_results;
}

test "fuzzing pattern matching" {
    var fuzzer = FuzzTester.init(std.testing.allocator, 42);
    const results = try fuzzer.fuzzPatternMatching(100);
    
    try std.testing.expect(results.pattern_tests == 100);
    try std.testing.expect(results.pattern_successes > 80); // Should be mostly successful
}

test "fuzzing JSON parsing" {
    var fuzzer = FuzzTester.init(std.testing.allocator, 42);
    const results = try fuzzer.fuzzJsonParsing(50);
    
    try std.testing.expect(results.json_tests == 50);
    try std.testing.expect(results.json_successes > 0); // Some should succeed
}

test "fuzzing SIMD algorithms" {
    var fuzzer = FuzzTester.init(std.testing.allocator, 42);
    const results = try fuzzer.fuzzSIMDAlgorithms(100);
    
    try std.testing.expect(results.simd_tests == 100);
    try std.testing.expectEqual(results.simd_successes, 100); // Should never crash
}

test "fuzzing memory safety" {
    var fuzzer = FuzzTester.init(std.testing.allocator, 42);
    const results = try fuzzer.fuzzMemorySafety();
    
    try std.testing.expect(results.memory_tests > 0);
    try std.testing.expectEqual(results.memory_successes, results.memory_tests); // Should be memory safe
}

test "edge case generation" {
    var fuzzer = FuzzTester.init(std.testing.allocator, 42);
    const edge_cases = try fuzzer.generateEdgeCases();
    defer {
        for (edge_cases) |case| {
            std.testing.allocator.free(case);
        }
        std.testing.allocator.free(edge_cases);
    }
    
    try std.testing.expect(edge_cases.len > 250); // Should generate many edge cases
}

test "comprehensive fuzzing" {
    const results = try runFuzzingTests(std.testing.allocator, 50);
    results.printSummary();
    
    try std.testing.expect(results.pattern_tests > 0);
    try std.testing.expect(results.json_tests > 0);
    try std.testing.expect(results.simd_tests > 0);
    try std.testing.expect(results.memory_tests > 0);
}