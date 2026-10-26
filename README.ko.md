<p align="center">
  <img src="AppIcon/blinky-icon-1024.png" width="112" alt="Blinky">
</p>

<h1 align="center">Blinky</h1>

<p align="center">
  <b>Blinky</b>는 Harris의 macOS 포크이며, 업스트림은 <a href="https://github.com/qunqin24/Pulse">Pulse</a>입니다. iOS 앱과 같은 이름입니다. 이 저장소는 업스트림 Pulse가 아닙니다.
</p>

<p align="center">
  <b>사용량 페이지를 하나하나 열지 않아도 Claude Code, Codex, Cursor가 얼마나 남았는지 알 수 있습니다.</b><br>
  화면 가장자리에 두기만 하면 모든 AI 코딩 한도를 한눈에 보여 주는 무료 오픈 소스 macOS 앱.
</p>

<p align="center">
  <a href="https://github.com/harrisliangsu/blinky-mac/releases/latest"><img src="https://img.shields.io/badge/%EB%8B%A4%EC%9A%B4%EB%A1%9C%EB%93%9C-000000?style=for-the-badge&logo=apple&logoColor=white" alt="macOS용 Blinky 다운로드"></a>
</p>

<p align="center">
  <a href="https://github.com/harrisliangsu/blinky-mac/releases/latest"><img src="https://img.shields.io/github/v/release/harrisliangsu/blinky-mac?color=black" alt="최신 릴리스"></a>
  <img src="https://img.shields.io/badge/macOS-14.0%2B%20Sonoma-333333?logo=apple" alt="macOS 14+">
  <a href="https://github.com/harrisliangsu/blinky-mac/actions/workflows/ci.yml"><img src="https://github.com/harrisliangsu/blinky-mac/actions/workflows/ci.yml/badge.svg" alt="CI 빌드"></a>
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue" alt="라이선스"></a>
  <a href="https://github.com/harrisliangsu/blinky-mac/stargazers"><img src="https://img.shields.io/github/stars/harrisliangsu/blinky-mac?color=black" alt="GitHub 스타"></a>
  <a href="https://github.com/harrisliangsu/blinky-mac/releases"><img src="https://img.shields.io/github/downloads/harrisliangsu/blinky-mac/total?color=black" alt="다운로드 수"></a>
  <a href="https://github.com/harrisliangsu/blinky-mac/issues"><img src="https://img.shields.io/github/issues/harrisliangsu/blinky-mac?color=black" alt="열린 이슈"></a>
  <a href="https://github.com/harrisliangsu/blinky-mac/commits/main"><img src="https://img.shields.io/github/last-commit/harrisliangsu/blinky-mac?color=black" alt="마지막 커밋"></a>
</p>

<p align="center">
  <sub><b>macOS 14 Sonoma 이상</b> · Apple 실리콘과 Intel 모두 지원 · <a href="README.md"><b>English</b></a> · <a href="README.zh-CN.md"><b>简体中文</b></a> · <a href="README.zh-Hant.md"><b>繁體中文</b></a> · <a href="README.ja.md"><b>日本語</b></a> · <b>한국어</b> · <a href="README.ru.md"><b>Русский</b></a></sub>
</p>

<p align="center">
  <img src="Docs/images/demo.gif" height="400" alt="화면 가장자리에 붙은 Blinky 플로팅 레일">
  &nbsp;&nbsp;
  <img src="Docs/images/panel.webp" height="400" alt="링에 포인터를 올리면 모든 한도와 초기화 시각을 담은 카드가 열립니다">
</p>

- **76개 서비스를 한눈에**——Claude Code, Codex, Cursor, GitHub Copilot, Antigravity, Kiro, Grok, DeepSeek, Kimi Code 등, 서비스마다 링이 하나씩 있습니다.
- **Blinky 계정도, Blinky 서버도 없습니다**——이미 쓰고 있는 로그인을 그대로 사용하며, 아무것도 되돌려 보내지 않습니다.
- **실제 숫자만 보여 줍니다**——사용률은 모두 서비스가 직접 보고한 값입니다. 몇 안 되는 추정치는 추정이라고 표시하고, 서비스가 숫자를 주지 않으면 짐작하지 않고 그렇다고 알려 줍니다.
- **네이티브하고 조용합니다**——Swift와 SwiftUI로 만들었고, macOS 26에서는 Liquid Glass로 그려집니다. 화면 왼쪽·오른쪽·위쪽, 또는 아래쪽 Dock 옆에 붙일 수 있고, 쓰지 않을 때는 가는 선으로 접히며, 메뉴 막대에만 둘 수도 있습니다.

**최근 추가:** 메뉴 막대 사용량 표시와 계정별 대시보드, 한도 초기화 후 사용 창 자동 시작, 움직이는 봇 마크. [새 소식](https://github.com/harrisliangsu/blinky-mac/releases/latest).

<p align="center">
  <img src="Docs/images/bot-mark.gif" width="300" alt="Blinky 애니메이션 마크: 각 링의 봇이 해당 계정의 상태에 반응합니다">
</p>

<p align="center">
  <sub>Blinky 덕분에 갑작스러운 한도를 피했다면, ⭐ 하나가 다른 사람들이 Blinky를 찾는 데 도움이 됩니다.</sub>
</p>

---

## 설치 및 빠른 시작

1. [Releases](https://github.com/harrisliangsu/blinky-mac/releases/latest)에서 최신 **`Blinky-x.y.z.dmg`**를 내려받습니다.
2. 디스크 이미지를 열고 **Blinky**를 응용 프로그램 폴더로 끌어다 놓습니다. 파일 이름은 `Blinky.app`입니다. 이미 `Pulse.app`이 있으면, 그 복사본을 다음에 열 때 `Blinky.app`으로 이름이 바뀝니다. 같은 폴더에 `Blinky.app`이 이미 있으면 그 파일은 그대로 둡니다.
3. 처음 실행하면 모니터링할 서비스를 선택합니다. 처음에는 모두 선택되지 않으며, **완료**를 누른 뒤에만 선택한 서비스의 인증 정보를 읽고 사용량을 확인합니다. 선택 창을 닫으면 모니터링을 시작하지 않습니다. 설정에서 서비스를 켜도 됩니다. 업데이트 후에도 기존 선택은 유지되며, 새로 지원하는 서비스가 Mac에서 발견되면 한 번만 추가 여부를 묻습니다.
4. Blinky는 메뉴 막대에 있습니다. 메뉴 막대가 복잡하다면 플로팅 레일——또는 접힌 가느다란 선——을 오른쪽 클릭해 **설정…**을 고르세요. **설정 › 일반 › 단축키**에서 전역 단축키를 지정할 수도 있습니다.

> [!NOTE]
> **macOS 첫 실행(Gatekeeper)**:<br>
> Blinky는 Apple Developer 인증서가 없는 오픈 소스 프로젝트입니다. 첫 실행 시 macOS가 앱을 막을 수 있습니다:
> - **방법 1(GUI)**: Blinky를 실행하고 경고를 닫은 뒤, **시스템 설정 → 개인정보 보호 및 보안**을 열고 **그래도 열기**를 클릭합니다.
> - **방법 2(터미널)**:
>   ```bash
>   xattr -cr /Applications/Blinky.app
>   ```
>   *업데이트는 앱 안에서 Sparkle로 제공됩니다. 업데이트 후 macOS가 브라우저 키체인 접근을 다시 요청할 수 있습니다.*

---

## 주요 기능

### 한눈에 보는 링
- **사용량을 따라가는 색**——초록에서 호박색, 빨강으로. 계정마다 원하는 색을 정할 수도 있습니다.
- **사용량 또는 남은 양**——`75% 사용` 또는 `25% 남음`. 창이 얼마나 지났는지 보여 주는 시계 호도 더할 수 있습니다.
- **실시간 활동**——에이전트가 일하는 동안 링 위에서 점이 돕니다. 계정 상태에 따라 움직이는 작은 봇도 고를 수 있습니다.

### 링을 가리키면 자세히
- **모든 한도와 초기화 시각**을 카드 한 장에. 막대는 이어진 형태와 나뉜 형태 중에서 고릅니다.
- **자세한 카드**——요금제, 읽은 시각, 한도별 추정 가치, 이 Mac 기록으로 본 최근 사용량.
- **소진 속도 예측**——지금 속도면 창이 초기화되기 전에 다 쓸 때 알려 줍니다.
- **메뉴 막대**——가장 많이 쓴 링을 숫자, 작은 링, 나란한 한도로. 대시보드도 열 수 있습니다.

<p align="center">
  <img src="Docs/images/detailed-card.webp" width="620" alt="같은 Codex 계정의 간단한 카드와 자세한 카드">
</p>

### 방해하지 않는
- **어디에나**——왼쪽, 오른쪽, 위, Dock 옆, 원하는 곳 어디든. 쓰지 않을 때는 가는 선으로 접힙니다.
- **고르는 알림**——한도가 선을 넘을 때, 다 썼을 때, 초기화, 연달아 실패한 검사, 잔액 부족, 제공업체 장애.
- **여섯 가지 언어**——영어, 중국어 간체, 중국어 번체, 일본어, 한국어, 러시아어.
- **선택 기능**——전역 단축키, 활성 디스플레이 따라가기, 스크린샷에서 숨기기.

### 사용량, 상태와 그 밖의 것
- **토큰 사용량**——54개 로컬 클라이언트가 쓴 양을 공개 API 가격으로 추정해 일, 모델, 에이전트별로, 원하는 기간으로. Claude Code, Codex, Grok, Kimi에서 답변 시간을 잴 수 있으면, 그 기간의 평균 출력 속도와 모델별 토큰/초도 보여 줍니다.
- **원하는 통화로 보는 추정 금액**——미국 달러, 중국 위안, 홍콩 달러, 신대만 달러, 일본 엔, 대한민국 원, 러시아 루블.
- **사용량 리포트**——같은 기록으로 만드는 하루, 한 주, 한 달, 한 해의 공유용 카드.
- **서비스 상태**——44개 제공업체의 공식 상태 페이지, 장애가 나면 알림도.
- **연결 진단**——각 숫자의 출처와 서버가 보낸 응답 그대로.
- **깊이 쓰는 분께**——제공업체별 여러 계정, 직접 만든 데이터 원본을 더하는 확장, 스크립트용 `--json`.

<p align="center">
  <img src="Docs/images/spend.webp" height="290" alt="토큰 사용량: 합계, 종류별 토큰, 일별 패턴">
  &nbsp;&nbsp;
  <img src="Docs/images/spend-history.webp" height="290" alt="토큰 사용량: 일별, 월별, 에이전트별">
</p>

**모든 기능 자세히 보기**(영어): [Docs/features.md](Docs/features.md).

**이 빌드에 더 있는 것:** 링 색 구성(빨간색 경고, 그라데이션, 차분함), Codex 재설정 예측과 최근 재설정, 주간 또는 월간 한도가 돌아왔을 때의 리본, Kimi Code 기기 코드 로그인과 여러 계정, 개인 토큰으로 쓰는 Qoder.

---

## 지원 제공업체와 데이터 경로

76개 서비스를 지원하며, 각각 그 제품이 동작하는 방식대로 읽습니다——제품의 사용량 엔드포인트, 편집기 로그인, 로컬 Language Server, 또는 붙여 넣은 키. 모든 비율은 서비스가 직접 알려 준 값입니다. [전체 목록과 각 서비스를 읽는 방법](Docs/supported-services.md)(영어).

---

## 개인정보와 보안

- **Blinky 계정도 서버도 없음**——여러분의 Mac이 여러분 자신의 로그인으로 사용 중인 서비스에 연결합니다.
- **연결은 다섯 가지뿐, 모두 여기에**——그 서비스들, 그 공개 상태 페이지, 모델 가격을 가져오는 [models.dev](https://models.dev), 미국 달러가 아닌 통화를 골랐을 때만 쓰는 [ExchangeRate-API](https://www.exchangerate-api.com), 업데이트를 확인하는 GitHub/Sparkle.
- **키는 암호화되어 이 Mac에만 저장되고**, Blinky가 읽는 로컬 사용 기록도 Mac 밖으로 나가지 않습니다.

[자세히](Docs/features.md#privacy-and-security)(영어).

---

## 소스에서 빌드

Blinky는 네이티브 Swift와 SwiftUI로 빌드됩니다. 현재 소스를 빌드하려면 전체 **Xcode**(Command Line Tools가 아님)와 **macOS 26 SDK**가 필요하며, 앱은 **macOS 14+**에서 실행됩니다.

```bash
# 저장소 복제
git clone https://github.com/harrisliangsu/blinky-mac.git
cd blinky-mac

# 앱 번들 빌드
./Scripts/bundle.sh

# 실행
open build.noindex/Blinky.app
```

`swift run Pulse`는 번들 없이 빠르게 빌드하고 실행하는 방법이지만, 알림과 앱 내 업데이트는 번들 앱에서만 동작합니다. 툴체인 설정은 [Docs/build-from-source.md](Docs/build-from-source.md)를 참고하세요. 릴리스 배포: [Docs/releasing.md](Docs/releasing.md).

---

## 기여

저장소 문서가 어떻게 조직되는지, 무엇이 퇴행하면 안 되는지, 올바른 페이지를 어떻게 갱신하는지: [CONTRIBUTING.md](CONTRIBUTING.md). 주제별 문서 지도: [Docs/README.md](Docs/README.md).

---

## 디자인 출처

화면은 [Pulse](https://github.com/qunqin24/Pulse)를 바탕으로 합니다. Pulse는 2026년 8월 [**Vinz**(@hivinz_)](https://x.com/hivinz_/status/2092996055248126353)가 X에 공유한 UI 콘셉트에서 출발한 독립 구현입니다. Blinky의 Mac 버전은 그 포크입니다. Vinz는 Pulse 및 Blinky와 제휴하지 않으며 책임지지 않습니다.

---

## 업스트림 작성자 후원

<p align="center">
  <sub>Blinky의 Mac 버전은 Pulse의 포크입니다. 아래 링크는 업스트림 작성자의 것입니다.</sub>
</p>

<p align="center">
  <a href="https://afdian.com/a/qunqin"><img src="https://img.shields.io/badge/Afdian-%EC%BB%A4%ED%94%BC_%ED%95%9C_%EC%9E%94-946CE6?style=for-the-badge" alt="Afdian에서 업스트림 작성자 후원"></a>
</p>

---

## 라이선스

[Apache 2.0](LICENSE)에 따라 라이선스됩니다. 함께 포함된 서드파티 자산은 각자의 라이선스를 유지합니다. 자세한 내용은 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)를 참고하세요.

---

## Star 추이

<a href="https://star-history.com/#harrisliangsu/blinky-mac&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=harrisliangsu/blinky-mac&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=harrisliangsu/blinky-mac&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=harrisliangsu/blinky-mac&type=Date" />
  </picture>
</a>
