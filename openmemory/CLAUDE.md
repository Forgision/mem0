# OpenMemory

Standalone subproject. Do NOT modify mem0/ without permission.

## Dev Commands

```bash
# Lint & Format
uv run ruff check .                            # Lint
uv run ruff check --fix .                      # Lint + auto-fix
uv run ruff format .                           # Format

# Type Check
uv run ty check .                              # Static type check
```

## Provider Factories

**File:** `api/app/utils/memory.py`

Pattern: `_build_<provider>_{llm,embedder}_config()` → register in `_LLM_CONFIG_FACTORIES` / `_EMBEDDER_CONFIG_FACTORIES`

Existing: ollama, openai, gemini

## Config

`api/config.json` is example only. Real config in database `configs` table via `/api/v1/config/*` API.

## Categorization

Memory categorization uses the configured LLM provider from mem0's Memory client.
- Structured output (JSON mode): openai, openai_structured, gemini
- Text fallback: ollama, anthropic, groq, together, and others

Set `LLM_PROVIDER` environment variable to control which LLM is used.

## Workarounds

Gemini base_url: Set `GOOGLE_GEMINI_BASE_URL` env var (mem0ai doesn't pass it).
