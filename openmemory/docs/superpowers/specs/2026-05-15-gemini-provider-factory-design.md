# Gemini Provider Factory Design

**Date:** 2026-05-15
**Status:** Proposed
**Component:** `openmemory/api/app/utils/memory.py`

## Problem

`openmemory` has dedicated factory functions for `ollama` and `openai` providers (with base_url support), but `gemini` falls back to generic handler. This creates inconsistency and lacks explicit base_url configuration.

## Context

- openmemory uses pip-installed `mem0ai 2.0.2` (not local worktree)
- `mem0ai`'s Gemini implementation (`gemini.py`) uses `genai.Client(api_key=...)` — does NOT pass base_url
- `google-genai` library (v1.52.0) supports base_url via:
  - `GOOGLE_GEMINI_BASE_URL` environment variable
  - `Client(http_options=HttpOptions(base_url=...))`
- UI already lists "gemini" in provider dropdowns

## Solution

Add Gemini provider factories matching the Ollama/OpenAI pattern.

## Implementation

### File: `openmemory/api/app/utils/memory.py`

#### 1. LLM Factory

```python
def _build_gemini_llm_config(model, api_key, base_url, ollama_base_url):
    config = {"model": model or "gemini-2.5-flash-lite"}
    if api_key:
        config["api_key"] = api_key
    if base_url:
        config["base_url"] = base_url
    return config
```

#### 2. Embedder Factory

```python
def _build_gemini_embedder_config(model, api_key, base_url, ollama_base_url, llm_base_url):
    config = {"model": model or "gemini-embedding-001"}
    if api_key:
        config["api_key"] = api_key
    if base_url:
        config["base_url"] = base_url
    return config
```

#### 3. Register Factories

```python
_LLM_CONFIG_FACTORIES["gemini"] = _build_gemini_llm_config
_EMBEDDER_CONFIG_FACTORIES["gemini"] = _build_gemini_embedder_config
```

### Location

Insert factories after line 158 (after `_build_openai_llm_config`) and before the generic fallback in `_create_llm_config`.

## Known Limitations

1. **mem0ai 2.0.2 ignores base_url** — Current mem0 Gemini classes don't pass `http_options` to `genai.Client`
2. **Workaround:** Set `GOOGLE_GEMINI_BASE_URL` environment variable — google-genai reads it directly
3. **Future:** mem0 SDK PR to add `http_options` support in `GeminiLLM` and `GoogleGenAIEmbedding`

## Default Models

| Provider | LLM Default | Embedder Default |
|----------|-------------|------------------|
| gemini   | `gemini-2.5-flash-lite` | `gemini-embedding-001` |

## Configuration Example

```json
{
  "mem0": {
    "llm": {
      "provider": "gemini",
      "config": {
        "model": "gemini-2.5-flash-lite",
        "api_key": "env:GOOGLE_API_KEY",
        "base_url": "https://custom-gateway.example.com"
      }
    },
    "embedder": {
      "provider": "gemini",
      "config": {
        "model": "gemini-embedding-001",
        "api_key": "env:GOOGLE_API_KEY"
      }
    }
  }
}
```

## Testing

1. Add Gemini as LLM provider via UI
2. Add Gemini as Embedder provider via UI
3. Verify memory operations work (add/search/update/delete)
4. Optional: Test `GOOGLE_GEMINI_BASE_URL` env var workaround

## Success Criteria

- Gemini has dedicated factory functions like Ollama/OpenAI
- Config can specify gemini model, api_key, and base_url
- Memory operations work with Gemini provider
