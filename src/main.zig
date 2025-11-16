const std = @import("std");
const Strings = @import("String_lib");
const String = Strings.String;

pub fn main() !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = allocator.allocator();

    try ex1(gpa);
    // try ex2(gpa);
    try ex3();
    // try ex4(gpa);

    try ex5(gpa);
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
    var s: String = try String.from(gpa, "cioè\n");
    defer s.deinit(gpa);

    for (0..s.len()) |i| {
        std.debug.print("{s}", .{s.charAt(i).?});
    }
}

fn ex5(gpa: std.mem.Allocator) !void {
    const file = try std.fs.createFileAbsolute("/tmp/file.txt", .{});

    var s: String = try String.from(gpa, "すありが");
    defer s.deinit(gpa);
    try s.insert(gpa, 2, "--ありがとうございま--");

    try file.writeAll(s.str);
    file.close();

    const file_handle = try std.fs.cwd().openFile("/tmp/file.txt", .{});
    defer file_handle.close();

    // read file contents

    var threaded: std.Io.Threaded = .init_single_threaded;
    var file_reader = file_handle.reader(threaded.io(), &.{});
    const file_buf = try file_reader.interface.allocRemaining(gpa, .unlimited);

    var s1: String = String.fromOwned(file_buf);
    defer s1.deinit(gpa);

    std.debug.print("{f}", .{s1});
}
