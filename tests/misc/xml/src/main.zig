//! Based on the "reader.zig" example in ianprime0509's zig-xml library.
//! This was made as an exercise to incorporate their library in this project.

const std = @import("std");
const ash = @import("ashbloom");

const xml = ash.xml;

pub fn main() !void
{
    var dba: std.heap.DebugAllocator(.{}) = .{};
    defer {
        const dba_result = dba.deinit();
        if(dba_result == .leak)
        {
            std.debug.print("Program terminates with {d} memory leaks.\n", .{@intFromEnum(dba_result)});
        }
    }

    const allocator = dba.allocator();

    try ash.init_graphics(&allocator);
    defer ash.deinit_graphics();

    var io_threaded = std.Io.Threaded.init(allocator, .{});
    defer io_threaded.deinit();

    const io = io_threaded.io();

    const cwd = std.Io.Dir.cwd();

    const file = try cwd.openFile(io, "../../src/test_xml.xml", .{});
    defer file.close(io);

    var read_buffer: [1024]u8 = undefined;
    var reader = file.reader(io, &read_buffer);

    var xml_streaming_reader: xml.Reader.Streaming = .init(allocator, &reader.interface, .{});
    defer xml_streaming_reader.deinit();

    var xml_reader = &xml_streaming_reader.interface;

    while(true)
    {
        // Read next XML node.
        const node = xml_reader.read() catch |err| switch (err) {
            error.MalformedXml => {
                const loc = xml_reader.errorLocation();
                std.debug.print("{}:{}: {}", .{ loc.line, loc.column, xml_reader.errorCode() });
                return error.MalformedXml;
            },
            else => |other| return other,
        };

        // Handle the node.
        switch (node)
        {
            .eof => break,
            .xml_declaration => {
                ash.print_stdout("xml_declaration: version={s} encoding={?s} standalone={?}\n", .{
                    xml_reader.xmlDeclarationVersion(),
                    xml_reader.xmlDeclarationEncoding(),
                    xml_reader.xmlDeclarationStandalone(),
                });
            },
            .element_start => {
                const element_name = xml_reader.elementNameNs();
                ash.print_stdout("ELEMENT START: {s}\n", .{element_name.local});
                for (0..xml_reader.attributeCount()) |i| {
                    const attribute_name = xml_reader.attributeNameNs(i);
                    ash.print_stdout("\tATTRIBUTE: {s} = {s}\n", .{
                        attribute_name.local,
                        try xml_reader.attributeValue(i),
                    });
                }
            },
            .element_end => {
                const element_name = xml_reader.elementNameNs();
                ash.print_stdout("ELEMENT END: {s}\n", .{element_name.local});
            },
            .comment => {},
            .pi => {
                ash.print_stdout("pi: \"{f}\" \"{f}\"\n", .{
                    std.zig.fmtString(xml_reader.piTarget()),
                    std.zig.fmtString(try xml_reader.piData()),
                });
            },
            .text => {
                const text = try xml_reader.text();
                var has_non_ws = false;
                for(text) |i|
                {
                    if(i != ' ' and i != '\n' and i != '\t' and i != '\r')
                    {
                        has_non_ws = true;
                        break;
                    }
                }
                if(has_non_ws)
                {
                    ash.print_stdout("TEXT: {s}\n", .{text});
                }
            },
            .cdata => {
                ash.print_stdout("CDATA: \"{f}\"\n", .{
                    std.zig.fmtString(try xml_reader.cdata()),
                });
            },
            .entity_reference => {
                ash.print_stdout("ENTITY REFERENCE: \"{f}\"\n", .{
                    std.zig.fmtString(xml_reader.entityReferenceName()),
                });
            },
            .character_reference => {
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(xml_reader.characterReferenceChar(), &buf) catch unreachable;
                ash.print_stdout("CHARACTER REFERENCE: {} (\"{f}\")\n", .{
                    xml_reader.characterReferenceChar(),
                    std.zig.fmtString(buf[0..len]),
                });
            },
        }
    }
}
