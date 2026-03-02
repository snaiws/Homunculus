# Homunculus

> The dwarf in the flask.

서버 안에서 살아가는 AI 에이전트입니다.
Discord로 대화하고, 스스로 코드를 개선하며, git PR로 진화합니다.

---

## 시작하기 전에

아래 3가지가 필요합니다.

| 필요한 것 | 설명 | 어디서? |
|-----------|------|---------|
| **서버** | Docker가 돌아가는 리눅스 서버 (Ubuntu 추천, RAM 2GB+) | 클라우드 VM, 집 서버, WSL 등 |
| **LLM API 키** | Anthropic, OpenAI, Gemini 중 하나 | [Anthropic Console](https://console.anthropic.com/) / [OpenAI Platform](https://platform.openai.com/) / [Google AI Studio](https://aistudio.google.com/) |
| **Discord 봇 토큰** | 호문쿨루스가 Discord에서 대화하려면 필요 (선택) | [Discord Developer Portal](https://discord.com/developers/applications) |

### Discord 봇 만들기 (처음이라면)

1. [Developer Portal](https://discord.com/developers/applications)에서 **New Application** 클릭
2. **Bot** 탭 → **Reset Token** → 토큰 복사 (한 번만 보임!)
3. **Bot** 탭 → **MESSAGE CONTENT INTENT** 켜기
4. **OAuth2 → URL Generator** → `bot` 체크 → **Send Messages, Read Message History** 체크
5. 생성된 URL로 내 서버에 봇 초대

---

## 설치

### 1단계: 서버에 코드 받기

```bash
git clone --recursive https://github.com/{your-username}/Homunculus.git
cd Homunculus
```

> `--recursive`를 빠뜨렸다면: `git submodule update --init --recursive`

### 2단계: 설치 마법사 실행

```bash
chmod +x install.sh
./install.sh
```

마법사가 7단계로 안내합니다:

```
Step 1/7 — 환경 & 네트워크 점검
  ├── Docker, Git, 서브모듈 확인
  ├── 인터넷 연결 (DNS, HTTPS)
  └── LLM/Discord/GitHub API 접근 가능 여부

Step 2/7 — LLM 프로바이더
  ├── Anthropic / OpenAI / Gemini 선택
  └── API 키 입력 → 실제 연결 테스트

Step 3/7 — Discord 설정
  ├── 봇 토큰 입력 → 실제 연결 테스트
  └── 건너뛰기 가능 (나중에 설정)

Step 4/7 — 호문쿨루스 정체성
  ├── 이름, 이모지
  └── 인스턴스 ID, 타임존

Step 5/7 — 기능 활성화
  ├── 자기 코드 수정 허용할까요? [y/N]
  ├── PR 생성 허용할까요? [y/N]
  ├── 자동 스케줄 활성화할까요? [y/N]
  ├── 스킬 관리 허용할까요? [y/N]
  ├── 토큰 예산 제한 활성화할까요? [y/N]
  └── 리소스 모니터링 활성화할까요? [y/N]

Step 6/7 — 설정 파일 생성
  ├── config/.env         (API 키, 토큰)
  ├── config/features.yaml (기능 허용 목록)
  └── config/instance.yaml (인스턴스 식별)

Step 7/7 — 연결 점검 요약 + 시작
  └── "지금 호문쿨루스를 깨우시겠습니까?" → Docker 빌드 & 시작
```

처음 빌드는 OpenClaw를 소스에서 컴파일하므로 **5~15분** 정도 걸립니다.

---

## 설치 후 확인

### 부팅 로그 보기

```bash
docker logs -f homunculus
```

정상이면 아래와 같이 나옵니다:

```
[BOOT] Generating openclaw.json from template...
[BOOT] Setting up workspace...
[BOOT] Linking Homunculus plugin...
[BOOT] Running boot health check...
  ### 1. Network
  - [x] Internet: OK (DNS + HTTPS)
  ### 2. LLM API
  - [x] Anthropic API key: present
  - [x] API connection: VERIFIED (HTTP 200)
  ### 3. Channels
  - [x] Discord connection: VERIFIED (bot: MyBot)
  ...
[BOOT] Health check: Passed=8 Warnings=0 Critical=0 Channels=1
[BOOT] Starting OpenClaw Gateway...
```

### 부팅 리포트 확인

```bash
docker exec homunculus cat /home/node/.openclaw/workspace/BOOT_REPORT.md
```

### Discord에서 말 걸기

봇에게 DM을 보내보세요. 응답하면 성공입니다.

---

## 일상 관리

### 시작 / 중지 / 재시작

```bash
# 시작
docker compose -f docker/docker-compose.yml --env-file config/.env up -d

# 중지
docker stop homunculus

# 재시작
docker restart homunculus

# 완전히 내리기 (컨테이너 삭제)
docker compose -f docker/docker-compose.yml down
```

### 설정 변경

`config/.env`를 수정한 뒤 재빌드:

```bash
docker compose -f docker/docker-compose.yml --env-file config/.env up --build -d
```

### 기능 허용 변경

`config/features.yaml`에서 항목을 수정:

```yaml
autonomy:
  self_modify:
    enabled: true    # ← false로 바꾸면 자기 수정 차단
  create_pr:
    enabled: false   # ← true로 바꾸면 PR 생성 허용
```

수정 후 `docker restart homunculus`.

### 데이터 보존

호문쿨루스의 상태(대화 기억, 설정 등)는 Docker 볼륨 `homunculus-state`에 저장됩니다.

```bash
# 볼륨 확인
docker volume inspect homunculus-state

# 주의: 아래 명령은 모든 상태를 삭제합니다
docker volume rm homunculus-state
```

---

## 문제 해결

### 부팅 시 `[CRIT] Network check FAILED`

인터넷 연결 불가. Docker 컨테이너가 자동으로 재시작을 시도합니다.
→ 서버의 인터넷 연결 확인, DNS 설정 확인.

### 부팅 시 `[CRIT] Anthropic API key invalid!`

API 키가 틀렸거나 만료됨.
→ `config/.env`의 `ANTHROPIC_API_KEY` 확인 후 재빌드.

### 부팅 시 `LLM API not verified — entering retry loop`

키는 있으나 API 서버에 연결 안 됨. 30초 간격으로 5회 재시도합니다.
→ API 서비스 장애 여부 확인. 5회 실패 시 degraded 모드로 시작.

### Discord 봇이 응답 안 함

```bash
docker logs homunculus | grep -i discord
```

- `Discord connection: FAILED - Invalid token` → 토큰 재확인
- `Discord disabled in openclaw.json` → 부팅 시 연결 실패로 자동 비활성화됨. 토큰 수정 후 재빌드.
- 봇에 **MESSAGE CONTENT INTENT**가 꺼져있을 수 있음.

### 처음부터 다시 설치

```bash
docker compose -f docker/docker-compose.yml down
docker volume rm homunculus-state
./install.sh
```

---

## 수동 설치 (install.sh 없이)

```bash
# 1. 환경변수 파일 생성
cp config/.env.example config/.env

# 2. config/.env 편집 — API 키, Discord 토큰 등 채우기

# 3. 빌드 & 시작
docker compose -f docker/docker-compose.yml --env-file config/.env up --build -d
```

---

## 프로젝트 구조

```
Homunculus/
├── install.sh                   # 대화형 설치 마법사
├── openclaw/                    # Git submodule (에이전트 프레임워크)
├── docker/
│   ├── Dockerfile               # 컨테이너 빌드 설정
│   ├── docker-compose.yml       # 서비스 정의
│   └── entrypoint.sh            # 부팅 순서 + 헬스체크
├── config/
│   ├── openclaw.template.json   # Gateway 설정 템플릿
│   ├── .env.example             # 환경변수 예시
│   ├── .env                     # 실제 환경변수 (git 무시)
│   ├── instance.yaml            # 인스턴스 식별
│   ├── features.yaml            # 기능 허용 목록
│   └── directives/              # 지침 프레임워크
├── plugin/
│   └── src/
│       └── index.ts             # 코어 플러그인
├── workspace/
│   ├── AGENTS.md                # 운영 지침
│   ├── SOUL.md                  # 페르소나
│   ├── IDENTITY.md              # 이름 + 이모지
│   └── MEMORY.md                # 장기 기억
└── docs/
    └── plan/
        └── REQUIREMENTS.md      # 전체 요구사항
```

---

## 로드맵

| Phase | 이름 | 상태 | 설명 |
|-------|------|------|------|
| 1 | 생존 | **현재** | 플라스크에서 눈을 뜨고, 주인과 대화 |
| 2 | 자율 | 예정 | 생활 리듬, 스킬 관리, 자기 수정 |
| 3 | 성장 | 예정 | Python 실행, 메모리 강화, 리소스 관리 |
| 4 | 번식 | 예정 | 멀티 인스턴스, PR 기반 분산 진화 |
