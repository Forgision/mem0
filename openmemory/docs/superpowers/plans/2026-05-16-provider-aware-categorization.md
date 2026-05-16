# Provider-Aware Categorization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor memory categorization to use the configured LLM provider (OpenAI, Gemini, etc.) from mem0's Memory client instead of hardcoded OpenAI client.

**Architecture:** Import the singleton Memory client, access its configured LLM instance, use provider-specific structured output handling with text fallback for unsupported providers.

**Tech Stack:** Python 3.12, mem0 SDK, Pydantic, pytest

---

## File Structure

| File | Change | Responsibility |
|------|--------|----------------|
| `openmemory/api/app/utils/categorization.py` | Modify | Memory categorization using configured LLM provider |
| `openmemory/api/tests/test_categorization.py` | Create | Tests for provider-aware categorization |

---

## Task 1: Add Fallback Text Parser

**Files:**
- Modify: `openmemory/api/app/utils/categorization.py`

- [ ] **Step 1: Add text parsing helper function**

Add this function after `MemoryCategories` class definition:

```python
def _parse_categories_from_text(text: str) -> List[str]:
    """Parse categories from plain text response (fallback for non-structured providers)."""
    try:
        # Try to extract comma-separated values
        categories = [cat.strip().lower() for cat in text.split(",")]
        return [cat for cat in categories if cat]
    except Exception:
        logging.warning(f"[WARN] Failed to parse categories from text: {text}")
        return []
```

- [ ] **Step 2: Commit**

```bash
git add openmemory/api/app/utils/categorization.py
git commit -m "feat: add text fallback parser for categorization"
```

---

## Task 2: Refactor get_categories_for_memory to Use Memory Client LLM

**Files:**
- Modify: `openmemory/api/app/utils/categorization.py`

- [ ] **Step 1: Remove OpenAI-specific imports and client**

Replace the imports at the top of the file:

```python
# Remove these lines:
# from openai import OpenAI
# _openai_client: OpenAI | None = None
# def _get_openai_client() -> OpenAI:
#     ...

# Add this import:
from app.utils.memory import get_memory_client
```

- [ ] **Step 2: Rewrite get_categories_for_memory function**

Replace the entire function with:

```python
@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=15))
def get_categories_for_memory(memory: str) -> List[str]:
    try:
        memory_client = get_memory_client()
        if not memory_client:
            raise RuntimeError("Memory client not initialized")

        llm = memory_client.llm
        provider = memory_client.config.llm.provider

        messages = [
            {"role": "system", "content": MEMORY_CATEGORIZATION_PROMPT},
            {"role": "user", "content": memory}
        ]

        # Structured output providers (OpenAI, Gemini)
        if provider in ("openai", "openai_structured", "gemini"):
            response = llm.generate_response(
                messages=messages,
                response_format={"type": "json_object"}
            )
            try:
                parsed = MemoryCategories.model_validate_json(response)
                return [cat.strip().lower() for cat in parsed.categories]
            except Exception as e:
                logging.error(f"[ERROR] Failed to parse structured output: {e}")
                return []

        # Fallback: text parsing for ollama, anthropic, groq, etc.
        else:
            response = llm.generate_response(messages=messages)
            return _parse_categories_from_text(response)

    except Exception as e:
        logging.error(f"[ERROR] Failed to get categories: {e}")
        raise
```

- [ ] **Step 3: Verify file compiles**

Run: `cd openmemory/api && python -c "from app.utils.categorization import get_categories_for_memory; print('Import OK')"`
Expected: `Import OK`

- [ ] **Step 4: Commit**

```bash
git add openmemory/api/app/utils/categorization.py
git commit -m "refactor: use Memory client LLM for categorization"
```

---

## Task 3: Write Tests

**Files:**
- Create: `openmemory/api/tests/test_categorization.py`

- [ ] **Step 1: Create test file with fixtures**

```python
import pytest
from unittest.mock import Mock, patch
from app.utils.categorization import get_categories_for_memory, _parse_categories_from_text


class TestTextFallbackParser:
    """Test the fallback text parser for non-structured providers."""

    def test_parse_comma_separated_categories(self):
        result = _parse_categories_from_text("work, personal, ideas")
        assert result == ["work", "personal", "ideas"]

    def test_parse_with_spaces(self):
        result = _parse_categories_from_text("  work  ,  personal  ,  ideas  ")
        assert result == ["work", "personal", "ideas"]

    def test_parse_empty_string(self):
        result = _parse_categories_from_text("")
        assert result == []

    def test_parse_invalid_input(self):
        result = _parse_categories_from_text("not valid comma separated")
        assert result == ["not valid comma separated"]


class TestCategorizationWithMemoryClient:
    """Test categorization using Memory client LLM."""

    @patch("app.utils.categorization.get_memory_client")
    def test_memory_client_not_initialized_raises_error(self, mock_get_client):
        mock_get_client.return_value = None
        with pytest.raises(RuntimeError, match="Memory client not initialized"):
            get_categories_for_memory("test memory")

    @patch("app.utils.categorization.get_memory_client")
    def test_openai_provider_structured_output(self, mock_get_client):
        # Setup mock Memory client
        mock_llm = Mock()
        mock_llm.generate_response.return_value = '{"categories": ["work", "personal"]}'
        mock_memory = Mock()
        mock_memory.llm = mock_llm
        mock_memory.config.llm.provider = "openai"
        mock_get_client.return_value = mock_memory

        result = get_categories_for_memory("buy groceries")

        assert result == ["work", "personal"]
        mock_llm.generate_response.assert_called_once()

    @patch("app.utils.categorization.get_memory_client")
    def test_gemini_provider_structured_output(self, mock_get_client):
        mock_llm = Mock()
        mock_llm.generate_response.return_value = '{"categories": ["ideas"]}'
        mock_memory = Mock()
        mock_memory.llm = mock_llm
        mock_memory.config.llm.provider = "gemini"
        mock_get_client.return_value = mock_memory

        result = get_categories_for_memory("new project idea")

        assert result == ["ideas"]

    @patch("app.utils.categorization.get_memory_client")
    def test_ollama_provider_text_fallback(self, mock_get_client):
        mock_llm = Mock()
        mock_llm.generate_response.return_value = "work, personal, tasks"
        mock_memory = Mock()
        mock_memory.llm = mock_llm
        mock_memory.config.llm.provider = "ollama"
        mock_get_client.return_value = mock_memory

        result = get_categories_for_memory("daily tasks")

        assert result == ["work", "personal", "tasks"]

    @patch("app.utils.categorization.get_memory_client")
    def test_invalid_json_returns_empty_list(self, mock_get_client):
        mock_llm = Mock()
        mock_llm.generate_response.return_value = "invalid json{{{"
        mock_memory = Mock()
        mock_memory.llm = mock_llm
        mock_memory.config.llm.provider = "openai"
        mock_get_client.return_value = mock_memory

        result = get_categories_for_memory("test memory")

        assert result == []
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd openmemory/api && uv run pytest tests/test_categorization.py -v`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add openmemory/api/tests/test_categorization.py
git commit -m "test: add categorization provider tests"
```

---

## Task 4: Verify Integration

**Files:**
- None (verification only)

- [ ] **Step 1: Verify Docker build**

Run: `cd openmemory && sudo docker compose build openmemory-mcp`
Expected: Build succeeds without errors

- [ ] **Step 2: Verify container starts**

Run: `timeout 5 sudo docker run --rm mem0/openmemory-mcp 2>&1 || true`
Expected output includes: `INFO: Application startup complete`

- [ ] **Step 3: Run full test suite**

Run: `cd openmemory/api && uv run pytest`
Expected: All existing tests still pass

---

## Task 5: Documentation Update

**Files:**
- Modify: `openmemory/CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md with categorization provider info**

Add to the relevant section:

```markdown
## Categorization

Memory categorization uses the configured LLM provider from mem0's Memory client.
- Structured output (JSON mode): openai, openai_structured, gemini
- Text fallback: ollama, anthropic, groq, together, and others

Set `LLM_PROVIDER` environment variable to control which LLM is used.
```

- [ ] **Step 2: Commit**

```bash
git add openmemory/CLAUDE.md
git commit -m "docs: document categorization provider support"
```

---

## Verification Checklist

After completing all tasks:

- [ ] `get_categories_for_memory` uses `get_memory_client()`
- [ ] OpenAI direct import removed
- [ ] `_get_openai_client` function removed
- [ ] Tests cover structured output providers
- [ ] Tests cover text fallback providers
- [ ] Tests cover Memory client not initialized error
- [ ] Docker build succeeds
- [ ] All tests pass
