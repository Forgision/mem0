# CLAUDE.md or AGENTS.md

Workspace for OpenMemory (self-hosted memory server) and mem0-plugin (AI editor plugin).

## Active Projects

| Directory | Description |
|-----------|-------------|
| `openmemory/` | Self-hosted memory platform — FastAPI API + MCP server + Next.js UI + Qdrant |
| `mem0-plugin/` | Claude Code / Cursor / Codex plugin — hooks, skills, MCP configs |
| `docs/` | Mintlify documentation site |
| `.references/` | Archived mem0 SDK + related packages — **read-only, do not modify** |

## Dev Commands

```bash
# OpenMemory
cd openmemory && make run                 # Dev mode: Qdrant + local uvicorn + pnpm
cd openmemory && make stop                # Stop all dev services
cd openmemory && docker-compose up -d     # Docker mode: all services in containers
cd openmemory/api && pytest tests/        # Run API tests
cd openmemory/api && ruff check .         # Lint
cd openmemory/api && ruff format .        # Format

# Debug
curl -sf http://localhost:8765/health                           # Backend health
curl -sf http://localhost:8765/api/v1/stats?user_id=user        # Test endpoint
curl -sf http://localhost:3000/api/v1/memories/categories?user_id=user  # Via frontend proxy
tail -f openmemory/logs/backend.log openmemory/logs/frontend.log  # Live logs

# Docs
cd docs && mintlify dev
```

## OpenMemory Architecture

**Stack:** FastAPI (api/) + Next.js 15 + React 19 (ui/) + Qdrant (vector store) + SQLite/PostgreSQL

**API entry point:** `openmemory/api/main.py` — uvicorn on port 8765

**Key files:**
- `openmemory/api/app/mcp_server.py` — MCP server (5 tools: add_memories, search_memory, list_memories, delete_memories, delete_all_memories)
- `openmemory/api/app/utils/memory.py` — Memory client init, provider factories
- `openmemory/api/app/utils/categorization.py` — Provider-aware memory categorization
- `openmemory/api/app/routers/` — REST API endpoints (memories, apps, stats, config, backup)
- `openmemory/ui/` — Next.js frontend, connects to API via rewrites in next.config.mjs

**Config:** Stored in database via `/api/v1/config/*` API. `api/config.json` is example only.

### Provider Factories

**File:** `openmemory/api/app/utils/memory.py`

Pattern: `_build_<provider>_{llm,embedder}_config()` → register in `_LLM_CONFIG_FACTORIES` / `_EMBEDDER_CONFIG_FACTORIES`

Existing providers: ollama, openai, gemini

### Categorization

Uses configured LLM provider from mem0's Memory client.
- Structured output (JSON mode): openai, openai_structured, gemini
- Text fallback: ollama, anthropic, groq, together, and others

Set `LLM_PROVIDER` env var to control which LLM is used.

### Workarounds

- Unified `.env`: `openmemory/.env` is single config source. Set `USER` once — `NEXT_PUBLIC_USER` derived automatically. No `api/.env` or `ui/.env`.
- FastAPI trailing slash: `/api/v1/stats` returns 307 redirect. Axios follows transparently.
- Gemini base_url: Set `GOOGLE_GEMINI_BASE_URL` env var (mem0ai SDK doesn't pass it natively)
- Gemini config: mem0 `BaseLlmConfig` and embedder base config reject `base_url` key. Provider factories set `GOOGLE_GEMINI_BASE_URL` env var instead.
- Gemini dependency: `google-genai` package required. Run `uv add google-genai`.
- Embedder provider independent: Set `EMBEDDER_PROVIDER=gemini` explicitly, otherwise defaults to `openai` even when `LLM_PROVIDER=gemini`.
- DinD proxy: `HTTP_PROXY` blocks Docker hostnames (om-store, om-mcp). `run-dev.sh` sets `NO_PROXY` automatically. If adding new Docker services, update the NO_PROXY line in `openmemory/scripts/run-dev.sh`.

### Docker Services

**DinD networking:** `localhost` can't reach Docker containers. Use Docker network hostnames (`om-store`, `om-mcp`).

| Service | Port | Description |
|---------|------|-------------|
| Qdrant | 6333 | Vector store |
| openmemory-mcp | 8765 | FastAPI + MCP server |
| openmemory-ui | 3000 | Next.js frontend |

## mem0-plugin Architecture

**Stack:** Shell scripts + stdlib Python + static JSON configs. Zero declared dependencies.

**MCP configs:** `.mcp.json` (Claude), `.cursor-mcp.json` (Cursor), `.codex-mcp.json` (Codex) — currently hardcoded to `mcp.mem0.ai`

**Hooks:** 6 lifecycle hooks in `hooks/` + `scripts/`
- SessionStart, UserPromptSubmit, PreToolUse, PreCompact, Stop, TaskCompleted

**Skills:** 2 skills in `skills/`
- `mem0` — SDK reference and integration patterns
- `mem0-mcp` — MCP memory protocol usage guide

## Future Goals

- Make openmemory production-ready for self-hosting (auth, CORS, health check, PostgreSQL)
- Make mem0-plugin configurable for self-hosted openmemory (env var URLs, API compat)

## Coding Standards

- Python: Ruff (line-length 120), Pydantic v2, pytest
- TypeScript (UI): Next.js 15, React 19, pnpm, TailwindCSS
- Follow existing patterns in each project
