# Gemini Provider Factory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add dedicated Gemini provider factory functions to `openmemory/api/app/utils/memory.py`, matching the pattern established by Ollama and OpenAI providers.

**Architecture:** Two factory functions (`_build_gemini_llm_config`, `_build_gemini_embedder_config`) that construct provider-specific config dicts with default models, api_key handling, and base_url support. Registered in `_LLM_CONFIG_FACTORIES` and `_EMBEDDER_CONFIG_FACTORIES` dicts.

**Tech Stack:** Python 3.9+, FastAPI, mem0ai SDK, google-genai library

## Post-Code Checklist

After modifying Python files, **always run**:

```bash
cd openmemory/api
uv run ruff check --fix .      # Lint + auto-fix
uv run ty check .               # Type check
uv run ruff format .            # Format
```

---

## File Structure

**Modified:**
- `openmemory/api/app/utils/memory.py` — Add two factory functions and register them

**No new files.**

---

## Task 1: Add Gemini LLM Factory Function

**Files:**
- Modify: `openmemory/api/app/utils/memory.py` (insert after line 158, after `_build_openai_llm_config`)

- [ ] **Step 1: Add the LLM factory function**

Insert this code after `_build_openai_llm_config` function (around line 158):

```python
def _build_gemini_llm_config(model, api_key, base_url, ollama_base_url):
    config = {"model": model or "gemini-2.5-flash-lite"}
    if api_key:
        config["api_key"] = api_key
    if base_url:
        config["base_url"] = base_url
    return config
```

This creates the Gemini LLM config factory following the same pattern as Ollama/OpenAI.

- [ ] **Step 2: Lint & Format**

```bash
cd openmemory/api
uv run ruff check --fix .
uv run ty check .
uv run ruff format .
```

Expected: No errors, formatted output

- [ ] **Step 3: Commit**

```bash
git add openmemory/api/app/utils/memory.py
git commit -m "feat(gemini): add LLM provider factory function

- Add _build_gemini_llm_config with default model gemini-2.5-flash-lite
- Supports api_key and base_url configuration
- Follows pattern established by Ollama/OpenAI factories

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 2: Add Gemini Embedder Factory Function

**Files:**
- Modify: `openmemory/api/app/utils/memory.py` (insert after the function added in Task 1)

- [ ] **Step 1: Add the embedder factory function**

Insert this code after `_build_gemini_llm_config`:

```python
def _build_gemini_embedder_config(model, api_key, base_url, ollama_base_url, llm_base_url):
    config = {"model": model or "gemini-embedding-001"}
    if api_key:
        config["api_key"] = api_key
    if base_url:
        config["base_url"] = base_url
    return config
```

This creates the Gemini embedder config factory.

- [ ] **Step 2: Lint & Format**

```bash
cd openmemory/api
uv run ruff check --fix .
uv run ty check .
uv run ruff format .
```

Expected: No errors, formatted output

- [ ] **Step 3: Commit**

```bash
git add openmemory/api/app/utils/memory.py
git commit -m "feat(gemini): add embedder provider factory function

- Add _build_gemini_embedder_config with default model gemini-embedding-001
- Supports api_key and base_url configuration
- Follows pattern established by Ollama/OpenAI factories

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 3: Register Gemini Factories

**Files:**
- Modify: `openmemory/api/app/utils/memory.py` (update `_LLM_CONFIG_FACTORIES` and `_EMBEDDER_CONFIG_FACTORIES`)

- [ ] **Step 1: Register LLM factory**

Find the `_LLM_CONFIG_FACTORIES` dictionary (around line 155-158):

```python
_LLM_CONFIG_FACTORIES = {
    "ollama": _build_ollama_llm_config,
    "openai": _build_openai_llm_config,
}
```

Add the gemini entry:

```python
_LLM_CONFIG_FACTORIES = {
    "ollama": _build_ollama_llm_config,
    "openai": _build_openai_llm_config,
    "gemini": _build_gemini_llm_config,
}
```

- [ ] **Step 2: Register embedder factory**

Find the `_EMBEDDER_CONFIG_FACTORIES` dictionary (around line 203-206):

```python
_EMBEDDER_CONFIG_FACTORIES = {
    "ollama": _build_ollama_embedder_config,
    "openai": _build_openai_embedder_config,
}
```

Add the gemini entry:

```python
_EMBEDDER_CONFIG_FACTORIES = {
    "ollama": _build_ollama_embedder_config,
    "openai": _build_openai_embedder_config,
    "gemini": _build_gemini_embedder_config,
}
```

- [ ] **Step 3: Lint & Format**

```bash
cd openmemory/api
uv run ruff check --fix .
uv run ty check .
uv run ruff format .
```

Expected: No errors, formatted output

- [ ] **Step 4: Commit**

```bash
git add openmemory/api/app/utils/memory.py
git commit -m "feat(gemini): register provider factories

- Register gemini in _LLM_CONFIG_FACTORIES
- Register gemini in _EMBEDDER_CONFIG_FACTORIES
- Gemini now uses dedicated factories instead of generic fallback

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 4: Verify Implementation

**Files:**
- Test: `openmemory/api/app/utils/memory.py`

- [ ] **Step 1: Import verification**

Run Python to verify factories are accessible:

```bash
cd openmemory/api
python3 -c "
from app.utils.memory import (
    _LLM_CONFIG_FACTORIES,
    _EMBEDDER_CONFIG_FACTORIES,
    _build_gemini_llm_config,
    _build_gemini_embedder_config
)

# Verify registration
assert 'gemini' in _LLM_CONFIG_FACTORIES, 'gemini not in LLM factories'
assert 'gemini' in _EMBEDDER_CONFIG_FACTORIES, 'gemini not in embedder factories'

# Verify LLM factory output
llm_config = _build_gemini_llm_config(None, 'test-key', 'https://test.com', None)
assert ll_config['model'] == 'gemini-2.5-flash-lite'
assert llm_config['api_key'] == 'test-key'
assert llm_config['base_url'] == 'https://test.com'

# Verify embedder factory output
emb_config = _build_gemini_embedder_config(None, 'test-key', None, None, None)
assert emb_config['model'] == 'gemini-embedding-001'
assert emb_config['api_key'] == 'test-key'

print('✓ All factory tests passed')
"
```

Expected: `✓ All factory tests passed`

- [ ] **Step 2: Check for regressions**

Run existing tests:

```bash
cd openmemory/api
pytest tests/ -v --tb=short
```

Expected: All existing tests pass

- [ ] **Step 3: Final commit (verification only)**

```bash
git add openmemory/api/app/utils/memory.py
git commit --allow-empty -m "test(gemini): verify factory implementation

- Verified gemini factories registered correctly
- Verified default models: gemini-2.5-flash-lite, gemini-embedding-001
- All existing tests pass

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 5: Optional Manual Testing (API Running)

**Files:**
- Test: Running OpenMemory API

- [ ] **Step 1: Start the API**

```bash
cd openmemory
docker-compose up -d
```

Wait for services to start.

- [ ] **Step 2: Set Gemini API key**

```bash
export GOOGLE_API_KEY="your-gemini-api-key"
```

- [ ] **Step 3: Configure Gemini via API**

```bash
curl -X PUT http://localhost:8765/api/v1/config/main \
  -H "Content-Type: application/json" \
  -d '{
    "mem0": {
      "llm": {
        "provider": "gemini",
        "config": {
          "model": "gemini-2.5-flash-lite",
          "api_key": "env:GOOGLE_API_KEY"
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
  }'
```

Expected: `200 OK` with config response

- [ ] **Step 4: Test memory operations**

```bash
curl -X POST http://localhost:8765/api/v1/memories \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "My name is Alice"}],
    "user_id": "test-user"
  }'
```

Expected: Memory created successfully

- [ ] **Step 5: Search memory**

```bash
curl "http://localhost:8765/api/v1/memories?user_id=test-user&query=What is my name"
```

Expected: Returns "Alice" memory

---

## Summary

**Total changes:**
- 2 new factory functions (~20 lines)
- 2 dictionary registrations (+2 lines)
- No breaking changes

**Known limitations:**
- mem0ai 2.0.2 ignores `base_url` in config (hardcoded `genai.Client(api_key=...)`)
- Workaround: Set `GOOGLE_GEMINI_BASE_URL` environment variable
- Future: mem0 SDK PR to add `http_options` support
