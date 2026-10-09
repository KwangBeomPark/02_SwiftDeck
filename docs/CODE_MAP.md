# SwiftDeck 공개 코드 지도

이 문서는 공개 저장소에서 공유하는 구조·대표 흐름입니다. 개인 작업 환경을 담은 로컬 `AI_CODE_MAP.md`는 별도로 유지합니다.

| 역할 | 위치와 대표 흐름 |
|---|---|
| 시작·단축키 | `src/SwiftDeck.ahk`: 설정 이관 → 파일 초기화 → 메뉴·단축키 등록 |
| 설정 저장 | `src/SettingsManager.ahk`, `src/AtomicSettings.ahk`: 새 설정 우선 → 누락된 레지스트리 설정 1회 복사 → 임시 파일 검증·원자적 교체 |
| 설정·복구 | `src/lib/Config.ahk`: 기존 Roaming INI 원본 보존·검증 복사, 다섯 INI 관리, 저장·백업·복원 |
| 앱 설정 | `src/lib/PreferencesManager.ahk`, `DashboardManager.ahk`: General 변경 → Apply → 단일 config.ini 저장 |
| 즐겨찾기·프롬프트 | `FolderManager.ahk`, `PromptManager.ahk`: 메뉴 편집 → Config 게이트 → 파일 저장 |
| 텍스트 확장·키 리매핑 | `HotstringManager.ahk`, `KeyRemapManager.ahk`: 편집 → INI 저장 → 단축 동작 재등록 |
| 자동 업데이트 | `src/lib/UpdateManager.ahk`: 릴리스 확인 → ReleaseJson으로 설치 장부 검증 → 해시·서명 게시자 확인 → 설치 프로그램 실행 (구형 INI/worker 호환 경로 유지) |
| 빌드·배포 | `scripts/build.ps1`, `sign.ps1`, `ReleaseSafety.ps1`, `publish.ps1`; `installer/setup.iss` |
| 검증 | `tests/*Tests.ahk`, `scripts/static-check.ps1`, `scripts/test_user_data_backup.ps1` |

활성 설정은 실행 파일 또는 소스 진입점 옆 `UserSetting`입니다. 일반 단축키는 `config.ini`, 즐겨찾기·프롬프트·텍스트 확장·키 리매핑은 기존 이름의 네 INI에 저장합니다. 이전 `%APPDATA%/SwiftDeck`과 `AHK_FolderHotKey` 사본은 이동·삭제하지 않습니다. 업데이트 확인 캐시는 `%APPDATA%/SwiftDeck/UpdateState.ini`에 남으며 백업 필수 설정에 포함되지 않습니다.

설정 위치·전체 백업·새 폴더 복원은 [사용자 자료 안내](USER_DATA.md)와 [관리 도구](../scripts/Manage-UserData.ps1)를 참고하세요. UI의 **Backup Saved**는 디스크에 저장된 다섯 INI를 보관합니다. **Restore**는 기존 네 INI만 있는 구버전 백업도 읽으며, 일반 단축키를 새 config.ini에 반영합니다. UI 기능은 전체 UserSetting ZIP 백업과 범위가 다릅니다.

배포 보호와 실제 설치 검수 경계는 [2단계 검수](STANDARDIZATION_PHASE2_REVIEW.md), 설정 통합 검수는 [3~5단계 검수](STANDARDIZATION_PHASE3_5_REVIEW.md)에 기록합니다. 앱 이름·설치 식별자·기본 단축키는 유지합니다.

2026-10-09 릴리즈 준비: `src/lib/ReleaseJson.ahk`는 중첩 서명 JSON의 엄격한 파서이며, `scripts/Verify-UpdateInstaller.ps1`은 설치 파일과 현재 앱의 서명·타임스탬프·게시자 인증서 일치를 검사합니다. [준비 검수](RELEASE_PREPARATION_20261009.md), [사용자 체크리스트](../RELEASE_CHECKLIST.md).
