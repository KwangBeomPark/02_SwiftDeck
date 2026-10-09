# SwiftDeck 3~5단계 검수

2026-10-08. 배포 보호 변경은 유지하고 설정·백업 범위·공개 지도·잘못된 설정 위치 안내를 정비했습니다. 앱 이름·설치 식별자·단축키·버전은 유지합니다.

## 변경된 동작

- 활성 설정을 실행 파일/소스 진입점 옆 `UserSetting`로 통합합니다. 기존 이름의 즐겨찾기·프롬프트·텍스트 확장·키 리매핑 네 INI를 Roaming에서 복사하며, 기존 대상이 우선합니다.
- 원본은 이동·삭제하지 않습니다. 복사본은 바이트·INI 가독성을 확인하며 네 파일 처리 성공 후에만 이관 마커를 기록합니다. 중간 실패는 시작을 막고, 다음 시도에서 이미 검증한 사본을 유지하며 나머지를 처리합니다.
- 일반 단축키 묶음은 `config.ini` 한 곳에 원자적으로 저장합니다. 명시적 빈 PromptModifier도 이전 기본값으로 되돌리지 않습니다. 기존 레지스트리는 새 설정의 누락된 키만 한 번 복사합니다.
- `AtomicSettings.ahk`는 형제 임시 파일 쓰기·검증·flush 후 ReplaceFileW/MoveFileExW로 반영합니다. 직접 쓰기 fallback은 없으며 일반 저장은 예외, 기존 SafeWriteLocalSetting 계약은 false로 실패를 전달합니다.
- **Backup Saved**에는 config.ini를 포함한 다섯 INI가 포함됩니다. 네 INI만 있는 구버전 UI 백업은 일반 단축키를 config.ini로 복원합니다. 초기 기본값·Factory Reset은 명시적 기본 단축키를 기록합니다.
- UI Restore는 변경 전 사본을 모두 검증한 뒤 파일을 원자 교체합니다. 복구가 실패하면 성공했다고 안내하지 않으며 사본 폴더를 보존합니다. 원래 없던 파일은 복구 때 없던 상태로 되돌립니다.
- 업데이트 창의 과거 Roaming 저장 위치 안내를 현재 UserSetting 안내로 고쳤습니다. 공개 구조는 [CODE_MAP](CODE_MAP.md), 전체 ZIP 백업은 [USER_DATA](USER_DATA.md)와 [관리 도구](../scripts/Manage-UserData.ps1)를 사용합니다.

## 실행한 검증

- 실제 AutoHotkey v2: 기존 ConfigCodec·ConfigPrompt·ConfigStorage·SettingsManager·UpdateManager·Utils와 새 ConfigMigration, 총 7개 suite 통과.
- ConfigMigration의 39개 검사: 대상 우선·Unicode 바이트 복사·원본 보존·마커 반복 방지·실패 후 재시도·레지스트리 누락키/잠금 실패·명시적 빈 값·단일 저장·UI 백업·구버전 복원·잠금 rollback 실패/재시도/사본 보존.
- 실제 main `/Validate`, 정적 검사, Windows PowerShell 5.1 공통 백업 안전성 32개 검사 통과. 빌드 게이트에 백업 검사를 연결했습니다.
- 기존 테스트가 저장소의 tests/UserSetting에 쓸 수 있던 경로를 고유 fixture로 격리했습니다. `--keep-fixtures`는 검사 자료를 보존하며 추가 재귀 정리를 요구하지 않습니다.
- 04·05 담당 독립 읽기 검수에서 rollback 오류 은폐 지적을 받아 보완했고 재검수에서 추가 차단 결함은 발견하지 않았습니다. 공통 백업의 버전/이름 변경 EXE 감지 누락도 총괄에게 전달해 수정·회귀 검사로 반영했습니다.

## Gemini 활용 증거

Antigravity CLI의 `gemini-3.8-flash-high`, effort high에 도구 없는 작은 설계 요청을 보내 내용 있는 응답을 받았습니다(54.89초). 로그는 git 제외된 `build/standardization/agy/settings-design-ed52337ff42e4a09bd4ac50c9fac14cf.json`입니다. 대상 우선·원본 보존·일반 단축키 단일 저장·전체 INI 백업 제안을 채택했습니다. 잘못된 임의 파일명과 Buffer 객체 자체 비교 예시는 채택하지 않고 실제 파일명·바이트 비교로 검증했습니다.

추가 코드 검수 요청 `settings-audit-eb5ef064957e4d76ab1845125a9522cc.json`은 90초 후 빈 응답·0토큰으로 끝났습니다. CLI의 SUCCESS 표시는 완료 증거로 인정하지 않았으며 NOT_COMPLETED로 기록했습니다. 실제 코드 검수·수정·실행 검증은 Codex가 수행했습니다.

## 남은 실제 동작 게이트

사용자의 실제 설치/포터블 사본에서 최초 이관, 앱 설정 Apply·Restore·Factory Reset, 기존 단축키 실행, 업데이트 재시작, 쓰기 불가능한 폴더의 안내를 확인해야 합니다. 파일시스템 원자 교체는 다중 프로세스의 논리적 동시 편집 병합을 제공하지 않습니다. 앱 종료 후 백업하며, 외부 AHK 소스 실행 종료는 사용자가 확인합니다. 기존 Roaming 백업은 참고용 원본이고 UpdateState.ini는 재생성 가능한 확인 캐시입니다.

실제 사용자 설정 이관·앱 UI 실행·설치·서명·게시·공식 배포 파일 변경은 수행하지 않았습니다.
