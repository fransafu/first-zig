const std = @import("std");
const Regex = @import("regex").Regex;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const filepath = "css-samples/fasteater_usd8docs_docs_css_chrome.css";

    const file = try std.fs.cwd().openFile(filepath, .{ .mode = .read_only });
    defer file.close();

    // read all file into memory (max 1 MiB here)
    const css = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(css);

    const pattern = "/\\*(.|\\n)*?\\*/";

    var re = try Regex.compile(allocator, pattern);
    defer re.deinit();

    var pos: usize = 0;
    while (pos < css.len) {
        const remaining = css[pos..];
        var caps = try re.captures(remaining);

        if (caps) |*c| {
            defer c.deinit();
            if (c.sliceAt(0)) |match| {
                std.debug.print("{s}\n---\n", .{match});
                if (c.boundsAt(0)) |bounds| {
                    pos += bounds.upper;
                } else {
                    break;
                }
            } else {
                break;
            }
        } else {
            break;
        }
    }
}
