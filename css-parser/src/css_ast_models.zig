const std = @import("std");

// CSS Declaration property-value pair
pub const CssDeclaration = struct {
    property: []const u8,
    value: []const u8,
};

// CSS Rule types
pub const CssRuleType = enum {
    rule,
    media,
    page,
};

// CSS Rule (recursive structure, for a few rules types)
pub const CssRule = union(CssRuleType) {
    rule: struct {
        selector: []const u8,
        declarations: std.ArrayList(CssDeclaration),
    },
    media: struct {
        query: []const u8,
        rules: std.ArrayList(CssRule),
    },
    page: struct {
        rules: std.ArrayList(CssRule),
    },

    pub fn deinit(self: *CssRule, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .rule => |*r| {
                allocator.free(r.selector);
                r.declarations.deinit(allocator);
            },
            .media => |*m| {
                for (m.rules.items) |*rule| {
                    rule.deinit(allocator);
                }
                m.rules.deinit(allocator);
            },
            .page => |*p| {
                for (p.rules.items) |*rule| {
                    rule.deinit(allocator);
                }
                p.rules.deinit(allocator);
            },
        }
    }

    pub fn jsonStringify(self: @This(), jws: anytype) !void {
        try jws.beginObject();
        switch (self) {
            .rule => |r| {
                try jws.objectField("rule");
                try jws.beginObject();
                try jws.objectField("selector");
                try jws.write(r.selector);
                try jws.objectField("declarations");
                try jws.write(r.declarations.items);
                try jws.endObject();
            },
            .media => |m| {
                try jws.objectField("media");
                try jws.beginObject();
                try jws.objectField("query");
                try jws.write(m.query);
                try jws.objectField("rules");
                try jws.write(m.rules.items);
                try jws.endObject();
            },
            .page => |p| {
                try jws.objectField("page");
                try jws.beginObject();
                try jws.objectField("rules");
                try jws.write(p.rules.items);
                try jws.endObject();
            },
        }
        try jws.endObject();
    }
};

// Style AST for <style> tags
pub const StyleAst = struct {
    type: []const u8, // fixed value "stylesheet"
    rules: std.ArrayList(CssRule),

    pub fn deinit(self: *StyleAst, allocator: std.mem.Allocator) void {
        for (self.rules.items) |*rule| {
            rule.deinit(allocator);
        }
        self.rules.deinit(allocator);
    }

    pub fn jsonStringify(self: @This(), jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("type");
        try jws.write(self.type);
        try jws.objectField("rules");
        try jws.write(self.rules.items);
        try jws.endObject();
    }
};
