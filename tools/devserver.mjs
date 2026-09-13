import http from "node:http";
import fs from "node:fs";
import path from "node:path";

/// Development server for the two front ends.
///
/// Static files with a fall-back to `shared/`, and `/api` proxied to the API
/// process so the browser sees a single origin — without that, cookies would
/// not be sent and every signed-in page would look signed out in development
/// but work in production, which is a miserable class of bug to chase.
///
/// No dependencies on purpose: `npm install` has nothing to do, so a checkout
/// runs immediately and there is no lockfile to keep current.
const root = path.resolve(process.argv[2] ?? ".");
const shared = path.resolve(process.env.SHARED_DIR ?? path.join(root, "..", "shared"));
const port = Number(process.env.PORT ?? 3000);
const api = process.env.API_URL ?? "http://localhost:8787";

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".webp": "image/webp",
  ".ico": "image/x-icon",
};

function resolve(pathname) {
  const clean = path.normalize(decodeURIComponent(pathname)).replace(/^(\.\.[/\\])+/, "");
  const candidates = [
    path.join(root, clean),
    path.join(root, clean, "index.html"),
    path.join(shared, clean),
  ];
  for (const file of candidates) {
    // Never serve outside the two directories this server owns.
    if (!file.startsWith(root) && !file.startsWith(shared)) continue;
    if (fs.existsSync(file) && fs.statSync(file).isFile()) return file;
  }
  return null;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${port}`);

  if (url.pathname.startsWith("/api/") || url.pathname === "/download") {
    try {
      const body = ["GET", "HEAD"].includes(req.method) ? undefined : await readBody(req);
      const upstream = await fetch(api + url.pathname + url.search, {
        method: req.method,
        headers: { ...req.headers, host: new URL(api).host },
        body,
        redirect: "manual",
      });
      const headers = Object.fromEntries(upstream.headers.entries());
      delete headers["content-encoding"];
      delete headers["content-length"];
      res.writeHead(upstream.status, headers);
      res.end(Buffer.from(await upstream.arrayBuffer()));
    } catch {
      res.writeHead(502, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: `The API is not running. Start it with: cd server && npm run dev` }));
    }
    return;
  }

  const file = resolve(url.pathname === "/" ? "/index.html" : url.pathname);
  if (!file) {
    res.writeHead(404, { "content-type": "text/plain" });
    return res.end("Not found");
  }
  res.writeHead(200, {
    "content-type": TYPES[path.extname(file)] ?? "application/octet-stream",
    "cache-control": "no-store",
  });
  fs.createReadStream(file).pipe(res);
});

const readBody = (req) =>
  new Promise((resolve) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => resolve(Buffer.concat(chunks)));
  });

server.listen(port, () => {
  console.log(`  ${path.basename(root)} → http://localhost:${port}`);
  console.log(`  api proxied to ${api}\n`);
});
