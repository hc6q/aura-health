<p><img src="assets/app-icon.png" width="128" height="128" alt="Aura app icon"></p>

<h1>Aura Health</h1>

<p>Your vitals, labs, medications, habits, and health notes in one private dashboard.<br>
Built for people who want to understand their own data, not just collect it.</p>

<p><strong>Version 1.0.0</strong> · iOS 17+ · macOS 14+</p>

<p>
  <img src="https://img.shields.io/badge/Swift-f05138" alt="Swift">
  <img src="https://img.shields.io/badge/SwiftUI-0066cc" alt="SwiftUI">
  <img src="https://img.shields.io/badge/HealthKit-fc3158" alt="HealthKit">
</p>

<p><a href="#build-from-source">Build Aura from source</a></p>

![Aura app screenshots across iOS and macOS](assets/screenshots.png)

I started Aura after the spreadsheet where I tracked biomarkers, habits, and health notes became harder to understand than the data inside it. The first version was a web app. Moving it to Swift made Apple Health integration and a shared iPhone/Mac experience possible.

Aura is currently distributed as source rather than through the App Store. Your health data stays in the app's local SwiftData store, with optional CloudKit sync between your own devices.

## What Aura keeps together

The main dashboard brings heart rate, HRV, blood pressure, sleep, steps, weight, SpO2, skin temperature, calories, and other measurements into one timeline. Each metric includes a trend, reference range, and a short explanation. Time filters run from the current day through the full history.

![Aura vitals dashboard](https://github.com/user-attachments/assets/461e9c5c-3aeb-475f-992c-851c2ba307ef)

Habits, medications, supplements, conditions, diet notes, and lab sessions live beside the measurements they may affect. Biomarkers are grouped by body system, and previous lab sessions remain available as dated snapshots. Correlation views help compare pairs such as sleep and recovery or HRV and strain.

The built-in health assistant can read and update vitals, biomarkers, medications, and habits. Attach a lab report as a PDF or photo and it can extract values for review before saving them. It uses your selected provider and your own API credential.

![Aura health assistant chat](https://github.com/user-attachments/assets/97c3587f-c2d9-4356-8d3c-1284d5e3e762)

https://github.com/user-attachments/assets/d81e0380-41ab-45e5-b22e-92e15c38edad

## Data and privacy

There is no Aura account, server, analytics service, or telemetry. Health data and documents are stored on your device; using optional AI features sends the relevant content described below. CloudKit can sync the local database between your Apple devices.

When you use the health assistant, Aura sends the message and relevant health context directly to the selected Groq, Cloudflare Workers AI, or Mistral endpoint with its credential stored in Keychain. Local data is not sent anywhere when the assistant is not in use.

Aura can read Apple Health data on iOS, accept manual entries on both platforms, import lab values from chat attachments, and export or restore a JSON backup.

## Build from source

Clone the repository, open `AuraHealth.xcodeproj`, and build the iOS or macOS target in Xcode.

```bash
git clone https://github.com/hc6q/aura-health.git
cd aura-health
open AuraHealth.xcodeproj
```

On first launch, grant Apple Health access on iOS. Configure an AI provider under **Settings → AI** only if you want to use the assistant.

Optional WHOOP OAuth credentials belong in an untracked `Secrets.local.xcconfig` file:

```xcconfig
WHOOP_CLIENT_ID = your-client-id
WHOOP_CLIENT_SECRET = your-client-secret
```

## Known limitations

HealthKit is not available on macOS. Mac users can import data through the app or route exported health data through iCloud Drive.

Lab extraction depends on image and document quality. Review the results in the lab import sheet before saving. Chat imports save values when explicitly requested and report the result; check imported values afterward. Local parsing can be incomplete even when it finds some values.

## Tech stack

- Swift, SwiftUI, and one shared iOS/macOS project
- SwiftData and CloudKit for storage and sync
- HealthKit on iOS
- OpenAI-compatible Chat Completions for the optional assistant
- Keychain storage for the API key

## Feedback

Found a bug or have a feature idea? [Open an issue](https://github.com/madebysan/aura-health/issues).

## License

[MIT](LICENSE)

Made by [santiagoalonso.com](https://santiagoalonso.com)

## AI configuration

Open **Settings → AI** (also available from onboarding and chat setup):

| Provider | Credential | Model |
| --- | --- | --- |
| Groq (default) | Create an API key in [Groq Console](https://console.groq.com/keys) | `openai/gpt-oss-120b`; select `openai/gpt-oss-20b` as a manual alternative |
| Cloudflare Workers AI | Create a Workers AI token in the [Cloudflare dashboard](https://dash.cloudflare.com/), plus your 32-character Account ID | `@cf/openai/gpt-oss-120b` |
| Mistral | Activate free mode and create an API key in [Mistral Studio](https://console.mistral.ai/) | `mistral-small-latest` |

Free tiers have quotas and model availability can vary by account. Aura does not promise unlimited free requests. Provider/model errors are shown to the user; there is no automatic model or provider fallback. No credentials are bundled. Secrets use separate Keychain entries, never UserDefaults. Existing credentials for the previous integration are left unused and never copied to a new provider. Remove deletes the selected provider's secret. The Cloudflare Account ID and model selection are ordinary preferences.

### Privacy controls

AI chat, AI-assisted lab extraction and **Generate AI habits** can send messages and relevant health context directly to the selected provider. Aura has no AI backend. The remaining records stay in local SwiftData, with optional CloudKit sync. Opening Habits, configuring AI or importing a locally recognized report does not make an AI request.

- Groq: enable **Zero Data Retention** in your account's Data Controls if desired. Aura cannot enable it for you. [Groq data policy](https://console.groq.com/docs/your-data).
- Cloudflare: review the [Workers AI data usage policy](https://developers.cloudflare.com/workers-ai/platform/data-usage/). Choosing a provider does not itself guarantee medical compliance or zero retention.
- Mistral free mode may use inputs/outputs for improvement or training. Review and disable training in your account's Privacy settings if desired. Training opt-out and retention are separate controls. [Mistral opt-out instructions](https://help.mistral.ai/en/articles/455207-can-i-opt-out-of-my-input-or-output-data-being-used-for-training).

The transport uses ephemeral URLSession storage, HTTPS and refuses redirects. It does not log prompts, files, tool results, credentials or model responses, and never displays raw provider error bodies.

### Architecture and attachments

`AIProvider` and `AIConfiguration` centralize endpoints, credentials, models and enabled capabilities. Codable request/response types and `AITransport` implement Chat Completions. `AIToolConversation` supports parallel tool requests (executed serially on the device), JSON argument decoding, matching tool IDs and at most four rounds. A request keeps the original provider configuration throughout its tool loop. All 21 tools still execute locally through `AIService`; the provider has no direct access to SwiftData, HealthKit, Keychain or files. Chat rules and `aura://` navigation links are preserved.

PDFKit extracts text on iOS and macOS. Vision OCR handles photos and scanned PDF pages locally. Local biomarker parsing is tried first; only unresolved reports use AI text extraction. Chat attachments use extracted text. Raw images and PDFs are never uploaded; this integration deliberately enables text/tools only for its initial model catalog. Unreadable documents show an actionable error. Limits: 20 MB, 30 PDF pages and 60,000 extracted characters; oversized content is rejected, not silently truncated. OCR and local parsing may miss values: verify dates, units and results.

Provider documentation checked for the model catalog:
- [Groq models and tool support](https://console.groq.com/docs/tool-use/overview)
- [Cloudflare OpenAI compatibility](https://developers.cloudflare.com/workers-ai/configuration/open-ai-compatibility/) and [GPT OSS 120B](https://developers.cloudflare.com/workers-ai/models/gpt-oss-120b/)
- [Mistral Small](https://docs.mistral.ai/models/mistral-small-4-0-26-03) and [free-mode setup and stable model alias](https://docs.mistral.ai/getting-started/quickstarts/studio/activate-and-generate-api-key)

### Validation

`swift test` on macOS 14+ exercises production Codable types, all tool schemas, multi-tool round trips, invalid arguments, round limits, status/timeout errors and local text/PDF/image/scanned-PDF import using synthetic fixtures and a mocked URLSession. No real API keys or health records are required. The AI validation workflow also builds the app for iOS Simulator and macOS without code signing. Live provider requests and device UI/OCR quality still require manual testing with your own account.
