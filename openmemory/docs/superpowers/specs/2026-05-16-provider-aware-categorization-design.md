# Provider-Aware Categorization Design

**Date:** 2026-05-16
**Status:** Approved
**Author:** Claude

## Problem

The `categorization.py` module hardcodes OpenAI client for memory categorization. When users configure Gemini or other LLM providers via `LLM_PROVIDER` env var or database config, categorization still uses OpenAI independently. This creates inconsistency and requires separate API keys.

## Solution

Refactor categorization to use the configured LLM provider from mem0's Memory client, ensuring consistent provider usage across openmemory.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    models.py                                │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  get_categories_for_memory(memory_text)               │  │
│  └───────────────────────┬───────────────────────────────┘  │
└──────────────────────────┼──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                 categorization.py                           │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  get_memory_client() → Memory instance                │  │
│  │  ├─ memory.llm (configured LLM instance)              │  │
│  │  └─ memory.config.llm.provider (provider name)        │  │
│  └───────────────────────────────────────────────────────┘  │
│                           │                                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Provider-specific structured output:                 │  │
│  │  • openai/openai_structured → JSON + Pydantic parse   │  │
│  │  • gemini → JSON + Pydantic parse                     │  │
│  │  • other → text fallback                              │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Changes

### 1. categorization.py

**Remove:**
- `openai` direct import
- `_get_openai_client()` function
- Module-level `_openai_client` variable

**Add:**
- Import `get_memory_client` from `app.utils.memory`
- Provider-specific structured output handling
- Fallback text parsing for unsupported providers

**New Implementation:**
```python
from app.utils.memory import get_memory_client

def get_categories_for_memory(memory: str) -> List[str]:
    memory_client = get_memory_client()
    if not memory_client:
        raise RuntimeError("Memory client not initialized")

    llm = memory_client.llm
    provider = memory_client.config.llm.provider

    messages = [
        {"role": "system", "content": MEMORY_CATEGORIZATION_PROMPT},
        {"role": "user", "content": memory}
    ]

    # Structured output providers
    if provider in ("openai", "openai_structured", "gemini"):
        json_str = llm.generate_response(
            messages=messages,
            response_format={"type": "json_object"}
        )
        return MemoryCategories.model_validate_json(json_str).categories

    # Fallback: text parsing
    else:
        response = llm.generate_response(messages=messages)
        return _parse_categories_from_text(response)
```

### 2. No Changes Required

- `memory.py` — already has provider factories and singleton
- `models.py` — caller signature unchanged
- `main.py` — no changes needed

## Provider Support Matrix

| Provider | Structured Output | Notes |
|----------|------------------|-------|
| openai | ✅ JSON mode | Manual Pydantic parse required |
| openai_structured | ✅ JSON mode | Manual Pydantic parse required |
| gemini | ✅ JSON schema | Optional schema parameter |
| ollama | ⚠️ Fallback | Text parsing |
| anthropic | ⚠️ Fallback | Text parsing |
| groq, together, etc. | ⚠️ Fallback | Text parsing |

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Memory client not initialized | Raise `RuntimeError` — server is broken |
| LLM API call fails | Retry with tenacity (existing behavior) |
| JSON parse fails | Return empty list (graceful degradation) |
| Fallback text parse fails | Return empty list (graceful degradation) |

## Dependencies

- `mem0.utils.llms.base.LLMBase` — for type checking
- `app.utils.memory.get_memory_client` — singleton Memory instance
- No new package dependencies

## Testing

- Test with `LLM_PROVIDER=openai` (default)
- Test with `LLM_PROVIDER=gemini`
- Test with `LLM_PROVIDER=ollama` (fallback)
- Verify Memory init failure propagates

## Migration Path

1. Update `categorization.py` with new implementation
2. No database migration required
3. No API changes required
