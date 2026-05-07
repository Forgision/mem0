import { NextRequest, NextResponse } from "next/server";
import { getServerApiUrl } from "@/lib/server-api-url";

const PROXY_HEADERS = ["authorization", "content-type", "accept"];

async function proxy(request: NextRequest): Promise<Response> {
  const path = request.nextUrl.pathname.replace(/^\/api\/?/, "");
  const search = request.nextUrl.search;
  const target = `${getServerApiUrl()}/${path}${search}`;

  const headers = new Headers();
  for (const name of PROXY_HEADERS) {
    const value = request.headers.get(name);
    if (value) headers.set(name, value);
  }

  const body =
    request.method === "GET" || request.method === "HEAD"
      ? undefined
      : await request.text();

  try {
    const upstream = await fetch(target, { method: request.method, headers, body });

    const resHeaders = new Headers();
    for (const [key, value] of upstream.headers.entries()) {
      resHeaders.set(key, value);
    }

    return new Response(upstream.body, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers: resHeaders,
    });
  } catch {
    return NextResponse.json({ error: "API proxy error" }, { status: 502 });
  }
}

export async function GET(request: NextRequest) {
  return proxy(request);
}
export async function POST(request: NextRequest) {
  return proxy(request);
}
export async function PUT(request: NextRequest) {
  return proxy(request);
}
export async function PATCH(request: NextRequest) {
  return proxy(request);
}
export async function DELETE(request: NextRequest) {
  return proxy(request);
}
