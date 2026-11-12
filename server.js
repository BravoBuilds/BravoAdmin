"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");

const ROOT = __dirname;
const PUBLIC_DIR = path.join(ROOT, "public");
const SESSION_TTL_MS = 8 * 60 * 60 * 1000;
const MAX_BODY_BYTES = 32 * 1024;
const KEY_DURATIONS = new Set(["24h", "7d", "30d", "90d", "180d", "365d"]);
const sessions = new Map();
const loginAttempts = new Map();

function loadEnv(file) {
	if (!fs.existsSync(file)) return;
	for (const rawLine of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
		const line = rawLine.trim();
		if (!line || line.startsWith("#")) continue;
		const separator = line.indexOf("=");
		if (separator < 1) continue;
		const key = line.slice(0, separator).trim();
		let value = line.slice(separator + 1).trim();
		if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
			value = value.slice(1, -1);
		}
		if (process.env[key] === undefined) process.env[key] = value;
	}
}

loadEnv(path.join(ROOT, ".env"));

const IS_PRODUCTION = process.env.NODE_ENV === "production";
const HOST = process.env.HOST || "127.0.0.1";
const PORT = Number(process.env.PORT || 4173);
const ADMIN_USER = process.env.SITE_ADMIN_USER || "";
const ADMIN_PASSWORD = process.env.SITE_ADMIN_PASSWORD || "";
const ADMIN_API_TOKEN = process.env.ADMIN_API_TOKEN || "";
const WORKER_URL = process.env.WORKER_URL || "";
const PUBLIC_HOSTNAMES = String(process.env.SITE_PUBLIC_HOSTNAMES || "")
	.split(",")
	.map((host) => host.trim().toLowerCase())
	.filter(Boolean);

function json(res, status, body) {
	res.writeHead(status, {
		"Content-Type": "application/json; charset=utf-8",
		"Cache-Control": "no-store",
	});
	res.end(JSON.stringify(body));
}

function text(res, status, body) {
	res.writeHead(status, {
		"Content-Type": "text/plain; charset=utf-8",
		"Cache-Control": "no-store",
	});
	res.end(body);
}

function safeEqual(left, right) {
	const a = Buffer.from(String(left), "utf8");
	const b = Buffer.from(String(right), "utf8");
	const size = Math.max(a.length, b.length, 1);
	const paddedA = Buffer.alloc(size);
	const paddedB = Buffer.alloc(size);
	a.copy(paddedA);
	b.copy(paddedB);
	const equal = crypto.timingSafeEqual(paddedA, paddedB);
	return equal && a.length === b.length;
}

function requestHostname(req) {
	try {
		return new URL("http://" + String(req.headers.host || "")).hostname.toLowerCase();
	} catch {
		return "";
	}
}

function isAllowedHost(req) {
	const hostname = requestHostname(req);
	if (PUBLIC_HOSTNAMES.length) return PUBLIC_HOSTNAMES.includes(hostname);
	return !IS_PRODUCTION && ["localhost", "127.0.0.1", "::1"].includes(hostname);
}

function isLoopback(req) {
	return ["127.0.0.1", "::1", "::ffff:127.0.0.1"].includes(req.socket.remoteAddress);
}

function sameOrigin(req) {
	if (!req.headers.origin) return !IS_PRODUCTION && isLoopback(req);
	try {
		const origin = new URL(req.headers.origin);
		return (origin.protocol === "http:" || origin.protocol === "https:")
			&& origin.host.toLowerCase() === String(req.headers.host || "").toLowerCase();
	} catch {
		return false;
	}
}

function parseCookies(req) {
	const cookies = new Map();
	for (const part of String(req.headers.cookie || "").split(";")) {
		const separator = part.indexOf("=");
		if (separator < 0) continue;
		try {
			cookies.set(part.slice(0, separator).trim(), decodeURIComponent(part.slice(separator + 1).trim()));
		} catch {
			continue;
		}
	}
	return cookies;
}

function currentSession(req) {
	const token = parseCookies(req).get("bravoadmin");
	const expiresAt = token && sessions.get(token);
	if (!expiresAt || expiresAt <= Date.now()) {
		if (token) sessions.delete(token);
		return null;
	}
	return token;
}

function requireSession(req, res) {
	if (currentSession(req)) return true;
	json(res, 401, { ok: false, error: "LOGIN_REQUIRED" });
	return false;
}

function sessionCookie(token, maxAge) {
	const secure = IS_PRODUCTION ? "; Secure" : "";
	return `bravoadmin=${encodeURIComponent(token)}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${maxAge}${secure}`;
}

function readBody(req) {
	return new Promise((resolve, reject) => {
		let body = "";
		let bytes = 0;
		req.setEncoding("utf8");
		req.on("data", (chunk) => {
			bytes += Buffer.byteLength(chunk);
			if (bytes > MAX_BODY_BYTES) {
				reject(new Error("Request body is too large."));
				req.resume();
				return;
			}
			body += chunk;
		});
		req.on("end", () => {
			if (bytes > MAX_BODY_BYTES) return;
			try {
				const parsed = body ? JSON.parse(body) : {};
				if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
					throw new Error("Expected a JSON object.");
				}
				resolve(parsed);
			} catch {
				reject(new Error("Invalid JSON request body."));
			}
		});
		req.on("error", reject);
	});
}

async function readJsonBody(req, res) {
	try {
		return await readBody(req);
	} catch (error) {
		json(res, 400, { ok: false, error: "BAD_REQUEST", message: error.message });
		return null;
	}
}

function jsonFile(res, filename, contentType) {
	try {
		const file = path.join(PUBLIC_DIR, filename);
		res.writeHead(200, {
			"Content-Type": contentType,
			"Cache-Control": "no-store",
			"Content-Length": fs.statSync(file).size,
		});
		fs.createReadStream(file).pipe(res);
	} catch {
		text(res, 500, "Admin page file is unavailable.");
	}
}

function validatedWorkerEndpoint() {
	const base = new URL(WORKER_URL);
	if (base.protocol !== "https:") throw new Error("WORKER_URL must use HTTPS.");
	return new URL("/api/admin/keys", base);
}

async function proxyKeyRequest(res, method, body, key, action) {
	let endpoint;
	try {
		endpoint = validatedWorkerEndpoint();
	} catch {
		json(res, 500, { ok: false, error: "INVALID_WORKER_URL" });
		return;
	}
	if (key) endpoint.searchParams.set("key", key);
	if (action) endpoint.searchParams.set("action", action);

	const headers = {
		Accept: "application/json",
		Authorization: `Bearer ${ADMIN_API_TOKEN}`,
	};
	const options = {
		method,
		headers,
		signal: AbortSignal.timeout(15000),
	};
	if (body !== undefined) {
		headers["Content-Type"] = "application/json";
		options.body = JSON.stringify(body);
	}

	try {
		const upstream = await fetch(endpoint, options);
		if (upstream.status === 204) {
			json(res, 200, { ok: true });
			return;
		}
		const raw = await upstream.text();
		let data;
		try {
			data = JSON.parse(raw);
		} catch {
			json(res, 502, { ok: false, error: "INVALID_UPSTREAM_RESPONSE" });
			return;
		}
		json(res, upstream.status, data);
	} catch (error) {
		console.error("BravoAdmin key API request failed:", error.message);
		json(res, 502, { ok: false, error: "KEY_API_UNREACHABLE" });
	}
}

function clientAddress(req) {
	return req.socket.remoteAddress || "unknown";
}

function loginLimitExceeded(address) {
	const now = Date.now();
	let attempts = loginAttempts.get(address);
	if (!attempts || attempts.resetAt <= now) {
		attempts = { count: 0, resetAt: now + 15 * 60 * 1000 };
		loginAttempts.set(address, attempts);
	}
	return attempts.count >= 10;
}

async function handleLogin(req, res) {
	if (!sameOrigin(req)) {
		json(res, 403, { ok: false, error: "BAD_ORIGIN" });
		return;
	}
	const address = clientAddress(req);
	if (loginLimitExceeded(address)) {
		json(res, 429, { ok: false, error: "TOO_MANY_ATTEMPTS" });
		return;
	}
	const body = await readJsonBody(req, res);
	if (!body) return;
	const username = typeof body.username === "string" ? body.username : "";
	const password = typeof body.password === "string" ? body.password : "";
	if (!safeEqual(username, ADMIN_USER) || !safeEqual(password, ADMIN_PASSWORD)) {
		loginAttempts.get(address).count += 1;
		json(res, 401, { ok: false, error: "INVALID_CREDENTIALS" });
		return;
	}
	loginAttempts.delete(address);
	const token = crypto.randomBytes(32).toString("hex");
	sessions.set(token, Date.now() + SESSION_TTL_MS);
	res.setHeader("Set-Cookie", sessionCookie(token, SESSION_TTL_MS / 1000));
	json(res, 200, { ok: true });
}

async function handleKeyRequest(req, res, url) {
	if (!requireSession(req, res)) return;
	if (req.method === "GET") {
		await proxyKeyRequest(res, "GET");
		return;
	}
	if (!sameOrigin(req)) {
		json(res, 403, { ok: false, error: "BAD_ORIGIN" });
		return;
	}

	if (req.method === "POST") {
		const body = await readJsonBody(req, res);
		if (!body) return;
		const count = Number(body.count);
		const duration = String(body.duration || "");
		if (!Number.isInteger(count) || count < 1 || count > 500) {
			json(res, 400, { ok: false, error: "INVALID_COUNT", message: "Choose between 1 and 500 keys." });
			return;
		}
		if (!KEY_DURATIONS.has(duration)) {
			json(res, 400, { ok: false, error: "INVALID_DURATION", message: "Choose a supported key duration." });
			return;
		}
		await proxyKeyRequest(res, "POST", {
			count,
			duration,
			allowMultipleAccounts: body.allowMultipleAccounts === true,
		});
		return;
	}

	if (req.method === "PATCH") {
		const body = await readJsonBody(req, res);
		if (!body) return;
		const key = typeof body.key === "string" ? body.key.trim() : "";
		const duration = String(body.duration || "");
		if (!key || key.length > 256 || !KEY_DURATIONS.has(duration)) {
			json(res, 400, { ok: false, error: "INVALID_UPDATE", message: "Provide a key and supported duration." });
			return;
		}
		await proxyKeyRequest(res, "PATCH", { key, action: "set_expiry", duration }, key, "set_expiry");
		return;
	}

	if (req.method === "DELETE") {
		const body = await readJsonBody(req, res);
		if (!body) return;
		const key = typeof body.key === "string" ? body.key.trim() : "";
		if (!key || key.length > 256) {
			json(res, 400, { ok: false, error: "INVALID_KEY" });
			return;
		}
		await proxyKeyRequest(res, "DELETE", undefined, key, "revoke");
		return;
	}

	json(res, 405, { ok: false, error: "METHOD_NOT_ALLOWED" });
}

const server = http.createServer(async (req, res) => {
	res.setHeader("X-Content-Type-Options", "nosniff");
	res.setHeader("X-Frame-Options", "DENY");
	res.setHeader("Referrer-Policy", "no-referrer");
	res.setHeader("Content-Security-Policy", "default-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'; form-action 'self'; object-src 'none'");

	if (!isAllowedHost(req)) {
		text(res, 421, "This hostname is not configured.");
		return;
	}
	if (IS_PRODUCTION && String(req.headers["x-forwarded-proto"] || "").split(",")[0].trim().toLowerCase() !== "https") {
		text(res, 426, "HTTPS is required.");
		return;
	}

	let url;
	try {
		url = new URL(req.url || "/", `http://${req.headers.host}`);
	} catch {
		json(res, 400, { ok: false, error: "BAD_URL" });
		return;
	}

	if (req.method === "GET" && ["/", "/admin", "/admin/"].includes(url.pathname)) {
		jsonFile(res, "admin.html", "text/html; charset=utf-8");
		return;
	}
	if (req.method === "GET" && url.pathname === "/admin.css") {
		jsonFile(res, "admin.css", "text/css; charset=utf-8");
		return;
	}
	if (req.method === "GET" && url.pathname === "/admin.js") {
		jsonFile(res, "admin.js", "text/javascript; charset=utf-8");
		return;
	}
	if (req.method === "GET" && url.pathname === "/api/session") {
		json(res, 200, { ok: true, authenticated: Boolean(currentSession(req)) });
		return;
	}
	if (req.method === "POST" && url.pathname === "/api/login") {
		await handleLogin(req, res);
		return;
	}
	if (req.method === "POST" && url.pathname === "/api/logout") {
		if (!sameOrigin(req)) {
			json(res, 403, { ok: false, error: "BAD_ORIGIN" });
			return;
		}
		const token = currentSession(req);
		if (token) sessions.delete(token);
		res.setHeader("Set-Cookie", sessionCookie("", 0));
		json(res, 200, { ok: true });
		return;
	}
	if (url.pathname === "/api/keys" && ["GET", "POST", "PATCH", "DELETE"].includes(req.method)) {
		await handleKeyRequest(req, res, url);
		return;
	}
	json(res, 404, { ok: false, error: "NOT_FOUND" });
});

function validateConfiguration() {
	if (!Number.isInteger(PORT) || PORT < 1 || PORT > 65535) throw new Error("PORT must be a valid TCP port.");
	if (!ADMIN_USER || ADMIN_PASSWORD.length < 14) {
		throw new Error("Set SITE_ADMIN_USER and a SITE_ADMIN_PASSWORD of at least 14 characters.");
	}
	if (!ADMIN_API_TOKEN) throw new Error("Set ADMIN_API_TOKEN before starting BravoAdmin.");
	try {
		if (new URL(WORKER_URL).protocol !== "https:") throw new Error();
	} catch {
		throw new Error("Set WORKER_URL to a valid HTTPS key API URL.");
	}
	if (IS_PRODUCTION && !PUBLIC_HOSTNAMES.length) {
		throw new Error("Set SITE_PUBLIC_HOSTNAMES before production startup.");
	}
}

if (require.main === module) {
	try {
		validateConfiguration();
		server.listen(PORT, HOST, () => {
			console.log(`BravoAdmin listening on http://${HOST}:${PORT}`);
		});
	} catch (error) {
		console.error("BravoAdmin configuration error:", error.message);
		process.exitCode = 1;
	}
}

module.exports = { server, validateConfiguration };
