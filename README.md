## Another Zig String Library

My personal exercise project to learn zig and to handle strings more easily with some UTF-8 support. Still a work in progress.

### Basic
```zig
const std = @import("std");
const Strings = @import("String_lib");
const String = Strings.String;

pub fn main() !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = allocator.allocator();

    var s = String.empty();
    s.deinit(gpa);

    try s.append(gpa, "Hello, ");
    try s.append(gpa, "World!\n");

    std.debug.print("{f}", .{s});
}
```

### Unicode support
```zig
var s: String = try String.from(gpa, "Hello, 🌍!\n");
defer s.deinit(gpa);

for (0..s.len()) |i| {
  std.debug.print("{s}", .{s.unicodeCharAt(i).?});
}
std.debug.print("{f}", .{s});
```

### Manipulation
```zig
var s: String = try String.from(gpa, "  HELLO,WORLD!  ");
defer s.deinit(gpa);

try s.trim(gpa);
s.lowercase();
try s.insert(gpa, 6, " ");
s.capitalize();
std.debug.print("{f}", .{s});
```

### Builder
```zig
var s: String = String.empty();
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
const gpa: std.mem.Allocator = fba.allocator();

var s = Strings.ManagedString.empty(gpa);
defer s.deinit();

try s.append("Hello,");
try s.append(" World!\n");

std.debug.print("{f}", .{s});
```

