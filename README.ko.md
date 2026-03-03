# 감정표현모듈

Claude Code 에이전트의 표정과 말풍선을 화면에 띄워주는 macOS 플로팅 뷰어입니다. `agents/` 디렉토리를 스캔해 에이전트를 자동 탐지하며, 경로나 이름이 하드코딩되어 있지 않습니다. 세션 시작 시 자동 기동, 종료 시 자동 정리됩니다.

뷰어 실행/종료, 표정 변경, 말풍선 표시는 모두 에이전트가 자동으로 수행합니다. 사용자가 할 일은 **초기 설정**뿐입니다.

## 요구사항

- macOS
- Swift 런타임 (Xcode Command Line Tools에 포함)
  ```bash
  xcode-select --install
  ```

## 설치

원하는 위치에 디렉토리를 복사하고 실행 권한을 부여합니다.

```bash
cd claude-expression
chmod +x expr start.sh stop.sh
```

## 설정

### 1. 에이전트 이미지 배치

`agents/` 아래에 에이전트 이름으로 디렉토리를 만들고, 표정 이미지를 넣습니다.

```bash
mkdir agents/myagent
```

표정 이미지는 `{표정}.png` 형식 (240x240 권장):
```
agents/myagent/normal.png
agents/myagent/angry.png
agents/myagent/thinking.png
...
```

지원 표정: `normal`, `angry`, `confused`, `proud`, `shy`, `surprise`, `thinking`

이미지가 없으면 에이전트 이름의 첫 글자가 placeholder로 표시됩니다.

### 2. CLAUDE.md에 연동 설정 추가

프로젝트의 `CLAUDE.md`에 아래 내용을 추가합니다. 경로와 에이전트 이름은 본인 환경에 맞게 수정하세요.

```markdown
# Emotion Expression Module

See `/path/to/claude-expression/EXPRESSION.md` for full instructions.

- **EXPRESSION_DIR**: `/path/to/claude-expression`
- **AGENT_NAME**: `myagent`
```

이것만 넣어두면 에이전트가 `EXPRESSION.md`를 읽고 뷰어 실행부터 표정 제어까지 알아서 처리합니다.

## 멀티 에이전트

여러 에이전트를 동시에 표시할 수 있습니다. 각 에이전트에 필요한 것:
- `agents/` 안의 이미지 디렉토리
- `state/` 안의 expression 파일 (`expr` 헬퍼가 자동 생성)

뷰어는 `agents/`를 스캔하고, `state/{이름}_expression` 파일 존재 여부로 표시/숨김을 결정합니다.

## 디렉토리 구조

```
claude-expression/
├── README.md           # 영문 안내
├── README.ko.md        # 한글 안내 (이 파일)
├── EXPRESSION.md       # 에이전트용 표정 모듈 지시문
├── viewer.swift        # macOS 뷰어 (상대 경로 기반)
├── expr                # 표정/말풍선 헬퍼 스크립트
├── start.sh            # 뷰어 실행
├── stop.sh             # 뷰어 종료
├── state/              # 런타임 상태 파일 (자동 관리)
└── agents/             # 에이전트별 이미지 디렉토리
    └── sample/         # 샘플 에이전트 (placeholder 데모)
```

## 작동 원리

- `start.sh`가 `viewer.swift`를 컴파일·실행하며, 패키지 디렉토리 경로를 인자로 전달. 또한 `~/.claude/settings.json`에 `SessionEnd` hook을 등록하여 세션 종료 시 뷰어가 자동으로 정리됨
- 뷰어는 `agents/` 하위 디렉토리를 스캔해 에이전트 목록을 구성
- 0.3초마다 `state/{이름}_expression` 파일을 확인해 에이전트 표시/숨김 처리
- 표정 이미지는 `agents/{이름}/{표정}.png`에서 로드
- 말풍선은 `state/{이름}_speech`에서 읽음
- 뷰어 윈도우는 화면 좌상단에 플로팅 (세로 모니터 우선)

## 라이선스

MIT
