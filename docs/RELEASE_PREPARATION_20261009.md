# SwiftDeck 1.4.2 릴리즈 준비 검수

2026-10-09. 소스 준비와 자동 검수를 마쳤으며 실제 새 KSP 서명·앱 설치·게시·태그 생성은 하지 않았습니다. 기존 사용자 변경·설정·공식 배포 파일을 보존했습니다.

## 변경과 효과

- 공식 설치 파일은 `App02_SwiftDeck_Setup_v1.4.2.exe` 한 개와 검증용 `SHA256SUMS.txt`, `build-manifest.json`입니다. Inno 출력과 sign.ps1이 찾는 파일이 달랐던 결함을 해결했고 새 파일을 직접 서명합니다. 공식 세트에 ZIP·별칭·내부 EXE를 중복으로 남기지 않습니다. AppId·기본 설치 폴더·내부 앱 EXE명은 유지합니다.
- 기존 v1.4.1 태그가 있으므로 최소 패치 후보를 1.4.2로 올렸습니다. 원격 태그 조회 당시 v1.4.2는 없었습니다. 서명 직전 다시 확인해야 하며 버전을 예약하지 않습니다.
- signed 장부의 중첩 signature 객체를 정규식으로 읽지 못하던 결함을 `ReleaseJson.ahk`의 엄격한 JSON 파서로 해결했습니다. 제품·버전·허용 파일명·크기·SHA-256과 중복 키/자산·모호한 두 설치 파일·다른 객체의 해시·문법·Unicode·깊이/길이를 검사합니다. 과거 App02 설치 이름은 호환 읽기에 남깁니다.
- 실제 설치 프로그램 실행 직전에 쓰기/교체를 차단한 읽기 공유 핸들을 열고 해시를 재검사합니다. 설치 파일과 현재 앱의 유효 Authenticode·타임스탬프·같은 게시자 인증서를 확인해야 Run으로 진행합니다. 검수용 PS helper는 컴파일된 앱에 포함되며 고유 임시 파일로 추출됩니다. 실패 시 앱을 변경하지 않고 수동 설치를 안내합니다.
- 게시는 기존 서명 세트만 소비합니다. GitHub 호스트/저장소·origin·origin/main 승인 SHA를 고정·검증하고 draft 업로드의 digest 확인 후 공개합니다. 자동 push/재서명/기존 자산 덮어쓰기 없이 실패한 draft를 보존합니다.

## 검증

| 검사 | 결과 |
| --- | --- |
| Windows PowerShell 5.1 릴리즈 보호 | 54개 통과; 서명 객체는 fixture이며 새 KSP 사용 없음 |
| 설치 파일 서명/게시자 정책 | 9개 통과; 유효 동일 게시자, 미서명·변조·타임스탬프 없음·게시자 불일치·기존 앱 미서명 차단 |
| 도구 탐색 | 5개 통과 |
| 공통 사용자 백업 | 32개 통과; 실제 UserSetting을 사용하지 않음 |
| 실제 AHK 회귀 | 7개 suite 통과; 새 signed 장부/JSON 안전성 31개 검사와 기존 이관/복원 39개 포함 |
| 실제 Windows 서명 읽기 verifier | 기존 서명 설치 파일을 같은 게시자 비교 입력으로 사용해 exit 0, 미서명 합성 파일은 exit 13. 새 서명 앱을 실행하거나 설치한 검증은 아님 |
| 정적 검사·diff 공백 검사 | 통과 |
| 새 이름 실제 미서명 설치 파일 컴파일 | 고유 `build/standardization/installer-ready-024883fd41a846b8816cc5e313ec5d01/`에서 생성. 공식 release에 반영하지 않음 |

근거는 git 제외 `build/standardization/release-final-tests-d9761ebd0f2a4ddd84acb02a53247b3e/`의 AHK/PS/서명 읽기 기록과 각 build의 `result-final.json`입니다. PowerShell 7 모듈 경로를 상속한 첫 격리 Windows PowerShell 검사는 Get-FileHash를 못 찾아 실패했습니다. 검사 프로세스에만 Windows PowerShell 모듈 경로를 명시한 뒤 통과했으며 전역 환경은 바꾸지 않았습니다.

## 구버전 이행과 남은 게이트

1.3.1·1.4.0·1.4.1 클라이언트는 fixed EXE 또는 update.ini를 기대하므로 **최초 1.4.2는 수동 설치**해야 합니다. 과거 자산은 삭제하지 않으며 새 코드가 배포된 구형 앱을 소급 수정하지 않습니다. 새 버전부터 JSON 장부 설치 업데이트를 사용합니다.

인증서가 바뀌거나 기존 앱이 미서명이거나 PowerShell/정책/오프라인 신뢰 확인이 실패하면 자동 설치가 중단됩니다. 동일 인증서 정책을 완화하지 않고 사용자가 서명과 게시자를 확인해 수동 설치합니다. 실제 컴파일 앱에서 helper 추출·정책 허용·진행 창·잠금·Run·기존 프로세스 종료와 실제 upgrade/cancel/uninstall 검수는 사용자 세션의 남은 게이트입니다. 네트워크 검사와 런타임 설치 성공을 mock 및 파서 테스트로 대신하지 않습니다.

## Gemini와 사용자 실행

`gemini-3.8-flash-high`, effort high의 내용 있는 설계 검토를 61.67초에 받았습니다. Map CaseSense·compiled guard와 정책/인증서/오프라인 실패 안내를 확인했고, 기존 도구를 재사용하는 최소 PS helper를 택했습니다. 광범위 Win32 인증 라이브러리 도입은 하지 않았습니다. CLI 시간 단위 오류 1회와 stdout 인코딩 수집 실패 1회는 완료로 계산하지 않았습니다. 원문: `build/standardization/agy/release-parser-review-cd48945a3df14f4aa15613d459d1d834.json`. 계정 크레딧 차감·절약은 확인하지 않았습니다.

[루트 체크리스트](../RELEASE_CHECKLIST.md)에 현재 release.ps1의 환경변수/인자와 별도 게시 명령을 정리했습니다. 승인 clean main → 사용자 관리자 서명 세션에서 release → 실제 새 서명/앱/실행 중 업그레이드 검수 → 같은 커밋 별도 push → publish 순서입니다.
