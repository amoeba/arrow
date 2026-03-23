jsign stuff

update 05-release-binary.sh to have a jsign step

diff --git a/dev/release/05-binary-upload.sh b/dev/release/05-binary-upload.sh
index f628cce0e0..e66b5af646 100755
--- a/dev/release/05-binary-upload.sh
+++ b/dev/release/05-binary-upload.sh
@@ -98,6 +98,9 @@ upload_to_github_release() {
       shasum -a 512 "${base_name}" >"${base_name}.sha512"
       popd
     fi
+    if [[ "${base_name}" = *.msi ]]; then
+      jsign ... "${dist_dir}/${base_name}"
+    fi
   done
   gh release upload \
     --repo apache/arrow \

make it really helpful

so we need to build the .MSI at release time!!!


https://infra.apache.org/code-signing-use.html


 jsign --storetype ESIGNER --alias d97c5110-c66a-4c0c-ac0c-1cd6af812ee6 --storepass "<ssl.com user name>|<ssl.com password>" --keypass "<ssl.com eSigner secret code (not the PIN)>" --tsaurl="http://ts.ssl.com" --tsmode RFC3161 --alg SHA256 application.exe

  jsign --storetype ESIGNER --alias d97c5110-c66a-4c0c-ac0c-1cd6af812ee6 --storepass "brycemecum|TnTnoeoWU88PvXLMQ-Ru!JWm7-ow*A!" --keypass "3+hq9ODJ3zsU0QyIB17VNO5AKFeJXV3McR4GLs2TJYQ=" --tsaurl="http://ts.ssl.com" --tsmode RFC3161 --alg SHA256 "Apache Arrow Flight SQL ODBC-1.0.0-win64.msi"
