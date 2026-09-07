#!/bin/bash
set -euo pipefail

required=(MACOS_CERTIFICATE MACOS_CERTIFICATE_PWD MACOS_CERTIFICATE_NAME MACOS_CI_KEYCHAIN_PWD
    PROD_MACOS_NOTARIZATION_APPLE_ID PROD_MACOS_NOTARIZATION_TEAM_ID PROD_MACOS_NOTARIZATION_PWD)
missing=()
for name in "${required[@]}"; do
    if [[ -z "${!name:-}" ]]; then missing+=("$name"); fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
    if [[ "${REQUIRE_SIGNING:-true}" == true ]]; then
        printf 'Missing signing configuration: %s\n' "${missing[*]}" >&2
        exit 1
    fi
    echo '::notice::Signing secrets are not configured; this build is ad-hoc signed.'
    echo 'signed=false' >> "$GITHUB_OUTPUT"
    exit 0
fi

umask 077
cert="$RUNNER_TEMP/smac-certificate.p12"
keychain="$RUNNER_TEMP/smac-build.keychain-db"
cleanup()
{
    rm -f "$cert"
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s' "$MACOS_CERTIFICATE" | base64 --decode > "$cert"
security create-keychain -p "$MACOS_CI_KEYCHAIN_PWD" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$MACOS_CI_KEYCHAIN_PWD" "$keychain"
security list-keychains -d user -s "$keychain" login.keychain-db
security import "$cert" -k "$keychain" -P "$MACOS_CERTIFICATE_PWD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$MACOS_CI_KEYCHAIN_PWD" "$keychain" >/dev/null
rm -f "$cert"

make sign
export NOTARY_PROFILE=smac-ci
export NOTARY_KEYCHAIN="$keychain"
xcrun notarytool store-credentials "$NOTARY_PROFILE" --keychain "$keychain" \
    --apple-id "$PROD_MACOS_NOTARIZATION_APPLE_ID" --team-id "$PROD_MACOS_NOTARIZATION_TEAM_ID" \
    --password "$PROD_MACOS_NOTARIZATION_PWD"
make notarize
echo 'signed=true' >> "$GITHUB_OUTPUT"
