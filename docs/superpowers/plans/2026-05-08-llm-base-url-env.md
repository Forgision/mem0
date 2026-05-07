# LLM Base URL from Environment Variables — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ANTHROPIC_BASE_URL` and `GEMINI_BASE_URL` environment variable support so users can redirect API requests through proxies or custom endpoints.

**Architecture:** Read env var directly in each provider's `__init__`, pass to SDK client constructor. No config class changes. Matches existing `OPENAI_BASE_URL` pattern.

**Tech Stack:** Python, pytest, anthropic SDK, google-genai SDK

---

### Task 1: Anthropic base_url support — test + implementation

**Files:**
- Modify: `mem0/llms/anthropic.py:40-41`
- Modify: `tests/llms/test_anthropic.py`

- [ ] **Step 1: Write failing test for Anthropic base_url**

Append to `tests/llms/test_anthropic.py`:

```python
def test_anthropic_base_url_from_env(mock_anthropic_client):
    """ANTHROPIC_BASE_URL env var should be passed to the Anthropic client."""
    with patch.dict("os.environ", {"ANTHROPIC_BASE_URL": "https://proxy.example.com"}):
        config = AnthropicConfig(model="claude-3-5-sonnet-20240620", api_key="test-key")
        AnthropicLLM(config)

    mock_anthropic.Anthropic.assert_called_once_with(
        api_key="test-key", base_url="https://proxy.example.com"
    )


def test_anthropic_no_base_url_by_default(mock_anthropic_client):
    """Without ANTHROPIC_BASE_URL, base_url should not be passed to client."""
    config = AnthropicConfig(model="claude-3-5-sonnet-20240620", api_key="test-key")
    AnthropicLLM(config)

    mock_anthropic.Anthropic.assert_called_once_with(api_key="test-key")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/llms/test_anthropic.py::test_anthropic_base_url_from_env tests/llms/test_anthropic.py::test_anthropic_no_base_url_by_default -v`
Expected: FAIL — `assert_called_once_with` gets `api_key="test-key"` only, no `base_url` arg.

- [ ] **Step 3: Implement Anthropic base_url**

In `mem0/llms/anthropic.py`, replace lines 40-41:

```python
        api_key = self.config.api_key or os.getenv("ANTHROPIC_API_KEY")
        self.client = anthropic.Anthropic(api_key=api_key)
```

with:

```python
        api_key = self.config.api_key or os.getenv("ANTHROPIC_API_KEY")
        base_url = os.getenv("ANTHROPIC_BASE_URL")
        kwargs = {"api_key": api_key}
        if base_url:
            kwargs["base_url"] = base_url
        self.client = anthropic.Anthropic(**kwargs)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/llms/test_anthropic.py -v`
Expected: All 7 tests PASS.

- [ ] **Step 5: Run full test suite for regressions**

Run: `uv run pytest tests/llms/ -v`
Expected: All LLM tests PASS.

- [ ] **Step 6: Commit**

```bash
git add mem0/llms/anthropic.py tests/llms/test_anthropic.py
git commit -m "feat(llm): add ANTHROPIC_BASE_URL env var support"
```

---

### Task 2: Gemini base_url support — test + implementation

**Files:**
- Modify: `mem0/llms/gemini.py:21-22`
- Modify: `tests/llms/test_gemini.py`

- [ ] **Step 1: Write failing test for Gemini base_url**

Append to `tests/llms/test_gemini.py`:

```python
def test_gemini_base_url_from_env(mock_gemini_client):
    """GEMINI_BASE_URL env var should be passed as http_options to genai.Client."""
    with patch("mem0.llms.gemini.genai.Client") as mock_client_class, \
         patch.dict("os.environ", {"GEMINI_BASE_URL": "https://proxy.example.com"}):
        mock_client_class.return_value = Mock()
        config = BaseLlmConfig(model="gemini-2.0-flash", api_key="test-key")
        llm = GeminiLLM(config)

        mock_client_class.assert_called_once()
        call_kwargs = mock_client_class.call_args[1]
        assert call_kwargs["api_key"] == "test-key"
        assert call_kwargs["http_options"] is not None
        assert call_kwargs["http_options"].base_url == "https://proxy.example.com"


def test_gemini_no_base_url_by_default(mock_gemini_client):
    """Without GEMINI_BASE_URL, http_options should not be passed."""
    with patch("mem0.llms.gemini.genai.Client") as mock_client_class:
        mock_client_class.return_value = Mock()
        config = BaseLlmConfig(model="gemini-2.0-flash", api_key="test-key")
        GeminiLLM(config)

        call_kwargs = mock_client_class.call_args[1]
        assert call_kwargs["http_options"] is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/llms/test_gemini.py::test_gemini_base_url_from_env tests/llms/test_gemini.py::test_gemini_no_base_url_by_default -v`
Expected: FAIL — `genai.Client` not called with `http_options`.

- [ ] **Step 3: Implement Gemini base_url**

In `mem0/llms/gemini.py`, replace lines 21-22:

```python
        api_key = self.config.api_key or os.getenv("GOOGLE_API_KEY")
        self.client = genai.Client(api_key=api_key)
```

with:

```python
        api_key = self.config.api_key or os.getenv("GOOGLE_API_KEY")
        base_url = os.getenv("GEMINI_BASE_URL")
        http_options = types.HttpOptions(base_url=base_url) if base_url else None
        self.client = genai.Client(api_key=api_key, http_options=http_options)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/llms/test_gemini.py -v`
Expected: All 9 tests PASS.

- [ ] **Step 5: Run full test suite for regressions**

Run: `uv run pytest tests/llms/ -v`
Expected: All LLM tests PASS.

- [ ] **Step 6: Commit**

```bash
git add mem0/llms/gemini.py tests/llms/test_gemini.py
git commit -m "feat(llm): add GEMINI_BASE_URL env var support"
```

---

### Task 3: Update server .env.example

**Files:**
- Modify: `server/.env.example`

- [ ] **Step 1: Add base URL env vars to .env.example**

In `server/.env.example`, after the line `# GOOGLE_API_KEY=`, add:

```
# ANTHROPIC_BASE_URL=
# GEMINI_BASE_URL=
```

Full diff — replace:

```
# Optional: other bundled LLM/embedder providers (set the key for the one you want to use)
# ANTHROPIC_API_KEY=
# GOOGLE_API_KEY=
```

with:

```
# Optional: other bundled LLM/embedder providers (set the key for the one you want to use)
# ANTHROPIC_API_KEY=
# GOOGLE_API_KEY=
# ANTHROPIC_BASE_URL=
# GEMINI_BASE_URL=
```

- [ ] **Step 2: Commit**

```bash
git add server/.env.example
git commit -m "docs(server): add ANTHROPIC_BASE_URL and GEMINI_BASE_URL to .env.example"
```

---

### Task 4: Lint and final verification

- [ ] **Step 1: Run ruff lint + format**

Run: `uv run ruff check --fix mem0/llms/anthropic.py mem0/llms/gemini.py tests/llms/test_anthropic.py tests/llms/test_gemini.py && uv run ruff format mem0/llms/anthropic.py mem0/llms/gemini.py tests/llms/test_anthropic.py tests/llms/test_gemini.py`
Expected: No errors.

- [ ] **Step 2: Run full LLM test suite**

Run: `uv run pytest tests/llms/ -v`
Expected: All tests PASS.
