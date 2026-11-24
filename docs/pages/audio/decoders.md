# `decoders`

Contains a list of decoders (objects that spawn `Producer`s which read from an audio file) for different audio formats.

## WAVDecoder (`struct`)

Creates producers that read and export PCM data from .wav files.

### Fields

`allocator: *const std.mem.Allocator` - Allocator handle.

`io_threaded: *std.Io.Threaded` - IO handle.

`path: []const u8` - Path of the .wav file to read from.

`format: AudioFormat` - Format of the .wav file (set during **`init`**).

`data_offset: usize` - Offset of the .wav PCM data (set during **`init`**).

`data_size: usize` - Size of the .wav PCM data (set during **`init`**).

`file_buffer: [128]u8 = undefined` - File read buffer.
