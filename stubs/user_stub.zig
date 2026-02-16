//! No-op user commands stub.
//! Used when no custom Zig module is provided via -Duser-zig.

const silk = @import("silk");

pub fn setup(_: *silk.Router) void {}
