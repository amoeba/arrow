# Implementation Plan: ODBC MSI Build Artifact Control

## Problem Analysis

After investigating the workflow triggers, the current setup **already builds from the correct git hash** when an RC tag is pushed:

1. RC tag `apache-arrow-17.0.0-rc0` points to commit A
2. GitHub Actions triggers on the tag push
3. `check-labels` sets `force=true` for push events
4. `odbc-msvc` and `odbc-release` both checkout the commit the tag points to
5. MSI is built from commit A

**However**, we want the release manager to have control over MSI creation, similar to how they sign and upload other artifacts. This allows for:
- Consistent signing process (all artifacts signed together locally)
- Ability to rebuild MSI if needed without re-running CI
- Better separation of CI testing vs release packaging

## Goals

1. **For CI/non-release builds**: Continue building DLL → creating MSI → testing
2. **For release builds (RC tags)**: Build and test DLL, then upload **raw build artifacts** (not MSI)
3. **For release upload**: Download raw artifacts → create MSI locally → sign → upload

## Revised Architecture

### Current Flow
```
CI on RC tag push:
  - Build DLL
  - Create MSI via cpack
  - Upload MSI to GitHub Release
Release manager:
  - Download MSI
  - Sign
  - Re-upload
```

### New Flow
```
CI on RC tag push:
  - Build DLL
  - Test DLL
  - Package raw build artifacts (DLLs, WiX sources, CMake files)
  - Upload tarball to GitHub Release

CI on non-release (PRs, main branch, nightlies):
  - Build DLL
  - Create MSI via cpack
  - Test MSI installation
  - Upload MSI to nightlies (for nightly builds)

Release manager:
  - Download tarball from GitHub Release
  - Extract and run cpack to create MSI
  - Sign MSI
  - Upload final MSI to GitHub Release
```

---

## Detailed Implementation Steps

### Step 1: Modify `cpp_extra.yml` - Add Conditional Behavior

**File**: `.github/workflows/cpp_extra.yml`

**Modify the `odbc-msvc` job** (starting at line 450):

Add a condition to detect if this is a release build:

```yaml
- name: Check if release build
  id: release-check
  shell: bash
  run: |
    if [[ "${GITHUB_REF_TYPE}" == "tag" ]] && \
       [[ "${GITHUB_REF_NAME}" == apache-arrow-*-rc* ]]; then
      echo "is_release=true" >> $GITHUB_OUTPUT
    else
      echo "is_release=false" >> $GITHUB_OUTPUT
    fi
```

**Modify the WiX installation and MSI building steps** (lines 560-578):

```yaml
- name: Install WiX Toolset
  if: steps.release-check.outputs.is_release == 'false'
  shell: pwsh
  run: |
    Invoke-WebRequest -Uri https://github.com/wixtoolset/wix/releases/download/v6.0.0/wix-cli-x64.msi -OutFile wix-cli-x64.msi
    Start-Process -FilePath wix-cli-x64.msi -ArgumentList '/quiet', 'Include_freethreaded=1' -Wait
    echo "C:\Program Files\WiX Toolset v6.0\bin\" | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append

- name: Build MSI ODBC installer
  if: steps.release-check.outputs.is_release == 'false'
  shell: pwsh
  run: |
    wix --version
    cd build/cpp
    cpack

- name: Upload the artifacts to the job
  if: steps.release-check.outputs.is_release == 'false'
  uses: actions/upload-artifact@v7
  with:
    name: flight-sql-odbc-msi-installer
    path: build/cpp/Apache-Arrow-Flight-SQL-ODBC-*-win64.msi
    if-no-files-found: error
```

**Add new step to package build artifacts for releases**:

```yaml
- name: Package build artifacts for release
  if: steps.release-check.outputs.is_release == 'true'
  shell: bash
  run: |
    cd build/cpp
    # Get version from CMakeLists.txt or environment
    ARROW_VERSION=$(grep 'set(ARROW_VERSION' ../../cpp/CMakeLists.txt | \
                    grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

    # Create tarball with everything needed for cpack to create MSI
    tar -czf ../../odbc-build-windows-${ARROW_VERSION}.tar.gz \
      release/*.dll \
      release/*.lib \
      _CPack_Packages/ \
      CPackConfig.cmake \
      CPackSourceConfig.cmake \
      cmake_install.cmake

    # Also include WiX sources and other needed files from source tree
    cd ../..
    tar -rf odbc-build-windows-${ARROW_VERSION}.tar.gz \
      --transform 's|^|arrow/|' \
      LICENSE.txt \
      cpp/src/arrow/flight/sql/odbc/install/

- name: Upload build artifacts to the job
  if: steps.release-check.outputs.is_release == 'true'
  uses: actions/upload-artifact@v7
  with:
    name: flight-sql-odbc-build-artifacts
    path: odbc-build-windows-*.tar.gz
    if-no-files-found: error
```

**Modify the MSI installation test** (lines 579-613):

```yaml
- name: Install ODBC MSI
  if: steps.release-check.outputs.is_release == 'false'
  run: |
    cd build/cpp
    $odbc_msi = Get-ChildItem -Filter "Apache-Arrow-Flight-SQL-ODBC-*-win64.msi"
    if (-not $odbc_msi) {
      Write-Error "ODBC MSI not found"
      exit 1
    }
    # ... rest of installation test

- name: Check ODBC DLL installation
  if: steps.release-check.outputs.is_release == 'false'
  run: |
    # ... rest of DLL check
```

---

### Step 2: Modify `odbc-release` Job

**File**: `.github/workflows/cpp_extra.yml` (lines 661-692)

**Replace the entire job** with:

```yaml
  odbc-release:
    needs: odbc-msvc
    name: ODBC release
    runs-on: ubuntu-latest
    if: ${{ startsWith(github.ref_name, 'apache-arrow-') && contains(github.ref_name, '-rc') }}
    permissions:
      contents: write
    steps:
      - name: Checkout Arrow
        uses: actions/checkout@v6
        with:
          fetch-depth: 0
          submodules: recursive
      - name: Download the build artifacts
        uses: actions/download-artifact@v8
        with:
          name: flight-sql-odbc-build-artifacts
      - name: Wait for creating GitHub Release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          dev/release/utils-watch-gh-workflow.sh \
            ${GITHUB_REF_NAME} \
            release_candidate.yml
      - name: Upload the build artifacts to GitHub Release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release upload ${GITHUB_REF_NAME} \
            --clobber \
            odbc-build-windows-*.tar.gz
```

---

### Step 3: Modify `odbc-nightly` Job (No Changes Needed)

**File**: `.github/workflows/cpp_extra.yml` (lines 615-659)

This job should continue to work as-is because:
- It depends on `odbc-msvc` which will still create MSI for non-release builds
- The condition `github.event_name == 'schedule'` ensures it only runs on scheduled builds
- Scheduled builds are not tag pushes, so `is_release` will be `false` and MSI will be created

---

### Step 4: Update `04-binary-download.sh`

**File**: `dev/release/04-binary-download.sh`

**Modify lines 47-59**:

```bash
archery crossbow download-artifacts --no-fetch ${CROSSBOW_JOB_ID} "$@"

# Download Linux packages and ODBC build artifacts.
gh release download "${tag}" \
  --dir "packages/${CROSSBOW_JOB_ID}" \
  --pattern "almalinux-*.tar.gz" \
  --pattern "amazon-linux-*.tar.gz" \
  --pattern "centos-*.tar.gz" \
  --pattern "debian-*.tar.gz" \
  --pattern "ubuntu-*.tar.gz" \
  --pattern "odbc-build-windows-*.tar.gz" \
  --repo "${REPOSITORY:-apache/arrow}" \
  --skip-existing
```

**Key change**: Changed from downloading `Apache-Arrow-Flight-SQL-ODBC-*-win64.msi` to `odbc-build-windows-*.tar.gz`

---

### Step 5: Update `05-binary-upload.sh`

**File**: `dev/release/05-binary-upload.sh`

**Add new function after line 107** (after `upload_to_github_release` function):

```bash
create_odbc_msi() {
  local version="$1"
  local rc="$2"

  echo "Creating ODBC MSI from build artifacts..."

  # Find the ODBC build tarball
  local odbc_tarball=$(find "${ARROW_ARTIFACTS_DIR}" -name "odbc-build-windows-*.tar.gz" | head -n 1)
  if [ -z "${odbc_tarball}" ]; then
    echo "ERROR: ODBC build tarball not found in ${ARROW_ARTIFACTS_DIR}"
    return 1
  fi

  echo "Found ODBC build tarball: ${odbc_tarball}"

  # Extract to temporary directory
  local odbc_work_dir="${tmp_dir}/odbc-build"
  mkdir -p "${odbc_work_dir}"
  tar -xzf "${odbc_tarball}" -C "${odbc_work_dir}"

  # Check if we're on a system that can run WiX
  if [[ "$OSTYPE" != "msys" ]] && [[ "$OSTYPE" != "win32" ]]; then
    echo "ERROR: MSI creation requires Windows. Please run this script on Windows or WSL2 with Windows tools."
    echo "Alternatively, use a Windows Docker container."
    return 1
  fi

  # Install WiX if not already available
  if ! command -v wix &> /dev/null; then
    echo "Installing WiX Toolset..."
    curl -L https://github.com/wixtoolset/wix/releases/download/v6.0.0/wix-cli-x64.msi -o /tmp/wix-cli-x64.msi
    msiexec //i /tmp/wix-cli-x64.msi //quiet Include_freethreaded=1
    export PATH="/c/Program Files/WiX Toolset v6.0/bin:${PATH}"
  fi

  # Verify WiX version
  wix --version || {
    echo "ERROR: WiX not found. Cannot create MSI."
    return 1
  }

  # Navigate to build directory
  cd "${odbc_work_dir}/build/cpp"

  # Run cpack to create MSI
  echo "Running cpack to create MSI..."
  cpack || {
    echo "ERROR: cpack failed"
    cd -
    return 1
  }

  # Find the generated MSI
  local msi_file=$(find . -name "Apache-Arrow-Flight-SQL-ODBC-*-win64.msi" | head -n 1)
  if [ -z "${msi_file}" ]; then
    echo "ERROR: MSI not created by cpack"
    cd -
    return 1
  fi

  echo "MSI created: ${msi_file}"

  # Move MSI to tmp directory for signing
  local msi_name=$(basename "${msi_file}")
  mkdir -p "${tmp_dir}/odbc"
  cp "${msi_file}" "${tmp_dir}/odbc/${msi_name}"

  cd -
  echo "ODBC MSI ready for signing: ${tmp_dir}/odbc/${msi_name}"
  return 0
}
```

**Update the ODBC upload section** (lines 112-114):

```bash
if [ "${UPLOAD_ODBC}" -gt 0 ]; then
  # Create MSI from build artifacts
  if ! create_odbc_msi "${version}" "${rc}"; then
    echo "ERROR: Failed to create ODBC MSI"
    exit 1
  fi

  # Sign and upload the MSI
  upload_to_github_release odbc "${tmp_dir}"/odbc/*.msi
fi
```

---

## Testing Plan

### Phase 1: Test on a Branch (Non-Release Build)

1. Create a test branch and push:
   ```bash
   git checkout -b test-odbc-build
   # Make changes to cpp_extra.yml
   git push origin test-odbc-build
   ```

2. Verify in CI:
   - `odbc-msvc` job runs
   - `is_release` is `false`
   - MSI is created via cpack
   - MSI installation tests pass

### Phase 2: Test with a Test RC Tag

1. Create a test RC tag on your fork:
   ```bash
   git tag apache-arrow-99.0.0-rc0
   git push origin apache-arrow-99.0.0-rc0
   ```

2. Verify in CI:
   - `odbc-msvc` job runs
   - `is_release` is `true`
   - Build artifacts tarball is created (not MSI)
   - `odbc-release` job uploads tarball to GitHub Release

3. Test download:
   ```bash
   REPOSITORY=youruser/arrow ./04-binary-download.sh 99.0.0 0
   # Verify tarball is in packages/release-99.0.0-rc0-0/
   ```

4. Test MSI creation (requires Windows):
   ```bash
   # On Windows machine or WSL2
   ./05-binary-upload.sh 99.0.0 0
   # Verify MSI is created in tmp directory
   ```

### Phase 3: Verify Nightlies Still Work

1. Wait for next scheduled nightly build
2. Verify:
   - MSI is still created and uploaded to nightlies
   - No regression in nightly behavior

---

## Critical Considerations

### Running on Windows for MSI Creation

The `05-binary-upload.sh` script now **requires Windows** to run (at least the ODBC MSI creation part).

**Options**:

1. **Release manager runs on Windows**
   - Simplest approach
   - Can use WSL2 with Windows tools accessible

2. **Split the script**
   - `05-binary-upload.sh` for Linux artifacts
   - `05-binary-upload-windows.ps1` for ODBC MSI

3. **Use Docker with Windows containers**
   - More complex but allows running from Linux
   - Requires Docker Desktop on Windows

**Recommendation**: Document that ODBC MSI creation requires Windows, provide clear instructions for release managers.

---

## Benefits of This Approach

✅ **No Crossbow changes needed** - Simpler, fewer moving parts
✅ **CI continues to work** - MSI still created and tested on PRs/main/nightlies
✅ **Proper provenance** - MSI built from artifacts at exact RC tag commit
✅ **Release manager control** - MSI creation happens during upload step
✅ **Consistent signing** - All artifacts signed together locally
✅ **Rebuild capability** - Can rebuild MSI from downloaded artifacts if needed
✅ **Backward compatible** - Nightlies and CI workflows unchanged

---

## Summary of Changes

1. **`cpp_extra.yml`**: Add conditional logic to create MSI for non-release, tarball for release
2. **`04-binary-download.sh`**: Download tarball instead of MSI for releases
3. **`05-binary-upload.sh`**: Add function to create MSI from tarball, requires Windows

Total files changed: **3**

No new files needed, no Crossbow integration required.
