const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const StringError = error{
    IndexOutOfBounds,
};

const OpFn = enum { trim, uppercase, lowercase, capitalize, append, prepend, insert, remove, reverse };

const Op = union(OpFn) {
    trim: void,
    uppercase: void,
    lowercase: void,
    capitalize: void,
    append: []const u8,
    prepend: []const u8,
    insert: struct { index: usize, str: []const u8 },
    remove: struct { index: usize, n: usize },
    reverse: void,
};

pub const StringBuilder = struct {
    const Self = @This();

    str: []const u8,
    ops: [255]Op = undefined,
    idx: usize = 0,

    pub fn init(slice: []const u8) Self {
        return Self{ .str = slice };
    }

    fn addOp(self: *Self, op: Op) *Self {
        if (self.idx >= self.ops.len) @panic("StringBuilder ops overflow");
        self.ops[self.idx] = op;
        self.idx += 1;
        return self;
    }

    pub fn trim(self: *Self) *Self {
        return addOp(self, .trim);
    }

    pub fn uppercase(self: *Self) *Self {
        return addOp(self, .uppercase);
    }

    pub fn lowercase(self: *Self) *Self {
        return addOp(self, .lowercase);
    }

    pub fn capitalize(self: *Self) *Self {
        return addOp(self, .capitalize);
    }

    pub fn append(self: *Self, str: []const u8) *Self {
        return addOp(self, .{ .append = str });
    }

    pub fn prepend(self: *Self, str: []const u8) *Self {
        return addOp(self, .{ .prepend = str });
    }

    pub fn insert(self: *Self, index: usize, str: []const u8) *Self {
        return addOp(self, .{ .insert = .{ .index = index, .str = str } });
    }

    pub fn remove(self: *Self, index: usize, n: usize) *Self {
        return addOp(self, .{ .remove = .{ .index = index, .n = n } });
    }

    pub fn reverse(self: *Self) *Self {
        return addOp(self, .reverse);
    }

    pub fn build(self: *Self, gpa: mem.Allocator) !String {
        var new_str = String{
            .str = try gpa.dupe(u8, self.str),
        };

        errdefer new_str.deinit(gpa);

        var opIdx: usize = 0;
        while (opIdx < self.idx) : (opIdx += 1) {
            const op = self.ops[opIdx];
            switch (op) {
                .trim => {
                    try new_str.trim(gpa);
                },
                .uppercase => {
                    new_str.uppercase();
                },
                .lowercase => {
                    new_str.lowercase();
                },
                .capitalize => {
                    new_str.capitalize();
                },
                .append => |str| {
                    try new_str.append(gpa, str);
                },
                .prepend => |str| {
                    try new_str.prepend(gpa, str);
                },
                .insert => |tuple| {
                    try new_str.insert(gpa, tuple.index, tuple.str);
                },
                .remove => |tuple| {
                    try new_str.remove(gpa, tuple.index, tuple.n);
                },
                .reverse => {
                    try new_str.reverse(gpa);
                },
            }
        }
        return new_str;
    }
};

/// Given the first byte of a UTF-8 codepoint,
/// returns a number 1-4 indicating the total length of the codepoint in bytes.
/// If this byte does not match the form of a UTF-8 start byte, returns Utf8InvalidStartByte.
inline fn utf8Size(char: u8) !u3 {
    return try std.unicode.utf8ByteSequenceLength(char);
}

inline fn bufferIndex(str: []const u8, byte_start: usize, index_start: usize, index: usize) !usize {
    var i: usize = byte_start;
    var utf8_index: usize = index_start;
    while (i < str.len) : (i += try utf8Size(str[i])) {
        if (utf8_index == index) break;
        utf8_index += 1;
    }
    return i;
}

const Utf8 = struct {
    byte_index: usize, // Points to the byte where the UTF-8 codepoint starts
    slice: []const u8, // UTF-8 slice
};

const Utf8Iter = struct {
    internal_view: std.unicode.Utf8View = undefined,
    internal_iterator: std.unicode.Utf8Iterator = undefined,

    pub fn init(s: []const u8) Utf8Iter {
        const view: std.unicode.Utf8View = std.unicode.Utf8View.initUnchecked(s);
        const internal_iterator: std.unicode.Utf8Iterator = view.iterator();
        return Utf8Iter{
            .internal_view = view,
            .internal_iterator = internal_iterator,
        };
    }

    /// Returns true if there is a next character
    pub fn next(self: *Utf8Iter) ?Utf8 {
        const byte_index = self.internal_iterator.i;
        const next_slice = self.internal_iterator.nextCodepointSlice();
        if (next_slice) |slice| {
            const result = Utf8{
                .byte_index = byte_index,
                .slice = slice,
            };
            return result;
        }
        return null;
    }
};

pub const String = struct {
    const Self = @This();

    // A chunck of memory heap allocated
    str: []u8,

    /// Create an empty a String
    pub fn empty(gpa: mem.Allocator) !Self {
        const str = try gpa.alloc(u8, 0);
        return String{
            .str = str,
        };
    }

    /// Create and inizialize a String
    /// A copy is made.
    pub fn from(gpa: mem.Allocator, initStr: []const u8) !Self {
        const str = try gpa.alloc(u8, initStr.len);
        @memcpy(str, initStr);
        return String{
            .str = str,
        };
    }

    /// Create and inizialize a case-sensitivering
    /// String now own the memory.
    pub fn fromOwned(str: []u8) Self {
        return String{
            .str = str,
        };
    }

    pub fn len(self: String) usize {
        var iter = Utf8Iter.init(self.str);
        var size: usize = 0;
        while (iter.next()) |_| {
            size += 1;
        }
        return size;
    }

    pub fn uppercase(self: *Self) void {
        var iter = Utf8Iter.init(self.str);
        while (iter.next()) |c| {
            if (c.slice.len > 1) {
                continue;
            }
            const i = c.byte_index;
            self.str[i] = std.ascii.toUpper(self.str[i]);
        }
    }

    pub fn lowercase(self: *Self) void {
        var iter = Utf8Iter.init(self.str);
        while (iter.next()) |c| {
            if (c.slice.len > 1) {
                continue;
            }
            const i = c.byte_index;
            self.str[i] = std.ascii.toLower(self.str[i]);
        }
    }

    // WARNING: there is some confusion on what capitalize means
    pub fn capitalize(self: *Self) void {
        var iter = Utf8Iter.init(self.str);
        while (iter.next()) |c| {
            const i = c.byte_index;
            const char = self.str[i];
            if (std.ascii.isAlphabetic(char)) {
                self.str[i] = std.ascii.toUpper(char);
                break;
            }
        }
    }

    pub fn append(self: *Self, gpa: mem.Allocator, str: []const u8) !void {
        try self.insert(gpa, self.len(), str);
    }

    pub fn prepend(self: *Self, gpa: mem.Allocator, str: []const u8) !void {
        try self.insert(gpa, 0, str);
    }

    pub fn insert(self: *Self, gpa: mem.Allocator, index: usize, str: []const u8) !void {
        const length = self.len();

        if (index > length) {
            return StringError.IndexOutOfBounds;
        }

        var new_str = try gpa.alloc(u8, self.str.len + str.len);
        errdefer gpa.free(new_str);

        if (index == 0) {
            // prepend
            @memcpy(new_str[0..str.len], str);
            @memcpy(new_str[str.len..], self.str);
        } else if (index == length) {
            // append
            @memcpy(new_str[0..self.str.len], self.str);
            @memcpy(new_str[self.str.len..], str);
        } else {
            // Index is in the middle
            const byte_index = try bufferIndex(self.str, 0, 0, index);
            if (byte_index > 0) @memcpy(new_str[0..byte_index], self.str[0..byte_index]);
            @memcpy(new_str[byte_index + str.len ..], self.str[byte_index..]);
            if (byte_index <= self.str.len) @memcpy(new_str[byte_index .. byte_index + str.len], str);
        }

        gpa.free(self.str);
        self.str = new_str;
    }

    pub fn remove(self: *Self, gpa: mem.Allocator, index: usize, n: usize) !void {
        const str_len = self.len();
        if (index + n > str_len) {
            return StringError.IndexOutOfBounds;
        }

        // Nothing to remove
        if (n == 0) return;

        const start_byte = try bufferIndex(self.str, 0, 0, index);
        const end_byte = try bufferIndex(self.str, start_byte, index, index + n);

        const new_len = self.str.len - (end_byte - start_byte);
        var new_str = try gpa.alloc(u8, new_len);
        errdefer gpa.free(new_str);

        // Copy bytes before start
        if (start_byte > 0) @memcpy(new_str[0..start_byte], self.str[0..start_byte]);
        // Copy bytes after end
        if (end_byte < self.str.len) @memcpy(new_str[start_byte..], self.str[end_byte..]);

        gpa.free(self.str);
        self.str = new_str;
    }

    pub fn charAt(self: *Self, index: usize) ?[]const u8 {
        if (index > self.len()) {
            return null;
        }

        // TODO: unreachable because the string is already validated?
        const byte_index = bufferIndex(self.str, 0, 0, index) catch unreachable;
        const size = utf8Size(self.str[byte_index]) catch unreachable;
        return self.str[byte_index .. byte_index + size];
    }

    pub fn byteAt(self: *Self, index: usize) ?u8 {
        if (index > self.str.len) {
            return null;
        }
        return self.str[index];
    }

    pub fn indexOf(self: *Self, needle: []const u8) ?usize {
        return _indexOf(self.str, needle, struct {
            fn compare(left: u8, right: u8) bool {
                return left == right;
            }
        }.compare);
    }

    pub fn indexOfIgnoreCase(self: *Self, needle: []const u8) ?usize {
        return _indexOf(self.str, needle, struct {
            fn compare(left: u8, right: u8) bool {
                return std.ascii.toLower(left) == std.ascii.toLower(right);
            }
        }.compare);
    }

    fn _indexOf(haystack: []const u8, needle: []const u8, comptime compare: fn (u8, u8) bool) ?usize {
        // Early out for empty needle
        if (needle.len == 0) return 0;

        var haystack_byte_index: usize = 0;
        var haystack_char_index: usize = 0;

        while (haystack_byte_index < haystack.len) : (haystack_byte_index += utf8Size(haystack[haystack_byte_index]) catch unreachable) {
            // Try to match needle starting here
            var match: bool = true;
            var needle_byte_index: usize = 0;
            var hay_byte_index: usize = haystack_byte_index;

            while (needle_byte_index < needle.len) : (needle_byte_index += 1) {
                if (hay_byte_index >= haystack.len) {
                    match = false;
                    break;
                }
                if (!compare(haystack[hay_byte_index], needle[needle_byte_index])) {
                    match = false;
                    break;
                }
                hay_byte_index += 1;
            }

            if (match) return haystack_char_index;

            haystack_char_index += 1;
        }

        return null;
    }

    /// Returns true if the string contains the given substring
    pub fn contains(self: *Self, needle: []const u8, ignore_case: bool) bool {
        if (if (ignore_case) self.indexOfIgnoreCase(needle) else self.indexOf(needle)) |_| {
            return true;
        }
        return false;
    }

    /// Returns true if the string starts with the given substring
    pub fn startsWith(self: *Self, prefix: []const u8) bool {
        return std.mem.eql(u8, self.str[0..prefix.len], prefix);
    }

    /// Returns true if the string ends with the given substring
    pub fn endsWith(self: *Self, suffix: []const u8) bool {
        return std.mem.eql(u8, self.str[self.str.len - suffix.len ..], suffix);
    }

    /// Finds the last occurrence of a substring, returning its character index
    // TODO: implement UTF-8 safe search from the end
    pub fn lastIndexOf(self: *Self, needle: []const u8) ?usize {
        _ = self;
        _ = needle;
        return null;
    }

    /// Counts how many times the substring appears in the string
    // TODO: implement UTF-8 aware count
    pub fn count(self: *Self, needle: []const u8) usize {
        _ = self;
        _ = needle;
        return 0;
    }

    /// Returns a substring from index to index + n
    pub fn substring(self: *Self, gpa: mem.Allocator, index: usize, n: usize) !Self {
        const str_len = self.len();
        if (index + n > str_len) {
            return StringError.IndexOutOfBounds;
        }

        if (n == 0) {
            return try String.empty(gpa);
        }

        const start_byte = try bufferIndex(self.str, 0, 0, index);
        const end_byte = try bufferIndex(self.str, start_byte, index, index + n);

        const new_str = try gpa.alloc(u8, end_byte - start_byte);
        errdefer gpa.free(new_str);

        @memcpy(new_str, self.str[start_byte..end_byte]);

        return .{ .str = new_str };
    }

    /// Reverses the string by UTF-8 characters
    pub fn reverse(self: *Self, gpa: mem.Allocator) !void {
        var new_str = try gpa.alloc(u8, self.str.len);
        errdefer gpa.free(new_str);

        var i_forward: usize = 0;
        var i_backward_signed: isize = @intCast(self.str.len - 1);
        while (i_backward_signed >= 0) : (i_backward_signed += -1) {
            const i_backward: usize = @intCast(i_backward_signed);
            if (self.str[i_backward] & 0xC0 != 0x80) {
                const size = try utf8Size(self.str[i_backward]);
                @memcpy(new_str[i_forward .. i_forward + size], self.str[i_backward .. i_backward + size]);
                i_forward += size;
            }
        }

        gpa.free(self.str);
        self.str = new_str;
    }

    /// Replaces all occurrences of old with new
    // TODO: implement UTF-8 safe replacement
    pub fn replace(self: *Self, gpa: mem.Allocator, old: []const u8, new: []const u8) !void {
        _ = self;
        _ = gpa;
        _ = old;
        _ = new;
    }

    /// Repeats the string n times
    // TODO: repeat the string n times efficiently
    pub fn repeat(self: *Self, gpa: mem.Allocator, n: usize) !void {
        _ = self;
        _ = gpa;
        _ = n;
    }

    /// Remove empty spaces at the start and at the end.
    /// Invalidates str if less memory is needed.
    pub fn trim(self: *Self, gpa: mem.Allocator) !void {
        const trimmed_slice: []const u8 = mem.trim(u8, self.str, "\t\n\r ");
        if (std.mem.eql(u8, self.str, trimmed_slice)) {
            return;
        }
        const trimmed = try gpa.dupe(u8, trimmed_slice);
        gpa.free(self.str);
        self.str = trimmed;
    }

    /// Trims whitespace only from the start
    pub fn trimStart(self: *Self, gpa: mem.Allocator) !void {
        const trimmed_slice: []const u8 = mem.trimStart(u8, self.str, "\t\n\r ");
        if (std.mem.eql(u8, self.str, trimmed_slice)) {
            return;
        }
        const trimmed = try gpa.dupe(u8, trimmed_slice);
        gpa.free(self.str);
        self.str = trimmed;
    }

    /// Trims whitespace only from the end
    pub fn trimEnd(self: *Self, gpa: mem.Allocator) !void {
        const trimmed_slice: []const u8 = mem.trimEnd(u8, self.str, "\t\n\r ");
        if (std.mem.eql(u8, self.str, trimmed_slice)) {
            return;
        }
        const trimmed = try gpa.dupe(u8, trimmed_slice);
        gpa.free(self.str);
        self.str = trimmed;
    }

    /// Returns true if the string is empty
    pub fn isEmpty(self: Self) bool {
        return self.len() == 0;
    }

    /// Iterates over each UTF-8 character, calling the callback
    pub fn forEachChar(self: *Self, callback: fn ([]const u8) void) void {
        _ = self;
        _ = callback;
    }

    pub fn builder(self: Self) StringBuilder {
        return StringBuilder{ .str = self.str };
    }

    pub fn deinit(self: Self, gpa: mem.Allocator) void {
        gpa.free(self.str);
    }

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try std.unicode.fmtUtf8(self.str).format(writer);
        // try writer.print("{s}", .{self.str});
    }
};

pub const ManagedString = struct {
    const Self = @This();

    gpa: mem.Allocator,
    string: String = undefined,

    /// Create an empty a String
    pub fn empty(gpa: mem.Allocator) !Self {
        var inst: Self = .{ .gpa = gpa };
        inst.string = try String.empty(gpa);
        return inst;
    }

    /// Create and inizialize a String
    pub fn from(gpa: mem.Allocator, initStr: []const u8) !Self {
        var inst: Self = .{ .gpa = gpa };
        inst.string = try String.from(inst.gpa, initStr);
        return inst;
    }

    /// Remove empty spaces at the start and at the end.
    /// Invalidates str if less memory is needed.
    pub fn trim(self: *Self) !void {
        try self.string.trim(self.gpa);
    }

    pub fn uppercase(self: *Self) void {
        self.string.uppercase();
    }

    pub fn lowercase(self: *Self) void {
        self.string.lowercase();
    }

    pub fn capitalize(self: *Self) void {
        self.string.capitalize();
    }

    pub fn append(self: *Self, str: []const u8) !void {
        try self.string.append(self.gpa, str);
    }

    pub fn prepend(self: *Self, str: []const u8) !void {
        try self.string.prepend(self.gpa, str);
    }

    pub fn insert(self: *Self, index: usize, str: []const u8) !void {
        try self.string.insert(self.gpa, index, str);
    }

    pub fn deinit(self: Self) void {
        self.string.deinit(self.gpa);
    }

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try self.string.format(writer);
        // try std.unicode.fmtUtf8(self.str).format(writer);
        // try writer.print("{s}", .{self.string.str});
    }
};

test "Unicode" {
    const gpa = testing.allocator;
    var s = try String.from(gpa, "Hello, 世界 HELLO");
    defer s.deinit(gpa);
    s.uppercase();
    try std.testing.expectEqualSlices(u8, "HELLO, 世界 HELLO", s.str);

    s.lowercase();
    try std.testing.expectEqualSlices(u8, "hello, 世界 hello", s.str);

    try std.testing.expectEqualStrings("h", s.charAt(0).?);
    try std.testing.expectEqualStrings("h", s.charAt(0).?);
    try std.testing.expectEqualStrings("世", s.charAt(7).?);
    try std.testing.expectEqualStrings("界", s.charAt(8).?);
}

test "Fixed Buffer, no gpa" {
    const gpa = testing.allocator;

    {
        var string_1 = try ManagedString.from(gpa, "Hello");
        defer string_1.deinit();
        try string_1.append(", 世界");
        try std.testing.expectEqualSlices(u8, "Hello, 世界", string_1.string.str);
    }

    {
        var string_1 = try ManagedString.empty(gpa);
        defer string_1.deinit();
        try string_1.append("Aseo");
        try std.testing.expectEqualSlices(u8, "Aseo", string_1.string.str);
    }
}

test "String builder trim - lowercase - capitalize - append" {
    const gpa = testing.allocator;

    {
        var string_1 = try String.from(gpa, "Œ!");
        defer string_1.deinit(gpa);

        try string_1.append(gpa, "R");
        try std.testing.expectEqualSlices(u8, "Œ!R", string_1.str);

        var builder = string_1.builder();
        const string_2 = try builder.trim().lowercase().capitalize().append(" ANOTHER STRING ").build(gpa);
        defer string_2.deinit(gpa);

        try std.testing.expectEqualSlices(u8, "Œ!R ANOTHER STRING ", string_2.str);
    }

    {
        const string_1 = try String.from(gpa, "ello");
        defer string_1.deinit(gpa);

        var builder = string_1.builder();
        const string_2 = try builder.append("World!").prepend("H").insert(5, ", ").trim().build(gpa);
        defer string_2.deinit(gpa);

        try std.testing.expectEqualSlices(u8, "Hello, World!", string_2.str);
    }

    {
        const string_1 = try String.from(gpa, "Hello");
        defer string_1.deinit(gpa);

        var builder = string_1.builder();
        const string_2 = builder.insert(20, "").build(gpa);
        try std.testing.expectError(StringError.IndexOutOfBounds, string_2);
    }
}

test "string empty" {
    const gpa = testing.allocator;

    {
        var string_1 = try String.empty(gpa);
        defer string_1.deinit(gpa);
        try string_1.trim(gpa);
        try std.testing.expectEqualSlices(u8, "", string_1.str);
    }

    {
        var string_1 = try String.empty(gpa);
        defer string_1.deinit(gpa);
        try string_1.append(gpa, "Hello");
        try std.testing.expectEqualSlices(u8, "Hello", string_1.str);
    }
}

test "String trim" {
    const gpa = testing.allocator;

    var string_1 = try String.from(gpa, " trim me ");
    defer string_1.deinit(gpa);
    try string_1.trim(gpa);

    try std.testing.expectEqualSlices(u8, "trim me", string_1.str);
}

test "String uppercase" {
    const gpa = testing.allocator;

    var string_1 = try String.from(gpa, "uppercase?");
    defer string_1.deinit(gpa);
    string_1.uppercase();

    try std.testing.expectEqualSlices(u8, "UPPERCASE?", string_1.str);
}

test "String lowercase" {
    const gpa = testing.allocator;

    var string_1 = try String.from(gpa, "LOWercaSE?");
    defer string_1.deinit(gpa);
    string_1.lowercase();

    try std.testing.expectEqualSlices(u8, "lowercase?", string_1.str);
}

test "String capitalize" {
    const gpa = testing.allocator;

    var string_1 = try String.from(gpa, "hello");
    defer string_1.deinit(gpa);
    string_1.capitalize();

    try std.testing.expectEqualSlices(u8, "Hello", string_1.str);
}

test "String append const" {
    const gpa = testing.allocator;

    var string_1 = try String.from(gpa, "Hello");
    defer string_1.deinit(gpa);
    try string_1.append(gpa, " World!");

    try std.testing.expectEqualSlices(u8, "Hello World!", string_1.str);
}

test "String prepend const" {
    const gpa = testing.allocator;

    var string_1 = try String.from(gpa, "Hello");
    defer string_1.deinit(gpa);
    try string_1.prepend(gpa, "World! ");

    try std.testing.expectEqualSlices(u8, "World! Hello", string_1.str);
}

test "String insert const" {
    const gpa = testing.allocator;

    var string_1 = try String.from(gpa, "Heo");
    defer string_1.deinit(gpa);
    try string_1.insert(gpa, 2, "ll");

    try std.testing.expectEqualSlices(u8, "Hello", string_1.str);
}

test "String indexOf" {
    const gpa = testing.allocator;

    var s = try String.from(gpa, "Hello");
    defer s.deinit(gpa);

    try std.testing.expectEqual(0, s.indexOf("H"));
    try std.testing.expectEqual(1, s.indexOf("e"));
    try std.testing.expectEqual(2, s.indexOf("l"));

    try std.testing.expectEqual(0, s.indexOf("He"));
    try std.testing.expectEqual(1, s.indexOf("el"));
    try std.testing.expectEqual(2, s.indexOf("ll"));

    try std.testing.expectEqual(0, s.indexOf("Hell"));

    try std.testing.expectEqual(null, s.indexOf("lll"));
}

test "String indexOfIgnoreCase" {
    const gpa = testing.allocator;

    var s = try String.from(gpa, "Hello");
    defer s.deinit(gpa);

    try std.testing.expectEqual(0, s.indexOfIgnoreCase("h"));
    try std.testing.expectEqual(1, s.indexOfIgnoreCase("E"));
    try std.testing.expectEqual(2, s.indexOfIgnoreCase("L"));

    try std.testing.expectEqual(0, s.indexOfIgnoreCase("HE"));
    try std.testing.expectEqual(1, s.indexOfIgnoreCase("EL"));
    try std.testing.expectEqual(2, s.indexOfIgnoreCase("LL"));
}

test "String format" {
    const gpa = testing.allocator;

    var string_1 = try String.from(gpa, "String");
    defer string_1.deinit(gpa);

    const string_2 = try std.fmt.allocPrint(gpa, "I can format with my {f}", .{string_1});
    defer gpa.free(string_2);

    try std.testing.expectEqualSlices(u8, "I can format with my String", string_2);
}

test "UTF-8 multi-byte insertion" {
    const gpa = testing.allocator;
    var s = try String.from(gpa, "A!");
    defer s.deinit(gpa);

    // Insert a 2-byte UTF-8 character at index 1
    try s.insert(gpa, 1, "Œ");
    try std.testing.expectEqualSlices(u8, "AŒ!", s.str);
}

test "Insert at beginning and end" {
    const gpa = testing.allocator;
    var s = try String.from(gpa, "middle");
    defer s.deinit(gpa);

    try s.insert(gpa, 0, "start-");
    try s.insert(gpa, s.len(), "-end");
    try std.testing.expectEqualSlices(u8, "start-middle-end", s.str);
}

test "Insert out-of-bounds error" {
    const gpa = testing.allocator;
    var s = try String.from(gpa, "test");
    defer s.deinit(gpa);

    try std.testing.expectError(StringError.IndexOutOfBounds, s.insert(gpa, 5, "!"));
}

test "Uppercase with mixed Unicode" {
    const gpa = testing.allocator;
    var s = try String.from(gpa, "hello 世界");
    defer s.deinit(gpa);

    s.uppercase();
    try std.testing.expectEqualSlices(u8, "HELLO 世界", s.str);
}

test "Lowercase with mixed Unicode" {
    const gpa = testing.allocator;
    var s = try String.from(gpa, "HELLO 世界");
    defer s.deinit(gpa);

    s.lowercase();
    try std.testing.expectEqualSlices(u8, "hello 世界", s.str);
}

test "Capitalize first ASCII character only" {
    const gpa = testing.allocator;
    var s = try String.from(gpa, "éhello world");
    defer s.deinit(gpa);

    s.capitalize();
    // first ASCII alphabetic character is 'h', so 'h' -> 'H'
    try std.testing.expectEqualSlices(u8, "éHello world", s.str);
}

test "Trim with Unicode and spaces" {
    const gpa = testing.allocator;
    var s = try String.from(gpa, " \t 世界 hello \n ");
    defer s.deinit(gpa);

    try s.trim(gpa);
    try std.testing.expectEqualSlices(u8, "世界 hello", s.str);
}

test "StringBuilder multiple operations" {
    const gpa = testing.allocator;
    var s = try String.from(gpa, "abc");
    defer s.deinit(gpa);

    var builder = s.builder();
    const new_s = try builder.uppercase().append("XYZ").prepend("123").build(gpa);
    defer new_s.deinit(gpa);

    try std.testing.expectEqualSlices(u8, "123ABCXYZ", new_s.str);
}

test "IndexOf and IndexOfIgnoreCase Unicode" {
    const gpa = testing.allocator;
    var s = try String.from(gpa, "hello 世界");
    defer s.deinit(gpa);

    try std.testing.expectEqual(null, s.indexOf("X"));
    try std.testing.expectEqual(0, s.indexOfIgnoreCase("H"));
    try std.testing.expectEqual(6, s.indexOf("世"));
}

test "Unicode charAt and unicodeCharAt consistency" {
    const gpa = testing.allocator;
    var s = try String.from(gpa, "AŒB");
    defer s.deinit(gpa);

    try std.testing.expectEqual('A', s.byteAt(0).?);
    try std.testing.expectEqualStrings("Œ", s.charAt(1).?);
    try std.testing.expectEqual('B', s.byteAt(3).?);
}

test "String remove with ASCII, multi-byte, and emoji" {
    const gpa = std.testing.allocator;

    // Case 1: Remove single ASCII character
    {
        var s = try String.from(gpa, "Hello");
        defer s.deinit(gpa);

        try s.remove(gpa, 1, 1); // remove 'e'
        try std.testing.expectEqualSlices(u8, "Hllo", s.str);
    }

    // Case 2: Remove multiple ASCII characters
    {
        var s = try String.from(gpa, "Hello, World!");
        defer s.deinit(gpa);

        try s.remove(gpa, 5, 2); // remove ", "
        try std.testing.expectEqualSlices(u8, "HelloWorld!", s.str);
    }

    // Case 3: Remove multi-byte character (é)
    {
        var s = try String.from(gpa, "Café");
        defer s.deinit(gpa);

        try s.remove(gpa, 3, 1); // remove 'é'
        try std.testing.expectEqualSlices(u8, "Caf", s.str);
    }

    // Case 4: Remove emoji (😀)
    {
        var s = try String.from(gpa, "Hi 😀!");
        defer s.deinit(gpa);

        try s.remove(gpa, 3, 1); // remove emoji
        try std.testing.expectEqualSlices(u8, "Hi !", s.str);
    }

    // Case 5: Remove range including multi-byte + ASCII
    {
        var s = try String.from(gpa, "AéB");
        defer s.deinit(gpa);

        try s.remove(gpa, 0, 2); // remove 'Aé'
        try std.testing.expectEqualSlices(u8, "B", s.str);
    }

    // Case 6: Remove from start to end (clear string)
    {
        var s = try String.from(gpa, "Clear me");
        defer s.deinit(gpa);

        try s.remove(gpa, 0, s.len());
        try std.testing.expectEqualSlices(u8, "", s.str);
    }

    // Case 7: Remove single emoji at the start
    {
        var s = try String.from(gpa, "😀Hello");
        defer s.deinit(gpa);

        try s.remove(gpa, 0, 1);
        try std.testing.expectEqualSlices(u8, "Hello", s.str);
    }

    // Case 8: Remove multiple emojis
    {
        var s = try String.from(gpa, "😀😁😂");
        defer s.deinit(gpa);

        try s.remove(gpa, 1, 2); // remove last two emojis
        try std.testing.expectEqualSlices(u8, "😀", s.str);
    }

    // Case 9: Remove last character
    {
        var s = try String.from(gpa, "End!");
        defer s.deinit(gpa);

        try s.remove(gpa, 3, 1);
        try std.testing.expectEqualSlices(u8, "End", s.str);
    }

    // Case 10: Remove middle emoji in text
    {
        var s = try String.from(gpa, "A😀B");
        defer s.deinit(gpa);

        try s.remove(gpa, 1, 1);
        try std.testing.expectEqualSlices(u8, "AB", s.str);
    }
}

test "remove fails for end_index beyond string length" {
    const gpa = testing.allocator;
    var s = try String.from(gpa, "Hello");
    defer s.deinit(gpa);

    try std.testing.expectError(StringError.IndexOutOfBounds, s.remove(gpa, 2, 10));
}

test "remove fails for start_index beyond string length" {
    const gpa = testing.allocator;
    var s = try String.from(gpa, "World");
    defer s.deinit(gpa);

    try std.testing.expectError(StringError.IndexOutOfBounds, s.remove(gpa, 6, 1));
}

test "indexOf with ASCII, emoji, and Kanji" {
    const gpa = testing.allocator;

    var s = try String.from(gpa, "Hello 😀 世界");
    defer s.deinit(gpa);

    // ASCII
    try std.testing.expectEqual(0, s.indexOf("H"));
    try std.testing.expectEqual(1, s.indexOf("e"));
    try std.testing.expectEqual(0, s.indexOf("He"));
    try std.testing.expectEqual(2, s.indexOf("llo"));

    // Emoji (😀)
    try std.testing.expectEqual(6, s.indexOf("😀"));

    // Kanji (世界)
    try std.testing.expectEqual(8, s.indexOf("世"));
    try std.testing.expectEqual(9, s.indexOf("界"));

    // Not found
    try std.testing.expectEqual(null, s.indexOf("😎"));
    try std.testing.expectEqual(null, s.indexOf("不存在"));
}

test "indexOfIgnoreCase with ASCII" {
    const gpa = testing.allocator;

    var s = try String.from(gpa, "HeLLo World");
    defer s.deinit(gpa);

    try std.testing.expectEqual(0, s.indexOfIgnoreCase("h"));
    try std.testing.expectEqual(1, s.indexOfIgnoreCase("e"));
    try std.testing.expectEqual(2, s.indexOfIgnoreCase("lL"));
    try std.testing.expectEqual(6, s.indexOfIgnoreCase("world"));

    // Not found
    try std.testing.expectEqual(null, s.indexOfIgnoreCase("planet"));
}

test "indexOfIgnoreCase with emoji and Kanji" {
    const gpa = testing.allocator;

    var s = try String.from(gpa, "a😀B世界c");
    defer s.deinit(gpa);

    // Emoji and Kanji are not case-sensitive, so exact match only
    try std.testing.expectEqual(1, s.indexOfIgnoreCase("😀"));
    try std.testing.expectEqual(3, s.indexOfIgnoreCase("世"));
    try std.testing.expectEqual(4, s.indexOfIgnoreCase("界"));

    // Not found
    try std.testing.expectEqual(null, s.indexOfIgnoreCase("😎"));
}

test "indexOf with Latin-1 characters" {
    const gpa = testing.allocator;

    var s = try String.from(gpa, "Café Noël à côté");
    defer s.deinit(gpa);

    // ASCII
    try std.testing.expectEqual(0, s.indexOf("C"));
    try std.testing.expectEqual(1, s.indexOf("a"));

    // Latin-1 accented letters
    try std.testing.expectEqual(3, s.indexOf("é")); // 'Café'
    try std.testing.expectEqual(5, s.indexOf("Noë")); // 'Noël'
    try std.testing.expectEqual(7, s.indexOf("ë")); // 'Noël'
    try std.testing.expectEqual(10, s.indexOf("à")); // 'à'

    // Not found
    try std.testing.expectEqual(null, s.indexOf("ü"));
}

test "contains" {
    const gpa = testing.allocator;

    var s = try String.from(gpa, "Café Noël à côté 🌍");
    defer s.deinit(gpa);

    try std.testing.expect(s.contains("C", false));
    try std.testing.expect(s.contains("n", true));
    try std.testing.expect(s.contains("Café", false));
    try std.testing.expect(s.contains("côté", false));
    try std.testing.expect(s.contains("🌍", false));
    try std.testing.expect(!s.contains("Hello", false));
}

test "start width and ends with" {
    const gpa = testing.allocator;

    var s = try String.from(gpa, "Café Noël à côté 🌍");
    defer s.deinit(gpa);

    try std.testing.expect(s.startsWith("C"));
    try std.testing.expect(!s.startsWith("🌍"));
    try std.testing.expect(s.endsWith("🌍"));

    try s.prepend(gpa, "🌍");
    try std.testing.expect(s.startsWith("🌍"));
    try std.testing.expect(!s.startsWith("C"));
}

test "substring" {
    const gpa = testing.allocator;

    var s = try String.from(gpa, "Café Noël à côté 🌍");
    defer s.deinit(gpa);

    {
        var sub_str = try s.substring(gpa, 0, 4);
        defer sub_str.deinit(gpa);
        try std.testing.expectEqualStrings("Café", sub_str.str);
        try std.testing.expectEqual(5, sub_str.str.len);
    }
    {
        var sub_str = try s.substring(gpa, s.len() - 1, 1);
        defer sub_str.deinit(gpa);
        try std.testing.expectEqualStrings("🌍", sub_str.str);
        try std.testing.expectEqual(4, sub_str.str.len);
    }
    {
        var sub_str = try s.substring(gpa, 10, 1);
        defer sub_str.deinit(gpa);
        try std.testing.expectEqualStrings("à", sub_str.str);
        try std.testing.expectEqual(2, sub_str.str.len);
    }
}

test "reverse" {
    const gpa = testing.allocator;

    {
        var s = try String.from(gpa, "🌍è$@#ùà°ç:_éPé");
        defer s.deinit(gpa);
        try s.reverse(gpa);
        try std.testing.expectEqualStrings("éPé_:ç°àù#@$è🌍", s.str);
    }

    {
        var s = try String.from(gpa, "Lorem🌍ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.");
        defer s.deinit(gpa);
        try s.reverse(gpa);
        try std.testing.expectEqualStrings(".murobal tse di mina tillom tnuresed aiciffo iuq apluc ni tnus ,tnediorp non tatadipuc taceacco tnis ruetpecxE .rutairap allun taiguf ue erolod mullic esse tilev etatpulov ni tiredneherper ni rolod eruri etua siuD .tauqesnoc odommoc ae xe piuqila tu isin sirobal ocmallu noitaticrexe durtson siuq ,mainev minim da mine tU .auqila angam erolod te erobal tu tnudidicni ropmet domsuie od des ,tile gnicsipida rutetcesnoc ,tema tis rolod muspi🌍meroL", s.str);
    }
}
