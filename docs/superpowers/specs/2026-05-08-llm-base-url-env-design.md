# LLM Base URL from Environment Variables

**Date:** 2026-05-08
**Status:** Approved
**Scope:** Anthropic + Gemini LLM providers

## Problem

Anthropic and Gemini LLM providers have no way to configure a custom API endpoint (base URL). Users behind proxies, using compatible API gateways, or running self-hosted endpoints cannot redirect requests. Other providers (OpenAI, DeepSeek, xAI, vLLM, etc.) already support this via environment variables.

## Solution

Add `ANTHROPIC_BASE_URL` and `GEMINI_BASE_URL` environment variable support to their respective LLM providers. Read directly in provider `__init__`, pass to SDK client constructor. No config class changes.

### Files Changed

| File | Change |
|------|--------|
| `mem0/llms/anthropic.py` | Read `ANTHROPIC_BASE_URL` env var, pass `base_url` to `anthropic.Anthropic()` |
| `mem0/llms/gemini.py` | Read `GEMINI_BASE_URL` env var, pass `http_options` to `genai.Client()` |
| `server/.env.example` | Add `ANTHROPIC_BASE_URL` and `GEMINI_BASE_URL` entries |
| `tests/llms/test_anthropic.py` | Add test for base_url env var |
| `tests/llms/test_gemini.py` | Add test for base_url env var |

### Implementation Details

**Anthropic** (`mem0/llms/anthropic.py`, line ~41):

```python
api_key = self.config.api_key or os.getenv("ANTHROPIC_API_KEY")
base_url = os.getenv("ANTHROPIC_BASE_URL")
kwargs = {"api_key": api_key}
if base_url:
    kwargs["base_url"] = base_url
self.client = anthropic.Anthropic(**kwargs)
```

**Gemini** (`mem0/llms/gemini.py`, line ~22):

```python
api_key = self.config.api_key or os.getenv("GOOGLE_API_KEY")
base_url = os.getenv("GEMINI_BASE_URL")
http_options = types.HttpOptions(base_url=base_url) if base_url else None
self.client = genai.Client(api_key=api_key, http_options=http_options)
```

### Behavior

- **Env var not set:** `base_url` is `None`, SDK uses default endpoint. No behavior change.
- **Env var set to valid URL:** SDK sends requests to custom endpoint.
- **Env var set to invalid URL:** SDK raises connection error. No special handling needed.

### Testing

Follow existing test pattern from `tests/llms/test_openai.py`:

1. **Default case:** No env var set, verify client constructed without `base_url`
2. **Env var set:** Set `ANTHROPIC_BASE_URL` / `GEMINI_BASE_URL`, verify client receives the URL

Use `@pytest.fixture` with `patch` for client mocking, same pattern as existing tests.

### Not In Scope

- Adding `base_url` to `BaseLlmConfig`
- Changing other providers (Groq, Together, etc.)
- Config-level `base_url` parameter (env var only for now)
