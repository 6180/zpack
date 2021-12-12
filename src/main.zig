const std = @import("std");
const Allocator = std.mem.Allocator;
const Arch = std.Target.Cpu.Arch;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var mps = try MsgpackStream.init(&gpa.allocator);
    defer mps.deinit();

    _ = try mps.packBool(true);
    _ = try mps.packBool(false);
    mps.dump();

    // std.log.info("Type of `noomba` is {s}", .{@typeName(@TypeOf(noomba))});
}

// !!! The programmer must make sure `dest_type` is large enough to hold the
// value of `n` without losing any information.  Use `beCastSafe` for an error-
// checked version that returns an UnsafeTypeNarrowing if the cast would discard
// bits.
fn beCast(dest_type: type, n: anytype) !dest_type {
    var num = n;
    const num_ti = @typeInfo(num);
    // If big endian,
    if (Arch.endian() == .Big)
        return @intCast(dest_type, num);

    return switch (num_ti) {
        .Int, .ComptimeInt => @byteSwap(dest_type, @intCast(dest_type, num)),
        .Float, .ComptimeFloat => @byteSwap(dest_type, @floatCast(dest_type, num)),
        .Bool => num,
        else => if (@TypeOf(n) == dest_type) n else error{IncompatibleTypes},
    };
}
 
// fn beCastSafe(dest_type: type, n: anytype) !dest_type {

// }

/// Writes a native int with BE byte ordering.
/// Returns: number of bytes written.
const MsgpackStream = struct {
    ator: *Allocator = undefinedntype,
    buf: []u8 = undefined,
    capacity: usize = undefined,
    // end: usize = 0,
    pos: usize = 0,
wqdwdqwdqwdqwd
    /// Prints type and value of all objects in this stream.
    pub fn dump(mps: MsgpackStream) void {
        var i: usize = 0;
        while (i < mps.pos) {
            var tag: u8 = mps.buf[i];

            switch (tag) {
                0xC2 => {
                    std.log.info("Bool: False", .{});
                    i += 1;
                },
                0xC3 => {
                    std.log.info("Bool: True", .{});
                    i += 1;
                },
                else => std.log.info("Unknown tag: {X}", .{tag}),
            }
        }
    }

    pub fn packNil(mps: *MsgpackStream) anyerror!void {
        mps.buf[mps.pos] = 0xC0;
        mps.pos += 1;
    }
    /// Writes a 1 byte bool to the object stream.
    /// False: 0xC2, True: 0xC3
    /// Returns number of bytes written (always 1)
    pub fn packBool(mps: *MsgpackStream, b: bool) !usize {
        mps.buf[mps.pos] = @as(u8, if (b) 0xC3 else 0xC2);
        mps.pos += 1;
        return 1;
    }
    /// Writes a native int with BE byte ordering to the stream.
    /// Returns: number of bytes written.
    pub fn PackUint(mps: MsgpackStream, n: anytype) !usize {
        var num = n;
        const num_ti = @typeInfo(num);
        const endianess = Arch.endian();

        // Make sure n is an int.
        if (num_ti != .Int)
            return error{TypeError};

        const is_signed: bool = (num_ti.signedness == .signed);

        // If arch is LE, swap byte order.
        if (endianess == .Little)
            num = @byteSwap(@TypeOf(n), num);

        // const bit_width = @bitSizeOf(num);

        if (is_signed and num < 0 and num >= -32) {
            // Negative fixint stores a 5 bit negative number. [ 111YYYYY ]
            mps.buf[mps.pos] = @intCast(u8, num) & @as(u8, 0b1110_0000);
            mps.pos += 1;
        }
    }

    pub fn init(alligator: *Allocator) !MsgpackStream {
        var buff: []u8 = undefined;
        const cap: usize = 64;
        buff = try alligator.alloc(u8, cap); // XXX: magic


        return MsgpackStream{
            .ator = alligator,
            .buf = buff,
            .capacity = cap,
            .pos = 0,
        };
    }
    // Free the buffer.
    pub fn deinit(mps: MsgpackStream) void {
        mps.ator.free(mps.buf);
    }
};
