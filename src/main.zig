const std = @import("std");
const Strings = @import("String_lib");
const String = Strings.String;

pub fn main() !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = allocator.allocator();

    try ex1(gpa);
    // try ex2(gpa);
    // try ex3();
    try ex4(gpa);
}

pub fn ex1(gpa: std.mem.Allocator) !void {
    var s: String = try String.from(gpa, "  HELLO,WORLD!  \n");
    defer s.deinit(gpa);

    try s.trim(gpa);
    s.lowercase();
    try s.insert(gpa, 6, " ");
    s.capitalize();
    std.debug.print("{f}", .{s});
}

pub fn ex2(gpa: std.mem.Allocator) !void {
    var s: String = String.empty();
    defer s.deinit(gpa);

    // var builder = s.builder();
    // var new_string = try builder.append(" World!\n").insert(0, "hello").capitalize().insert(5, ",").build(gpa);
    // defer new_string.deinit(gpa);

    // std.debug.print("{f}", .{new_string});
}

pub fn ex3() !void {
    const Fixed: type = Strings.FixedString(1024);
    var s = Fixed.empty();

    try s.append("Hello,");
    try s.append(" World!\n");

    std.debug.print("{f}", .{s});
}

pub fn ex4(gpa: std.mem.Allocator) !void {
    var s: String = try String.from(gpa, "Hello,𒀀 🌍!\n");
    defer s.deinit(gpa);

    for (0..s.len()) |i| {
        std.debug.print("{s}", .{s.unicodeCharAt(i).?});
    }

    std.debug.print("{f}", .{s});
}
