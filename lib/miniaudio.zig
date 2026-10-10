const std = @import("std");

pub const Bool32 = enum(u32)
{
    False,
    True
};

const Result = enum(c_int)
{
    Success                           =   0,
    Error                             =  -1,
    InvalidArguments                  =  -2,
    InvalidOperation                  =  -3,
    OutOfMemory                       =  -4,
    OutOfRange                        =  -5,
    AccessDenied                      =  -6,
    DoesNotExist                      =  -7,
    AlreadyExists                     =  -8,
    TooManyOpenFiles                  =  -9,
    InvalidFile                       = -10,
    TooBig                            = -11,
    PathTooLong                       = -12,
    NameTooLong                       = -13,
    NotDirectory                      = -14,
    IsDirectory                       = -15,
    DirectoryNotEmpty                 = -16,
    AtEnd                             = -17,
    NoSpace                           = -18,
    Busy                              = -19,
    IOError                           = -20,
    Interrupt                         = -21,
    Unavailable                       = -22,
    AlreadyInUse                      = -23,
    BadAddress                        = -24,
    BadSeek                           = -25,
    BadPipe                           = -26,
    Deadlock                          = -27,
    TooManyLinks                      = -28,
    NotImplemented                    = -29,
    NoMessage                         = -30,
    BadMessage                        = -31,
    NoDataAvailable                   = -32,
    InvalidData                       = -33,
    Timeout                           = -34,
    NoNetwork                         = -35,
    NotUnique                         = -36,
    NotSocket                         = -37,
    NoAddress                         = -38,
    BadProtocol                       = -39,
    ProtocolUnavailable               = -40,
    ProtocolNotSupported              = -41,
    ProtocolFamilyNotSupported        = -42,
    AddressFamilyNotSupported         = -43,
    SocketNotSupported                = -44,
    ConnectionReset                   = -45,
    AlreadyConnected                  = -46,
    NotConnected                      = -47,
    ConnectionRefused                 = -48,
    NoHost                            = -49,
    InProgress                        = -50,
    Cancelled                         = -51,
    MemoryAlreadyMapped               = -52,
    
    // Non-standard generic errors.
    CRCMismatch                       = -100,

    // Miniaudio-specific errors.
    FormatNotSupported                = -200,
    DeviceTypeNotSupported            = -201,
    ShareModeNotSupported             = -202,
    NoBackend                         = -203,
    NoDevice                          = -204,
    APINotFound                       = -205,
    InvalidDeviceConfig               = -206,
    Loop                              = -207,
    BackendNotEnabled                 = -208,

    // State errors.
    DeviceNotInitialized              = -300,
    DeviceAlreadyInitialized          = -301,
    DeviceNotStarted                  = -302,
    DeviceNotStopped                  = -303,

    // Operation errors.
    FailedToInitBackend               = -400,
    FailedToOpenBackendDevice         = -401,
    FailedToStartBackendDevice        = -402,
    FailedToStopBackendDevice         = -403
};

pub const Error = error
{
    GenericError,
    InvalidArgs,
    InvalidOperation,
    OutOfMemory,
    OutOfRange,
    AccessDenied,
    DoesNotExist,
    AlreadyExists,
    TooManyOpenFiles,
    InvalidFile,
    TooBig,
    PathTooLong,
    NameTooLong,
    NotDirectory,
    IsDirectory,
    DirectoryNotEmpty,
    AtEnd,
    NoSpace,
    Busy,
    IOError,
    Interrupt,
    Unavailable,
    AlreadyInUse,
    BadAddress,
    BadSeek,
    BadPipe,
    Deadlock,
    TooManyLinks,
    NotImplemented,
    NoMessage,
    BadMessage,
    NoDataAvailable,
    InvalidData,
    Timeout,
    NoNetwork,
    NotUnique,
    NotSocket,
    NoAddress,
    BadProtocol,
    ProtocolUnavailable,
    ProtocolNotSupported,
    ProtocolFamilyNotSupported,
    AddressFamilyNotSupported,
    SocketNotSupported,
    ConnectionReset,
    AlreadyConnected,
    NotConnected,
    ConnectionRefused,
    NoHost,
    InProgress,
    Cancelled,
    MemoryAlreadyMapped,

    CRCMismatch,

    FormatNotSupported,
    DeviceTypeNotSupported,
    ShareModeNotSupported,
    NoBackend,
    NoDevice,
    APINotFound,
    InvalidDeviceConfig,
    Loop,
    BackendNotEnabled,

    DeviceNotInitialized,
    DeviceAlreadyInitialized,
    DeviceNotStarted,
    DeviceNotStopped,

    FailedToInitBackend,
    FailedToOpenBackendDevice,
    FailedToStartBackendDevice,
    FailedToStopBackendDevice,
};

pub fn result_to_error(result: Result) ?Error
{
    return switch(result)
    {
        .Success => null,
        .Error => Error.GenericError,
        .InvalidArguments => Error.InvalidArgs,
        .InvalidOperation => Error.InvalidOperation,
        .OutOfMemory => Error.OutOfMemory,
        .OutOfRange => Error.OutOfRange,
        .AccessDenied => Error.AccessDenied,
        .DoesNotExist => Error.DoesNotExist,
        .AlreadyExists => Error.AlreadyExists,
        .TooManyOpenFiles => Error.TooManyOpenFiles,
        .InvalidFile => Error.InvalidFile,
        .TooBig => Error.TooBig,
        .PathTooLong => Error.PathTooLong,
        .NameTooLong => Error.NameTooLong,
        .NotDirectory => Error.NotDirectory,
        .IsDirectory => Error.IsDirectory,
        .DirectoryNotEmpty => Error.DirectoryNotEmpty,
        .AtEnd => Error.AtEnd,
        .NoSpace => Error.NoSpace,
        .Busy => Error.Busy,
        .IOError => Error.IOError,
        .Interrupt => Error.Interrupt,
        .Unavailable => Error.Unavailable,
        .AlreadyInUse => Error.AlreadyInUse,
        .BadAddress => Error.BadAddress,
        .BadSeek => Error.BadSeek,
        .BadPipe => Error.BadPipe,
        .Deadlock => Error.Deadlock,
        .TooManyLinks => Error.TooManyLinks,
        .NotImplemented => Error.NotImplemented,
        .NoMessage => Error.NoMessage,
        .BadMessage => Error.BadMessage,
        .NoDataAvailable => Error.NoDataAvailable,
        .InvalidData => Error.InvalidData,
        .Timeout => Error.Timeout,
        .NoNetwork => Error.NoNetwork,
        .NotUnique => Error.NotUnique,
        .NotSocket => Error.NotSocket,
        .NoAddress => Error.NoAddress,
        .BadProtocol => Error.BadProtocol,
        .ProtocolUnavailable => Error.ProtocolUnavailable,
        .ProtocolNotSupported => Error.ProtocolNotSupported,
        .ProtocolFamilyNotSupported => Error.ProtocolFamilyNotSupported,
        .AddressFamilyNotSupported => Error.AddressFamilyNotSupported,
        .SocketNotSupported => Error.SocketNotSupported,
        .ConnectionReset => Error.ConnectionReset,
        .AlreadyConnected => Error.AlreadyConnected,
        .NotConnected => Error.NotConnected,
        .ConnectionRefused => Error.ConnectionRefused,
        .NoHost => Error.NoHost,
        .InProgress => Error.InProgress,
        .Cancelled => Error.Cancelled,
        .MemoryAlreadyMapped => Error.MemoryAlreadyMapped,

        .CRCMismatch => Error.CRCMismatch,

        .FormatNotSupported => Error.FormatNotSupported,
        .DeviceTypeNotSupported => Error.DeviceTypeNotSupported,
        .ShareModeNotSupported => Error.ShareModeNotSupported,
        .NoBackend => Error.NoBackend,
        .NoDevice => Error.NoDevice,
        .APINotFound => Error.APINotFound,
        .InvalidDeviceConfig => Error.InvalidDeviceConfig,
        .Loop => Error.Loop,
        .BackendNotEnabled => Error.BackendNotEnabled,

        .DeviceNotInitialized => Error.DeviceNotInitialized,
        .DeviceAlreadyInitialized => Error.DeviceAlreadyInitialized,
        .DeviceNotStarted => Error.DeviceNotStarted,
        .DeviceNotStopped => Error.DeviceNotStopped,

        .FailedToInitBackend => Error.FailedToInitBackend,
        .FailedToOpenBackendDevice => Error.FailedToOpenBackendDevice,
        .FailedToStartBackendDevice => Error.FailedToStartBackendDevice,
        .FailedToStopBackendDevice => Error.FailedToStopBackendDevice
    };
}

pub const AllocationCallbacks = extern struct
{
    on_malloc: *const fn(usize, *anyopaque) *anyopaque,
    on_realloc: *const fn(*anyopaque, usize, *anyopaque) *anyopaque,
    on_free: *const fn(*anyopaque, *anyopaque) void,

    user_data: *anyopaque
};

pub const ShareMode = enum(c_uint)
{
    Shared,
    Exclusive
};

pub const Format = enum(c_uint)
{
    Unknown,
    Unsigned8,
    Signed16,
    Signed24,
    Signed32,
    Float32,

    pub fn get_size(self: Format) usize
    {
        return switch(self)
        {
            .Unknown => @panic("Can't get size of unknown data format."),
            .Unsigned8 => 1,
            .Signed16 => 2,
            .Signed24 => 3,
            .Signed32 => 4,
            .Float32 => 4
        };
    }
};

pub const DeviceType = enum(c_uint)
{
    Playback = 1,
    Capture = 2,
    Duplex = 3,
    Loopback = 4
};

pub const DeviceState = enum(c_uint)
{
    Uninitialized = 0,
    Stopped,
    Started,
    Starting,
    Stopping
};

pub const ResampleAlgorithm = enum(c_uint)
{
    Linear = 0,
    Custom
};

pub const PerformanceProfile = enum(c_uint)
{
    LowLatency,
    Conservative
};

pub const ChannelMixMode = enum(c_uint)
{
    Rectangular,
    Simple,
    CustomWeights,

    pub const Default: ChannelMixMode = .Rectangular;
};

pub const Log = opaque
{
    extern fn mazig_log_init(callbacks: *const AllocationCallbacks, log: *?*Log) Result;

    pub fn init(callbacks: *const AllocationCallbacks) Error!*Log
    {
        var log: *?*Log = undefined;
        const result = mazig_log_init(callbacks, &log);
        if(result_to_error(result)) |r| return r;

        return log.?;
    }

    extern fn ma_log_uninit(log: *Log) void;

    pub fn uninit(self: *Log) void
    {
        ma_log_uninit(self);
    }
};

pub const Backend = enum(c_uint)
{
    WASAPI,
    DSound,
    WinMM,
    CoreAudio,
    SndIO,
    Audio4,
    OSS,
    PulseAudio,
    ALSA,
    JACK,
    AAudio,
    OpenSL,
    WebAudio,
    Custom,
    null
};

pub const DeviceDataProc = *const fn(device: *Device, output: *anyopaque, input: *anyopaque, frame_count: u32) callconv(.c) void;
pub const NotificationDataProc = *const fn(notification: *const anyopaque) callconv(.c) void;
pub const StopProc = *const fn(device: *Device) callconv(.c) void;

pub const ResamplerConfig = extern struct
{
    format: Format,
    channels: u32,
    sample_rate_in: u32,
    sample_rate_out: u32,
    resample_algorithm: ResampleAlgorithm,
    backend_vtable: ?*anyopaque,
    backend_user_data: ?*anyopaque,
    linear: extern struct
    {
        lpf_order: u32
    }
};

pub const AudioIOConfig = extern struct
{
    device_id: *const Device.ID,
    format: Format,
    channels: u32,
    channel_map: [*]u8,
    channel_mix_mode: ChannelMixMode,
    calculate_LFE_from_spatial_channels: Bool32,
    share_mode: ShareMode
};

pub const WASAPIUsage = enum(c_uint)
{
    Default,
    Games,
    ProAudio
};

pub const OpenSLStreamType = enum(c_uint)
{
    Default,
    Voice,
    System,
    Ring,
    Media,
    Alarm,
    Notification
};

pub const OpenSLRecordingPreset = enum(c_uint)
{
    Default,
    Generic,
    Camcorder,
    Recognition,
    VoiceCommunication,
    VoiceUnprocessed
};

pub const AAudioUsage = enum(c_uint)
{
    Default,
    Media,
    VoiceCommunication,
    VoiceCommunicationSignalling,
    Alarm,
    Notification,
    NotificationRingtone,
    NotificationEvent,
    AssistanceAccessibility,
    AssistanceNavigationGuidance,
    AssistanceSonification,
    Game,
    Assitant,
    Emergency,
    Safety,
    VehicleStatus,
    Announcement
};

pub const AAudioContentType = enum(c_uint)
{
    Default,
    Speech,
    Music,
    Movie,
    Sonification,
};

pub const AAudioInputPreset = enum(c_uint)
{
    Default,
    Generic,
    Camcorder,
    VoiceRecognition,
    VoiceCommunication,
    Unprocessed,
    VoicePerformance
};

pub const AAudioAllowedCapturePolicy = enum(c_uint)
{
    Default,
    ByAll,
    BySystem,
    ByNone
};

pub const Context = opaque
{
    pub const DeviceList = struct
    {
        playback_devices: []const Device.Info,
        capture_devices: []const Device.Info,

        pub fn print(self: DeviceList) void
        {
            std.debug.print("Playback devices:\n", .{});
            for(self.playback_devices) |d|
            {
                for(d.name, 0..) |_, i|
                {
                    if(d.name[i] == 0)
                    {
                        std.debug.print("\t{s}\n", .{d.name[0..i]});
                        break;
                    }
                }
            }
            std.debug.print("Capture devices:\n", .{});
            for(self.capture_devices) |d|
            {
                for(d.name, 0..) |_, i|
                {
                    if(d.name[i] == 0)
                    {
                        std.debug.print("\t{s}\n", .{d.name[0..i]});
                        break;
                    }
                }
            }
        }
    };

    extern fn ma_context_uninit(context: ?*Context) Result;

    pub fn deinit(self: *Context) void
    {
        _ = ma_context_uninit(self);
    }

    extern fn mazig_context_init(context: *?*Context) Result;

    pub fn init() Error!*Context
    {
        var context: ?*Context = undefined;
        const result = mazig_context_init(&context);
        if(result_to_error(result)) |r| return r;

        return context.?;
    }

    extern fn ma_context_get_devices(context: ?*Context, playback_infos: ?*[*]Device.Info, playback_count: ?*u32, capture_infos: ?*[*]Device.Info, capture_count: ?*u32) Result;

    pub fn get_devices(self: *Context) Error!DeviceList
    {
        var playback_devices: [*]Device.Info = undefined;
        var capture_devices: [*]Device.Info = undefined;

        var playback_count: u32 = undefined;
        var capture_count: u32 = undefined;

        const result = ma_context_get_devices(self, &playback_devices, &playback_count, &capture_devices, &capture_count);
        if(result_to_error(result)) |r| return r;

        return .{
            .playback_devices = playback_devices[0..playback_count],
            .capture_devices = capture_devices[0..capture_count]
        };
    }

    extern fn ma_context_get_device_info(context: ?*Context, device_type: DeviceType, device_id: *const Device.ID, device_info: *Device.Info) Result;

    pub fn get_device_info(self: *Context, device_type: DeviceType, id: *const Device.ID) Error!Device.Info
    {
        var info: Device.Info = undefined;
        const result = ma_context_get_device_info(self, device_type, id, &info);
        if(result_to_error(result)) |r| return r;

        return info;
    }
};

pub const Device = opaque 
{
    const ID = extern union
    {
        wasapi: [64]i32,
        dsound: [16]u8,
        winmm: u32,
        alsa: [256]u8,
        pulse: [256]u8,
        jack: i32,
        coreaudio: [256]u8,
        sndio: [256]u8,
        audio4: [256]u8,
        oss: [64]u8,
        aaudio: i32,
        opensl: u32,
        webaudio: [32]u8,
        custom: extern union
        {
            i: i32,
            s: [256]u8,
            p: ?*anyopaque,
        },
        nullbackend: i32
    };

    pub const Config = extern struct
    {
        device_type: DeviceType,
        sample_rate: u32,
        period_size_in_frames: u32,
        period_size_in_milliseconds: u32,
        periods: u32,
        performance_profile: PerformanceProfile,
        no_presilenced_output_buffer: bool,
        no_clip: bool,
        no_disable_denormals: bool,
        no_fixed_sized_callback: bool,
        data_callback: ?DeviceDataProc,
        notification_callback: ?NotificationDataProc,
        stop_callback: ?StopProc,
        user_data: ?*anyopaque,
        resampler_config: ResamplerConfig,
        playback: AudioIOConfig,
        capture: AudioIOConfig,
        wasapi: extern struct
        {
            usage: WASAPIUsage,
            no_auto_convert_src: bool,
            no_default_quality_src: bool,
            no_auto_stream_routing: bool,
            no_hardware_offloading: bool,
            loopback_process_id: u32,
            loopback_process_exclude: bool
        },
        alsa: extern struct
        {
            no_mmap: Bool32,
            no_auto_format: Bool32,
            no_auto_channels: Bool32,
            no_auto_resample: Bool32
        },
        pulse: extern struct
        {
            stream_name_playback: [*:0]const u8,
            stream_name_capture: [*:0]const u8,
            channel_map: i32
        },
        coreaudio: extern struct
        {
            allow_nominal_sample_rate_change: Bool32,
        },
        opensl: extern struct
        {
            stream_type: OpenSLStreamType,
            recording_preset: OpenSLRecordingPreset,
            enable_compatibility_workarounds: Bool32
        },
        aaudio: extern struct
        {
            usage: AAudioUsage,
            content_type: AAudioContentType,
            input_preset: AAudioInputPreset,
            allowed_capture_policy: AAudioAllowedCapturePolicy,
            no_auto_start_after_reroute: Bool32,
            enable_compatibility_workarounds: Bool32,
            allow_set_buffer_capacity: Bool32
        },

        extern fn ma_device_config_init(device_type: DeviceType) Config;

        pub fn init(device_type: DeviceType) Config
        {
            return ma_device_config_init(device_type);
        }
    };

    pub const Info = extern struct
    {
        id: ID,
        name: [256]u8,
        is_default: Bool32,
        native_data_format_count: u32,
        native_data_formats: [64]NativeDataFormat,

        pub const NativeDataFormat = extern struct
        {
            format: Format,
            channels: u32,
            sample_rate: u32,
            flags: u32
        };
    };

    extern fn mazig_device_uninit(device: *Device) void;

    pub fn deinit(self: *Device) void
    {
        mazig_device_uninit(self);
    }

    extern fn mazig_device_init(context: ?*anyopaque, device_config: *const Config, device: *?*Device) Result;

    pub fn init(context: ?*anyopaque, device_config: *const Config) Error!*Device
    {
        var device: ?*Device = undefined;
        const result = mazig_device_init(context, device_config, &device);
        if(result_to_error(result)) |r| return r;

        return device.?;
    }

    extern fn ma_device_start(device: *Device) Result;

    pub fn start(self: *Device) Error!void
    {
        if(result_to_error(ma_device_start(self))) |r| return r;
    }

    extern fn ma_device_stop(device: *Device) Result;

    pub fn stop(self: *Device) void
    {
        _ = ma_device_stop(self);
    }
};
