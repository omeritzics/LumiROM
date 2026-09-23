#!/bin/bash

source scripts/utils/bash_colors.sh

REPLACE_SMALI_METHOD() {
    local FILE="$1"
    local METHOD_NAME="$2"
    local NEW_BODY=$(echo "$3" | tail -n +2)

    echo "- Patching: $FILE"
    echo "  Method: $METHOD_NAME"

    if ! grep -Fq "$METHOD_NAME" "$FILE"; then
        echo "${RED}- Method not found${RESET}"
        return 0
    fi

    # Extract method key
    local METHOD_KEY
    METHOD_KEY=$(echo "$METHOD_NAME" | sed -E 's/.* ([^ ]+\().*/\1/')

    sed -i "
/^[[:space:]]*\.method.*$METHOD_KEY/,/^[[:space:]]*\.end method/{
    /^[[:space:]]*\.method/{
        p
        r /dev/stdin
        d
    }
    /^[[:space:]]*\.end method/p
    d
}" "$FILE" <<< "$NEW_BODY"
}


PATCH_SECURE_FOLDER() {
    echo ""
	if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_SERVICES_DIRECTORY>"
        return 1
    fi

    echo "${YELLOW}Patching secure folder.${RESET}"

	local FILE_1="${1}/smali/com/android/server/knox/dar/DarManagerService.smali"
	local METHOD_NAME_1=".method public final checkDeviceIntegrity([Ljava/security/cert/Certificate;)Z"
	local METHOD_NAME_2=".method public final isDeviceRootKeyInstalled()Z"
    local METHOD_NAME_3=".method public final isKnoxKeyInstallable()Z"
    
    local REPLACE_BODY_1='
    .locals 0
 
    const/4 p0, 0x1
 
    return p0
    '

    REPLACE_SMALI_METHOD "$FILE_1" "$METHOD_NAME_1" "$REPLACE_BODY_1"
    REPLACE_SMALI_METHOD "$FILE_1" "$METHOD_NAME_2" "$REPLACE_BODY_1"
	REPLACE_SMALI_METHOD "$FILE_1" "$METHOD_NAME_3" "$REPLACE_BODY_1"

    local FILE_2="${1}/smali/com/android/server/StorageManagerService.smali"
    local METHOD_NAME_4=".method public static isRootedDevice()Z"
    local REPLACE_BODY_2='
    .locals 1
 
    const/4 v0, 0x0
 
    return v0
    '
    REPLACE_SMALI_METHOD "$FILE_2" "$METHOD_NAME_4" "$REPLACE_BODY_2"
}


PATCH_PRIVATE_SHARE() {
    echo ""
	if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_SERVICES_DIRECTORY>"
        return 1
    fi

    echo "${YELLOW}Patching private share.${RESET}"
	
    local FILE="${1}/smali/com/samsung/android/security/keystore/AttestParameterSpec.smali"
    local METHOD_NAME=".method public isVerifiableIntegrity()Z"
    local REPLACE_BODY='
    .locals 1
 
    const/4 v0, 0x1
 
    return v0
    '
	REPLACE_SMALI_METHOD "$FILE" "$METHOD_NAME" "$REPLACE_BODY"
}


CUSTOM_PLATFORM_SIGNATURE() {
    echo ""
	if [ "$#" -ne 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_SERVICES_DIRECTORY> <PLATFORM_CERT_HEX>"
        echo "  Applies the custom platform signature patch and injects the"
        echo "  DER hex of the platform certificate into services.jar."
        return 1
    fi

    echo "${YELLOW}Enabling custom platform signature.${RESET}"

    local SERVICES_DIR="$1"
    local CERT_HEX="$2"
    local PATCH_FILE="$(pwd)/scripts/patches/0001-Allow-custom-platform-signature.patch"

    if [ ! -f "$PATCH_FILE" ]; then
        echo "${RED}Patch not found: $PATCH_FILE${RESET}"
        return 1
    fi

    if [ -z "$CERT_HEX" ]; then
        echo "${RED}Empty platform certificate hex.${RESET}"
        return 1
    fi

    if ! patch -p1 -d "$SERVICES_DIR" < "$PATCH_FILE" >/dev/null 2>&1; then
        echo "${RED}Failed to apply custom platform signature patch.${RESET}"
        return 1
    fi

    local TARGET_FILE="$SERVICES_DIR/smali_classes2/com/android/server/pm/InstallPackageHelper.smali"

    if ! grep -q "CONFIG_CUSTOM_PLATFORM_SIGNATURE" "$TARGET_FILE"; then
        echo "${RED}Placeholder CONFIG_CUSTOM_PLATFORM_SIGNATURE not found.${RESET}"
        return 1
    fi

    sed -i "s/CONFIG_CUSTOM_PLATFORM_SIGNATURE/$CERT_HEX/g" "$TARGET_FILE"

    echo "${GREEN}Custom platform signature enabled.${RESET}"
}


DISABLE_SIGNATURE_VERIFICATION() {
    echo ""
	if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_SERVICES_DIRECTORY>"
        return 1
    fi

    echo "${YELLOW}Disabling signature verification.${RESET}"

    local FILE="${1}/smali_classes4/android/util/apk/ApkSignatureVerifier.smali"
    local METHOD_NAME=".method public static blacklist getMinimumSignatureSchemeVersionForTargetSdk(I)I"
    local REPLACE_BODY='
    .locals 1

    const/4 v0, 0x1
 
    return v0
    '
	REPLACE_SMALI_METHOD "$FILE" "$METHOD_NAME" "$REPLACE_BODY"
}


PATCH_KNOX_GUARD() {
    echo ""
	if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_SERVICES_DIRECTORY>"
        return 1
    fi

    echo "${YELLOW}Patching knox guard.${RESET}"
    local FILE="${1}/smali_classes2/com/samsung/android/knoxguard/service/KnoxGuardSeService.smali"
    local METHOD_NAME_1=".method public constructor <init>(Landroid/content/Context;)V"
    local REPLACE_BODY_1='
    .locals 0
 
	invoke-direct {p0}, Lcom/samsung/android/knoxguard/IKnoxGuardManager$Stub;-><init>()V
 
    const/4 p1, 0x0
 
    iput-object p1, p0, Lcom/samsung/android/knoxguard/service/KnoxGuardSeService;->mConnectivityManagerService:Landroid/net/ConnectivityManager;
 
    new-instance p0, Ljava/lang/UnsupportedOperationException;
 
    const-string p1, "KnoxGuard is disabled"
 

    invoke-direct {p0, p1}, Ljava/lang/UnsupportedOperationException;-><init>(Ljava/lang/String;)V

    throw p0
    '
    REPLACE_SMALI_METHOD "$FILE" "$METHOD_NAME_1" "$REPLACE_BODY_1"
	rm -rf "$FIRM_DIR/$TARGET_DEVICE/system/system/priv-app/KnoxGuard"
}

PATCH_SSRM() {
    echo ""
	if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_SSRM_DIRECTORY>"
        return 1
    fi

    # Fix for SSRM Warning when powering on the phone
    local SSRM_DIR="$1"
	local FILE="$SSRM_DIR/smali/com/android/server/ssrm/Feature.smali"

	echo "${YELLOW}Patching ssrm${RESET}"

    sed -i "s/\(const-string v[0-9]\+,\s*\"\)siop_[^\"]*\"/\1$STOCK_SIOP_FILENAME\"/g" "$FILE"
    sed -i "/dvfs_policy_default/! s/\(const-string v[0-9]\+,\s*\"\)dvfs_policy_[^\"]*\"/\1$STOCK_DVFS_FILENAME\"/g" "$FILE"
}
