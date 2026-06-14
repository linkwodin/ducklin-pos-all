import * as fs from "fs";
import * as path from "path";
import * as jwt from "jsonwebtoken";
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const jwtSecret = defineSecret("JWT_SECRET");

let playbookBody: string | null = null;

function loadPlaybook(): string {
  if (playbookBody === null) {
    const mdPath = path.join(__dirname, "assets", "ai-playbook-wholesale-po-to-order.md");
    playbookBody = fs.readFileSync(mdPath, "utf8");
  }
  return playbookBody;
}

/**
 * Cross-origin browser fetch sends Authorization → preflight OPTIONS must echo Allow-* headers.
 * Firebase Gen2 cors: true does not always cover this; set explicitly. Same-origin Hosting rewrite
 * (/api/ai-playbook) avoids preflight entirely.
 */
function applyCors(req: { headers: { origin?: string | string[] } }, res: { setHeader: (k: string, v: string) => void }): void {
  const raw = req.headers.origin;
  const origin = typeof raw === "string" ? raw : Array.isArray(raw) ? raw[0] : "";
  if (origin.length > 0) {
    const allowed =
      /\.web\.app$/i.test(origin) ||
      /\.firebaseapp\.com$/i.test(origin) ||
      origin.includes("storage.googleapis.com") ||
      /^http:\/\/localhost(?::\d+)?$/i.test(origin) ||
      /^http:\/\/127\.0\.0\.1(?::\d+)?$/i.test(origin);
    if (allowed) {
      res.setHeader("Access-Control-Allow-Origin", origin);
      res.setHeader("Access-Control-Allow-Credentials", "true");
    }
  }
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Authorization, Content-Type");
  res.setHeader("Access-Control-Max-Age", "3600");
  res.setHeader("Vary", "Origin");
}

/**
 * GET only. Requires Authorization: Bearer <same JWT as POS/management API>.
 * Markdown is bundled at deploy time (sync from repo docs/); no database.
 */
export const aiPlaybook = onRequest(
  {
    region: "europe-west1",
    secrets: [jwtSecret],
  },
  (req, res): void => {
    applyCors(req, res);
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "GET") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    const raw = req.headers.authorization || "";
    const token = raw.startsWith("Bearer ") ? raw.slice(7).trim() : "";
    if (!token) {
      res.status(401).json({ error: "Authorization required" });
      return;
    }

    const secret = jwtSecret.value();
    try {
      jwt.verify(token, secret, { algorithms: ["HS256"] });
    } catch {
      res.status(401).json({ error: "Invalid or expired token" });
      return;
    }

    try {
      const body = loadPlaybook();
      res.setHeader("Content-Type", "text/markdown; charset=utf-8");
      res.setHeader("Cache-Control", "private, no-store");
      res.status(200).send(body);
    } catch (e) {
      console.error("aiPlaybook: failed to load markdown", e);
      res.status(500).json({ error: "Playbook unavailable" });
    }
  }
);
