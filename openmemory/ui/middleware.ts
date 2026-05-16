import { NextResponse } from "next/server"
import type { NextRequest } from "next/server"

export function middleware(request: NextRequest) {
  const apiUrl = process.env.NEXT_LOCAL_API_URL || "http://openmemory-mcp:8765"
  const destination = new URL(request.nextUrl.pathname, apiUrl)
  destination.search = request.nextUrl.search
  return NextResponse.rewrite(destination)
}

export const config = {
  matcher: "/api/:path*",
}
