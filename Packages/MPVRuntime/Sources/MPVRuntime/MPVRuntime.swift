// Re-exports libmpv's C API (`mpv_create`, `mpv_command`, …) from this dynamic framework.
@_exported import Libmpv

/// libmpv's client API version. Referencing the client API here is what keeps it in this
/// framework: with no reference, the linker drops libmpv's static archive entirely.
public let mpvClientAPIVersion: UInt = mpv_client_api_version()
