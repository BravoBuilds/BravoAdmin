# BravoAdmin

BravoAdmin is a web-based admin page for managing access keys, based on the dark navy and blue design in the supplied archive. It includes a protected sign-in, a key list with search/filtering, key creation, expiry updates, and revocation.

## Run locally

Requirements: Node.js 18 or newer.

1. Copy `.env.example` to `.env`.
2. Set `SITE_ADMIN_USER`, `SITE_ADMIN_PASSWORD` (at least 14 characters), `ADMIN_API_TOKEN`, and `WORKER_URL` to your own values.
3. Run `node server.js`.
4. Open `http://127.0.0.1:4173`.

The admin session is held in an HttpOnly, SameSite cookie. The worker token remains server-side and is never sent to the browser. The Node server proxies key operations to `WORKER_URL` at `/api/admin/keys`; it does not store or invent keys itself.

## Key actions

- List keys from the configured key API.
- Create 1–500 keys with a supported duration and optional multi-account use.
- Search and filter the returned key records.
- Copy a key value, update its expiry, or revoke it.

The configured worker must support `GET`, `POST`, `PATCH`, and `DELETE` on `/api/admin/keys` with the expected bearer token. The UI displays an explicit error if the worker is unavailable or returns an unrecognized key-list shape.

## Production

Set `NODE_ENV=production` and `SITE_PUBLIC_HOSTNAMES` to the exact public hostname(s). Keep the Node server behind an HTTPS reverse proxy. Use unique secrets, do not commit `.env`, and restrict access to the server and key API credentials. Login sessions are in memory and will expire when the process restarts.

## Validation

Run `node --check server.js`, `node --check public/admin.js`, and `node --test`. The tests use a mocked worker to verify session protection, server-only token forwarding, request validation, and origin checks. A real key list/create/update/revoke operation requires the configured worker endpoint and credentials.
