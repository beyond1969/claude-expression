# 감정표현모듈 마이그레이션 플랜

원본 시스템(`~/agent_images/`)에서 배포용(`~/Desktop/claude-expression/`)으로 전환하기 위한 계획.

## 백업 내역

`backup/` 디렉토리에 아래 원본 데이터가 보관되어 있음.

| 백업 항목 | 원본 경로 | 백업 경로 |
|-----------|-----------|-----------|
| 뷰어 + 이미지 디렉토리 | `~/agent_images/` | `backup/agent_images/` |
| 클루카이 expression | `~/.klukai_expression` | `backup/.klukai_expression` |
| 클루카이 speech | `~/.klukai_speech` | `backup/.klukai_speech` |
| 뷰어 PID | `~/.agent_viewer.pid` | `backup/.agent_viewer.pid` |

## 지휘관이 해야 할 일

### 1. 이미지 복사 (자동화 가능 — 클루카이에게 지시)

404 소대원 이미지를 `agents/`로 복사:
```
agents/klukai/    ← agent_images/klukai/*.png
agents/andoris/   ← agent_images/andoris/*.png
agents/mishuti/   ← agent_images/mishuti/*.png
agents/viyolka/   ← agent_images/viyolka/*.png
```

### 2. CLAUDE.md 수정 (지휘관 직접 작업)

`~/CLAUDE.md`의 감정 표현 모듈 섹션을 새 경로로 교체해야 함.

**변경 대상:**
- `~/agent_images/expr` → `~/Desktop/claude-expression/expr`
- `~/agent_images/viewer` 관련 경로 → `~/Desktop/claude-expression/start.sh`
- `~/.{name}_expression` → `state/{name}_expression` (에이전트가 expr 헬퍼로 접근하므로 직접 참조 불필요)
- expression/speech 파일 경로 테이블 → 불필요 (expr 헬퍼가 상대 경로로 처리)

**핵심:** CLAUDE.md에서 `EXPRESSION.md`를 참조하도록 바꾸면, 경로 세부사항을 CLAUDE.md에 하드코딩할 필요 없음.

### 3. 기존 원본 정리 (마이그레이션 확인 후)

마이그레이션이 정상 동작하는 걸 확인한 뒤에 정리:
- `~/agent_images/` 삭제
- `~/.klukai_expression`, `~/.klukai_speech` 삭제
- `~/.agent_viewer.pid` 삭제
- (다른 소대원의 `~/.{name}_expression`, `~/.{name}_speech`가 있다면 함께 삭제)

## 클루카이가 할 일

지휘관 지시 시:
1. 이미지를 `backup/agent_images/{name}/` → `agents/{name}/`으로 복사
2. `sample/` 디렉토리 정리 (필요시 삭제)
3. CLAUDE.md의 감정표현모듈 섹션 교체안 제시
4. 새 시스템으로 뷰어 실행 후 동작 확인
5. 원본 파일 정리 (지휘관 승인 후)
