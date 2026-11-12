"use strict";

const assert = require("node:assert/strict");
const http = require("node:http");
const { after, before, test } = require("node:test");

process.env.NODE_ENV = "development";
process.env.HOST = "127.0.0.1";
process.env.PORT = "0";
process.env.SITE_ADMIN_USER = "test-admin";
process.env.SITE_ADMIN_PASSWORD = "test-password-long-enough";
process.env.ADMIN_API_TOKEN = "test-worker-token";
process.env.WORKER_URL = "https://keys.example.test";

const { server } = require("../server");
const originalFetch = global.fetch;
let origin;
let cookie;
const workerCalls = [];

function request(path, { method = "GET", body, headers = {} } = {}) {
	return new Promise((resolve, reject) => {
		const url = new URL(path, origin);
		const serializedBody = body === undefined ? undefined : JSON.stringify(body);
		const req = http.request(url, {
			method,
			headers: {
				...(body === undefined ? {} : {
					"Content-Type": "application/json",
					"Content-Length": Buffer.byteLength(serializedBody),
				}),
				...headers,
			},
		}, (res) => {
			let raw = "";
			res.setEncoding("utf8");
			res.on("data", (chunk) => { raw += chunk; });
			res.on("end", () => {
				let data;
				try { data = JSON.parse(raw); } catch { data = raw; }
				resolve({ status: res.statusCode, headers: res.headers, data });
			});
		});
		req.on("error", reject);
		if (serializedBody !== undefined) req.write(serializedBody);
		req.end();
	});
}

before(async () => {
	await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
	origin = `http://127.0.0.1:${server.address().port}`;
	global.fetch = async (url, options) => {
		workerCalls.push({ url: new URL(url), options });
		if (options.method === "DELETE") return new Response(null, { status: 204 });
		return new Response(JSON.stringify({ ok: true, keys: [{ key: "TEST-KEY" }] }), {
			status: 200,
			headers: { "Content-Type": "application/json" },
		});
	};
});

after(async () => {
	global.fetch = originalFetch;
	await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
});

test("serves the admin page and keeps key APIs behind an authenticated session", async (t) => {
	const page = await request("/");
	assert.equal(page.status, 200);
	assert.match(String(page.headers["content-type"]), /text\/html/);
	assert.match(page.data, /Key management/);

	const unauthenticated = await request("/api/keys");
	assert.equal(unauthenticated.status, 401);
	assert.equal(workerCalls.length, 0);

	const badLogin = await request("/api/login", {
		method: "POST",
		headers: { Origin: origin },
		body: { username: "test-admin", password: "wrong-password" },
	});
	assert.equal(badLogin.status, 401);

	const login = await request("/api/login", {
		method: "POST",
		headers: { Origin: origin },
		body: { username: "test-admin", password: "test-password-long-enough" },
	});
	assert.equal(login.status, 200);
	cookie = String(login.headers["set-cookie"][0]).split(";")[0];

	await t.test("lists keys through the worker with a server-only token", async () => {
		const result = await request("/api/keys", { headers: { Cookie: cookie } });
		assert.equal(result.status, 200);
		assert.equal(result.data.keys[0].key, "TEST-KEY");
		assert.equal(workerCalls.at(-1).options.headers.Authorization, "Bearer test-worker-token");
	});

	await t.test("rejects invalid key creation before proxying", async () => {
		const beforeCalls = workerCalls.length;
		const result = await request("/api/keys", {
			method: "POST",
			headers: { Cookie: cookie, Origin: origin },
			body: { count: 501, duration: "30d" },
		});
		assert.equal(result.status, 400);
		assert.equal(workerCalls.length, beforeCalls);
	});

	await t.test("validates and proxies key creation", async () => {
		const result = await request("/api/keys", {
			method: "POST",
			headers: { Cookie: cookie, Origin: origin },
			body: { count: 2, duration: "30d", allowMultipleAccounts: true },
		});
		assert.equal(result.status, 200);
		assert.deepEqual(JSON.parse(workerCalls.at(-1).options.body), {
			count: 2,
			duration: "30d",
			allowMultipleAccounts: true,
		});
	});

	await t.test("updates expiry and handles an empty successful revoke response", async () => {
		const updated = await request("/api/keys", {
			method: "PATCH",
			headers: { Cookie: cookie, Origin: origin },
			body: { key: "TEST-KEY", duration: "90d" },
		});
		assert.equal(updated.status, 200);
		assert.equal(workerCalls.at(-1).url.searchParams.get("action"), "set_expiry");
		assert.equal(JSON.parse(workerCalls.at(-1).options.body).duration, "90d");

		const revoked = await request("/api/keys", {
			method: "DELETE",
			headers: { Cookie: cookie, Origin: origin },
			body: { key: "TEST-KEY" },
		});
		assert.equal(revoked.status, 200, JSON.stringify(revoked.data));
		assert.equal(revoked.data.ok, true);
		assert.equal(workerCalls.at(-1).url.searchParams.get("action"), "revoke");
	});

	await t.test("rejects cross-origin key changes", async () => {
		const beforeCalls = workerCalls.length;
		const result = await request("/api/keys", {
			method: "DELETE",
			headers: { Cookie: cookie, Origin: "https://attacker.example" },
			body: { key: "TEST-KEY" },
		});
		assert.equal(result.status, 403);
		assert.equal(workerCalls.length, beforeCalls);
	});

	const logout = await request("/api/logout", {
		method: "POST",
		headers: { Cookie: cookie, Origin: origin },
	});
	assert.equal(logout.status, 200);
	assert.equal((await request("/api/keys", { headers: { Cookie: cookie } })).status, 401);
});
