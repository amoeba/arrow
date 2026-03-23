# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
# PowerShell build script for Apache Arrow Flight SQL ODBC Driver on Windows
# This script mimics the CI build process from .github/workflows/cpp_extra.yml

param(
    [string]$BuildType = "release",
    [switch]$SkipTests,
    [switch]$BuildInstaller
)

# Colors for output
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

Write-Info "Apache Arrow Flight SQL ODBC Driver Build Script"
Write-Info "=================================================="
Write-Info "Build Type: $BuildType"
Write-Info "Skip Tests: $SkipTests"
Write-Info "Build Installer: $BuildInstaller"
Write-Host ""

# Get the Arrow source directory
$SourceDir = $PSScriptRoot
$BuildDir = Join-Path $SourceDir "build"

Write-Info "Source directory: $SourceDir"
Write-Info "Build directory: $BuildDir"
Write-Host ""

# Check for required tools
Write-Info "Checking for required tools..."

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    Write-Error-Custom "cmake not found. Please install CMake."
    exit 1
}

if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) {
    Write-Error-Custom "ninja not found. Please install Ninja."
    exit 1
}

Write-Info "All required tools found."
Write-Host ""

# Set up vcpkg
$VcpkgDir = Join-Path $SourceDir "vcpkg"
if (-not (Test-Path $VcpkgDir)) {
    Write-Info "vcpkg not found. Cloning vcpkg repository..."
    git clone https://github.com/microsoft/vcpkg.git $VcpkgDir
    Write-Info "Bootstrapping vcpkg..."
    Push-Location $VcpkgDir
    .\bootstrap-vcpkg.bat
    Pop-Location
} else {
    Write-Info "vcpkg directory found at $VcpkgDir"
}

$env:VCPKG_ROOT = $VcpkgDir
Write-Info "VCPKG_ROOT set to: $env:VCPKG_ROOT"
Write-Host ""

# Set up ccache if available
if (Get-Command ccache -ErrorAction SilentlyContinue) {
    Write-Info "ccache found, setting up..."
    $env:ARROW_USE_CCACHE = "ON"
    if (Test-Path "ci\scripts\ccache_setup.sh") {
        bash ci/scripts/ccache_setup.sh
    }
} else {
    Write-Warn "ccache not found. Build will be slower."
    $env:ARROW_USE_CCACHE = "OFF"
}
Write-Host ""

# Download timezone database
Write-Info "Downloading timezone database..."
if (Test-Path "ci\scripts\download_tz_database.sh") {
    bash ci/scripts/download_tz_database.sh
} else {
    Write-Warn "download_tz_database.sh not found, skipping."
}
Write-Host ""

# Set environment variables for the build
$env:ARROW_BUILD_SHARED = "ON"
$env:ARROW_BUILD_STATIC = "OFF"
$env:ARROW_BUILD_TESTS = "ON"
$env:ARROW_BUILD_TYPE = $BuildType
$env:ARROW_CSV = "OFF"
$env:ARROW_DEPENDENCY_SOURCE = "VCPKG"
$env:ARROW_FLIGHT_SQL_ODBC = "ON"
$env:ARROW_FLIGHT_SQL_ODBC_INSTALLER = if ($BuildInstaller) { "ON" } else { "OFF" }
$env:ARROW_HOME = "/usr"
$env:CMAKE_GENERATOR = "Ninja"
$env:CMAKE_INSTALL_PREFIX = "/usr"
$env:VCPKG_BINARY_SOURCES = "clear;nugettimeout,600"
$env:VCPKG_DEFAULT_TRIPLET = "x64-windows"

Write-Info "Environment variables set:"
Write-Host "  ARROW_BUILD_SHARED=$env:ARROW_BUILD_SHARED"
Write-Host "  ARROW_BUILD_STATIC=$env:ARROW_BUILD_STATIC"
Write-Host "  ARROW_BUILD_TESTS=$env:ARROW_BUILD_TESTS"
Write-Host "  ARROW_BUILD_TYPE=$env:ARROW_BUILD_TYPE"
Write-Host "  ARROW_CSV=$env:ARROW_CSV"
Write-Host "  ARROW_DEPENDENCY_SOURCE=$env:ARROW_DEPENDENCY_SOURCE"
Write-Host "  ARROW_FLIGHT_SQL_ODBC=$env:ARROW_FLIGHT_SQL_ODBC"
Write-Host "  ARROW_FLIGHT_SQL_ODBC_INSTALLER=$env:ARROW_FLIGHT_SQL_ODBC_INSTALLER"
Write-Host "  ARROW_USE_CCACHE=$env:ARROW_USE_CCACHE"
Write-Host "  VCPKG_DEFAULT_TRIPLET=$env:VCPKG_DEFAULT_TRIPLET"
Write-Host ""

# Check for Visual Studio and set up the environment
Write-Info "Setting up Visual Studio environment..."

$VcvarsallPaths = @(
    "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvarsall.bat",
    "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat",
    "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\Enterprise\VC\Auxiliary\Build\vcvarsall.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\VC\Auxiliary\Build\vcvarsall.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat"
)

$VcvarsallPath = $null
foreach ($path in $VcvarsallPaths) {
    if (Test-Path $path) {
        $VcvarsallPath = $path
        Write-Info "Found vcvarsall.bat at: $VcvarsallPath"
        break
    }
}

if (-not $VcvarsallPath) {
    Write-Error-Custom "Could not find vcvarsall.bat. Please ensure Visual Studio is installed."
    exit 1
}

Write-Host ""
Write-Info "Starting build..."
Write-Info "This may take a while (30-60 minutes for first build)..."
Write-Host ""

# Build using cmd to call vcvarsall
$VcpkgRootKeep = $env:VCPKG_ROOT
cmd /c "`"$VcvarsallPath`" x64 && set VCPKG_ROOT=$VcpkgRootKeep && bash -c `"ci/scripts/cpp_build.sh `$(pwd) `$(pwd)/build`""

if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "Build failed!"
    exit 1
}

Write-Host ""
Write-Info "Build completed successfully!"
Write-Host ""

# Run tests if requested
if (-not $SkipTests) {
    Write-Info "Registering ODBC driver for testing..."

    $OdbcDllPath = Join-Path $BuildDir "cpp\$BuildType\arrow_flight_sql_odbc.dll"
    if (Test-Path $OdbcDllPath) {
        cmd /c "cpp\src\arrow\flight\sql\odbc\tests\install_odbc.cmd `"$OdbcDllPath`""

        Write-Host ""
        Write-Info "Running tests..."

        # Convert VCPKG Windows path to MSYS path for tests
        $VcpkgRootMsys = bash -c "cygpath -u `"$VcpkgRootKeep`""
        cmd /c "`"$VcvarsallPath`" x64 && set VCPKG_ROOT=$VcpkgRootMsys && bash -c `"ci/scripts/cpp_test.sh `$(pwd) `$(pwd)/build`""

        if ($LASTEXITCODE -eq 0) {
            Write-Info "Tests passed!"
        } else {
            Write-Warn "Some tests failed. Check the output above for details."
        }
    } else {
        Write-Error-Custom "ODBC DLL not found at $OdbcDllPath. Cannot run tests."
    }
}

# Build installer if requested
if ($BuildInstaller) {
    Write-Host ""
    Write-Info "Building MSI installer..."

    if (Get-Command wix -ErrorAction SilentlyContinue) {
        Push-Location "$BuildDir\cpp"
        cpack

        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Info "MSI installer built successfully!"
            $MsiFiles = Get-ChildItem -Filter "*.msi" -File
            foreach ($msi in $MsiFiles) {
                Write-Info "MSI installer: $($msi.FullName)"
            }
        } else {
            Write-Error-Custom "Failed to build MSI installer."
        }
        Pop-Location
    } else {
        Write-Error-Custom "WiX Toolset not found. Cannot build MSI installer."
        Write-Info "Install WiX from: https://github.com/wixtoolset/wix/releases"
    }
}

Write-Host ""
Write-Info "=================================================="
Write-Info "Build Summary"
Write-Info "=================================================="
Write-Info "Build directory: $BuildDir"
Write-Info "ODBC DLL: $BuildDir\cpp\$BuildType\arrow_flight_sql_odbc.dll"
Write-Host ""
Write-Info "To register the ODBC driver manually:"
Write-Info "  cmd /c cpp\src\arrow\flight\sql\odbc\tests\install_odbc.cmd `"$BuildDir\cpp\$BuildType\arrow_flight_sql_odbc.dll`""
Write-Host ""
Write-Info "Build completed!"
