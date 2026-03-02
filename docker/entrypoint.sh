#!/usr/bin/env bash
# ============================================================
# Homunculus Entrypoint
# ============================================================
# 1. 환경변수로 openclaw.json 생성
# 2. 워크스페이스 파일 복사
# 3. 플러그인 링크
# 4. 부트 헬스체크
# 5. Gateway 시작
# ============================================================

set -euo pipefail

OPENCLAW_DIR="${HOME}/.openclaw"
OPENCLAW_CONFIG="${OPENCLAW_DIR}/openclaw.json"
WORKSPACE_DIR="${OPENCLAW_DIR}/workspace"
BOOT_REPORT="${WORKSPACE_DIR}/BOOT_REPORT.md"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[BOOT]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[CRIT]${NC} $1"; }

# ============================================================
# Step 1: Generate openclaw.json from template + env vars
# ============================================================
log_info "Generating openclaw.json from template..."

generate_config() {
    local template="/app/config/openclaw.template.json"

    if [ ! -f "$template" ]; then
        log_error "Config template not found: $template"
        exit 1
    fi

    mkdir -p "$OPENCLAW_DIR"

    # If user already has a config, don't overwrite
    if [ -f "$OPENCLAW_CONFIG" ]; then
        log_info "Existing openclaw.json found, skipping generation."
        return
    fi

    # Simple env var substitution in template
    local content
    content=$(cat "$template")

    # Replace ${VAR:-default} patterns
    content=$(echo "$content" | sed \
        -e "s|\${ANTHROPIC_API_KEY}|${ANTHROPIC_API_KEY:-}|g" \
        -e "s|\${OPENAI_API_KEY}|${OPENAI_API_KEY:-}|g" \
        -e "s|\${GEMINI_API_KEY}|${GEMINI_API_KEY:-}|g" \
        -e "s|\${OPENCLAW_GATEWAY_TOKEN}|${OPENCLAW_GATEWAY_TOKEN:-change-me}|g" \
        -e "s|\${DISCORD_BOT_TOKEN}|${DISCORD_BOT_TOKEN:-}|g" \
        -e "s|\${DISCORD_ENABLED:-true}|${DISCORD_ENABLED:-true}|g" \
        -e "s|\${LLM_MODEL:-anthropic/claude-sonnet-4-5}|${LLM_MODEL:-anthropic/claude-sonnet-4-5}|g" \
        -e "s|\${HOMUNCULUS_NAME:-호문쿨루스}|${HOMUNCULUS_NAME:-호문쿨루스}|g" \
        -e "s|\${HOMUNCULUS_EMOJI:-🧪}|${HOMUNCULUS_EMOJI:-🧪}|g" \
        -e "s|\${LOG_LEVEL:-info}|${LOG_LEVEL:-info}|g" \
    )

    echo "$content" > "$OPENCLAW_CONFIG"
    log_info "openclaw.json generated."
}

generate_config

# ============================================================
# Step 2: Copy workspace files (only if not already present)
# ============================================================
log_info "Setting up workspace..."

mkdir -p "$WORKSPACE_DIR"

for f in AGENTS.md SOUL.md IDENTITY.md MEMORY.md; do
    if [ ! -f "${WORKSPACE_DIR}/${f}" ]; then
        cp "/app/workspace/${f}" "${WORKSPACE_DIR}/${f}"
        log_info "  Copied ${f}"
    fi
done

# ============================================================
# Step 3: Link plugin
# ============================================================
log_info "Linking Homunculus plugin..."

PLUGIN_LINK="${OPENCLAW_DIR}/extensions/homunculus-core"
if [ ! -L "$PLUGIN_LINK" ] && [ ! -d "$PLUGIN_LINK" ]; then
    ln -sf /app/plugin "$PLUGIN_LINK"
    log_info "  Plugin linked: homunculus-core"
fi

# ============================================================
# Step 4: Boot Health Check
# ============================================================
log_info "Running boot health check..."

CHECKS_PASSED=0
CHECKS_WARNED=0
CHECKS_FAILED=0
NETWORK_OK=false
LLM_OK=false
ACTIVE_CHANNELS=0

report() { echo "$1" >> "$BOOT_REPORT"; }
pass()   { CHECKS_PASSED=$((CHECKS_PASSED + 1)); }
warn()   { CHECKS_WARNED=$((CHECKS_WARNED + 1)); }
fail()   { CHECKS_FAILED=$((CHECKS_FAILED + 1)); }

cat > "$BOOT_REPORT" <<HEADER
# Boot Report

Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

## Health Checks

HEADER

# --- 4.1: 네트워크 기본 연결 ---
report "### 1. Network"
if curl -s --max-time 5 https://httpbin.org/get > /dev/null 2>&1; then
    report "- [x] Internet: OK (DNS + HTTPS)"
    NETWORK_OK=true
    pass
else
    report "- [ ] Internet: **CRITICAL** - No internet access"
    fail
    log_error "Network check FAILED — no internet access"
fi
report ""

# --- 4.2: LLM API 연결 (실제 호출) ---
report "### 2. LLM API"
LLM_PROVIDER="none"

if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    LLM_PROVIDER="anthropic"
    report "- [x] Anthropic API key: present"
    LLM_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
        -H "x-api-key: ${ANTHROPIC_API_KEY}" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}' \
        "https://api.anthropic.com/v1/messages" 2>/dev/null || echo "000")
    case "$LLM_HTTP" in
        200|429|400|529) report "- [x] API connection: **VERIFIED** (HTTP ${LLM_HTTP})"; LLM_OK=true; pass ;;
        401) report "- [ ] API connection: **CRITICAL** - Invalid key (HTTP 401)"; fail; log_error "Anthropic API key invalid!" ;;
        *)   report "- [ ] API connection: **WARNING** - HTTP ${LLM_HTTP}"; warn ;;
    esac
elif [ -n "${OPENAI_API_KEY:-}" ]; then
    LLM_PROVIDER="openai"
    report "- [x] OpenAI API key: present"
    LLM_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
        -H "Authorization: Bearer ${OPENAI_API_KEY}" \
        "https://api.openai.com/v1/models" 2>/dev/null || echo "000")
    case "$LLM_HTTP" in
        200|429) report "- [x] API connection: **VERIFIED** (HTTP ${LLM_HTTP})"; LLM_OK=true; pass ;;
        401)     report "- [ ] API connection: **CRITICAL** - Invalid key (HTTP 401)"; fail; log_error "OpenAI API key invalid!" ;;
        *)       report "- [ ] API connection: **WARNING** - HTTP ${LLM_HTTP}"; warn ;;
    esac
elif [ -n "${GEMINI_API_KEY:-}" ]; then
    LLM_PROVIDER="gemini"
    report "- [x] Gemini API key: present"
    LLM_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
        "https://generativelanguage.googleapis.com/v1beta/models?key=${GEMINI_API_KEY}" 2>/dev/null || echo "000")
    case "$LLM_HTTP" in
        200|429) report "- [x] API connection: **VERIFIED** (HTTP ${LLM_HTTP})"; LLM_OK=true; pass ;;
        400|403) report "- [ ] API connection: **CRITICAL** - Invalid key (HTTP ${LLM_HTTP})"; fail; log_error "Gemini API key invalid!" ;;
        *)       report "- [ ] API connection: **WARNING** - HTTP ${LLM_HTTP}"; warn ;;
    esac
else
    report "- [ ] LLM API key: **CRITICAL** - No API key configured"
    fail
    log_error "No LLM API key! Set ANTHROPIC_API_KEY, OPENAI_API_KEY, or GEMINI_API_KEY"
fi
report "- Provider: ${LLM_PROVIDER}"
report "- Model: ${LLM_MODEL:-anthropic/claude-sonnet-4-5}"
report ""

# --- 4.3: 채널 연결 + 자동 감지 (P1-6) ---
report "### 3. Channels"

# Discord
DISCORD_ACTIVE=false
if [ "${DISCORD_ENABLED:-true}" = "true" ]; then
    if [ -n "${DISCORD_BOT_TOKEN:-}" ]; then
        report "- [x] Discord: token present"
        DISCORD_HTTP=$(curl -s -o /tmp/discord_me.json -w "%{http_code}" --max-time 10 \
            -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
            "https://discord.com/api/v10/users/@me" 2>/dev/null || echo "000")
        case "$DISCORD_HTTP" in
            200)
                DISCORD_BOT_NAME=$(grep -o '"username":"[^"]*"' /tmp/discord_me.json 2>/dev/null | head -1 | cut -d'"' -f4)
                report "- [x] Discord connection: **VERIFIED** (bot: ${DISCORD_BOT_NAME:-unknown})"
                DISCORD_ACTIVE=true
                ACTIVE_CHANNELS=$((ACTIVE_CHANNELS + 1))
                pass
                ;;
            401)
                report "- [ ] Discord connection: **FAILED** - Invalid token → channel disabled"
                warn
                log_warn "Discord token invalid — disabling channel"
                ;;
            *)
                report "- [ ] Discord connection: **FAILED** - Cannot reach API (HTTP ${DISCORD_HTTP}) → channel disabled"
                warn
                log_warn "Discord unreachable — disabling channel"
                ;;
        esac
        rm -f /tmp/discord_me.json

        # 채널 자동 감지: 연결 실패 시 config에서 비활성화
        if [ "$DISCORD_ACTIVE" = false ] && [ -f "$OPENCLAW_CONFIG" ]; then
            # JSON5에서 discord enabled를 false로 변경
            sed -i 's/"enabled":.*"true"/"enabled": false/' "$OPENCLAW_CONFIG" 2>/dev/null || true
            log_warn "Discord disabled in openclaw.json due to connection failure"
        fi
    else
        report "- [ ] Discord: enabled but no token → channel disabled"
        warn
        log_warn "Discord enabled but no token configured"
    fi
else
    report "- [-] Discord: disabled by config"
fi

# 채널 자동 감지 결과
report ""
if [ "$ACTIVE_CHANNELS" -eq 0 ]; then
    report "**No active channels — headless mode (logs only)**"
    log_error "No active communication channels! Operating in headless mode."
    # 이건 WARNING이 아니라 운영 모드 알림
fi
report ""

# --- 4.4: Git Remote (분산 진화용) ---
report "### 4. Git Remote"
if command -v git &> /dev/null; then
    report "- [x] git: available ($(git --version | head -1))"
    pass

    # GitHub API 접근 가능 여부
    if [ "$NETWORK_OK" = true ]; then
        GH_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
            "https://api.github.com" 2>/dev/null || echo "000")
        if [ "$GH_HTTP" = "200" ]; then
            report "- [x] GitHub API: reachable"
            pass
        else
            report "- [ ] GitHub API: **WARNING** - unreachable (HTTP ${GH_HTTP}) → self-modify/PR disabled"
            warn
            log_warn "GitHub API unreachable — self-modify/PR features disabled"
        fi
    else
        report "- [ ] GitHub API: **WARNING** - skipped (no network)"
        warn
    fi

    # push 권한 토큰 확인 (GH_TOKEN 또는 GITHUB_TOKEN)
    if [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; then
        report "- [x] GitHub push token: configured"
        pass
    else
        report "- [ ] GitHub push token: **WARNING** - not set → PR creation disabled"
        warn
    fi
else
    report "- [ ] git: **WARNING** - not installed → self-modify disabled"
    warn
fi
report ""

# --- 4.5: 로컬 리소스 ---
report "### 5. Local Resources"

# 디스크 여유 공간
DISK_AVAIL=$(df -h /home/node 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")
DISK_PCT=$(df /home/node 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%' || echo "0")
report "- Disk available: ${DISK_AVAIL}"
if [ "$DISK_PCT" -gt 90 ] 2>/dev/null; then
    report "- [ ] Disk usage: **WARNING** - ${DISK_PCT}% used"
    warn
    log_warn "Disk usage at ${DISK_PCT}%!"
else
    report "- [x] Disk usage: OK (${DISK_PCT}% used)"
fi

# Python
if command -v python3 &> /dev/null; then
    report "- [x] Python: $(python3 --version 2>&1)"
    pass
else
    report "- [ ] Python: **WARNING** - not installed"
    warn
fi

# workspace 쓰기 가능
if [ -w "$WORKSPACE_DIR" ]; then
    report "- [x] Workspace writable: yes"
    pass
else
    report "- [ ] Workspace writable: **CRITICAL** - no write permission"
    fail
fi

# 플러그인 존재
if [ -d /app/plugin ]; then
    report "- [x] Plugin directory: present"
else
    report "- [ ] Plugin directory: **WARNING** - missing"
    warn
fi
report ""

# --- Summary ---
{
    echo "## Summary"
    echo ""
    echo "- Passed: ${CHECKS_PASSED}"
    echo "- Warnings: ${CHECKS_WARNED}"
    echo "- Critical: ${CHECKS_FAILED}"
    echo "- Active channels: ${ACTIVE_CHANNELS}"
    echo ""
    if [ "$CHECKS_FAILED" -gt 0 ]; then
        echo "**Status: DEGRADED**"
    elif [ "$CHECKS_WARNED" -gt 0 ]; then
        echo "**Status: PARTIAL**"
    else
        echo "**Status: HEALTHY**"
    fi
} >> "$BOOT_REPORT"

# Print to console
cat "$BOOT_REPORT"

log_info "Health check: Passed=${CHECKS_PASSED} Warnings=${CHECKS_WARNED} Critical=${CHECKS_FAILED} Channels=${ACTIVE_CHANNELS}"

# ============================================================
# Step 5: 실패 처리
# ============================================================

# 네트워크 실패 → exit code 1 (Docker restart 정책이 재시도)
if [ "$NETWORK_OK" = false ]; then
    log_error "Network unavailable — exiting with code 1 for retry"
    exit 1
fi

# LLM API 실패 → 재시도 루프 (최대 5회, 30초 간격)
if [ "$LLM_OK" = false ] && [ "$NETWORK_OK" = true ]; then
    log_warn "LLM API not verified — entering retry loop..."
    LLM_RETRY_MAX=5
    LLM_RETRY_INTERVAL=30

    for i in $(seq 1 $LLM_RETRY_MAX); do
        log_warn "LLM retry ${i}/${LLM_RETRY_MAX} (waiting ${LLM_RETRY_INTERVAL}s)..."
        sleep $LLM_RETRY_INTERVAL

        # 프로바이더별 재시도
        RETRY_HTTP="000"
        if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
            RETRY_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
                -H "x-api-key: ${ANTHROPIC_API_KEY}" -H "anthropic-version: 2023-06-01" \
                -H "content-type: application/json" \
                -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}' \
                "https://api.anthropic.com/v1/messages" 2>/dev/null || echo "000")
        elif [ -n "${OPENAI_API_KEY:-}" ]; then
            RETRY_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
                -H "Authorization: Bearer ${OPENAI_API_KEY}" \
                "https://api.openai.com/v1/models" 2>/dev/null || echo "000")
        elif [ -n "${GEMINI_API_KEY:-}" ]; then
            RETRY_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
                "https://generativelanguage.googleapis.com/v1beta/models?key=${GEMINI_API_KEY}" 2>/dev/null || echo "000")
        fi

        case "$RETRY_HTTP" in
            200|429|400|529)
                log_info "LLM API verified on retry ${i}! (HTTP ${RETRY_HTTP})"
                LLM_OK=true
                break
                ;;
            401)
                log_error "LLM API key is invalid (HTTP 401) — retrying won't help"
                break
                ;;
            *)
                log_warn "LLM retry ${i} failed (HTTP ${RETRY_HTTP})"
                ;;
        esac
    done

    if [ "$LLM_OK" = false ]; then
        log_error "LLM API failed after ${LLM_RETRY_MAX} retries — starting in degraded mode"
    fi
fi

# ============================================================
# Step 6: Start OpenClaw Gateway
# ============================================================
log_info "Starting OpenClaw Gateway..."

exec node /app/openclaw/dist/index.js gateway \
    --bind "${OPENCLAW_GATEWAY_BIND:-lan}" \
    --port "${OPENCLAW_GATEWAY_PORT:-18789}" \
    --allow-unconfigured
