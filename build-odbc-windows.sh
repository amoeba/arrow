#!/usr/bin/env bash
set -e

# Parse command line arguments
BUILD_TYPE="${1:-release}"
RUN_TESTS="${2:-yes}"
BUILD_INSTALLER="${3:-no}"

echo "Apache Arrow Flight SQL ODBC Driver Build Script"
echo "=================================================="
echo "Build Type: ${BUILD_TYPE}"
echo "Run Tests: ${RUN_TESTS}"
echo "Build Installer: ${BUILD_INSTALLER}"
echo ""

# Get the Arrow source directory (script location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}"
BUILD_DIR="${SOURCE_DIR}/build"

echo "Source directory: ${SOURCE_DIR}"
echo "Build directory: ${BUILD_DIR}"
echo ""

# Check for required tools
echo "Checking for required tools..."

if ! command -v cmake &> /dev/null; then
    echo "ERROR: cmake not found. Please install CMake."
    exit 1
fi

echo "CMake found. Visual Studio will provide Ninja and compilers."
echo ""

# Set up vcpkg
VCPKG_ROOT="${VCPKG_ROOT:-C:/vcpkg}"
if [ ! -d "${VCPKG_ROOT}" ]; then
    echo "vcpkg not found at ${VCPKG_ROOT}."
    echo "Cloning vcpkg repository..."
    git clone https://github.com/microsoft/vcpkg.git "${VCPKG_ROOT}"
    echo "Bootstrapping vcpkg..."
    cd "${VCPKG_ROOT}"
    cmd //c bootstrap-vcpkg.bat
    cd "${SOURCE_DIR}"
else
    echo "vcpkg directory found at ${VCPKG_ROOT}"
    echo "Updating vcpkg..."
    cd "${VCPKG_ROOT}"
    git fetch --all
    git pull
    cd "${SOURCE_DIR}"
fi

export VCPKG_ROOT
echo "VCPKG_ROOT set to: ${VCPKG_ROOT}"
echo ""

# Disable ccache for local builds
export ARROW_USE_CCACHE=OFF
echo "ccache disabled"
echo ""

# Download timezone database
echo "Downloading timezone database..."
if [ -f "ci/scripts/download_tz_database.sh" ]; then
    ci/scripts/download_tz_database.sh
else
    echo "WARNING: download_tz_database.sh not found, skipping."
fi
echo ""

# Set environment variables for the build
export ARROW_BUILD_SHARED=ON
export ARROW_BUILD_STATIC=OFF
export ARROW_BUILD_TESTS=ON
export ARROW_BUILD_TYPE="${BUILD_TYPE}"
export ARROW_CSV=OFF
export ARROW_DEPENDENCY_SOURCE=VCPKG
export ARROW_FLIGHT_SQL_ODBC=ON
if [ "${BUILD_INSTALLER}" = "yes" ]; then
    export ARROW_FLIGHT_SQL_ODBC_INSTALLER=ON
else
    export ARROW_FLIGHT_SQL_ODBC_INSTALLER=OFF
fi
export ARROW_HOME=/usr
export CMAKE_GENERATOR=Ninja
export CMAKE_INSTALL_PREFIX=/usr
export VCPKG_DEFAULT_TRIPLET=x64-windows

echo "Environment variables set:"
echo "  ARROW_BUILD_SHARED=${ARROW_BUILD_SHARED}"
echo "  ARROW_BUILD_STATIC=${ARROW_BUILD_STATIC}"
echo "  ARROW_BUILD_TESTS=${ARROW_BUILD_TESTS}"
echo "  ARROW_BUILD_TYPE=${ARROW_BUILD_TYPE}"
echo "  ARROW_CSV=${ARROW_CSV}"
echo "  ARROW_DEPENDENCY_SOURCE=${ARROW_DEPENDENCY_SOURCE}"
echo "  ARROW_FLIGHT_SQL_ODBC=${ARROW_FLIGHT_SQL_ODBC}"
echo "  ARROW_FLIGHT_SQL_ODBC_INSTALLER=${ARROW_FLIGHT_SQL_ODBC_INSTALLER}"
echo "  ARROW_USE_CCACHE=${ARROW_USE_CCACHE}"
echo "  VCPKG_DEFAULT_TRIPLET=${VCPKG_DEFAULT_TRIPLET}"
echo ""

# Check for Visual Studio and set up the environment
echo "Setting up Visual Studio environment..."

VCVARSALL_PATHS=(
    "C:\\Program Files\\Microsoft Visual Studio\\2022\\Enterprise\\VC\\Auxiliary\\Build\\vcvarsall.bat"
    "C:\\Program Files\\Microsoft Visual Studio\\2022\\Professional\\VC\\Auxiliary\\Build\\vcvarsall.bat"
    "C:\\Program Files\\Microsoft Visual Studio\\2022\\Community\\VC\\Auxiliary\\Build\\vcvarsall.bat"
    "C:\\Program Files (x86)\\Microsoft Visual Studio\\2019\\Enterprise\\VC\\Auxiliary\\Build\\vcvarsall.bat"
    "C:\\Program Files (x86)\\Microsoft Visual Studio\\2019\\Professional\\VC\\Auxiliary\\Build\\vcvarsall.bat"
    "C:\\Program Files (x86)\\Microsoft Visual Studio\\2019\\Community\\VC\\Auxiliary\\Build\\vcvarsall.bat"
)

VCVARSALL_PATH=""
for path in "${VCVARSALL_PATHS[@]}"; do
    if [ -f "$path" ]; then
        VCVARSALL_PATH="$path"
        echo "Found vcvarsall.bat at: ${VCVARSALL_PATH}"
        break
    fi
done

if [ -z "${VCVARSALL_PATH}" ]; then
    echo "ERROR: Could not find vcvarsall.bat. Please ensure Visual Studio is installed."
    exit 1
fi

mkdir -p "${BUILD_DIR}"

# Create a wrapper script to call vcvarsall and then run the build
WRAPPER_SCRIPT="${BUILD_DIR}/build_wrapper.cmd"

cat > "${WRAPPER_SCRIPT}" << EOF
@echo off
set VCPKG_ROOT_KEEP=%VCPKG_ROOT%
call "${VCVARSALL_PATH}" x64
if %errorlevel% neq 0 exit /b %errorlevel%
set VCPKG_ROOT=%VCPKG_ROOT_KEEP%
bash -c "ci/scripts/cpp_build.sh \$(pwd) \$(pwd)/build"
EOF

echo ""
echo "Starting build..."
echo "This may take a while (30-60 minutes for first build)..."
echo ""

# Run the build
cd "${SOURCE_DIR}"
cmd //c "${WRAPPER_SCRIPT}"

if [ $? -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi

echo ""
echo "Build completed successfully!"
echo ""

# Run tests if requested
if [ "${RUN_TESTS}" = "yes" ]; then
    echo "Registering ODBC driver for testing..."

    # Register the ODBC driver
    ODBC_DLL_PATH="${BUILD_DIR}/cpp/${BUILD_TYPE}/arrow_flight_sql_odbc.dll"
    if [ -f "${ODBC_DLL_PATH}" ]; then
        cmd //c "cpp\\src\\arrow\\flight\\sql\\odbc\\tests\\install_odbc.cmd ${ODBC_DLL_PATH}"

        echo ""
        echo "Running tests..."

        # Create test wrapper script
        TEST_WRAPPER="${BUILD_DIR}/test_wrapper.cmd"
        cat > "${TEST_WRAPPER}" << EOF
@echo off
set VCPKG_ROOT_KEEP=%VCPKG_ROOT%
call "${VCVARSALL_PATH}" x64
if %errorlevel% neq 0 exit /b %errorlevel%
set VCPKG_ROOT=%VCPKG_ROOT_KEEP%
REM Convert VCPKG Windows path to MSYS path
for /f "usebackq delims=" %%I in (\`bash -c "cygpath -u \"%VCPKG_ROOT_KEEP%\""\`) do set VCPKG_ROOT=%%I
bash -c "ci/scripts/cpp_test.sh \$(pwd) \$(pwd)/build"
EOF

        cd "${SOURCE_DIR}"
        cmd //c "${TEST_WRAPPER}"

        if [ $? -eq 0 ]; then
            echo "Tests passed!"
        else
            echo "WARNING: Some tests failed. Check the output above for details."
        fi
    else
        echo "ODBC DLL not found at ${ODBC_DLL_PATH}. Cannot run tests."
    fi
fi

# Build installer if requested
if [ "${BUILD_INSTALLER}" = "yes" ]; then
    echo ""
    echo "Building MSI installer..."

    # Check if WiX is installed
    if command -v wix &> /dev/null; then
        cd "${BUILD_DIR}/cpp"
        cpack

        if [ $? -eq 0 ]; then
            echo ""
            echo "MSI installer built successfully!"
            MSI_PATH=$(find . -name "*.msi" -type f)
            if [ -n "${MSI_PATH}" ]; then
                echo "MSI installer: ${MSI_PATH}"
            fi
        else
            echo "Failed to build MSI installer."
        fi
    else
        echo "WiX Toolset not found. Cannot build MSI installer."
        echo "Install WiX from: https://github.com/wixtoolset/wix/releases"
    fi
fi

echo ""
echo "=================================================="
echo "Build Summary"
echo "=================================================="
echo "Build directory: ${BUILD_DIR}"
echo "ODBC DLL: ${BUILD_DIR}/cpp/${BUILD_TYPE}/arrow_flight_sql_odbc.dll"
echo ""
echo "To register the ODBC driver manually:"
echo "  cmd //c cpp\\src\\arrow\\flight\\sql\\odbc\\tests\\install_odbc.cmd ${BUILD_DIR}/cpp/${BUILD_TYPE}/arrow_flight_sql_odbc.dll"
echo ""
echo "Build completed!"
