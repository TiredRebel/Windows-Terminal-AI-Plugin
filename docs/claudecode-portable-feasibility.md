# Feasibility study: ClaudeCode-Portable approach for TerminalAI

Date: 2026-09-12  
Local project: `E:\Windows Terminal Ai plugin`  
Local revision: `3f19250a033a205d5353293497051875eabd12d1`  
Upstream reviewed: `techjarves/ClaudeCode-Portable` at `eb7265eb5d45c6fc115190e422f784381b363d9c`

## Executive conclusion

**VERIFIED: the approach is technically feasible, but ClaudeCode-Portable is not a drop-in LLM provider for TerminalAI.** It is a portable distribution and orchestration layer around the official Claude Code executable and Agent SDK. Its most useful ideas for TerminalAI are app-local runtime installation, per-provider environment isolation, a separate agent process, explicit tool approval, and staged update/rollback.

The recommended design is **not** to replace TerminalAI's current Ollama HTTP path. Keep it for fast command generation and add an optional, clearly separated `ai-agent` mode that launches Claude Code against Ollama's Anthropic-compatible API. Ollama itself now documents and ships this integration, so TerminalAI does not need ClaudeCode-Portable's OpenAI-to-Anthropic adapters for its existing local backend.

This separation preserves the current lightweight use cases while making the heavier agentic behavior explicit. It also prevents Claude Code's runtime, session, tool-permission, context-window, and licensing concerns from leaking into every `ai`, `ai-fix`, or F2 invocation.

## Scope and evidence quality

This was a read-only study. No application code was changed. Only this report was added.

Primary evidence used:

- the upstream repository source, history, tests, and MIT license;
- official Anthropic Claude Code documentation;
- official Ollama documentation and the locally installed Ollama/Claude executables;
- the local TerminalAI source.

The local `.codegraph/codegraph.db` reports a complete index, but it contains only five C# files and two XML files under the AOT surface. It contains no PowerShell nodes. Because AOT is excluded from the current project phase, CodeGraph cannot substantiate the main PowerShell call graph. The PowerShell flow below was therefore traced directly from source. This is a **verified tooling limitation**, not an inferred absence of calls.

## What ClaudeCode-Portable actually does

### 1. Runtime packaging

**VERIFIED.** `START.bat` invokes a PowerShell bootstrapper. The bootstrapper downloads a platform-specific Node.js 24.21.0 archive into `engine/node-win32-<arch>`, verifies its SHA-256 against Node.js's published checksum list, prepends the local Node directory to the child process `PATH`, and runs the JavaScript launcher. See [START.bat](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/START.bat#L1-L4) and [tools/bootstrap.ps1](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/tools/bootstrap.ps1#L1-L120).

The runtime manifest pins top-level versions of Claude Code, the Claude Agent SDK, `claude-adapter`, and dashboard packages. At the reviewed revision these are Claude Code 2.1.247 and Agent SDK 0.3.247. See [tools/runtime-manifest.json](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/tools/runtime-manifest.json#L1-L11).

**Boundary:** the repository has no committed npm lockfile. Top-level versions are exact, but transitive dependency resolution is delegated to npm at installation time. Node's archive is explicitly hash-checked; the npm install relies on registry/package-manager integrity rather than hashes committed by this project. Therefore “pinned” does not mean a fully reproducible or offline-verifiable dependency graph.

### 2. Claude Code invocation

There are two distinct invocation paths:

1. **Terminal mode:** the launcher starts the platform-native Claude executable as a child process, passes `--model`, inherits terminal standard I/O, and uses the caller's current working directory. Resume adds Claude Code's `--resume` argument. See [tools/launcher.mjs](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/tools/launcher.mjs#L53-L79).
2. **Dashboard mode:** `AgentManager` loads the official Agent SDK, calls `sdk.query()`, supplies the selected workspace as `cwd`, points the SDK at the bundled Claude executable, streams SDK events, persists the real Claude session ID, and resumes it on later turns. Tool calls go through `canUseTool`, where approval can be requested, denied, cancelled, or timed out. See [lib/agent.mjs](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/lib/agent.mjs#L23-L159).

Anthropic officially documents non-interactive `claude -p`, structured output, turn limits, model selection, continuation/resume, and permission controls. See the [Claude Code CLI reference](https://docs.anthropic.com/en/docs/claude-code/cli-usage). The official SDK documentation also describes Claude Code as a subprocess integration and exposes `cwd`, `abortController`, and a path to the Claude executable. See [Claude Code SDK](https://docs.anthropic.com/en/docs/claude-code/sdk).

### 3. Providers and protocol adapters

**VERIFIED.** ClaudeCode-Portable defines nine profiles: Anthropic, OpenRouter, DeepSeek, NVIDIA NIM, Gemini, OpenAI, Ollama, LM Studio, and a custom endpoint. Anthropic-compatible endpoints are passed directly to Claude Code. OpenAI-compatible endpoints are wrapped by one of three local adapters. See [lib/providers.mjs](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/lib/providers.mjs#L6-L48).

The built-in adapter listens on an ephemeral `127.0.0.1` port, requires a random per-run token, translates Anthropic Messages requests and SSE responses to/from OpenAI Chat Completions, validates tool-call JSON, propagates cancellation, and caps request size. See [lib/adapter.mjs](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/lib/adapter.mjs#L22-L65) and [lib/adapter.mjs](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/lib/adapter.mjs#L79-L163). A separate adapter translates to the OpenAI Responses API; an optional pinned `claude-adapter` package is wrapped without using its global configuration. See [lib/responses-adapter.mjs](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/lib/responses-adapter.mjs#L16-L34) and [lib/external-adapter.mjs](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/lib/external-adapter.mjs#L8-L15).

**Important compatibility boundary:** ClaudeCode-Portable itself labels non-Claude model support experimental and provider-dependent. Translation can make protocols compatible; it cannot make a weak model reliable at tool use, long-context reasoning, or session continuation. See its [README](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/README.md#L120-L144).

### 4. Authentication, configuration, and isolation

**VERIFIED.** Profiles are stored under the project-owned `data/settings.json`. API keys are written there as plaintext, although public dashboard configuration strips the key and log/event redaction replaces configured secrets and common token patterns. Configuration writes use a temporary file followed by rename. See [lib/config.mjs](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/lib/config.mjs#L7-L12), [lib/config.mjs](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/lib/config.mjs#L49-L105), and the upstream [security notes](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/README.md#L194-L205).

Before launch, ambient Anthropic, Claude, OpenAI, Gemini, OpenRouter, DeepSeek, NVIDIA, AWS, and Azure variables are removed from the child environment. A provider/auth-specific `CLAUDE_CONFIG_DIR` and app-local cache are set; auto-update, telemetry, error reporting, and nonessential traffic are disabled. Provider URL, token, and model aliases are then added only to the child environment. See [lib/providers.mjs](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/lib/providers.mjs#L28-L48).

This is **configuration isolation, not a sandbox**. The child still inherits the remaining environment and operating-system facilities, and Claude Code tools can read files, run commands, and modify the selected workspace subject to its permission flow. Anthropic recommends project-specific permissions and stronger isolation such as devcontainers for sensitive code. See [Claude Code security](https://docs.anthropic.com/en/docs/claude-code/security).

Anthropic account login is terminal-only in ClaudeCode-Portable. The dashboard requires an API credential or local provider. Subscription credentials are rejected for non-Anthropic endpoints. See `lib/providers.mjs:35-38` and `lib/agent.mjs:29-35` at the links above.

### 5. Sessions and portability

**VERIFIED.** App-owned data lives under `data/`; runtime files live under `engine/<os>-<arch>/current`; both are ignored by Git. Claude configuration is redirected into `data/claude/<provider>-<auth>`, and native Claude JSONL sessions are imported into the dashboard's session store. See [lib/paths.mjs](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/lib/paths.mjs#L1-L9), [lib/sessions.mjs](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/lib/sessions.mjs#L8-L35), and [lib/native-sessions.mjs](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/lib/native-sessions.mjs#L28-L36).

Portability is limited by platform binaries, filesystem behavior, host prerequisites, provider connectivity, and OS integrations. The project installs one runtime per OS/architecture and explicitly states that account login and subprocess tools may leave host traces. It is not a zero-footprint sandbox. See [README portability and requirements](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/README.md#L178-L217).

### 6. Updates and rollback

**VERIFIED.** Installation happens in a staging directory under a lock, verifies that every top-level dependency exists, runs `claude --version` as an identity check, preserves the current runtime as `previous`, and swaps staging into place. Failure leaves the working runtime intact. Rollback swaps `current` and `previous`. See [lib/runtime.mjs](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/lib/runtime.mjs#L73-L135).

The “update” command reinstalls the versions in the checked-out manifest; it does not itself fetch a newer repository revision. A newer Claude Code version requires first updating the source/manifest. This distinction matters for support and security patching.

### 7. Licensing

ClaudeCode-Portable's own source is MIT licensed and can be reused if its copyright and license notice are retained. See [LICENSE](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/LICENSE#L1-L20).

That MIT license does **not** relicense Claude Code, the Agent SDK, or other dependencies. The upstream README says those retain their own licenses and terms. Anthropic states that Claude Code is provided under its commercial terms. See [upstream license note](https://github.com/techjarves/ClaudeCode-Portable/blob/eb7265eb5d45c6fc115190e422f784381b363d9c/README.md#L240-L244) and [Anthropic legal and compliance](https://docs.anthropic.com/en/docs/claude-code/legal-and-compliance).

**UNRESOLVED:** this study found no primary-source grant that clearly authorizes TerminalAI to redistribute Claude Code binaries as part of its own package. ClaudeCode-Portable downloads them at first launch rather than committing them. For a multi-user release, the safe pattern is installer-time download from the official source plus acceptance of applicable terms; redistribution requires explicit legal confirmation.

## Current TerminalAI architecture

### Verified facts

- TerminalAI is a PowerShell module targeting Windows PowerShell 5.1 and PowerShell 7+, with a nested AOT DLL and exported functions/aliases (`E:\Windows Terminal Ai plugin\TerminalAI.psd1:5-22`, `:24-80`). AOT remains outside this phase.
- The documented and implemented LLM backend is only local Ollama (`README.md:8-10`, `TerminalAI.psd1:13`, `TerminalAiConfig.ps1:11-23`). The config contains `OllamaUrl`, `Model`, temperature, timeout, UI settings, and no provider/auth/key abstraction.
- The shared `Invoke-OllamaApi` sends one `/api/generate` request with a prompt and optional system prompt, fixed `num_ctx = 2048`, no message list, and returns `response.response` (`TerminalAI.psm1:865-914`).
- `ai`, question answering, explanation, `ai-fix`, script generation, and the interactive assistant route through `Invoke-OllamaApi` (`TerminalAI.psm1:987`, `:1364`, `:1508`, `:1585`, `:1701`; `TerminalAiAssistant.ps1:371`).
- The PSReadLine hotkey is a second, duplicated direct Ollama path. It constructs and posts its own `/api/generate` request instead of calling `Invoke-OllamaApi` (`TerminalAI.psm1:1840-1862`). A backend change that touches only `Invoke-OllamaApi` would leave F2/Ctrl+G on Ollama and create inconsistent behavior.
- Despite the README/help wording about chat history, the interactive assistant does not build or send a conversation message history. It reads one line, constructs a system prompt, sends the current input only, and stores only the last detected code block for copy/save (`TerminalAiAssistant.ps1:261-379`).
- The current automated live-generation check accepts any non-empty response; it does not verify command correctness, safety, tool behavior, or hallucinations (`Test-TerminalAi.ps1:61-67`).
- The README claim that `temperature: 0.0` “excludes cmdlet hallucinations” is not supported by an evaluator or semantic test (`README.md:382-386`). Temperature zero reduces sampling variability; it is not a correctness proof.
- Installation copies the module into a user module directory, edits `$PROFILE`, and adds Windows Terminal actions/fragments (`Install-TerminalAi.ps1:250-275`, `:293-379`). This is an installed PowerShell extension, not currently an app-local portable runtime.

### Local environment snapshot

Read-only checks on 2026-09-12 found:

- Claude Code `2.1.267` at `C:\Users\mcgun\.local\bin\claude.exe`;
- Node.js `24.21.0`;
- Ollama client `0.34.0`, running server/API `0.30.11`;
- `ollama launch claude --help` lists Claude Code as a supported integration;
- installed models report these capabilities through `/api/show`:
  - `qwen2.5-coder:7b`: completion, tools; advertised context 32,768;
  - `granite4.2:8b`: tools, thinking, completion; advertised context 131,072;
  - `qwen3.5:9b`: completion, vision, tools, thinking; advertised context 262,144;
  - `gemma4:latest`: completion, vision, audio, tools, thinking; advertised context 131,072.

The installed client/server version mismatch should be removed before reproducibility testing. It did not prevent read-only API discovery, but it is an avoidable variable.

Official Ollama documentation confirms that Ollama exposes an Anthropic-compatible Messages API for Claude Code, documents `ollama launch claude`, and recommends at least a 64k context window. See [Claude Code integration](https://docs.ollama.com/integrations/claude-code) and [Anthropic compatibility](https://github.com/ollama/ollama/blob/main/docs/api/anthropic-compatibility.mdx).

### Existing unrelated baseline defect

A read-only PowerShell parser check found zero syntax errors in the main module, assistant, config, installer, and test script, but one syntax error in `Uninstall-TerminalAi.ps1:46` (`$wtSettingsFile:` requires delimiting the variable). This predates the report and was not changed. It should be corrected and covered before claiming a stable distributable baseline.

## Compatibility assessment

| Concern | ClaudeCode-Portable | Current TerminalAI | Compatibility conclusion |
|---|---|---|---|
| LLM protocol | Anthropic Messages; adapters for OpenAI protocols | Ollama `/api/generate` | Not interchangeable, but the same Ollama server can expose both APIs |
| Interaction model | Stateful agent with tools, approvals, resume | Mostly stateless prompt-to-text/command | Agent mode must be a separate product path |
| Runtime | Bundled Node + Claude Code + Agent SDK | PowerShell module + Ollama service | Feasible as optional sidecar; too heavy for every command |
| Provider support | Nine profiles, some experimental | Ollama only | Multi-provider support is possible but is a separate scope |
| Configuration | App-local profiles and credentials | User-home config, no secrets | Do not merge schemas blindly; agent config needs its own section/location |
| Privacy | Local or cloud depending on provider; plaintext portable keys | Documented local-only Ollama | Cloud profiles invalidate TerminalAI's current “100% local” promise |
| Permissions | Tool approval and unrestricted-mode guard | Generated commands are shown through TerminalAI UI; no Claude tool loop | Claude permissions must remain enabled and visible |
| History | Native Claude sessions and SDK resume | Current assistant sends no history | Claude sessions can add real history without retrofitting `/api/generate` |
| Portability | App-owned runtime/data, not zero-footprint | Installed into profile/module/Terminal directories | Portable distribution is a separate packaging decision |
| Windows support | Native binary plus host facilities | Windows-native PowerShell | Feasible; official Claude setup still has host prerequisites such as Git for Windows |

## Concrete options

### Option A — optional Claude Code + Ollama agent mode (**recommended**)

Add a distinct command such as `ai-agent` that launches Claude Code with a tool-capable Ollama model and a dedicated agent configuration. Keep `ai`, `ai-fix`, `ai-script`, and hotkeys on the existing fast `/api/generate` path.

Use process-scoped environment values equivalent to Ollama's official documented setup:

- `ANTHROPIC_AUTH_TOKEN=ollama`;
- `ANTHROPIC_API_KEY=`;
- `ANTHROPIC_BASE_URL=http://127.0.0.1:11434`;
- a dedicated `CLAUDE_CONFIG_DIR` under TerminalAI-owned data;
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` if the local-only privacy claim is retained.

Launch the executable with an argument array, an explicit working directory, the selected agent model, and default permission mode. Do not invoke through a constructed shell string. Do not use `--dangerously-skip-permissions`.

Pros:

- smallest useful integration;
- uses Ollama's officially documented Claude Code compatibility;
- gains real sessions, tools, project context, and approvals;
- no custom protocol adapter;
- does not regress fast one-shot commands.

Cons/prerequisites:

- requires Claude Code plus its applicable terms and Windows prerequisites;
- requires a tool-capable model and practical context of at least 64k;
- local model quality and memory use must be measured;
- separate UX/documentation is necessary because this mode may read, edit, and execute in a workspace.

### Option B — portable Agent SDK sidecar

Adapt ClaudeCode-Portable's runtime installer and `AgentManager` pattern: download Node and Claude Code into an app-owned runtime, use the SDK for structured streaming/events, and retain a staging/previous rollback pair.

Pros:

- strongest programmatic control over approvals, cancellation, sessions, timeouts, and UI events;
- supports a future richer Windows Terminal interface;
- can isolate app-owned configuration and runtime files.

Cons/prerequisites:

- materially larger implementation and test surface;
- approximately hundreds of megabytes of runtime download;
- update, integrity, cleanup, and support obligations;
- legal review of distribution/installation terms;
- requires a real session store and concurrency policy;
- should not be attempted inside the first ten-cycle stabilization effort unless agent mode is explicitly made its sole objective.

### Option C — transplant the multi-provider adapters

Reuse/adapt ClaudeCode-Portable's Chat Completions or Responses adapter to run Claude Code against OpenAI-compatible providers.

Pros:

- broad provider/model choice;
- reuses tested protocol translation concepts.

Cons:

- unnecessary for Ollama, which already supports Anthropic Messages;
- non-Claude feature behavior remains provider/model dependent;
- adds credentials, cloud privacy, billing, protocol drift, and error-mapping complexity;
- copying MIT source requires preserved notices; dependencies retain separate terms.

**Recommendation:** defer. Add only after the Ollama agent mode has stable acceptance tests and there is a validated user requirement for cloud providers.

### Option D — replace all TerminalAI calls with Claude Code

This would send every simple command request through the full agent runtime.

**Recommendation: reject.** It increases startup/context/tool complexity, changes safety semantics, and makes the existing fast path dependent on a much larger runtime without evidence that users need agent behavior for one-line command generation.

## Recommended phased design

### Phase 0 — stabilize the current baseline

1. Fix the existing uninstaller parse error.
2. Replace the non-empty-only live assertion with semantic and safety cases.
3. Remove or qualify the unsupported documentation claim that temperature zero eliminates hallucinations.
4. Align the installed Ollama client and server versions.
5. Re-index the PowerShell sources with a CodeGraph version/parser that supports them, or explicitly document that source tracing is the evidence mechanism.

### Phase 1 — no-code feasibility spike

Run Claude Code manually through Ollama against a disposable fixture repository, not the TerminalAI working tree. Use a tool-capable installed model with at least 64k configured context. Verify:

- startup without Anthropic cloud authentication;
- response quality for PowerShell tasks;
- correct tool-call JSON and multi-turn resume;
- default permission prompts;
- denial, cancellation, timeout, and process exit behavior;
- no nonessential external traffic when local-only mode is selected;
- acceptable RAM/VRAM and latency.

This phase must use a fixed evaluator and hallucination checks from the prior Autoresearch prompt. A model advertising a `tools` capability is only a prerequisite, not proof of reliable agent behavior.

### Phase 2 — minimum product integration

If the spike passes, add only an optional agent launcher and its checks:

1. `AgentModel`, `AgentBackend`, `ClaudeExecutable`, and `AgentDataDirectory` in a separate agent configuration section; do not overload the existing one-shot `Model` field.
2. Preflight checks for Claude Code, Ollama version, model existence/capabilities, configured context, and working-directory trust.
3. Process-scoped environment isolation and explicit `cwd`.
4. Default Claude permission flow with no bypass flag.
5. A single process runner with cancellation, exit-code propagation, and stderr redaction.
6. Regression tests proving the existing `/api/generate` commands and hotkey behavior are unchanged.

### Phase 3 — portable runtime only if required

If users demonstrably need a zero-install/USB experience, adapt the upstream bootstrap concepts instead of copying its dashboard:

- exact runtime manifest;
- official-source download;
- Node checksum verification;
- npm integrity/lock strategy;
- staging install, identity check, atomic swap, previous-version rollback;
- per-platform runtime directories;
- explicit cleanup and disk-space reporting.

Do not claim zero footprint. Keep provider credentials out of plaintext JSON if cloud providers are added; use Windows Credential Manager, SecretManagement, or an external secret helper.

## Acceptance gates for the previous Autoresearch workflow

The prior prompt should treat this integration as a hypothesis, not a predetermined implementation. Before any code is accepted, require:

1. **Protocol gate:** a recorded `/v1/messages` or `ollama launch claude` spike succeeds on the supported Ollama version.
2. **Model gate:** the chosen model passes fixed PowerShell tool-use and hallucination cases at the configured context.
3. **Permission gate:** file writes and commands require visible approval; bypass mode is rejected.
4. **Isolation gate:** selected workspace and app-owned Claude config are verified; ambient provider credentials do not affect routing.
5. **Privacy gate:** local mode makes no provider request outside loopback, apart from explicitly documented update/setup checks.
6. **Regression gate:** current `ai`, `ai-fix`, `ai-script`, assistant, and PSReadLine hotkey paths still work.
7. **Lifecycle gate:** cancellation terminates the child; failures return a nonzero state and an actionable, redacted message.
8. **Licensing gate:** installer/download behavior and user terms are approved before multi-user distribution.

Cross-agent hallucination review must independently verify claimed files, commands, provider features, model capabilities, test output, and network behavior. Agreement between agents is not evidence; each accepted claim needs source or reproducible command output.

## Risks and unresolved questions

| Risk/question | Status | Required action |
|---|---|---|
| Local models advertise tools but may fail complex Claude Code loops | VERIFIED risk | fixed task suite and repeated runs |
| Current `num_ctx=2048` is suitable for Claude Code | REJECTED | use separate agent context; official Ollama recommendation is at least 64k |
| Existing default `qwen2.5-coder:7b` is a production-ready agent model | UNVERIFIED | benchmark; do not infer from tool capability alone |
| `qwen3.5:9b` is good enough for multi-user production | UNVERIFIED | quality, latency, memory, and concurrency tests |
| ClaudeCode-Portable is a zero-footprint sandbox | REJECTED | describe it as app-local portability with host dependencies |
| MIT license covers Claude Code binaries | REJECTED | separate Anthropic terms apply |
| Bundling Claude Code in TerminalAI is permitted | UNRESOLVED | legal/terms review; prefer official download at setup time |
| Direct cloud providers preserve TerminalAI's current privacy promise | REJECTED | separate local/cloud modes and explicit disclosure |
| Ten Autoresearch cycles are enough for full portable Agent SDK integration | UNVERIFIED and unlikely | limit the first stage to a spike or optional launcher |

## Verification performed

- Upstream repository cloned at `eb7265eb5d45c6fc115190e422f784381b363d9c`.
- Upstream unit suite executed with Node 24.21.0: **50 passed, 0 failed**. This validates the checked-out tests, not production suitability or every live provider.
- Local PowerShell files parsed without execution; one pre-existing error was found in `Uninstall-TerminalAi.ps1:46`.
- Local Ollama version, model list, and advertised capabilities read through local commands/API without generating content.
- `ollama launch claude --help` verified that the installed Ollama client exposes the Claude Code integration.
- No Claude/Ollama configuration was changed, no live LLM prompt was sent, and no application test with side effects was run.

## Final recommendation

Proceed with **Option A as a bounded experiment**: an optional `ai-agent` mode backed by Claude Code over Ollama's native Anthropic-compatible API. Do not transplant the dashboard or protocol adapters, do not replace the current fast LLM path, and do not package Claude Code binaries yet.

If the no-code spike cannot pass the model, permission, isolation, privacy, and regression gates, stop. The existing direct Ollama integration remains the simpler and safer product for command generation. If it passes and users need richer programmatic UI control, then evaluate Option B as a separate phase with its own scope and acceptance contract.
