const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const StringError = error{
    IndexOutOfBounds,
};

const OpFn = enum { trim, uppercase, lowercase, capitalize, append, prepend, insert };

const Op = union(OpFn) {
    trim: void,
    uppercase: void,
    lowercase: void,
    capitalize: void,
    append: []const u8,
    prepend: []const u8,
    insert: struct { index: usize, str: []const u8 },
};

pub const StringBuilder = struct {
    const Self = @This();

    str: []const u8,
    ops: [255]Op = undefined,
    idx: usize = 0,

    pub fn trim(self: *Self) *Self {
        if (self.idx >= self.ops.len) @panic("StringBuilder ops overflow");
        self.ops[self.idx] = Op.trim;
        self.idx += 1;
        return self;
    }

    pub fn uppercase(self: *Self) *Self {
        if (self.idx >= self.ops.len) @panic("StringBuilder ops overflow");
        self.ops[self.idx] = Op.uppercase;
        self.idx += 1;
        return self;
    }

    pub fn lowercase(self: *Self) *Self {
        if (self.idx >= self.ops.len) @panic("StringBuilder ops overflow");
        self.ops[self.idx] = Op.lowercase;
        self.idx += 1;
        return self;
    }

    pub fn capitalize(self: *Self) *Self {
        if (self.idx >= self.ops.len) @panic("StringBuilder ops overflow");
        self.ops[self.idx] = Op.capitalize;
        self.idx += 1;
        return self;
    }

    pub fn append(self: *Self, str: []const u8) *Self {
        if (self.idx >= self.ops.len) @panic("StringBuilder ops overflow");
        self.ops[self.idx] = .{ .append = str };
        self.idx += 1;
        return self;
    }

    pub fn prepend(self: *Self, str: []const u8) *Self {
        if (self.idx >= self.ops.len) @panic("StringBuilder ops overflow");
        self.ops[self.idx] = .{ .prepend = str };
        self.idx += 1;
        return self;
    }

    pub fn insert(self: *Self, index: usize, str: []const u8) *Self {
        if (self.idx >= self.ops.len) @panic("StringBuilder ops overflow");
        self.ops[self.idx] = .{ .insert = .{ .index = index, .str = str } };
        self.idx += 1;
        return self;
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
    byte_index: usize, // index in buffer
    char_index: usize, // index in chars
    char_len: u3, // number of bytes for this character
    slice: []const u8, // the bytes of the character
};

const Utf8Iter = struct {
    str: []const u8,
    byte_index: usize = 0,
    char_index: usize = 0,

    pub fn init(s: []const u8) Utf8Iter {
        return Utf8Iter{
            .str = s,
            .byte_index = 0,
            .char_index = 0,
        };
    }

    /// Returns true if there is a next character
    pub fn next(self: *Utf8Iter) ?Utf8 {
        if (self.byte_index >= self.str.len) return null;

        const start = self.byte_index;

        // TODO: unreachable because the input is already validated?
        const len = utf8Size(self.str[start]) catch unreachable;
        const slice = self.str[start .. start + len];

        const result = Utf8{
            .byte_index = start,
            .char_index = self.char_index,
            .char_len = len,
            .slice = slice,
        };

        self.byte_index += len;
        self.char_index += 1;
        return result;
    }
};

pub const String = struct {
    const Self = @This();

    // A chunck of memory heap allocated
    str: []u8,

    /// Create an empty a String
    pub fn empty() Self {
        return String{
            .str = &.{},
        };
    }

    /// Create and inizialize a String
    pub fn from(gpa: mem.Allocator, initStr: []const u8) !Self {
        const str = try gpa.alloc(u8, initStr.len);
        @memcpy(str, initStr);
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

    pub fn uppercase(self: *Self) void {
        var iter = Utf8Iter.init(self.str);
        while (iter.next()) |c| {
            const i = c.byte_index;
            self.str[i] = std.ascii.toUpper(self.str[i]);
        }
    }

    pub fn lowercase(self: *Self) void {
        var iter = Utf8Iter.init(self.str);
        while (iter.next()) |c| {
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
        const end_index = self.len();

        if (index == 0) {
            // prepend
            var new_str = try gpa.alloc(u8, self.str.len + str.len);
            errdefer gpa.free(new_str);

            @memcpy(new_str[0..str.len], str);
            @memcpy(new_str[str.len..], self.str);
            if (self.str.len != 0) gpa.free(self.str);
            self.str = new_str;
            return;
        } else if (index == end_index) {
            // append
            var new_str = try gpa.alloc(u8, self.str.len + str.len);
            errdefer gpa.free(new_str);

            if (self.str.len != 0) @memcpy(new_str[0..self.str.len], self.str);
            @memcpy(new_str[self.str.len..], str);
            if (self.str.len != 0) gpa.free(self.str);
            self.str = new_str;
            return;
        } else if (index > end_index) {
            // error
            return StringError.IndexOutOfBounds;
        }

        // Index is in the middle
        const byte_index = try bufferIndex(self.str, 0, 0, index);

        var new_str = try gpa.alloc(u8, self.str.len + str.len);
        errdefer gpa.free(new_str);

        if (byte_index > 0) @memcpy(new_str[0..byte_index], self.str[0..byte_index]);
        @memcpy(new_str[byte_index + str.len ..], self.str[byte_index..]);
        if (byte_index <= self.str.len) @memcpy(new_str[byte_index .. byte_index + str.len], str);

        gpa.free(self.str);
        self.str = new_str;
    }

    pub fn remove(self: *Self, gpa: mem.Allocator, start_index: usize, end_index: usize) !void {
        const str_len = self.len();
        if (start_index > end_index or end_index > str_len) {
            return StringError.IndexOutOfBounds;
        }

        // Nothing to remove
        if (start_index == end_index) return;

        const start_byte = try bufferIndex(self.str, 0, 0, start_index);
        const end_byte = try bufferIndex(self.str, start_byte, start_index, end_index);

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
    // TODO: implement UTF-8 safe substring check
    pub fn contains(self: *Self, needle: []const u8) bool {
        _ = self;
        _ = needle;
        return false;
    }

    /// Returns true if the string starts with the given substring
    // TODO: implement UTF-8 safe prefix check
    pub fn startsWith(self: *Self, prefix: []const u8) bool {
        _ = self;
        _ = prefix;
        return false;
    }

    /// Returns true if the string ends with the given substring
    // TODO: implement UTF-8 safe suffix check
    pub fn endsWith(self: *Self, suffix: []const u8) bool {
        _ = self;
        _ = suffix;
        return false;
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

    /// Returns a substring from start (inclusive) to end (exclusive) indices
    // TODO: slice the string safely by UTF-8 character indices
    pub fn substring(self: *Self, start: usize, end: usize) !Self {
        _ = self;
        _ = start;
        _ = end;
    }

    /// Reverses the string by UTF-8 characters
    // TODO: reverse the string while respecting UTF-8 codepoints
    pub fn reverse(self: *Self, gpa: mem.Allocator) !void {
        _ = self;
        _ = gpa;
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

    /// Trims whitespace only from the start
    // TODO: trim leading whitespace UTF-8 aware
    pub fn trimStart(self: *Self, gpa: mem.Allocator) !void {
        _ = self;
        _ = gpa;
    }

    /// Trims whitespace only from the end
    // TODO: trim trailing whitespace UTF-8 aware
    pub fn trimEnd(self: *Self, gpa: mem.Allocator) !void {
        _ = self;
        _ = gpa;
    }

    /// Returns true if the string is empty
    pub fn isEmpty(self: *Self) bool {
        return self.len() == 0;
    }

    /// Converts string to ASCII only (drops non-ASCII characters)
    // TODO: create ASCII-only version, drop or replace non-ASCII
    pub fn toAscii(self: *Self, gpa: mem.Allocator) !void {
        _ = self;
        _ = gpa;
    }

    /// Iterates over each UTF-8 character, calling the callback
    // pub fn forEachChar(self: *Self, callback: fn ([]const u8) void) void {
    // }

    /// Maps each UTF-8 character into a new string
    // pub fn map(self: *Self, gpa: mem.Allocator, callback: fn ([]const u8) []const u8) !Self {
    // return Self{ .str = &.{} };
    // }

    pub fn builder(self: Self) StringBuilder {
        return StringBuilder{ .str = self.str };
    }

    pub fn deinit(self: Self, gpa: mem.Allocator) void {
        // If the slice has length 0 we assume it's the static empty slice and do not free.
        // (If you ever allocate a true zero-length buffer, this will leak it.)
        if (self.str.len == 0) return;
        gpa.free(self.str);
    }

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("{s}", .{self.str});
    }
};

pub fn FixedString(comptime max_size: usize) type {
    return struct {
        const Self = @This();

        buffer: [max_size]u8 = undefined,
        gpa: std.heap.FixedBufferAllocator = undefined,
        string: String = undefined,

        /// Create an empty a String
        pub fn empty() Self {
            var inst: Self = .{};
            inst.gpa = std.heap.FixedBufferAllocator.init(inst.buffer[0..]);
            inst.string = String.from(inst.gpa.allocator(), "") catch unreachable;
            return inst;
        }

        /// Create and inizialize a String
        pub fn from(initStr: []const u8) !Self {
            var inst: Self = .{};
            inst.gpa = std.heap.FixedBufferAllocator.init(inst.buffer[0..]);
            inst.string = try String.from(inst.gpa.allocator(), initStr);
            return inst;
        }

        /// Remove empty spaces at the start and at the end.
        /// Invalidates str if less memory is needed.
        pub fn trim(self: *Self) !void {
            try self.string.trim(self.gpa.allocator());
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
            try self.string.append(self.gpa.allocator(), str);
        }

        pub fn prepend(self: *Self, str: []const u8) !void {
            try self.string.prepend(self.gpa.allocator(), str);
        }

        pub fn insert(self: *Self, index: usize, str: []const u8) !void {
            try self.string.insert(self.gpa.allocator(), index, str);
        }

        pub fn deinit(self: Self) void {
            self.string.deinit(self.gpa.allocator());
        }

        pub fn format(self: Self, writer: *std.Io.Writer) !void {
            try writer.print("{f}", .{self.string});
        }
    };
}

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
    {
        var string_1 = try FixedString(1024).from("Hello");
        try string_1.append(", 世界");
        try std.testing.expectEqualSlices(u8, "Hello, 世界", string_1.string.str);
    }

    {
        var string_1 = FixedString(1024).empty();
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
        var string_1 = String.empty();
        defer string_1.deinit(gpa);
        try string_1.trim(gpa);
        try std.testing.expectEqualSlices(u8, "", string_1.str);
    }

    {
        var string_1 = String.empty();
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

        try s.remove(gpa, 1, 2); // remove 'e'
        try std.testing.expectEqualSlices(u8, "Hllo", s.str);
    }

    // Case 2: Remove multiple ASCII characters
    {
        var s = try String.from(gpa, "Hello, World!");
        defer s.deinit(gpa);

        try s.remove(gpa, 5, 7); // remove ", "
        try std.testing.expectEqualSlices(u8, "HelloWorld!", s.str);
    }

    // Case 3: Remove multi-byte character (é)
    {
        var s = try String.from(gpa, "Café");
        defer s.deinit(gpa);

        try s.remove(gpa, 3, 4); // remove 'é'
        try std.testing.expectEqualSlices(u8, "Caf", s.str);
    }

    // Case 4: Remove emoji (😀)
    {
        var s = try String.from(gpa, "Hi 😀!");
        defer s.deinit(gpa);

        try s.remove(gpa, 3, 4); // remove emoji
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

        try s.remove(gpa, 1, 3); // remove last two emojis
        try std.testing.expectEqualSlices(u8, "😀", s.str);
    }

    // Case 9: Remove last character
    {
        var s = try String.from(gpa, "End!");
        defer s.deinit(gpa);

        try s.remove(gpa, 3, 4);
        try std.testing.expectEqualSlices(u8, "End", s.str);
    }

    // Case 10: Remove middle emoji in text
    {
        var s = try String.from(gpa, "A😀B");
        defer s.deinit(gpa);

        try s.remove(gpa, 1, 2);
        try std.testing.expectEqualSlices(u8, "AB", s.str);
    }
}

test "remove fails for start_index > end_index" {
    const gpa = testing.allocator;
    var s = try String.from(gpa, "Hello");
    defer s.deinit(gpa);

    try std.testing.expectError(StringError.IndexOutOfBounds, s.remove(gpa, 3, 2));
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

    try std.testing.expectError(StringError.IndexOutOfBounds, s.remove(gpa, 6, 7));
}

test "remove fails for negative range simulation (start > end)" {
    // Zig usize cannot be negative, but testing logical error
    const gpa = testing.allocator;
    var s = try String.from(gpa, "Zig");
    defer s.deinit(gpa);

    try std.testing.expectError(StringError.IndexOutOfBounds, s.remove(gpa, 2, 1));
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
    try std.testing.expectEqual(5, s.indexOf("N")); // 'Noël'
    try std.testing.expectEqual(7, s.indexOf("ë")); // 'Noël'
    try std.testing.expectEqual(10, s.indexOf("à")); // 'à'

    // Not found
    try std.testing.expectEqual(null, s.indexOf("ü"));
}
