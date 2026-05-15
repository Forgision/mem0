# CORS Fix via Next.js Rewrites — Implementation Plan

> **REQUIRED SUB-SKILL:** Use the executing-plans skill to implement this plan task-by-task.

**Goal:** Eliminate CORS errors when accessing OpenMemory UI from non-localhost origins by proxying API calls through Next.js rewrites.

**Architecture:** Next.js built-in rewrites proxy `/api/*` browser requests to uvicorn `:8765`. This makes all browser→API calls same-origin. MCP clients continue connecting to `:8765` directly. No new containers or processes needed.

**Tech Stack:** Next.js rewrites, Docker Compose

**Design doc:** `openmemory/docs/plans/2026-05-15-cors-fix-nextjs-rewrites-design.md`

---

### Task 1: Add rewrites to Next.js config files

**Files:**
- Modify: `openmemory/ui/next.config.mjs`
- Modify: `openmemory/ui/next.config.dev.mjs`

**Step 1: Update `next.config.mjs`**

Add the `rewrites()` function to the config object:

```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  eslint: {
    ignoreDuringBuilds: true,
  },
  typescript: {
    ignoreBuildErrors: true,
  },
  images: {
    unoptimized: true,
  },
  async rewrites() {
    return [
      {
        source: "/api/:path*",
        destination: "http://localhost:8765/api/:path*",
      },
    ];
  },
}

export default nextConfig
```

**Step 2: Update `next.config.dev.mjs`**

Same change, but keep the `output: "standalone"` line that already exists:

```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "standalone",
  eslint: {
    ignoreDuringBuilds: true,
  },
  typescript: {
    ignoreBuildErrors: true,
  },
  images: {
    unoptimized: true,
  },
  async rewrites() {
    return [
      {
        source: "/api/:path*",
        destination: "http://localhost:8765/api/:path*",
      },
    ];
  },
}

export default nextConfig
```

**Step 3: Commit**

```bash
git add openmemory/ui/next.config.mjs openmemory/ui/next.config.dev.mjs
git commit -m "feat: add Next.js rewrites to proxy /api/* to uvicorn"
```

---

### Task 2: Change URL fallback in hook files

Each hook file has the same line to change. The pattern is identical across all files:

**Before:**
```typescript
const URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8765";
```

**After:**
```typescript
const URL = process.env.NEXT_PUBLIC_API_URL || "";
```

**Files:**
- Modify: `openmemory/ui/hooks/useConfig.ts` (line 33)
- Modify: `openmemory/ui/hooks/useMemoriesApi.ts` (line 107)
- Modify: `openmemory/ui/hooks/useAppsApi.ts` (line 70)
- Modify: `openmemory/ui/hooks/useFiltersApi.ts` (line 35)
- Modify: `openmemory/ui/hooks/useStats.ts` (line 38)

**Step 1: Change all 5 files**

In each file, find the line:
```
const URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8765";
```
Replace with:
```
const URL = process.env.NEXT_PUBLIC_API_URL || "";
```

**Step 2: Commit**

```bash
git add openmemory/ui/hooks/useConfig.ts openmemory/ui/hooks/useMemoriesApi.ts openmemory/ui/hooks/useAppsApi.ts openmemory/ui/hooks/useFiltersApi.ts openmemory/ui/hooks/useStats.ts
git commit -m "fix: use relative API paths to avoid CORS issues"
```

---

### Task 3: Change URL fallback in component files

**Files:**
- Modify: `openmemory/ui/components/dashboard/Install.tsx` (line 50)
- Modify: `openmemory/ui/components/form-view.tsx` (line 29)

**Step 1: Update `Install.tsx`**

Find (line 50):
```typescript
const URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8765";
```
Replace with:
```typescript
const URL = process.env.NEXT_PUBLIC_API_URL || "";
```

**Step 2: Update `form-view.tsx`**

Find (line 29):
```typescript
const API_URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8765"
```
Replace with:
```typescript
const API_URL = process.env.NEXT_PUBLIC_API_URL || ""
```

Note: This file uses `API_URL` not `URL` — make sure to preserve the variable name.

**Step 3: Commit**

```bash
git add openmemory/ui/components/dashboard/Install.tsx openmemory/ui/components/form-view.tsx
git commit -m "fix: use relative API paths in Install and form-view components"
```

---

### Task 4: Remove NEXT_PUBLIC_API_URL from docker-compose.yml

**Files:**
- Modify: `openmemory/docker-compose.yml`

**Step 1: Remove the env var**

Find the `openmemory-ui` service environment section:

```yaml
  openmemory-ui:
    build:
      context: ui/
      dockerfile: Dockerfile
    image: mem0/openmemory-ui:latest
    ports:
      - "3000:3000"
    environment:
      - NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL}
      - NEXT_PUBLIC_USER_ID=${USER}
```

Change to:

```yaml
  openmemory-ui:
    build:
      context: ui/
      dockerfile: Dockerfile
    image: mem0/openmemory-ui:latest
    ports:
      - "3000:3000"
    environment:
      - NEXT_PUBLIC_USER_ID=${USER}
```

Only remove `NEXT_PUBLIC_API_URL`. Keep `NEXT_PUBLIC_USER_ID`.

**Step 2: Commit**

```bash
git add openmemory/docker-compose.yml
git commit -m "chore: remove NEXT_PUBLIC_API_URL from docker-compose"
```

---

### Task 5: Verify no remaining references

**Step 1: Search for remaining references**

```bash
cd openmemory
grep -rn 'NEXT_PUBLIC_API_URL\|"http://localhost:8765"' ui/ --include="*.ts" --include="*.tsx" --include="*.mjs" --include="*.js" | grep -v node_modules | grep -v .next
```

Expected: **No results** (all references removed).

If any remain, update them following the same pattern before continuing.

**Step 2: Final commit (if cleanup needed)**

```bash
git add -A
git commit -m "fix: remove remaining NEXT_PUBLIC_API_URL references"
```

---

## Testing Checklist

After all tasks are complete:

- [ ] `docker-compose build` succeeds
- [ ] `docker-compose up` starts both services
- [ ] Open UI from a non-localhost origin (e.g., LAN IP or deployed domain)
- [ ] Memories page loads without CORS errors (check browser console)
- [ ] Config page loads and saves
- [ ] Stats page loads
- [ ] MCP client can connect to `:8765/mcp/{client}/http/{user_id}` directly
- [ ] Create, update, delete memories work from UI
