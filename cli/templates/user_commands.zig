const std = @import("std");
const silk = @import("silk");

pub fn register(host: *silk.Host) !void {
    try host.register("user:greet", greet);
}

fn greet(_: *anyopaque, args: std.json.Value) !std.json.Value {
    const obj = try silk.expectObject(args);
    _ = try silk.getOptionalString(obj, "name");
    return .{ .string = "hello from user:greet" };
}
