import core.text.Text

@cfg(target_arch = "x86_64")
pub const ARCH: read Text from static = "x86_64"

@cfg(target_arch = "aarch64")
pub const ARCH: read Text from static = "aarch64"

@cfg(target_arch = "wasm32")
pub const ARCH: read Text from static = "wasm32"

@cfg(any(target_os = "linux", target_os = "android", target_os = "macos"))
pub const FAMILY: read Text from static = "unix"

@cfg(target_os = "windows")
pub const FAMILY: read Text from static = "windows"

@cfg(target_os = "wasi")
pub const FAMILY: read Text from static = ""

@cfg(target_os = "linux")
pub const OS: read Text from static = "linux"

@cfg(target_os = "android")
pub const OS: read Text from static = "android"

@cfg(target_os = "macos")
pub const OS: read Text from static = "macos"

@cfg(target_os = "windows")
pub const OS: read Text from static = "windows"

@cfg(target_os = "wasi")
pub const OS: read Text from static = ""

@cfg(any(target_os = "linux", target_os = "android", target_os = "macos"))
pub const DLL_PREFIX: read Text from static = "lib"

@cfg(any(target_os = "windows", target_os = "wasi"))
pub const DLL_PREFIX: read Text from static = ""

@cfg(any(target_os = "linux", target_os = "android"))
pub const DLL_SUFFIX: read Text from static = ".so"

@cfg(target_os = "macos")
pub const DLL_SUFFIX: read Text from static = ".dylib"

@cfg(target_os = "windows")
pub const DLL_SUFFIX: read Text from static = ".dll"

@cfg(target_os = "wasi")
pub const DLL_SUFFIX: read Text from static = ".wasm"

@cfg(any(target_os = "linux", target_os = "android"))
pub const DLL_EXTENSION: read Text from static = "so"

@cfg(target_os = "macos")
pub const DLL_EXTENSION: read Text from static = "dylib"

@cfg(target_os = "windows")
pub const DLL_EXTENSION: read Text from static = "dll"

@cfg(target_os = "wasi")
pub const DLL_EXTENSION: read Text from static = "wasm"

@cfg(any(target_os = "linux", target_os = "android", target_os = "macos"))
pub const EXE_SUFFIX: read Text from static = ""

@cfg(target_os = "windows")
pub const EXE_SUFFIX: read Text from static = ".exe"

@cfg(target_os = "wasi")
pub const EXE_SUFFIX: read Text from static = ".wasm"

@cfg(any(target_os = "linux", target_os = "android", target_os = "macos"))
pub const EXE_EXTENSION: read Text from static = ""

@cfg(target_os = "windows")
pub const EXE_EXTENSION: read Text from static = "exe"

@cfg(target_os = "wasi")
pub const EXE_EXTENSION: read Text from static = "wasm"
