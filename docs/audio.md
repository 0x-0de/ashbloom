# Audio

Contains everything related to audio input and output. Allows you to record and play audio from a selected input and output.

Audio is stored in processed in `SoundNode` objects. These objects are responsible for transforming linear streams of audio prior to playback or any necessary recording operations. The objects that generate this audio in the first place are called `Producer`s. Producers will always produce audio according to some format (\# of channels, sample rate, bit rate, etc.) and one purpose of `SoundNode`s is to automatically handle transformation from the source format to the application's native (output) format. `SoundNode`s can also be routed into other `SoundNode`s for multiple layers of transformation.

Producers can either be audio generators or may exist to decode existing pieces of audio. Various decoders for formats like WAV, FLAC, and MP3 can be found in the `decoders` module, and a few simple transforms can be found in the `transforms` module.

## Modules

1. [decoders](./pages/audio/decoders.md)
2. [nodes](./pages/audio/nodes.md)
3. [transforms](./pages/audio/transforms.md)

## Public Functions

**`add_output_node(allocator: *const std.mem.Allocator, node: *audio.SoundNode) !void`**

When called, Ashbloom will emit any sound processed through `node` in addition to other nodes added through this function.

**`deinit(allocator: *const std.mem.Allocator) void`**

Disables and deinitializes the audio faculties of the ashbloom framework.

**`init(allocator: *const std.mem.Allocator) !void`**

Initializes the audio faculties of the Ashbloom framework. Creates a default miniaudio context and polls all available audio I/O devices (speakers, microphones, etc.).

**`input_producer() Producer`**

Returns a `Producer` which records data from the chosen audio input device.

**`remove_output_node(index: usize) void`**

Removes an output node from Ashbloom's listening queue by its index. Will effectively stop audio output from this node immediately.

## Private Functions

**`input_producer_generate(_: *anyopaque, output: *const []f32, _: audio.Producer.GeneratorFlags) Producer.Result`**

Producer generation callback for the input producer created with **`input_producer`**. Simply records audio from the audio input buffer.