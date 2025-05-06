const std = @import("std");
const ByteStream = @import("byte_stream.zig").ByteStream;
const Position = @import("common.zig").Position;

pub const TokenType = struct {
    id: u32,
    name: []const u8,
};

pub const Token = struct {
    type: TokenType,
    position: Position,
    lexeme: []const u8,

    pub fn init(token_type: TokenType, position: Position, lexeme: []const u8) Token {
        return .{
            .type = token_type,
            .position = position,
            .lexeme = lexeme,
        };
    }
};

pub const TokenMatcher = struct {
    match_fn: *const fn(stream: *ByteStream, allocator: std.mem.Allocator) anyerror!?Token,

    pub fn init(comptime matcher_fn: anytype) TokenMatcher {
        return .{
            .match_fn = matcher_fn,
        };
    }

    pub fn match(self: TokenMatcher, stream: *ByteStream, allocator: std.mem.Allocator) !?Token {
        return self.match_fn(stream, allocator);
    }
};

pub const Tokenizer = struct {
    allocator: std.mem.Allocator,
    stream: *ByteStream,
    matchers: []const TokenMatcher,
    skip_types: []const TokenType,
    token_buffer: std.ArrayList(u8),

    pub fn init(
        allocator: std.mem.Allocator,
        stream: *ByteStream,
        matchers: []const TokenMatcher,
        skip_types: []const TokenType,
    ) !Tokenizer {
        return .{
            .allocator = allocator,
            .stream = stream,
            .matchers = matchers,
            .skip_types = skip_types,
            .token_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Tokenizer) void {
        self.token_buffer.deinit();
    }

    pub fn nextToken(self: *Tokenizer) !?Token {
        while (true) {
            const position = self.stream.getPosition();

            // Try each matcher
            for (self.matchers) |matcher| {
                if (try matcher.match(self.stream, self.allocator)) |token| {
                    // Check if this token type should be skipped
                    var should_skip = false;
                    for (self.skip_types) |skip_type| {
                        if (token.type.id == skip_type.id) {
                            should_skip = true;
                            break;
                        }
                    }

                    if (!should_skip) {
                        return token;
                    } else {
                        // Skip this token and continue
                        break;
                    }
                }
            }

            // No matcher matched, check if at EOF
            const next_byte = try self.stream.peek();
            if (next_byte == null) {
                return null; // EOF
            }

            // No matcher matched but not at EOF - unrecognized character
            _ = try self.stream.consume();
            return Token.init(
                .{ .id = std.math.maxInt(u32), .name = "ERROR" },
                position,
                &[_]u8{next_byte.?}
            );
        }
    }
};