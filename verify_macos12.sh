#!/usr/bin/env bash
# verify_macos12.sh
# 在 macOS 上运行，用于验证编译产物确实是 macOS 12 部署目标。
# 用法: bash verify_macos12.sh /path/to/你的.app
set -euo pipefail

APP="${1:-}"
if [ -z "${APP}" ]; then
    echo "用法: bash verify_macos12.sh <路径>.app"
    exit 1
fi
if [ ! -d "${APP}" ]; then
    echo "[FAIL] 应用不存在: ${APP}"
    exit 1
fi

EXEC_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${APP}/Contents/Info.plist")
BIN="${APP}/Contents/MacOS/${EXEC_NAME}"

echo "=========================================="
echo " MacOptimizer macOS 12 兼容性验证"
echo "=========================================="
echo "应用: ${APP}"
echo "可执行: ${BIN}"
echo ""

FAIL=0
pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAIL=1; }

# --- 1. Info.plist 最低系统版本 ---
echo "[1/6] LSMinimumSystemVersion"
MINV=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "${APP}/Contents/Info.plist")
echo "      当前值: ${MINV}"
if [[ "${MINV}" == 12.* ]]; then
    pass "最低系统版本为 12.x"
else
    fail "最低系统版本不是 12.x（当前 ${MINV}）"
fi

# --- 2. 二进制架构 ---
echo ""
echo "[2/6] 二进制架构"
ARCHS=$(lipo -archs "${BIN}")
echo "      当前架构: ${ARCHS}"
if [[ "${ARCHS}" == *x86_64* ]]; then
    pass "包含 x86_64 (Intel, MacBookPro14,1 需要)"
else
    fail "缺少 x86_64，Intel Mac 无法运行"
fi

# --- 3. Mach-O 加载命令的 minos 版本 ---
echo ""
echo "[3/6] Mach-O LC_BUILD_VERSION / LC_VERSION_MIN_MACOSX"
OTOOL_OUT=$(otool -l "${BIN}" | grep -A5 -E "LC_BUILD_VERSION|LC_VERSION_MIN_MACOSX" || true)
if [ -n "${OTOOL_OUT}" ]; then
    echo "${OTOOL_OUT}" | grep -E "minos|version|platform" | sed 's/^/      /'
    if echo "${OTOOL_OUT}" | grep -qE "minos 12\."; then
        pass "二进制 minos = 12.x"
    elif echo "${OTOOL_OUT}" | grep -qE "minos 13\."; then
        fail "二进制 minos = 13.x，仍无法在 macOS 12 上运行"
    else
        fail "未能解析出明确的 minos 值"
    fi
else
    fail "未找到版本加载命令"
fi

# --- 4. 对每个 slice 单独确认 ---
echo ""
echo "[4/6] 逐 slice 检查 minos"
for arch in $(lipo -archs "${BIN}"); do
    TMP=$(mktemp -d)
    lipo -thin "${arch}" "${BIN}" -output "${TMP}/thin" 2>/dev/null
    MV=$(otool -l "${TMP}/thin" | grep -A5 -E "LC_BUILD_VERSION|LC_VERSION_MIN_MACOSX" | grep "minos" | head -1 | awk '{print $2}')
    echo "      ${arch}: minos ${MV}"
    if [[ "${MV}" == 12.* ]]; then
        pass "${arch} slice 支持 macOS 12"
    else
        fail "${arch} slice minos=${MV}，不支持 macOS 12"
    fi
    rm -rf "${TMP}"
done

# --- 5. 代码签名 ---
echo ""
echo "[5/6] 代码签名"
if codesign -dv "${APP}" 2>&1 | grep -q "Signature"; then
    pass "已签名 ($(codesign -dv "${APP}" 2>&1 | grep -E "^Signature" | head -1))"
else
    fail "未签名，macOS 12 上会被 Gatekeeper 拦截"
fi

# --- 6. 架构说明 ---
echo ""
echo "[6/6] 架构适配提醒"
if [[ "${ARCHS}" == arm64* && "${ARCHS}" != *x86_64* ]]; then
    fail "只有 arm64，Intel Mac 无法运行"
else
    pass "架构组合可覆盖 Intel Mac"
fi

echo ""
echo "=========================================="
if [ ${FAIL} -eq 0 ]; then
    echo " 结果: 全部通过 — 可在 macOS 12 上运行"
else
    echo " 结果: 存在未通过项"
fi
echo "=========================================="
exit ${FAIL}
