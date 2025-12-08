const std = @import("std");
const css_comment_parser = @import("css_comment_parser.zig");
const css_parser = @import("css_parser.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const filepath = "css-samples/sample_1.css";

    const file = try std.fs.cwd().openFile(filepath, .{ .mode = .read_only });
    defer file.close();

    const css = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(css);

    // 1. Handle Comments (TODO: for a future versions the comments will be parsed and stored in the AST)
    const has_comments = css_comment_parser.countComments(css) > 0;
    const cleaned_css = if (has_comments)
        try css_comment_parser.removeComments(allocator, css)
    else
        css;
    defer if (has_comments) allocator.free(cleaned_css);

    // 2. Parse CSS
    var parser = css_parser.CssParser.init(allocator, cleaned_css);
    var ast = try parser.parse();
    defer ast.deinit(allocator);

    // 3. Write JSON
    const out_file = try std.fs.cwd().createFile("output.json", .{});
    defer out_file.close();

    var buf: [4096]u8 = undefined;
    var file_writer = out_file.writer(&buf);

    try std.json.Stringify.value(
        ast,
        .{ .whitespace = .indent_2 },
        &file_writer.interface,
    );
    try file_writer.interface.flush();

    std.debug.print("AST written to output.json\n", .{});
}
