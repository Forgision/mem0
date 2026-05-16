import { NextResponse } from "next/server"
import type { NextRequest } from "next/server"

export function middleware(request: NextRequest) {
  const apiUrl = process.env.NEXT_LOCAL_API_URL || "http://openmemory-mcp:8765"
  let pathname = request.nextUrl.pathname
  if (pathname.length > 1 && pathname.endsWith("/")) {
    pathname = pathname.slice(0, -1)
  }
  const destination = new URL(pathname, apiUrl)
  destination.search = request.nextUrl.search
  return NextResponse.rewrite(destination)
}

export const config = {
  matcher: "/api/:path*",
}
