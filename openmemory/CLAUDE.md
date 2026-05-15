# OpenMemory

Standalone subproject. Do NOT modify mem0/ without permission.

## Provider Factories

**File:** `api/app/utils/memory.py`

Pattern: `_build_<provider>_{llm,embedder}_config()` → register in `_LLM_CONFIG_FACTORIES` / `_EMBEDDER_CONFIG_FACTORIES`

Existing: ollama, openai, gemini

## Config

`api/config.json` is example only. Real config in database `configs` table via `/api/v1/config/*` API.

## Workarounds

Gemini base_url: Set `GOOGLE_GEMINI_BASE_URL` env var (mem0ai doesn't pass it).
