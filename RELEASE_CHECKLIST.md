# SwiftDeck 다음 릴리스 체크리스트

2026-10-09 릴리즈 준비 검수 기준입니다. 기존 변경을 보존하며 명명·장부 파서·서명 게시자 검증·게시 보호를 최소 수정하고 자동 검사를 수행했습니다. 실제 KSP 서명·설치·게시·태그 변경은 실행하지 않았습니다.

## 현재 준비 상태

- [x] 설치 파일 이름은 `App02_SwiftDeck_Setup_v1.4.2.exe` 하나입니다. Inno·빌드·서명·장부·검사·업데이트·게시 목록을 맞췄습니다. AppId·기본 설치 폴더·앱 내부 EXE명은 유지합니다.
- [x] 새 소스 버전은 `1.4.2`입니다. 원격 v1.4.2 태그는 조회 시 없었습니다. 이는 태그 예약이나 게시 완료를 뜻하지 않습니다.
- [x] 중첩 signature가 있는 장부를 엄격한 JSON 파서로 읽습니다. 제품/버전/파일명/중복 키와 자산/크기/해시/JSON 길이와 깊이를 검증하며 다른 객체의 해시를 가져오지 않습니다.
- [x] 설치 파일 실행 전 쓰기·교체를 차단한 상태에서 해시를 재확인합니다. 설치 파일과 현재 앱 모두 유효하고 타임스탬프가 있는 Authenticode 서명 및 같은 게시자 인증서가 있어야 실행합니다. 인증서 교체·권한/보안 정책/오프라인 검증 실패는 수동 설치 안내와 함께 실행을 중단합니다.
- [x] 게시 명령은 이미 서명한 공식 세트만 사용하며 자동 push하지 않습니다. GitHub 호스트/저장소와 origin을 고정·대조하고 draft 자산의 digest 검증 후 공개합니다.
- [ ] 구형 1.3.1·1.4.0·1.4.1은 installer-only 배포로 최초 수동 업그레이드해야 합니다. 구형 앱의 fixed EXE/update.ini 의존성을 새 코드가 소급해서 바꾸지는 않습니다. 이번 버전 이후부터 새 JSON 설치 업데이트를 사용합니다.
- [ ] 리뷰한 소스를 clean `main` 커밋으로 확정하고 사용자 서명 명령을 실행합니다. 게시 전에 같은 커밋을 origin/main에 별도로 push해야 합니다.

## 사용자 할 일

- [ ] 기존 사용자 변경을 포함한 미커밋 소스를 검토합니다. 구형 앱 이행 정책·버전·릴리스 노트·원본 변경 포함 여부를 검토하고 clean `main` 커밋을 확정합니다.
- [ ] 실행 중인 앱/AHK 소스를 종료하고 활성 `UserSetting` 전체를 백업·검증합니다. `config.ini`와 즐겨찾기·프롬프트·텍스트 확장·리매핑의 네 INI를 포함하며, 기존 Roaming 설정/Backups는 별도 원본으로 보관합니다. [백업 안내](docs/USER_DATA.md).
- [ ] AutoHotkey v2, Ahk2Exe, Inno Setup, Microsoft SignTool을 준비합니다. SimplySign 로그인·인증서 선택·PIN/OTP는 사용자가 직접 실행하는 서명 세션에서 처리합니다.
- [ ] 현재 커밋의 정적 검사, AHK 7개 suite, 원자 저장/이관/복원 실패 보호, 백업과 릴리스 보호, 업데이트 파서·worker 검수를 다시 실행합니다. 이전 결과는 [3~5단계 검수](docs/STANDARDIZATION_PHASE3_5_REVIEW.md), [종합 검수](docs/STANDARDIZATION_FINAL_REVIEW.md)를 참고합니다. `SkipTests` 산출물은 공식 서명 입력으로 사용하지 않습니다.

```powershell
# 승인 커밋 확정 후, 사용자 직접 실행 관리자 Windows PowerShell에서 실행
$env:SIGNTOOL_PATH = '<Microsoft SignTool 전체 경로>'
.\scripts\release.ps1 -CertificateThumbprint '<선택한 공개 인증서 지문>'
```

- [ ] 위 release 명령은 sign.ps1에 위임해 고유 스테이징에서 검사·앱 EXE 서명·설치 파일 생성/서명·장부 검증 후 로컬 공식 폴더에 반영합니다. 설치 파일과 두 검증 메타데이터만 공식 폴더에 남깁니다. 기존 `release/`를 지우거나 다시 서명하지 않습니다. 기본 재빌드를 사용하고 `SkipBuild`의 오래된 입력을 임의로 채택하지 않습니다.
- [ ] 설치 파일과 실제 설치된 앱 EXE의 서명·게시자·타임스탬프, 장부/체크섬의 실제 파일·버전·커밋을 확인합니다. 설치 파일 한 개만 게시한다는 정책은 앱 내부 EXE 서명을 생략한다는 뜻이 아닙니다.
- [ ] 격리 Windows에서 실행 중 구버전 정상 종료, 종료 거부/잠금 시 설치 차단, 취소·실패, 업그레이드 후 설정 보존, 제거 후 설정 보존을 확인합니다. 최초 Roaming 이관·재시도, Apply·Restore·Factory Reset, 즐겨찾기·프롬프트·텍스트 확장·리매핑·기존 단축키와 쓰기 실패 안내를 실제 앱으로 점검합니다. [실제 설치 검수](docs/INSTALL_UPGRADE_ACCEPTANCE.md).
- [ ] 구형 앱의 실제 업데이트와 신버전의 JSON 설치 업데이트를 각각 확인합니다. 미서명 개발 산출물·소스 테스트는 실제 설치 업데이트 검수를 대신하지 않습니다. Office/VBA·공유 폴더의 `App02*` 패턴과 실제 배포된 값도 확인합니다.

```powershell
# 검증한 새 서명 세트의 게시만 수행합니다.
.\scripts\publish.ps1 -OutputDirectory release
```

- [ ] 새 GitHub 태그 커밋, stable/latest 상태, 설치 파일 한 개와 필요한 두 메타데이터의 이름·SHA-256·크기를 확인합니다. `sign.ps1 -Publish`도 실제 존재하는 옵션이지만 서명과 게시 검토를 나누려면 위 두 명령을 따로 실행합니다. 기존 자산을 덮어쓰지 않습니다. `publish.ps1 -Resume`는 같은 커밋/서명 세트의 누락 자산만 검증 후 추가하는 복구 경로이며 다른 파일로 교체하는 옵션이 아닙니다.

## 사용자와 검토할 삭제 후보

아래는 2026-10-09 현재 크기이며 **삭제 승인이 아닙니다**. 모두 Git 추적 파일 0개입니다. `build/` 전체와 실제 Roaming/UserSetting 백업을 묶어 지우지 않습니다.

| 후보 | 크기·개수 | 현재 참조와 이유 | 지우기 전 조건·재생성 |
| --- | --- | --- | --- |
| `build/backup-test-*` 6개 | 합계 51,930 bytes, 117 files | `scripts/test_user_data_backup.ps1`의 고유 반복 fixture이며 운영 백업 입력이 아닙니다. | 마지막 통과/실패 기록과 fixture의 합성 자료임을 확인한 뒤 승인받습니다. 같은 검사로 재생성합니다. |
| `build/settings-tests-*` 4개 | 합계 9,294 bytes, 77 files | `tests/ConfigMigrationTests.ahk`의 고유 이관/복원 fixture입니다. | 마지막 검수 근거 보존 후 승인받습니다. 같은 AHK 검사를 재실행해 생성합니다. |
| `build/phase2 verification 5a066f5bdefe48e79769d4e4b7b4406c` | 7,422,878 bytes, 7 files | 이전 배포 보호 검수 사본입니다. 현재 빌드 기본 입력으로 참조하지 않습니다. | 검수 JSON·로그와 공식 원본을 별도로 보존하고 승인받습니다. 같은 도구/소스로 검수 fixture를 만들 수 있지만 과거 서명 바이트 재현은 보장하지 않습니다. |
| `build/standardization/portable-signature-d9f834ca17a94c94b8e955ef497a9e5f` | 1,500,288 bytes, 1 file | 공개 ZIP에서 서명 검사에 사용한 EXE 추출 사본입니다. | 원본 ZIP·해시/서명 검수 JSON 보존 후 승인받습니다. 같은 원본 ZIP에서 재추출합니다. |
| `dist/`의 현재 생성 파일 6개 | 7,402,496 bytes | 로컬 빌드 산출물입니다. `sign.ps1 -SkipBuild -BuildOutputDir dist`가 이 폴더를 서명 입력으로 참조하므로 단순 캐시로 단정하지 않습니다. | 다음 서명에서 재빌드를 쓰는지 확인하고 마지막 입력 장부를 보관한 뒤 파일별 승인받습니다. 검사 성공 후 빌드로 재생성할 수 있으며 서명된 과거 바이트는 재현을 보장하지 않습니다. |

`release/`, `build/release-history/`, `build/standardization`의 Gemini 응답·원격/서명 검수 JSON, `UserSetting`, Roaming 설정/Backups, 레지스트리·인증 자료·사용자 파일은 삭제 후보에서 제외합니다. 실패 복원 사본도 정상 복구 확인 전에는 보존합니다.

## 검수 근거와 남은 경계

현재 소스의 자동 검수와 실제 미서명 설치 파일 컴파일 결과는 [릴리즈 준비 검수](docs/RELEASE_PREPARATION_20261009.md)에 기록합니다. Gemini High의 내용 있는 새 설계 검토 61.67초와 실패한 CLI 출력 수집을 구분했습니다. 과거 통과 기록은 이 변경의 통과로 대체하지 않습니다.

서명·설치·게시 명령은 사용자가 직접 실행합니다. 새 KSP 서명 성공, 실행 중 실제 업그레이드·제거, 새 GitHub 게시 완료는 아직 확인되지 않았습니다.
