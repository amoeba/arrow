# Building Apache Arrow Flight SQL ODBC Driver on Windows

This guide explains how to build the Apache Arrow Flight SQL ODBC driver locally on Windows, following the same process as the CI system.

## Prerequisites

### Required Tools

1. **Visual Studio 2019 or 2022** with C++ development tools
   - Download from: https://visualstudio.microsoft.com/

2. **CMake** (3.16 or later)
   - Download from: https://cmake.org/download/

3. **Ninja** build system
   - Download from: https://github.com/ninja-build/ninja/releases
   - Or install via: `choco install ninja` (if using Chocolatey)

4. **Git** for Windows
   - Download from: https://git-scm.com/download/win

5. **Git Bash** (comes with Git for Windows)

### Optional Tools

1. **ccache** - for faster incremental builds
   - Install via: `choco install ccache`

2. **WiX Toolset v6.0** - for building MSI installer
   - Download from: https://github.com/wixtoolset/wix/releases

## Quick Start

### Basic Build (Release mode, no tests)

```bash
./build-odbc-windows.sh
```

### Build with Tests

```bash
./build-odbc-windows.sh release yes
```

### Build with MSI Installer

```bash
./build-odbc-windows.sh release yes yes
```

## Usage

The script accepts three optional parameters:

```bash
./build-odbc-windows.sh [BUILD_TYPE] [RUN_TESTS] [BUILD_INSTALLER]
```

- **BUILD_TYPE**: `debug` or `release` (default: `release`)
- **RUN_TESTS**: `yes` or `no` (default: `yes`)
- **BUILD_INSTALLER**: `yes` or `no` (default: `no`)

### Examples

```bash
# Debug build without tests
./build-odbc-windows.sh debug no

# Release build with tests
./build-odbc-windows.sh release yes

# Release build with tests and installer
./build-odbc-windows.sh release yes yes
```

## Build Process

The script performs the following steps:

1. **Checks prerequisites**: Verifies that CMake, Ninja, and Visual Studio are installed
2. **Sets up vcpkg**: Clones and bootstraps vcpkg if not already present
3. **Downloads timezone database**: Required for date/time functions
4. **Configures environment**: Sets up environment variables matching CI configuration
5. **Runs CMake**: Configures the build with vcpkg dependencies
6. **Builds**: Compiles the ODBC driver and dependencies
7. **Registers driver** (if testing): Installs the ODBC driver for testing
8. **Runs tests** (optional): Executes the ODBC test suite
9. **Builds MSI** (optional): Creates a Windows installer package

## Build Output

After a successful build, you'll find:

- **ODBC DLL**: `build/cpp/release/arrow_flight_sql_odbc.dll`
- **Libraries**: `build/cpp/release/*.lib`
- **MSI Installer** (if built): `build/cpp/Apache-Arrow-Flight-SQL-ODBC-*.msi`

## Build Time

- **First build**: 30-60 minutes (downloads and builds all dependencies)
- **Incremental builds**: 5-15 minutes (with ccache)

## Registering the ODBC Driver

To manually register the driver for use with ODBC applications:

```bash
cmd //c cpp\\src\\arrow\\flight\\sql\\odbc\\tests\\install_odbc.cmd build/cpp/release/arrow_flight_sql_odbc.dll
```

Or install the MSI if you built it:

```powershell
msiexec /i build\cpp\Apache-Arrow-Flight-SQL-ODBC-*-win64.msi /qn
```

## Troubleshooting

### vcpkg Build Failures

If vcpkg fails to build dependencies:

```bash
# Clean vcpkg cache
rm -rf vcpkg/buildtrees
rm -rf vcpkg/packages

# Try again
./build-odbc-windows.sh
```

### CMake Configuration Errors

If CMake fails to configure:

```bash
# Clean build directory
rm -rf build

# Try again
./build-odbc-windows.sh
```

### Visual Studio Not Found

If the script can't find Visual Studio, make sure it's installed with C++ tools:

1. Open Visual Studio Installer
2. Modify your installation
3. Ensure "Desktop development with C++" workload is selected
4. Install/Update

### Out of Disk Space

The build requires approximately 20-30 GB of disk space for:
- vcpkg dependencies
- Build artifacts
- Intermediate object files

Free up space or use a different drive.

## Configuration

The script sets these key environment variables (matching CI):

```bash
ARROW_BUILD_SHARED=ON              # Build shared libraries
ARROW_BUILD_STATIC=OFF             # Don't build static libraries
ARROW_BUILD_TESTS=ON               # Build test suite
ARROW_CSV=OFF                      # CSV not needed for ODBC
ARROW_DEPENDENCY_SOURCE=VCPKG      # Use vcpkg for dependencies
ARROW_FLIGHT_SQL_ODBC=ON           # Enable ODBC driver
VCPKG_DEFAULT_TRIPLET=x64-windows  # 64-bit Windows build
```

## Advanced Usage

### Custom vcpkg Installation

If you already have vcpkg installed elsewhere:

```bash
export VCPKG_ROOT=/path/to/your/vcpkg
./build-odbc-windows.sh
```

### Using Different Build Directory

Edit the script to change `BUILD_DIR`:

```bash
BUILD_DIR="/path/to/custom/build"
```

### Parallel Builds

The script automatically uses all available CPU cores. To limit:

```bash
export CMAKE_BUILD_PARALLEL_LEVEL=4
./build-odbc-windows.sh
```

## CI Compatibility

This script replicates the `odbc-msvc` job from `.github/workflows/cpp_extra.yml`:

- Same environment variables
- Same build flags
- Same dependency management (vcpkg)
- Same test registration process

## Additional Resources

- [Arrow C++ Development](https://arrow.apache.org/docs/developers/cpp/building.html)
- [Arrow Flight SQL](https://arrow.apache.org/docs/format/FlightSql.html)
- [vcpkg Documentation](https://vcpkg.io/)

## Getting Help

If you encounter issues:

1. Check the [Apache Arrow mailing list](https://arrow.apache.org/community/)
2. File an issue: https://github.com/apache/arrow/issues
3. Join the [Arrow Slack](https://s.apache.org/arrow-slack)
