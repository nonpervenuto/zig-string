## Another Zig String Library

My personal exercise project to learn zig and to handle strings more easily with UTF-8 support. Still a work in progress.

### Basic
```zig
const std = @import("std");
const strings = @import("strings");
const String = strings.String;

pub fn main() !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = allocator.allocator();

    var s = try String.empty(gpa);
    s.deinit(gpa);

    try s.append(gpa, "Hello, ");
    try s.append(gpa, "World!");

    std.debug.print("{f}\n", .{s});
}
```

### Unicode support
```zig
var s = try String.from(gpa, "Hello, 🌍!\n");
defer s.deinit(gpa);

for (0..s.len()) |i| {
    std.debug.print("{s}", .{s.charAt(i).?});
}
```

### Manipulation
```zig
var s: String = try String.from(gpa, "  !dlro,olleH  ");
defer s.deinit(gpa);

try s.trim(gpa);
try s.reverse(gpa);
s.lowercase();
try s.insert(gpa, 6, " W");
s.capitalize();

std.debug.print("{f}\n", .{s});
```

### Builder
```zig
var s: String = try String.empty(gpa);
defer s.deinit(gpa);

var builder = s.builder();
var new_string = try builder.append(" World!\n").insert(0, "hello").capitalize().insert(5, ",").build(gpa);
defer new_string.deinit(gpa);

std.debug.print("{f}", .{new_string});
```

### Managed version
```zig
var fb: [1024]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&fb);
const alloc: std.mem.Allocator = fba.allocator();

var s = try strings.ManagedString.empty(alloc);
defer s.deinit();

try s.append("Hello,");
try s.append(" World!\n");

std.debug.print("{f}", .{s});
```

