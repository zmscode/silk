//! Permission System
//!
//! Controls which IPC methods are allowed to execute. Supports:
//! - Broad permissions: `fs` grants access to all `fs:*` commands
//! - Granular permissions: `fs` with `.paths` restricts to specific directories
//! - Exact method permissions: `fs:read` grants only that one command
//!
//! Check order: exact method → namespace (prefix before `:`) → deny.

const std = @import("std");

/// What a permission grant allows.
pub const Scope = union(enum) {
    /// Unrestricted access.
    all,
    /// Restricted to specific filesystem paths.
    paths: []const []const u8,
    /// Restricted to specific subcommands.
    commands: []const []const u8,
};

pub const Permissions = struct {
    grants: std.StringHashMap(Scope),

    pub fn init(allocator: std.mem.Allocator) Permissions {
        return .{ .grants = std.StringHashMap(Scope).init(allocator) };
    }

    pub fn deinit(self: *Permissions) void {
        self.grants.deinit();
    }

    /// Grant a permission. `key` is either a namespace ("fs") or exact method ("fs:read").
    pub fn grant(self: *Permissions, key: []const u8, scope: Scope) !void {
        try self.grants.put(key, scope);
    }

    /// Revoke a permission.
    pub fn revoke(self: *Permissions, key: []const u8) void {
        _ = self.grants.remove(key);
    }

    /// Check if a method is permitted.
    ///
    /// 1. Exact match: look up the full method name (e.g. "fs:read")
    /// 2. Namespace match: extract prefix before ":" and look up (e.g. "fs")
    /// 3. Deny
    pub fn check(self: *const Permissions, method: []const u8) bool {
        // 1. Exact match
        if (self.grants.contains(method)) return true;

        // 2. Namespace match — extract prefix before ":"
        if (std.mem.indexOfScalar(u8, method, ':')) |colon_idx| {
            const namespace = method[0..colon_idx];
            if (self.grants.get(namespace)) |scope| {
                switch (scope) {
                    .all => return true,
                    .commands => |cmds| {
                        // Check if the specific subcommand is in the allowed list
                        const subcommand = method[colon_idx + 1 ..];
                        for (cmds) |allowed| {
                            if (std.mem.eql(u8, subcommand, allowed)) return true;
                        }
                        return false;
                    },
                    .paths => {
                        // Path-scoped permissions are checked at the handler level,
                        // not here. Granting "fs" with paths means the namespace is
                        // accessible — the handler enforces path restrictions.
                        return true;
                    },
                }
            }
        }

        // 3. Deny
        return false;
    }

    /// Get the scope for a permission key (for handlers that need to enforce path restrictions etc.)
    pub fn getScope(self: *const Permissions, key: []const u8) ?Scope {
        if (self.grants.get(key)) |scope| return scope;

        // Also check namespace
        if (std.mem.indexOfScalar(u8, key, ':')) |colon_idx| {
            const namespace = key[0..colon_idx];
            return self.grants.get(namespace);
        }

        return null;
    }
};
