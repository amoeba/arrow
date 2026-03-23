@echo off
REM Licensed to the Apache Software Foundation (ASF) under one
REM or more contributor license agreements.  See the NOTICE file
REM distributed with this work for additional information
REM regarding copyright ownership.  The ASF licenses this file
REM to you under the Apache License, Version 2.0 (the
REM "License"); you may not use this file except in compliance
REM with the License.  You may obtain a copy of the License at
REM
REM   http://www.apache.org/licenses/LICENSE-2.0
REM
REM Unless required by applicable law or agreed to in writing,
REM software distributed under the License is distributed on an
REM "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
REM KIND, either express or implied.  See the License for the
REM specific language governing permissions and limitations
REM under the License.
REM
REM CMD build script for Apache Arrow Flight SQL ODBC Driver on Windows

setlocal enabledelayedexpansion

echo Apache Arrow Flight SQL ODBC Driver Build Script
echo ==================================================

REM Parse command line arguments
set BUILD_TYPE=%1
if "%BUILD_TYPE%"=="" set BUILD_TYPE=release

set RUN_TESTS=%2
if "%RUN_TESTS%"=="" set RUN_TESTS=yes

echo Build Type: %BUILD_TYPE%
echo Run Tests: %RUN_TESTS%
echo.

REM Get the Arrow source directory
set SOURCE_DIR=%~dp0
set BUILD_DIR=%SOURCE_DIR%build

echo Source directory: %SOURCE_DIR%
echo Build directory: %BUILD_DIR%
echo.

REM Check for CMake
where cmake >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: cmake not found. Please install CMake.
    exit /b 1
)

echo CMake found.
echo.

REM Set up vcpkg
set VCPKG_ROOT=C:\vcpkg
if not exist "%VCPKG_ROOT%" (
    echo vcpkg not found at %VCPKG_ROOT%.
    echo Cloning vcpkg repository...
    git clone https://github.com/microsoft/vcpkg.git "%VCPKG_ROOT%"
    echo Bootstrapping vcpkg...
    cd "%VCPKG_ROOT%"
    call bootstrap-vcpkg.bat
    cd "%SOURCE_DIR%"
) else (
    echo vcpkg directory found at %VCPKG_ROOT%
    echo Updating vcpkg...
    cd "%VCPKG_ROOT%"
    git fetch --all
    git pull
    cd "%SOURCE_DIR%"
)

echo VCPKG_ROOT set to: %VCPKG_ROOT%
echo.

REM Download timezone database
echo Downloading timezone database...
if exist "ci\scripts\download_tz_database.sh" (
    bash ci/scripts/download_tz_database.sh
) else (
    echo WARNING: download_tz_database.sh not found, skipping.
)
echo.

REM Set environment variables for the build
set ARROW_BUILD_SHARED=ON
set ARROW_BUILD_STATIC=OFF
set ARROW_BUILD_TESTS=ON
set ARROW_BUILD_TYPE=%BUILD_TYPE%
set ARROW_CSV=OFF
set ARROW_DEPENDENCY_SOURCE=VCPKG
set ARROW_FLIGHT_SQL_ODBC=ON
set ARROW_FLIGHT_SQL_ODBC_INSTALLER=ON

set ARROW_HOME=/usr
set ARROW_USE_CCACHE=OFF
set CMAKE_GENERATOR=Ninja
set CMAKE_INSTALL_PREFIX=/usr
set VCPKG_DEFAULT_TRIPLET=x64-windows

echo Environment variables set:
echo   ARROW_BUILD_SHARED=%ARROW_BUILD_SHARED%
echo   ARROW_BUILD_STATIC=%ARROW_BUILD_STATIC%
echo   ARROW_BUILD_TESTS=%ARROW_BUILD_TESTS%
echo   ARROW_BUILD_TYPE=%ARROW_BUILD_TYPE%
echo   ARROW_CSV=%ARROW_CSV%
echo   ARROW_DEPENDENCY_SOURCE=%ARROW_DEPENDENCY_SOURCE%
echo   ARROW_FLIGHT_SQL_ODBC=%ARROW_FLIGHT_SQL_ODBC%
echo   ARROW_FLIGHT_SQL_ODBC_INSTALLER=%ARROW_FLIGHT_SQL_ODBC_INSTALLER%
echo   ARROW_USE_CCACHE=%ARROW_USE_CCACHE%
echo   VCPKG_DEFAULT_TRIPLET=%VCPKG_DEFAULT_TRIPLET%
echo.

REM Find Visual Studio
echo Setting up Visual Studio environment...

set "VCVARSALL_PATH="

if exist "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvarsall.bat" (
    set "VCVARSALL_PATH=C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvarsall.bat"
    goto :found_vs
)
if exist "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat" (
    set "VCVARSALL_PATH=C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat"
    goto :found_vs
)
if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" (
    set "VCVARSALL_PATH=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat"
    goto :found_vs
)
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\Enterprise\VC\Auxiliary\Build\vcvarsall.bat" (
    set "VCVARSALL_PATH=C:\Program Files (x86)\Microsoft Visual Studio\2019\Enterprise\VC\Auxiliary\Build\vcvarsall.bat"
    goto :found_vs
)
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\VC\Auxiliary\Build\vcvarsall.bat" (
    set "VCVARSALL_PATH=C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\VC\Auxiliary\Build\vcvarsall.bat"
    goto :found_vs
)
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat" (
    set "VCVARSALL_PATH=C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat"
    goto :found_vs
)

echo ERROR: Could not find vcvarsall.bat. Please ensure Visual Studio is installed.
exit /b 1

:found_vs
echo Found vcvarsall.bat at: %VCVARSALL_PATH%
echo.

REM Setup Visual Studio environment
call "%VCVARSALL_PATH%" x64
if %errorlevel% neq 0 (
    echo ERROR: Failed to setup Visual Studio environment.
    exit /b 1
)

echo.
echo Starting build...
echo This may take a while (30-60 minutes for first build)...
echo.

REM Run the build
bash -c "ci/scripts/cpp_build.sh $(pwd) $(pwd)/build"
if %errorlevel% neq 0 (
    echo.
    echo ERROR: Build failed!
    exit /b 1
)

echo.
echo Build completed successfully!
echo.

REM Run tests if requested
if "%RUN_TESTS%"=="yes" (
    echo Registering ODBC driver for testing...

    set ODBC_DLL_PATH=%BUILD_DIR%\cpp\%BUILD_TYPE%\arrow_flight_sql_odbc.dll
    if exist "!ODBC_DLL_PATH!" (
        call cpp\src\arrow\flight\sql\odbc\tests\install_odbc.cmd "!ODBC_DLL_PATH!"

        echo.
        echo Running tests...
        bash -c "ci/scripts/cpp_test.sh $(pwd) $(pwd)/build"

        if !errorlevel! equ 0 (
            echo Tests passed!
        ) else (
            echo WARNING: Some tests failed. Check the output above for details.
        )
    ) else (
        echo ERROR: ODBC DLL not found at !ODBC_DLL_PATH!. Cannot run tests.
    )
)

REM Build installer if requested
if "%BUILD_INSTALLER%"=="yes" (
    echo.
    echo Building MSI installer...

    where wix >nul 2>&1
    if %errorlevel% equ 0 (
        cd "%BUILD_DIR%\cpp"
        cpack

        if %errorlevel% equ 0 (
            echo.
            echo MSI installer built successfully!
            dir /b *.msi
        ) else (
            echo ERROR: Failed to build MSI installer.
        )
        cd "%SOURCE_DIR%"
    ) else (
        echo ERROR: WiX Toolset not found. Cannot build MSI installer.
        echo Install WiX from: https://github.com/wixtoolset/wix/releases
    )
)

echo.
echo ==================================================
echo Build Summary
echo ==================================================
echo Build directory: %BUILD_DIR%
echo ODBC DLL: %BUILD_DIR%\cpp\%BUILD_TYPE%\arrow_flight_sql_odbc.dll
echo.
echo To register the ODBC driver manually:
echo   cpp\src\arrow\flight\sql\odbc\tests\install_odbc.cmd "%BUILD_DIR%\cpp\%BUILD_TYPE%\arrow_flight_sql_odbc.dll"
echo.
echo Build completed!
