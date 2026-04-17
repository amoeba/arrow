#!/usr/bin/env bash
#
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
# FlightSQL ODBC Release Signing Script
#
# This script handles the signing of FlightSQL ODBC Windows binaries and MSI installer.
# It requires jsign to be configured with ASF code signing credentials.
#
# Process:
# TODO

set -e
set -u
set -o pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <version> <rc-num>"
  exit 1
fi

# Temporary override? After this works well we can just use gh default.
 : "${GITHUB_REPOSITORY:=amoeba/arrow}"
 echo "GITHUB_REPOSITORY: ${GITHUB_REPOSITORY}"

# TODO: Verify our JSIGN credential is in place now
# ...

. "${SOURCE_DIR}/utils-env.sh"

version=$1
rc=$2

version_with_rc="${version}-rc${rc}"
# TODO: put backto 'apache' before merge
tag="AMOEBA-arrow-${version_with_rc}"

dll_unsigned="arrow_flight_sql_odbc_unsigned.dll"
dll_signed="arrow_flight_sql_odbc.dll"

: ${UPLOAD_DEFAULT=0}
# TODO: More steps here

# Do all of this in a temp dir
tmp_dir="flightsql-odbc-signing"
mkdir -p "${tmp_dir}"

echo "[1/9] Downloading ${dll_unsigned} from release"
# Download dll_unsigned from release
gh release download "${tag}" \
  --repo "${GITHUB_REPOSITORY}" \
  --pattern "${dll_unsigned}" \
  --dir "${tmp_dir}"

echo "[2/9] Signing ${dll_signed}..."
# TODO: Sign the ${dll_signed}
# jsign ...
# XXX: Temporary command to skip signing
mv "${tmp_dir}/${dll_unsigned}" "${tmp_dir}/${dll_signed}"

echo "[3/9] Uploading signed DLL to GitHub Release..."
gh release upload "${tag}" \
  --repo "${GITHUB_REPOSITORY}" \
  --clobber \
  "${tmp_dir}/${dll_signed}"

echo "[4/9] Triggering odbc_release_step in cpp_extra.yml workflow..."
gh workflow run cpp_extra.yml \
  --repo "${GITHUB_REPOSITORY}" \
  --ref "${tag}" \
  --field odbc_release_step=true

echo "[5/9] Waiting for workflow to complete..."
echo "Sleeping 5s..."
sleep 5

run_id=$(gh run list \
  --repo "${GITHUB_REPOSITORY}" \
  --workflow cpp_extra.yml \
  --ref "${tag}" \
  --limit 1 \
  --json databaseId \
  --jq '.[0].databaseId')

echo "Found run_id: ${run_id}. Watching..."
gh run watch "${run_id}" --repo "${GITHUB_REPOSITORY}" --exit-status
echo "Run id ${run_id} completed."

echo "[6/9] Downloading unsigned MSI..."
gh release download "${tag}" \
  --repo "${GITHUB_REPOSITORY}" \
  --pattern "Apache-Arrow-Flight-SQL-ODBC-*-win64.msi" \
  --dir "${tmp_dir}"

echo "[7/9] Signing MSI..."
# TODO: Sign the MSI installer
# jsign ...

echo "[8/9] Uploading signed MSI to GitHub Release..."
gh release upload "${tag}" \
  --repo "${GITHUB_REPOSITORY}" \
  --clobber \
  "${tmp_dir}/Apache-Arrow-Flight-SQL-ODBC-${version}-win64.msi"

echo "[9/9] Verifying uploaded MSI is signed..."
# TODO
