const ipc = @import("../ipc/router.zig");

const builtins = @import("../commands/builtin.zig");
const app = @import("app.zig");
const window = @import("window.zig");
const fs = @import("fs.zig");
const shell = @import("shell.zig");
const dialog = @import("dialog.zig");
const clipboard = @import("clipboard.zig");

pub fn registerAll(router: *ipc.Router) !void {
    try builtins.register(router);
    try app.register(router);
    try window.register(router);
    try fs.register(router);
    try shell.register(router);
    try dialog.register(router);
    try clipboard.register(router);
}
