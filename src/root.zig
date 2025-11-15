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
        self.ops[self.idx] = Op.trim;
        self.idx += 1;
        return self;
    }

    pub fn uppercase(self: *Self) *Self {
        self.ops[self.idx] = Op.uppercase;
        self.idx += 1;
        return self;
    }

    pub fn lowercase(self: *Self) *Self {
        self.ops[self.idx] = Op.lowercase;
        self.idx += 1;
        return self;
    }

    pub fn capitalize(self: *Self) *Self {
        self.ops[self.idx] = Op.capitalize;
        self.idx += 1;
        return self;
    }

    pub fn append(self: *Self, str: []const u8) *Self {
        self.ops[self.idx] = .{ .append = str };
        self.idx += 1;
        return self;
    }

    pub fn prepend(self: *Self, str: []const u8) *Self {
        self.ops[self.idx] = .{ .prepend = str };
        self.idx += 1;
        return self;
    }

    pub fn insert(self: *Self, index: usize, str: []const u8) *Self {
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

    /// Given the first byte of a UTF-8 codepoint,
    /// returns a number 1-4 indicating the total length of the codepoint in bytes.
    /// If this byte does not match the form of a UTF-8 start byte, returns Utf8InvalidStartByte.
    inline fn utf8Size(char: u8) u3 {
        return std.unicode.utf8ByteSequenceLength(char) catch 1;
    }

    pub fn len(self: String) usize {
        var size: usize = 0;
        var i: usize = 0;
        while (i < self.str.len) {
            size += 1;
            i += utf8Size(self.str[i]);
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
        var i: usize = 0;
        while (i < self.str.len) : (i += utf8Size(self.str[i])) {
            const c = self.str[i];
            self.str[i] = std.ascii.toUpper(c);
        }
    }

    pub fn lowercase(self: *Self) void {
        var i: usize = 0;
        while (i < self.str.len) : (i += utf8Size(self.str[i])) {
            const c = self.str[i];
            self.str[i] = std.ascii.toLower(c);
        }
    }

    pub fn capitalize(self: *Self) void {
        var i: usize = 0;
        while (i < self.str.len) : (i += utf8Size(self.str[i])) {
            const c = self.str[i];
            if (std.ascii.isAlphabetic(c)) {
                self.str[i] = std.ascii.toUpper(c);
                break;
            }
        }
    }

    pub fn append(self: *Self, gpa: mem.Allocator, str: []const u8) !void {
        try self.insert(gpa, self.str.len, str);
    }

    pub fn prepend(self: *Self, gpa: mem.Allocator, str: []const u8) !void {
        try self.insert(gpa, 0, str);
    }

    pub fn insert(self: *Self, gpa: mem.Allocator, index: usize, str: []const u8) !void {
        if (index > self.str.len) {
            return StringError.IndexOutOfBounds;
        }

        var new_str = try gpa.alloc(u8, self.str.len + str.len);

        if (index > 0) @memcpy(new_str[0..index], self.str[0..index]);
        @memcpy(new_str[index + str.len ..], self.str[index..]);
        if (index <= self.str.len) @memcpy(new_str[index .. index + str.len], str);

        gpa.free(self.str);
        self.str = new_str;
    }

    // UTF-8
    pub fn charAt(self: *Self, index: usize) ?u8 {
        if (index > self.str.len) {
            return null;
        }
        return self.str[index];
    }

    // Unicode
    pub fn unicodeCharAt(self: *Self, index: usize) ?[]const u8 {
        if (index > self.len()) {
            return null;
        }
        var i: usize = 0;
        var unicode_index: usize = 0;
        while (i < self.str.len) : (i += utf8Size(self.str[i])) {
            if (unicode_index == index) break;
            unicode_index += 1;
        }
        const char_size = utf8Size(self.str[i]);
        return self.str[i..(i + char_size)];
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
        const neeldle_len = needle.len;
        const haystack_len = haystack.len;

        if (neeldle_len > haystack_len) {
            return null;
        }

        for (0..haystack_len - neeldle_len + 1) |i| {
            if (compare(haystack[i], needle[0])) {
                var j: usize = 1;
                while (j < neeldle_len and (i + j) < haystack_len and compare(needle[j], haystack[i + j])) {
                    j += 1;
                }
                if (j == neeldle_len) {
                    return i;
                }
            }
        }

        return null;
    }

    pub fn builder(self: Self) StringBuilder {
        return StringBuilder{ .str = self.str };
    }

    pub fn deinit(self: Self, gpa: mem.Allocator) void {
        gpa.free(self.str);
    }

    pub fn format(self: Self, writer: *std.Io.Writer) !void {
        try writer.print("{s}", .{self.str});
    }
};

pub fn FixedString(comptime max_size: usize) type {
    return struct {
        const Self = @This();

        var buffer: [max_size]u8 = undefined;
        var gpa = std.heap.FixedBufferAllocator.init(buffer[0..]);

        string: String,

        /// Create an empty a String
        pub fn empty() Self {
            return .{
                .string = String.empty(),
            };
        }

        /// Create and inizialize a String
        pub fn from(initStr: []const u8) !Self {
            return .{
                .string = try String.from(gpa.allocator(), initStr),
            };
        }

        /// Remove empty spaces at the start and at the end.
        /// Invalidates str if less memory is needed.
        pub fn trim(self: *Self) !void {
            try self.string.trim(gpa.allocator());
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
            try self.string.append(gpa.allocator(), str);
        }

        pub fn prepend(self: *Self, str: []const u8) !void {
            try self.string.prepend(gpa.allocator(), str);
        }

        pub fn insert(self: *Self, index: usize, str: []const u8) !void {
            try self.insert(gpa.allocator(), index, str);
        }

        pub fn deinit(self: Self) void {
            self.string.deinit(gpa.allocator());
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

    try std.testing.expectEqual('h', s.charAt(0).?);
    try std.testing.expectEqual('\xE4', s.charAt(7).?);

    try std.testing.expectEqualStrings("h", s.unicodeCharAt(0).?);
    try std.testing.expectEqualStrings("世", s.unicodeCharAt(7).?);
    try std.testing.expectEqualStrings("界", s.unicodeCharAt(8).?);
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
        const string_1 = try String.from(gpa, "sŒoME StrinG!");
        defer string_1.deinit(gpa);

        var builder = string_1.builder();
        const string_2 = try builder.trim().lowercase().capitalize().append(" ANOTHER STRING ").build(gpa);
        defer string_2.deinit(gpa);

        try std.testing.expectEqualSlices(u8, "SŒome string! ANOTHER STRING ", string_2.str);
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
