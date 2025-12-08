const std = @import("std");
const css_ast_models = @import("css_ast_models.zig");

pub const CssParser = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    pos: usize,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) CssParser {
        return .{
            .allocator = allocator,
            .input = input,
            .pos = 0,
        };
    }

    pub fn parse(self: *CssParser) !css_ast_models.StyleAst {
        var rules: std.ArrayList(css_ast_models.CssRule) = .empty;

        while (self.pos < self.input.len) {
            self.skipWhitespace();

            if (self.pos >= self.input.len) break;

            // Check for media query
            if (self.peek("@media")) {
                const media_rule = try self.parseMediaRule();
                try rules.append(self.allocator, media_rule);
            } else if (self.peek("@page")) {
                const page_rule = try self.parsePageRule();
                try rules.append(self.allocator, page_rule);
            } else {
                // Regular rule
                const rule = try self.parseRule();
                if (rule) |r| {
                    try rules.append(self.allocator, r);
                }
            }
        }

        return css_ast_models.StyleAst{
            .type = "stylesheet",
            .rules = rules,
        };
    }

    fn parseMediaRule(self: *CssParser) !css_ast_models.CssRule {
        _ = try self.expect("@media");
        self.skipWhitespace();

        // Parse media query
        const query_start = self.pos;
        while (self.pos < self.input.len and self.input[self.pos] != '{') {
            self.pos += 1;
        }
        const query = std.mem.trim(u8, self.input[query_start..self.pos], " \t\n\r");

        _ = try self.expect("{");
        self.skipWhitespace();

        // Parse nested rules
        var nested_rules: std.ArrayList(css_ast_models.CssRule) = .empty;

        while (self.pos < self.input.len and self.input[self.pos] != '}') {
            self.skipWhitespace();

            if (self.pos >= self.input.len or self.input[self.pos] == '}') break;

            const rule = try self.parseRule();
            if (rule) |r| {
                try nested_rules.append(self.allocator, r);
            }
        }

        _ = try self.expect("}");

        return css_ast_models.CssRule{
            .media = .{
                .query = query,
                .rules = nested_rules,
            },
        };
    }

    fn parsePageRule(self: *CssParser) !css_ast_models.CssRule {
        _ = try self.expect("@page");
        self.skipWhitespace();

        _ = try self.expect("{");
        self.skipWhitespace();

        // Parse nested rules (like @top-center, @bottom-center, etc.)
        var nested_rules: std.ArrayList(css_ast_models.CssRule) = .empty;

        while (self.pos < self.input.len and self.input[self.pos] != '}') {
            self.skipWhitespace();

            if (self.pos >= self.input.len or self.input[self.pos] == '}') break;

            const rule = try self.parseRule();
            if (rule) |r| {
                try nested_rules.append(self.allocator, r);
            }
        }

        _ = try self.expect("}");

        return css_ast_models.CssRule{
            .page = .{
                .rules = nested_rules,
            },
        };
    }

    fn parseRule(self: *CssParser) !?css_ast_models.CssRule {
        self.skipWhitespace();
        if (self.pos >= self.input.len) return null;

        // Parse selector
        const selector_start = self.pos;
        while (self.pos < self.input.len and self.input[self.pos] != '{') {
            self.pos += 1;
        }

        if (self.pos >= self.input.len) return null;

        const raw_selector = std.mem.trim(u8, self.input[selector_start..self.pos], " \t\n\r");
        if (raw_selector.len == 0) return null;

        // Normalize selector: collapse whitespace (newlines, tabs, multiple spaces -> single space)
        const selector = try self.normalizeWhitespace(raw_selector);

        _ = try self.expect("{");
        self.skipWhitespace();

        // Parse declarations
        var declarations: std.ArrayList(css_ast_models.CssDeclaration) = .empty;

        while (self.pos < self.input.len and self.input[self.pos] != '}') {
            self.skipWhitespace();

            if (self.pos >= self.input.len or self.input[self.pos] == '}') break;

            const decl = try self.parseDeclaration();
            if (decl) |d| {
                try declarations.append(self.allocator, d);
            }
        }

        _ = try self.expect("}");

        return css_ast_models.CssRule{
            .rule = .{
                .selector = selector,
                .declarations = declarations,
            },
        };
    }

    fn parseDeclaration(self: *CssParser) !?css_ast_models.CssDeclaration {
        self.skipWhitespace();
        if (self.pos >= self.input.len or self.input[self.pos] == '}') return null;

        const prop_start = self.pos;
        try self.scanUntil(&[_]u8{ ':', '}' });

        if (self.pos >= self.input.len or self.input[self.pos] == '}') return null;

        const property = std.mem.trim(u8, self.input[prop_start..self.pos], " \t\n\r");
        if (property.len == 0) return null;

        _ = try self.expect(":");
        self.skipWhitespace();

        const value_start = self.pos;

        try self.scanUntil(&[_]u8{ ';', '}' });

        const value = std.mem.trim(u8, self.input[value_start..self.pos], " \t\n\r");

        if (self.pos < self.input.len and self.input[self.pos] == ';') {
            self.pos += 1;
        }

        return css_ast_models.CssDeclaration{
            .property = property,
            .value = value,
        };
    }

    fn scanUntil(self: *CssParser, delimiters: []const u8) !void {
        var paren_depth: usize = 0;

        while (self.pos < self.input.len) {
            const c = self.input[self.pos];

            // 1. Handle Strings (ignore content inside)
            if (c == '"' or c == '\'') {
                try self.skipString(c);
                continue; // Loop continues from new pos
            }

            // 2. Handle Parentheses (track depth)
            if (c == '(') {
                paren_depth += 1;
                self.pos += 1;
                continue;
            }
            if (c == ')') {
                if (paren_depth > 0) paren_depth -= 1;
                self.pos += 1;
                continue;
            }

            // 3. Check for Delimiter (ONLY if not nested in parens)
            if (paren_depth == 0) {
                for (delimiters) |d| {
                    if (c == d) return;
                }
            }

            self.pos += 1;
        }
    }

    // Fast-forward until matching quote
    fn skipString(self: *CssParser, quote_char: u8) !void {
        self.pos += 1;
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];

            if (c == '\\') {
                self.pos += 2;
                continue;
            }

            if (c == quote_char) {
                self.pos += 1;
                return;
            }
            self.pos += 1;
        }
        return error.UnclosedString;
    }

    fn skipWhitespace(self: *CssParser) void {
        while (self.pos < self.input.len and
            (self.input[self.pos] == ' ' or
                self.input[self.pos] == '\n' or
                self.input[self.pos] == '\r' or
                self.input[self.pos] == '\t'))
        {
            self.pos += 1;
        }
    }

    fn peek(self: *CssParser, str: []const u8) bool {
        if (self.pos + str.len > self.input.len) return false;
        return std.mem.eql(u8, self.input[self.pos .. self.pos + str.len], str);
    }

    fn expect(self: *CssParser, str: []const u8) !void {
        if (!self.peek(str)) return error.UnexpectedToken;
        self.pos += str.len;
    }

    /// Normalize whitespace for example: collapse newlines, tabs, and multiple spaces into single spaces
    fn normalizeWhitespace(self: *CssParser, input: []const u8) ![]const u8 {
        var result: std.ArrayList(u8) = .empty;
        var in_whitespace = false;

        for (input) |c| {
            if (c == ' ' or c == '\n' or c == '\r' or c == '\t') {
                if (!in_whitespace) {
                    try result.append(self.allocator, ' ');
                    in_whitespace = true;
                }
            } else {
                try result.append(self.allocator, c);
                in_whitespace = false;
            }
        }

        return result.toOwnedSlice(self.allocator);
    }
};

test "@page with nested rules" {
    const allocator = std.testing.allocator;
    const css =
        \\@page {
        \\    @top-center {
        \\        font-size: 0.8em;
        \\        font-weight: 600;
        \\        color: var(--base-2);
        \\        letter-spacing: 0.5px;
        \\    }
        \\    @bottom-center {
        \\        content: counter(page) " / " counter(pages);
        \\        font-size: 9pt;
        \\        color: var(--base-2);
        \\    }
        \\}
    ;

    var parser = CssParser.init(allocator, css);
    var ast = try parser.parse();
    defer ast.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), ast.rules.items.len);
    const page_rule = ast.rules.items[0];

    try std.testing.expect(page_rule == .page);
    try std.testing.expectEqual(@as(usize, 2), page_rule.page.rules.items.len);

    // Check the first rule @top-center
    const top_center = page_rule.page.rules.items[0];
    try std.testing.expect(top_center == .rule);
    try std.testing.expectEqualStrings("@top-center", top_center.rule.selector);
    try std.testing.expectEqual(@as(usize, 4), top_center.rule.declarations.items.len);
    try std.testing.expectEqualStrings("font-size", top_center.rule.declarations.items[0].property);
    try std.testing.expectEqualStrings("0.8em", top_center.rule.declarations.items[0].value);
    try std.testing.expectEqualStrings("font-weight", top_center.rule.declarations.items[1].property);
    try std.testing.expectEqualStrings("600", top_center.rule.declarations.items[1].value);
    try std.testing.expectEqualStrings("color", top_center.rule.declarations.items[2].property);
    try std.testing.expectEqualStrings("var(--base-2)", top_center.rule.declarations.items[2].value);
    try std.testing.expectEqualStrings("letter-spacing", top_center.rule.declarations.items[3].property);
    try std.testing.expectEqualStrings("0.5px", top_center.rule.declarations.items[3].value);

    // Check the second rule @bottom-center
    const bottom_center = page_rule.page.rules.items[1];
    try std.testing.expect(bottom_center == .rule);
    try std.testing.expectEqualStrings("@bottom-center", bottom_center.rule.selector);
    try std.testing.expectEqual(@as(usize, 3), bottom_center.rule.declarations.items.len);
    try std.testing.expectEqualStrings("content", bottom_center.rule.declarations.items[0].property);
    try std.testing.expectEqualStrings("counter(page) \" / \" counter(pages)", bottom_center.rule.declarations.items[0].value);
    try std.testing.expectEqualStrings("font-size", bottom_center.rule.declarations.items[1].property);
    try std.testing.expectEqualStrings("9pt", bottom_center.rule.declarations.items[1].value);
    try std.testing.expectEqualStrings("color", bottom_center.rule.declarations.items[2].property);
    try std.testing.expectEqualStrings("var(--base-2)", bottom_center.rule.declarations.items[2].value);
}

test "rules composed by comma" {
    const allocator = std.testing.allocator;
    const css =
        \\code.hljs, code.hljs * {
        \\    background: transparent !important;  
        \\    font-family: inherit !important;   
        \\    font-size: inherit !important;    
        \\    border: none !important;            
        \\}
    ;

    var parser = CssParser.init(allocator, css);
    var ast = try parser.parse();
    defer ast.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), ast.rules.items.len);
    const rule = ast.rules.items[0];
    try std.testing.expect(rule == .rule);
    try std.testing.expectEqualStrings("code.hljs, code.hljs *", rule.rule.selector);
    try std.testing.expectEqual(@as(usize, 4), rule.rule.declarations.items.len);
    try std.testing.expectEqualStrings("background", rule.rule.declarations.items[0].property);
    try std.testing.expectEqualStrings("transparent !important", rule.rule.declarations.items[0].value);
    try std.testing.expectEqualStrings("font-family", rule.rule.declarations.items[1].property);
    try std.testing.expectEqualStrings("inherit !important", rule.rule.declarations.items[1].value);
    try std.testing.expectEqualStrings("font-size", rule.rule.declarations.items[2].property);
    try std.testing.expectEqualStrings("inherit !important", rule.rule.declarations.items[2].value);
    try std.testing.expectEqualStrings("border", rule.rule.declarations.items[3].property);
    try std.testing.expectEqualStrings("none !important", rule.rule.declarations.items[3].value);
}

test "multiline selector with commas" {
    const allocator = std.testing.allocator;
    const css =
        \\h1
        \\a,
        \\h2
        \\a {
        \\  color: var(--base-5);
        \\  margin: 1em 0 0.4em 0;
        \\  font-weight: 600;
        \\  page-break-after: avoid;
        \\}
    ;

    var parser = CssParser.init(allocator, css);
    var ast = try parser.parse();
    defer ast.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), ast.rules.items.len);
    const rule = ast.rules.items[0];
    try std.testing.expect(rule == .rule);
    // NOTE: selector is normalized to compact form (newlines -> single space)
    try std.testing.expectEqualStrings("h1 a, h2 a", rule.rule.selector);
    try std.testing.expectEqual(@as(usize, 4), rule.rule.declarations.items.len);
    try std.testing.expectEqualStrings("color", rule.rule.declarations.items[0].property);
    try std.testing.expectEqualStrings("var(--base-5)", rule.rule.declarations.items[0].value);
    try std.testing.expectEqualStrings("margin", rule.rule.declarations.items[1].property);
    try std.testing.expectEqualStrings("1em 0 0.4em 0", rule.rule.declarations.items[1].value);
    try std.testing.expectEqualStrings("font-weight", rule.rule.declarations.items[2].property);
    try std.testing.expectEqualStrings("600", rule.rule.declarations.items[2].value);
    try std.testing.expectEqualStrings("page-break-after", rule.rule.declarations.items[3].property);
    try std.testing.expectEqualStrings("avoid", rule.rule.declarations.items[3].value);
}

test "multiline selector with commas duplicate, keep the duplicates" {
    const allocator = std.testing.allocator;
    const css =
        \\h1
        \\a,
        \\h2
        \\a {
        \\  color: var(--base-5);
        \\  margin: 1em 0 0.4em 0;
        \\  font-weight: 600;
        \\  page-break-after: avoid;
        \\}
        \\\\h1
        \\a,
        \\h2
        \\a {
        \\  color: var(--base-5);
        \\  margin: 1em 0 0.4em 0;
        \\  font-weight: 600;
        \\  page-break-after: avoid;
        \\}
    ;

    var parser = CssParser.init(allocator, css);
    var ast = try parser.parse();
    defer ast.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), ast.rules.items.len);
    const rule = ast.rules.items[0];
    try std.testing.expect(rule == .rule);
    // NOTE: selector is normalized to compact form (newlines -> single space)
    try std.testing.expectEqualStrings("h1 a, h2 a", rule.rule.selector);
    try std.testing.expectEqual(@as(usize, 4), rule.rule.declarations.items.len);
    try std.testing.expectEqualStrings("color", rule.rule.declarations.items[0].property);
    try std.testing.expectEqualStrings("var(--base-5)", rule.rule.declarations.items[0].value);
    try std.testing.expectEqualStrings("margin", rule.rule.declarations.items[1].property);
    try std.testing.expectEqualStrings("1em 0 0.4em 0", rule.rule.declarations.items[1].value);
    try std.testing.expectEqualStrings("font-weight", rule.rule.declarations.items[2].property);
    try std.testing.expectEqualStrings("600", rule.rule.declarations.items[2].value);
    try std.testing.expectEqualStrings("page-break-after", rule.rule.declarations.items[3].property);
    try std.testing.expectEqualStrings("avoid", rule.rule.declarations.items[3].value);
}
