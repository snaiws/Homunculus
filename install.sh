#!/usr/bin/env bash
# ============================================================
# Homunculus Interactive Installer
# ============================================================
# 사용법: git clone --recursive ... && cd Homunculus && ./install.sh
# ============================================================

set -euo pipefail

# ── 경로 ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
ENV_FILE="${CONFIG_DIR}/.env"
FEATURES_FILE="${CONFIG_DIR}/features.yaml"
INSTANCE_FILE="${CONFIG_DIR}/instance.yaml"

# ── 색상 ──
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ── 유틸 ──
print_banner() {
    echo ""
    echo -e "${MAGENTA}${BOLD}"
    echo "    ╔═══════════════════════════════════════╗"
    echo "    ║                                       ║"
    echo "    ║   🧪  H O M U N C U L U S  🧪        ║"
    echo "    ║       The Dwarf in the Flask           ║"
    echo "    ║                                       ║"
    echo "    ╚═══════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo ""
    echo -e "${CYAN}${BOLD}━━━ $1 ━━━${NC}"
    echo ""
}

print_info() {
    echo -e "  ${DIM}$1${NC}"
}

print_ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_fail() {
    echo -e "  ${RED}✗${NC} $1"
}

# 사용자 입력 (기본값 지원)
ask() {
    local prompt="$1"
    local default="${2:-}"
    local result

    if [ -n "$default" ]; then
        echo -ne "  ${BOLD}${prompt}${NC} ${DIM}[${default}]${NC}: "
    else
        echo -ne "  ${BOLD}${prompt}${NC}: "
    fi

    read -r result
    echo "${result:-$default}"
}

# Y/n 질문 (기본 Yes)
ask_yes() {
    local prompt="$1"
    local result
    echo -ne "  ${BOLD}${prompt}${NC} ${DIM}[Y/n]${NC}: "
    read -r result
    result="${result:-Y}"
    [[ "$result" =~ ^[Yy] ]]
}

# y/N 질문 (기본 No)
ask_no() {
    local prompt="$1"
    local result
    echo -ne "  ${BOLD}${prompt}${NC} ${DIM}[y/N]${NC}: "
    read -r result
    result="${result:-N}"
    [[ "$result" =~ ^[Yy] ]]
}

# 번호 선택
ask_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    local i=1

    for opt in "${options[@]}"; do
        echo -e "    ${BOLD}${i})${NC} ${opt}"
        i=$((i + 1))
    done
    echo ""

    local choice
    echo -ne "  ${BOLD}${prompt}${NC}: "
    read -r choice
    echo "$choice"
}

# 비밀 입력 (마스킹)
ask_secret() {
    local prompt="$1"
    local result
    echo -ne "  ${BOLD}${prompt}${NC}: "
    read -rs result
    echo ""
    echo "$result"
}

# 랜덤 토큰 생성
generate_token() {
    if command -v openssl &>/dev/null; then
        openssl rand -hex 24
    elif [ -f /dev/urandom ]; then
        head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'
    else
        echo "homunculus-$(date +%s)-$$"
    fi
}

# 스피너 (백그라운드 작업 대기 시)
spinner() {
    local pid=$1
    local msg="${2:-작업 중...}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        echo -ne "\r  ${CYAN}${frames[$i]}${NC} ${msg}"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.1
    done
    echo -ne "\r\033[K"  # 줄 지우기
}

# ── LLM API 검증 함수들 ──

verify_anthropic() {
    local key="$1"
    local response
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 \
        -H "x-api-key: ${key}" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
        "https://api.anthropic.com/v1/messages" 2>/dev/null)
    # 200=성공, 401=키무효, 429=리밋(키는유효), 400=요청에러(키는유효)
    case "$http_code" in
        200|429|400|529) return 0 ;;  # 키 유효
        401) return 1 ;;              # 키 무효
        *) return 2 ;;                # 네트워크/기타
    esac
}

verify_openai() {
    local key="$1"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 \
        -H "Authorization: Bearer ${key}" \
        "https://api.openai.com/v1/models" 2>/dev/null)
    case "$http_code" in
        200) return 0 ;;
        401) return 1 ;;
        429) return 0 ;;  # rate limit = 키 유효
        *) return 2 ;;
    esac
}

verify_gemini() {
    local key="$1"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 \
        "https://generativelanguage.googleapis.com/v1beta/models?key=${key}" 2>/dev/null)
    case "$http_code" in
        200) return 0 ;;
        400|403) return 1 ;;
        429) return 0 ;;
        *) return 2 ;;
    esac
}

# Discord 봇 토큰 검증
verify_discord() {
    local token="$1"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 \
        -H "Authorization: Bot ${token}" \
        "https://discord.com/api/v10/users/@me" 2>/dev/null)
    case "$http_code" in
        200) return 0 ;;
        401) return 1 ;;
        *) return 2 ;;
    esac
}

# ============================================================
# 본체
# ============================================================

main() {
    print_banner

    echo -e "  호문쿨루스 설치 마법사에 오신 것을 환영합니다."
    echo -e "  몇 가지 질문에 답하시면 설정이 자동으로 생성됩니다."
    echo ""

    # 기존 설정 존재 시 경고
    if [ -f "$ENV_FILE" ]; then
        echo ""
        print_warn "기존 설정 파일이 발견되었습니다: config/.env"
        if ! ask_yes "설정을 새로 만드시겠습니까? (기존 파일은 .env.bak으로 백업)"; then
            echo ""
            echo -e "  설치를 취소합니다. 기존 설정을 유지합니다."
            exit 0
        fi
        cp "$ENV_FILE" "${ENV_FILE}.bak"
        print_ok "기존 설정이 config/.env.bak 으로 백업되었습니다."
    fi

    # ──────────────────────────────────────────────
    # Step 1: 사전 요구사항 + 네트워크 점검
    # ──────────────────────────────────────────────
    print_step "Step 1/7 — 환경 및 네트워크 점검"

    local prereq_ok=true
    local network_ok=true

    echo -e "  ${BOLD}[필수 도구]${NC}"

    # curl (네트워크 점검에 필수)
    if command -v curl &>/dev/null; then
        print_ok "curl: $(curl --version | head -1 | awk '{print $1, $2}')"
    else
        print_fail "curl이 설치되어 있지 않습니다. (sudo apt install curl)"
        prereq_ok=false
    fi

    # Docker
    if command -v docker &>/dev/null; then
        print_ok "Docker: $(docker --version | head -1)"
    else
        print_fail "Docker가 설치되어 있지 않습니다."
        print_info "https://docs.docker.com/get-docker/ 에서 설치하세요."
        prereq_ok=false
    fi

    # Docker Compose
    if docker compose version &>/dev/null 2>&1; then
        print_ok "Docker Compose: $(docker compose version --short 2>/dev/null || echo 'available')"
    elif command -v docker-compose &>/dev/null; then
        print_ok "docker-compose: $(docker-compose --version | head -1)"
    else
        print_fail "Docker Compose가 설치되어 있지 않습니다."
        prereq_ok=false
    fi

    # Git
    if command -v git &>/dev/null; then
        print_ok "Git: $(git --version)"
    else
        print_fail "Git이 설치되어 있지 않습니다."
        prereq_ok=false
    fi

    # Submodule
    if [ -f "${SCRIPT_DIR}/openclaw/package.json" ]; then
        print_ok "OpenClaw submodule: 정상"
    else
        print_warn "OpenClaw submodule이 초기화되지 않았습니다."
        echo ""
        if ask_yes "지금 초기화하시겠습니까?"; then
            git -C "$SCRIPT_DIR" submodule update --init --recursive
            print_ok "Submodule 초기화 완료"
        else
            print_fail "OpenClaw 없이는 진행할 수 없습니다."
            prereq_ok=false
        fi
    fi

    if [ "$prereq_ok" = false ]; then
        echo ""
        print_fail "필수 요구사항이 충족되지 않았습니다. 위의 문제를 해결한 후 다시 실행하세요."
        exit 1
    fi

    # ── 네트워크 점검 ──
    echo ""
    echo -e "  ${BOLD}[네트워크]${NC}"

    # DNS 해석
    if host google.com &>/dev/null 2>&1 || nslookup google.com &>/dev/null 2>&1 || ping -c 1 -W 2 google.com &>/dev/null 2>&1; then
        print_ok "DNS 해석: 정상"
    else
        print_fail "DNS 해석 실패 — 인터넷 연결을 확인하세요."
        network_ok=false
    fi

    # HTTPS 연결 + 응답시간
    if [ "$network_ok" = true ]; then
        local http_time
        http_time=$(curl -s -o /dev/null -w "%{time_total}" --max-time 10 "https://httpbin.org/get" 2>/dev/null || echo "failed")
        if [ "$http_time" != "failed" ] && [ "$http_time" != "" ]; then
            # 소수점 비교를 위해 ms로 변환
            local ms
            ms=$(echo "$http_time" | awk '{printf "%.0f", $1 * 1000}')
            print_ok "HTTPS 연결: 정상 (${ms}ms)"
        else
            print_fail "HTTPS 연결 실패 — 방화벽 또는 프록시를 확인하세요."
            network_ok=false
        fi
    fi

    # LLM API 엔드포인트 접근 가능 여부 (키 없이 도달만 확인)
    if [ "$network_ok" = true ]; then
        local api_reach=0
        for endpoint in "api.anthropic.com" "api.openai.com" "generativelanguage.googleapis.com"; do
            if curl -s -o /dev/null --max-time 5 "https://${endpoint}" 2>/dev/null; then
                api_reach=$((api_reach + 1))
            fi
        done
        if [ "$api_reach" -gt 0 ]; then
            print_ok "LLM API 서버 도달: ${api_reach}/3 프로바이더 접근 가능"
        else
            print_warn "LLM API 서버에 도달할 수 없습니다. 방화벽을 확인하세요."
        fi

        # Discord API 도달
        if curl -s -o /dev/null --max-time 5 "https://discord.com/api/v10" 2>/dev/null; then
            print_ok "Discord API: 도달 가능"
        else
            print_warn "Discord API에 도달할 수 없습니다."
        fi

        # GitHub API 도달 (자기수정/PR 기능용)
        if curl -s -o /dev/null --max-time 5 "https://api.github.com" 2>/dev/null; then
            print_ok "GitHub API: 도달 가능"
        else
            print_warn "GitHub API에 도달할 수 없습니다. (자기수정/PR 기능 제한)"
        fi
    fi

    if [ "$network_ok" = false ]; then
        echo ""
        print_warn "네트워크 문제가 있지만 설치는 계속할 수 있습니다."
        print_info "Docker 빌드와 LLM 연결에 인터넷이 필요합니다."
        echo ""
        if ! ask_yes "네트워크 문제를 무시하고 계속하시겠습니까?"; then
            echo ""
            echo -e "  네트워크를 확인한 후 다시 실행하세요."
            exit 1
        fi
    fi

    echo ""
    print_ok "환경 점검 완료!"

    # ──────────────────────────────────────────────
    # Step 2: LLM 프로바이더 + API 검증
    # ──────────────────────────────────────────────
    print_step "Step 2/7 — LLM 프로바이더 설정"

    echo -e "  호문쿨루스의 두뇌가 될 LLM을 선택합니다."
    echo -e "  ${DIM}(API 키가 필요합니다. 하나만 선택하세요.)${NC}"
    echo ""

    local llm_provider=""
    local llm_api_key=""
    local llm_model=""
    local llm_verified=false

    local provider_choice
    provider_choice=$(ask_choice "사용할 프로바이더 번호" \
        "Anthropic (Claude) — 추천" \
        "OpenAI (GPT)" \
        "Google (Gemini)")

    case "$provider_choice" in
        1)
            llm_provider="anthropic"
            llm_model="anthropic/claude-sonnet-4-5"
            echo ""
            print_info "Anthropic API 키: https://console.anthropic.com/settings/keys"
            ;;
        2)
            llm_provider="openai"
            llm_model="openai/gpt-4o"
            echo ""
            print_info "OpenAI API 키: https://platform.openai.com/api-keys"
            ;;
        3)
            llm_provider="gemini"
            llm_model="gemini/gemini-2.0-flash"
            echo ""
            print_info "Gemini API 키: https://aistudio.google.com/apikey"
            ;;
        *)
            print_fail "잘못된 선택입니다."
            exit 1
            ;;
    esac

    # API 키 입력 + 검증 루프
    local llm_retry=true
    while [ "$llm_retry" = true ]; do
        llm_api_key=$(ask_secret "API 키 입력 (나중에 하려면 Enter)")

        if [ -z "$llm_api_key" ]; then
            print_warn "API 키가 비어 있습니다. 나중에 config/.env 에서 직접 입력하세요."
            llm_retry=false
            continue
        fi

        # 실제 API 호출로 키 검증
        echo -ne "  ${CYAN}⠋${NC} API 키 검증 중..."

        local verify_result=0
        case "$llm_provider" in
            anthropic) verify_anthropic "$llm_api_key" || verify_result=$? ;;
            openai)    verify_openai "$llm_api_key"    || verify_result=$? ;;
            gemini)    verify_gemini "$llm_api_key"     || verify_result=$? ;;
        esac

        echo -ne "\r\033[K"  # 줄 지우기

        case "$verify_result" in
            0)
                print_ok "API 키 검증 성공! (${llm_provider})"
                llm_verified=true
                llm_retry=false
                ;;
            1)
                print_fail "API 키가 유효하지 않습니다."
                echo ""
                if ask_yes "다시 입력하시겠습니까?"; then
                    continue
                else
                    print_warn "잘못된 키로 진행합니다. 나중에 config/.env 에서 수정하세요."
                    llm_retry=false
                fi
                ;;
            2)
                print_warn "API 서버에 연결할 수 없습니다. (네트워크 문제 가능)"
                print_info "키가 맞다면 네트워크 확인 후 다시 시도하세요."
                echo ""
                if ask_yes "입력한 키를 그대로 저장하시겠습니까?"; then
                    llm_retry=false
                else
                    continue
                fi
                ;;
        esac
    done

    echo ""
    if [ "$llm_verified" = true ]; then
        print_ok "LLM 연결 완료: ${llm_provider} (${llm_model})"
    elif [ -n "$llm_api_key" ]; then
        print_warn "LLM: ${llm_provider} (${llm_model}) — 키 미검증"
    fi

    # ──────────────────────────────────────────────
    # Step 3: 소통 채널 + 연결 검증
    # ──────────────────────────────────────────────
    print_step "Step 3/7 — 소통 채널 설정"

    echo -e "  호문쿨루스와 대화할 채널을 설정합니다."
    echo ""

    local discord_enabled="false"
    local discord_token=""
    local discord_verified=false
    local discord_bot_name=""

    if ask_yes "Discord 봇을 연결하시겠습니까?"; then
        discord_enabled="true"
        echo ""
        print_info "Discord 봇 만들기:"
        print_info "  1. https://discord.com/developers/applications 접속"
        print_info "  2. New Application → Bot 탭 → Reset Token"
        print_info "  3. MESSAGE CONTENT INTENT 켜기"
        print_info "  4. OAuth2 → bot + applications.commands 권한으로 서버 초대"
        echo ""

        local discord_retry=true
        while [ "$discord_retry" = true ]; do
            discord_token=$(ask_secret "봇 토큰 입력 (나중에 하려면 Enter)")

            if [ -z "$discord_token" ]; then
                print_warn "토큰을 나중에 config/.env 에서 입력하세요."
                discord_retry=false
                continue
            fi

            # Discord 봇 토큰 검증
            echo -ne "  ${CYAN}⠋${NC} Discord 봇 토큰 검증 중..."

            local discord_response
            discord_response=$(curl -s --max-time 10 \
                -H "Authorization: Bot ${discord_token}" \
                "https://discord.com/api/v10/users/@me" 2>/dev/null)

            echo -ne "\r\033[K"

            local discord_result=0
            verify_discord "$discord_token" || discord_result=$?

            case "$discord_result" in
                0)
                    # 봇 이름 추출
                    discord_bot_name=$(echo "$discord_response" | grep -o '"username":"[^"]*"' | head -1 | cut -d'"' -f4)
                    discord_verified=true
                    if [ -n "$discord_bot_name" ]; then
                        print_ok "Discord 봇 연결 성공! (봇 이름: ${discord_bot_name})"
                    else
                        print_ok "Discord 봇 토큰 검증 성공!"
                    fi
                    discord_retry=false
                    ;;
                1)
                    print_fail "Discord 봇 토큰이 유효하지 않습니다."
                    echo ""
                    if ask_yes "다시 입력하시겠습니까?"; then
                        continue
                    else
                        print_warn "잘못된 토큰으로 진행합니다. 나중에 수정하세요."
                        discord_retry=false
                    fi
                    ;;
                2)
                    print_warn "Discord API에 연결할 수 없습니다."
                    print_info "토큰을 그대로 저장합니다. 네트워크 확인 후 재시도하세요."
                    discord_retry=false
                    ;;
            esac
        done
    else
        print_info "Discord를 사용하지 않습니다. (나중에 config/.env 에서 켤 수 있습니다.)"
    fi

    # ──────────────────────────────────────────────
    # Step 4: 정체성
    # ──────────────────────────────────────────────
    print_step "Step 4/7 — 호문쿨루스 정체성"

    echo -e "  플라스크 속 존재의 이름을 지어주세요."
    echo ""

    local hom_name
    hom_name=$(ask "이름" "호문쿨루스")

    local hom_emoji
    hom_emoji=$(ask "이모지" "🧪")

    local instance_id
    instance_id=$(ask "인스턴스 ID (영문, 고유 식별자)" "seoul-01")

    local instance_location
    instance_location=$(ask "타임존" "Asia/Seoul")

    print_ok "정체성: ${hom_emoji} ${hom_name} (${instance_id})"

    # ──────────────────────────────────────────────
    # Step 5: 자율 기능 동의
    # ──────────────────────────────────────────────
    print_step "Step 5/7 — 기능 활성화"

    echo -e "  호문쿨루스에게 어떤 능력을 허용할지 선택합니다."
    echo -e "  ${DIM}(나중에 config/features.yaml 에서 변경할 수 있습니다.)${NC}"
    echo ""

    # 자기 수정
    echo -e "  ${BOLD}[자기 수정]${NC}"
    print_info "호문쿨루스가 자신의 코드, 스킬, 지침을 수정할 수 있습니다."
    print_info "모든 수정은 git 브랜치에서 진행되며, 실패 시 자동 롤백됩니다."
    local self_modify="false"
    if ask_no "자기 수정을 허용하시겠습니까?"; then
        self_modify="true"
        print_ok "자기 수정: 허용됨 (git 브랜치 기반, 안전장치 적용)"
    else
        print_info "자기 수정: 비활성. 읽기 전용 모드로 동작합니다."
    fi

    echo ""

    # PR 생성
    echo -e "  ${BOLD}[PR 제출]${NC}"
    print_info "호문쿨루스가 개선안을 GitHub PR로 제출할 수 있습니다."
    print_info "사용자(또는 다른 인스턴스)가 리뷰 후 머지합니다."
    local create_pr="false"
    if [ "$self_modify" = "true" ]; then
        if ask_no "GitHub PR 생성을 허용하시겠습니까?"; then
            create_pr="true"
            print_ok "PR 생성: 허용됨"
        else
            print_info "PR 생성: 비활성. 로컬 브랜치에서만 작업합니다."
        fi
    else
        print_info "PR 생성: 자기 수정이 꺼져 있어 자동 비활성."
    fi

    echo ""

    # 스케줄 (수면/기상)
    echo -e "  ${BOLD}[자동 스케줄]${NC}"
    print_info "호문쿨루스가 수면/기상 사이클을 자동으로 관리합니다."
    print_info "비활동 시간에 리소스를 정리하고, 활동 시간에 집중합니다."
    local auto_schedule="false"
    if ask_no "자동 수면/기상 스케줄을 활성화하시겠습니까?"; then
        auto_schedule="true"
        print_ok "자동 스케줄: 활성 (config/directives/schedule-sleep.yaml 에서 시간 조정 가능)"
    else
        print_info "자동 스케줄: 비활성. 항상 깨어있습니다."
    fi

    echo ""

    # 스킬 관리
    echo -e "  ${BOLD}[스킬 자율 관리]${NC}"
    print_info "호문쿨루스가 대화를 통해 새로운 스킬을 만들고 관리할 수 있습니다."
    local skill_mgmt="false"
    if ask_no "스킬 자율 관리를 허용하시겠습니까?"; then
        skill_mgmt="true"
        print_ok "스킬 관리: 허용됨"
    else
        print_info "스킬 관리: 비활성. 수동으로만 스킬을 추가합니다."
    fi

    echo ""

    # 토큰 예산
    echo -e "  ${BOLD}[토큰 예산]${NC}"
    print_info "LLM API 사용량을 추적하고 일일 한도를 설정합니다."
    local token_budget="false"
    local daily_limit=0
    if ask_no "토큰 예산 관리를 활성화하시겠습니까?"; then
        token_budget="true"
        daily_limit=$(ask "일일 토큰 한도 (0 = 무제한)" "0")
        print_ok "토큰 예산: 활성 (일일 한도: ${daily_limit})"
    else
        print_info "토큰 예산: 비활성. 사용량 제한 없이 동작합니다."
    fi

    echo ""

    # 리소스 모니터링
    echo -e "  ${BOLD}[리소스 모니터링]${NC}"
    print_info "디스크/메모리 사용량을 감시하고 임계값 초과 시 경고합니다."
    local resource_mon="false"
    if ask_no "리소스 모니터링을 활성화하시겠습니까?"; then
        resource_mon="true"
        print_ok "리소스 모니터링: 활성"
    else
        print_info "리소스 모니터링: 비활성."
    fi

    # ──────────────────────────────────────────────
    # Step 6: 설정 파일 생성
    # ──────────────────────────────────────────────
    print_step "Step 6/7 — 설정 파일 생성"

    local gateway_token
    gateway_token=$(generate_token)

    # --- .env ---
    local anthropic_key="" openai_key="" gemini_key=""
    case "$llm_provider" in
        anthropic) anthropic_key="$llm_api_key" ;;
        openai)    openai_key="$llm_api_key" ;;
        gemini)    gemini_key="$llm_api_key" ;;
    esac

    cat > "$ENV_FILE" <<ENVEOF
# ============================================================
# Homunculus - 환경 설정
# 생성일: $(date '+%Y-%m-%d %H:%M:%S')
# install.sh 에 의해 자동 생성됨
# ============================================================

# --- LLM Provider ---
ANTHROPIC_API_KEY=${anthropic_key}
OPENAI_API_KEY=${openai_key}
GEMINI_API_KEY=${gemini_key}
LLM_MODEL=${llm_model}

# --- Gateway ---
OPENCLAW_GATEWAY_TOKEN=${gateway_token}

# --- Discord ---
DISCORD_BOT_TOKEN=${discord_token}
DISCORD_ENABLED=${discord_enabled}

# --- Identity ---
HOMUNCULUS_NAME=${hom_name}
HOMUNCULUS_EMOJI=${hom_emoji}

# --- Logging ---
LOG_LEVEL=info
ENVEOF

    print_ok "config/.env 생성 완료"

    # --- features.yaml ---
    cat > "$FEATURES_FILE" <<FEATEOF
# ============================================================
# Homunculus Feature Permissions
# ============================================================
# install.sh 에 의해 자동 생성됨 — $(date '+%Y-%m-%d %H:%M:%S')
# 이 파일은 호문쿨루스와 사용자 간의 "계약서"입니다.
# 호문쿨루스는 여기 허용된 기능만 사용합니다.
# ============================================================

version: 1
installed_at: "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
installed_by: "user"

channels:
  discord:
    enabled: ${discord_enabled}

llm:
  provider: "${llm_provider}"

autonomy:
  self_modify:
    enabled: ${self_modify}
  create_pr:
    enabled: ${create_pr}
  auto_schedule:
    enabled: ${auto_schedule}
  skill_management:
    enabled: ${skill_mgmt}

resources:
  token_budget:
    enabled: ${token_budget}
    daily_limit: ${daily_limit}
  resource_monitoring:
    enabled: ${resource_mon}
FEATEOF

    print_ok "config/features.yaml 생성 완료"

    # --- instance.yaml ---
    local repo_origin=""
    repo_origin=$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || echo "")

    cat > "$INSTANCE_FILE" <<INSTEOF
# ============================================================
# Homunculus Instance Identification
# install.sh 에 의해 자동 생성됨 — $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================

instance:
  id: "${instance_id}"
  name: "${hom_name}"
  location: "${instance_location}"

  branch_prefix: "homunculus/${instance_id}"
  repo:
    origin: "${repo_origin}"
    main_branch: "main"

  capabilities:
    can_self_modify: ${self_modify}
    can_create_pr: ${create_pr}
    can_review_pr: false
INSTEOF

    print_ok "config/instance.yaml 생성 완료"

    # ──────────────────────────────────────────────
    # Step 7: 최종 연결 점검 요약
    # ──────────────────────────────────────────────
    print_step "Step 7/7 — 연결 점검 요약"

    local all_clear=true

    if [ "$llm_verified" = true ]; then
        print_ok "LLM API (${llm_provider}): 연결됨"
    elif [ -n "$llm_api_key" ]; then
        print_warn "LLM API (${llm_provider}): 키 입력됨, 미검증"
        all_clear=false
    else
        print_fail "LLM API: 키 없음 — config/.env 에서 설정 필요"
        all_clear=false
    fi

    if [ "$discord_enabled" = "true" ]; then
        if [ "$discord_verified" = true ]; then
            print_ok "Discord: 연결됨$([ -n "$discord_bot_name" ] && echo " (${discord_bot_name})" || echo "")"
        elif [ -n "$discord_token" ]; then
            print_warn "Discord: 토큰 입력됨, 미검증"
            all_clear=false
        else
            print_warn "Discord: 활성이지만 토큰 없음"
            all_clear=false
        fi
    else
        print_info "Discord: 비활성"
    fi

    if [ "$network_ok" = true ]; then
        print_ok "네트워크: 정상"
    else
        print_warn "네트워크: 문제 있음"
        all_clear=false
    fi

    echo ""
    if [ "$all_clear" = true ]; then
        print_ok "모든 연결 점검 통과!"
    else
        print_warn "일부 항목이 미완료입니다. 설치는 계속하지만 시작 전 config/.env 를 확인하세요."
    fi

    # ──────────────────────────────────────────────
    # 완료 요약
    # ──────────────────────────────────────────────
    echo ""
    echo -e "${GREEN}${BOLD}━━━ 설치 완료! ━━━${NC}"
    echo ""
    echo -e "  ${BOLD}설정 요약${NC}"
    echo -e "  ├── LLM: ${llm_provider} (${llm_model})"
    echo -e "  ├── Discord: $([ "$discord_enabled" = "true" ] && echo "활성" || echo "비활성")"
    echo -e "  ├── 정체성: ${hom_emoji} ${hom_name} (${instance_id})"
    echo -e "  ├── 자기 수정: $([ "$self_modify" = "true" ] && echo "허용" || echo "비활성")"
    echo -e "  ├── PR 생성: $([ "$create_pr" = "true" ] && echo "허용" || echo "비활성")"
    echo -e "  ├── 자동 스케줄: $([ "$auto_schedule" = "true" ] && echo "활성" || echo "비활성")"
    echo -e "  ├── 스킬 관리: $([ "$skill_mgmt" = "true" ] && echo "허용" || echo "비활성")"
    echo -e "  ├── 토큰 예산: $([ "$token_budget" = "true" ] && echo "활성 (${daily_limit})" || echo "비활성")"
    echo -e "  └── 리소스 모니터링: $([ "$resource_mon" = "true" ] && echo "활성" || echo "비활성")"
    echo ""
    echo -e "  ${BOLD}생성된 파일${NC}"
    echo -e "  ├── config/.env           — 환경변수 (비밀 키 포함)"
    echo -e "  ├── config/features.yaml  — 기능 허용 목록"
    echo -e "  └── config/instance.yaml  — 인스턴스 식별 정보"
    echo ""

    # 빌드 & 시작 제안
    echo -e "  ${BOLD}다음 단계${NC}"
    echo ""

    if ask_yes "지금 바로 호문쿨루스를 깨우시겠습니까? (Docker 빌드 + 시작)"; then
        echo ""
        echo -e "  ${CYAN}호문쿨루스를 플라스크에서 깨우는 중...${NC}"
        echo ""

        # docker compose 명령어 결정
        local compose_cmd="docker compose"
        if ! docker compose version &>/dev/null 2>&1; then
            compose_cmd="docker-compose"
        fi

        $compose_cmd -f "${SCRIPT_DIR}/docker/docker-compose.yml" \
            --env-file "$ENV_FILE" \
            up --build -d

        echo ""
        print_ok "호문쿨루스가 깨어났습니다!"
        echo ""
        echo -e "  ${BOLD}확인 방법${NC}"
        echo -e "  ├── 로그 보기:    ${DIM}docker logs -f homunculus${NC}"
        echo -e "  ├── 상태 확인:    ${DIM}docker ps | grep homunculus${NC}"
        echo -e "  ├── 부팅 리포트:  ${DIM}docker exec homunculus cat /home/node/.openclaw/workspace/BOOT_REPORT.md${NC}"
        echo -e "  └── 중지:         ${DIM}docker stop homunculus${NC}"
        echo ""

        if [ "$discord_enabled" = "true" ] && [ -n "$discord_token" ]; then
            echo -e "  ${BOLD}Discord에서 봇에게 DM을 보내보세요!${NC}"
        fi
    else
        echo -e "  나중에 시작하려면:"
        echo ""
        echo -e "    ${DIM}docker compose -f docker/docker-compose.yml --env-file config/.env up --build -d${NC}"
    fi

    echo ""
    echo -e "  ${DIM}설정 변경: config/.env 또는 config/features.yaml 을 수정 후 재시작${NC}"
    echo -e "  ${DIM}재설치:    ./install.sh 를 다시 실행${NC}"
    echo ""
}

main "$@"
