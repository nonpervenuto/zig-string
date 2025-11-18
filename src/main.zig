const std = @import("std");
const Strings = @import("String_lib");
const String = Strings.String;

pub fn main() !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = allocator.allocator();

    var s = try String.empty(gpa);
    defer s.deinit(gpa);

    var builder = Strings.StringBuilder.init("000");
    const s1: String = try builder.append(".zig").build(gpa);

    std.debug.print("{f}\n", .{s1});
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
