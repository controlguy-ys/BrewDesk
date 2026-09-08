# BrewDesk

[English](README.md) · **한국어**

[Apple Silicon DMG 다운로드](https://github.com/controlguy-ys/BrewDesk/releases/tag/v0.2.0) · [실제 조작 영상](docs/media/brewdesk-walkthrough.mp4)

![BrewDesk 설치 목록](docs/media/installed-en.png)

Homebrew로 설치한 앱과 개발 도구를 조회하고, 선택한 변경을 확인한 뒤 실행하는 SwiftUI macOS 앱입니다. 실행에는 macOS 14 이상과 기존 Homebrew 설치가 필요합니다. 빌드에는 Swift 6 도구 체인, 테스트에는 XCTest를 포함한 Xcode와 최초 의존성 다운로드를 위한 인터넷 연결이 필요합니다. 빌드한 Mac의 CPU 아키텍처용 앱을 만듭니다. 이번 검증 환경은 Apple Silicon입니다. SwiftTerm은 Package.resolved에 고정합니다.

## 실행

```sh
./scripts/test.sh && ./scripts/build-app.sh && open dist/BrewDesk.app
```

개발 중에는 `swift run BrewDesk`로 실행할 수도 있습니다. 앱 번들은 `dist/BrewDesk.app`, 로컬 DMG는 `./scripts/package-dmg.sh`로 생성하는 `dist/BrewDesk-local.dmg`입니다. File Provider가 관리하는 Documents 폴더에서는 앱 메타데이터가 자동으로 추가될 수 있으므로, 실행용 앱은 DMG에서 로컬 Applications 폴더로 복사하는 편이 좋습니다. DMG 안의 앱은 별도 임시 폴더에서 서명을 검증합니다. 현재 빌드는 ad-hoc 서명만 적용합니다. GitHub에는 Apple Silicon용 미리보기 버전으로 제공합니다. Developer ID 서명·Apple 공증은 아직 없으며 다른 Mac에서의 실행 검증도 남아 있습니다. 다운로드한 앱이 macOS에서 차단될 수 있습니다. 파일을 신뢰하고 실행하려는 경우에만 macOS 시스템 설정의 개인정보 보호 및 보안에서 해당 앱의 열기 허용을 사용하세요. 보안 설정을 전역으로 끄지 마세요.

## 언어

기본 언어는 영어입니다. **Settings → Language → App language**에서 English, 한국어, System language를 선택할 수 있습니다. 앱 문구는 즉시 바뀌고 선택은 다음 실행에도 유지됩니다. System language는 macOS의 선호 언어 중 처음 지원되는 영어·한국어를 선택하며, 둘 다 없으면 영어를 사용합니다. macOS 선호 언어 자체를 변경했다면 앱을 다시 실행하세요.

번역 대상은 앱이 소유한 메뉴·화면·확인창·오류 안내·상태 문구입니다. 새 작업 기록의 결과는 선택 언어에 맞춰 표시하며, 이전 버전에서 저장한 기록과 Homebrew 설명·콘솔 출력은 원문을 유지합니다. 숫자와 패키지 이름은 번역 템플릿과 분리해 보존합니다.

번역은 `Sources/BrewDesk/Resources/en.json`과 `ko.json`에서 관리합니다. 키는 원문 템플릿이며 `{0}`, `{1}`은 삽입 값입니다. 새 언어는 `Localization.swift`의 `AppLanguage`, 시스템 언어 선택 규칙, 카탈로그 로더와 `scripts/build-app.sh`의 `CFBundleLocalizations`에 등록합니다. 누락 키는 영어, 영어에도 없으면 원문 키로 표시합니다. `./scripts/test.sh`로 언어 기본값·선택 저장·시스템 대체 언어·카탈로그 키와 삽입 값 일치·기존 기록 호환성을 검증합니다.

## 사용 흐름

기존 Homebrew 패키지를 관리하는 앱이며 신규 설치는 제공하지 않습니다.

1. 기본 Homebrew 경로를 확인합니다. 두 환경이 있으면 설정에서 하나를 선택합니다. 선택한 경로는 기억하며 목록은 분리합니다. 기록은 환경 경로를 표시하는 통합 기록입니다. 필요하면 신뢰할 수 있는 `brew` 실행 파일을 직접 지정합니다.
2. 설치 목록에서 검색·유형 필터를 사용하고 항목을 선택해 상세 정보를 봅니다. Command 키로 여러 항목을 선택할 수 있습니다.
3. 목록 새로고침은 로컬 정의로 설치 상태만 읽습니다. 업데이트 확인은 확인창을 거쳐 `brew update` 후 `brew outdated --json=v2`를 실행합니다.
4. 선택 업데이트·제거는 대상과 명령을 확인한 뒤 순서대로 실행합니다. 실패·중단 후 남은 작업은 폐기하며 자동 재개하지 않습니다. 필요하면 목록을 다시 확인해 선택합니다. Formula 제거 전에는 설치된 역의존성을 다시 조회하고, 사용하는 항목이 있으면 제거를 차단합니다.
5. 인증·확인 입력은 하단 콘솔을 클릭해 처리합니다. 비밀번호를 별도 앱 입력창에 수집하지 않습니다. 중단 요청은 터미널의 Ctrl-C이며 원상 복구가 아닙니다. 실행 중에는 종료를 차단하므로 작업이 끝나거나 중단 처리가 완료된 뒤 종료합니다.
6. 실행 후 Homebrew를 다시 읽어 관찰된 버전 변경을 기록합니다. 추가 의존성 변화도 표시합니다. 외부 변경과 앱의 변경을 완전히 구별하거나 롤백하지는 않습니다.

`--zap`, 강제 제거, root로 Homebrew 실행, 신규 설치, 서비스 관리는 제공하지 않습니다. 자체 업데이트·`latest` Cask에는 확인 제한을 표시합니다. 설치 경로는 실제 파일이 확인된 경우만 제공합니다.

## 기록과 인증

기록은 `~/Library/Application Support/BrewDesk/history.json`에 명령 단위로 최근 200개를 저장합니다. 디렉터리는 0700, 기록 파일은 0600 권한으로 저장합니다. 콘솔에 보내는 입력은 기록하지 않습니다. PTY의 echo 비트가 꺼진 상태에서 전송한 입력을 비밀 입력으로 취급합니다. echo가 꺼진 동안 출력을 기록하지 않으며, 비밀 입력 이후에는 해당 작업의 나머지 출력도 기록하지 않습니다. 따라서 인증 작업의 저장 로그가 일부 생략될 수 있습니다. 화면의 터미널 출력과 사용자가 직접 저장한 로그에는 로컬 경로나 설치 프로그램의 출력이 포함될 수 있습니다.

## 구현과 검증 범위

- `Localization.swift`: 언어 설정, 번역 파일 로딩, 동적 문구와 날짜 표시
- `Domain.swift`: 패키지 모델, JSON 해석, 명령 허용 목록, 버전 차이 계산
- `BrewRepository.swift`: 읽기 프로세스, 환경 확인, Homebrew 조회, 기록 저장
- `PTYRunner.swift`: SwiftTerm PTY, 입력·출력 분리, 종료 상태 해석
- `AppModel.swift`: 화면 상태, 단일 실행기와 FIFO 배치 처리, 재조회
- `BrewDeskApp.swift`: 네이티브 테이블·상세·콘솔·설정·기록 UI

테스트 22개는 명령 인수 검증, JSON 호환성, 간접 버전 변화, 기록 권한, 대용량 stderr, PTY 종료 코드·중단·비밀 입력, 순차 실행과 실패 시 대기열 중단을 확인합니다. 짧은 프로세스의 종료 경합을 검사하는 테스트는 같은 명령을 12회 실행합니다. 실제 관리자 암호를 요구하는 Cask의 설치·제거와 서명·공증은 별도 실환경 검증이 필요합니다. 테스트는 실제 패키지를 업데이트하거나 제거하지 않습니다.

명령 의미와 JSON 형식은 [Homebrew 매뉴얼](https://docs.brew.sh/Manpage), [JSON 조회 문서](https://docs.brew.sh/Querying-Brew)를 기준으로 합니다. PTY 구현은 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)을 사용합니다.

## 스크린샷과 사용 영상

[60초 실제 조작 영상](docs/media/brewdesk-walkthrough.mp4)은 Computer Use로 앱을 조작하며 녹화했습니다. 패키지 상세 확인, 제거 확인 후 취소, 영어·한국어 전환을 보여줍니다. 실제 패키지는 변경하지 않았습니다.

![한국어 설정](docs/media/language-ko.png)

[추가 스크린샷과 촬영 정보](docs/media/README.md) · [서드파티 고지](THIRD_PARTY_NOTICES.md)
