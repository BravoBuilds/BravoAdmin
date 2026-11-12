"use strict";

(() => {
  const loginView = document.getElementById("loginView");
  const adminView = document.getElementById("adminView");
  const loginForm = document.getElementById("loginForm");
  const loginMessage = document.getElementById("loginMessage");
  const keyRows = document.getElementById("keyRows");
  const keysError = document.getElementById("keysError");
  const resultCount = document.getElementById("resultCount");
  const searchInput = document.getElementById("searchInput");
  const statusFilter = document.getElementById("statusFilter");
  const createForm = document.getElementById("createForm");
  const createButton = document.getElementById("createButton");
  const createMessage = document.getElementById("createMessage");
  const expiryDialog = document.getElementById("expiryDialog");
  const expiryForm = document.getElementById("expiryForm");
  const expiryKeyLabel = document.getElementById("expiryKeyLabel");
  const toastElement = document.getElementById("toast");
  const supportedDurations = new Set(["24h", "7d", "30d", "90d", "180d", "365d"]);
  let keys = [];
  let selectedKey = "";
  let toastTimer;

  function showToast(message, isError = false) {
    toastElement.textContent = message;
    toastElement.classList.toggle("error", isError);
    toastElement.classList.remove("hidden");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastElement.classList.add("hidden"), 3500);
  }

  async function request(url, options = {}) {
    const response = await fetch(url, {
      cache: "no-store",
      credentials: "same-origin",
      ...options,
      headers: {
        ...(options.body ? { "Content-Type": "application/json" } : {}),
        ...options.headers,
      },
    });
    const type = response.headers.get("content-type") || "";
    if (!type.includes("application/json")) {
      throw new Error("The server returned an unexpected response.");
    }
    const result = await response.json();
    if (!response.ok || result.ok === false) {
      const messages = {
        LOGIN_REQUIRED: "Your session expired. Sign in again.",
        INVALID_CREDENTIALS: "Username or password is incorrect.",
        TOO_MANY_ATTEMPTS: "Too many sign-in attempts. Try again later.",
        KEY_API_UNREACHABLE: "Could not reach the key service. Check the server configuration.",
        INVALID_UPSTREAM_RESPONSE: "The key service returned an invalid response.",
      };
      throw new Error(result.message || messages[result.error] || result.error || "Request failed.");
    }
    return result;
  }

  function showAuthenticated(authenticated) {
    loginView.classList.toggle("hidden", authenticated);
    adminView.classList.toggle("hidden", !authenticated);
  }

  function unwrapKeys(response) {
    const candidates = [
      response.keys,
      response.data,
      response.data && response.data.keys,
      response.data && response.data.licenses,
      response.licenses,
      response.items,
      response.data && response.data.items,
    ];
    const list = candidates.find(Array.isArray);
    if (!list) {
      throw new Error("The key service response did not contain a key list.");
    }
    return list.map((record) => typeof record === "string" ? { key: record } : record)
      .filter((record) => record && typeof record === "object");
  }

  function getKeyValue(record) {
    const value = record.key ?? record.licenseKey ?? record.license ?? record.token ?? record.code ?? record.id ?? record.keyId;
    return value == null ? "" : String(value);
  }

  function getExpiry(record) {
    return record.expiresAt ?? record.expires_at ?? record.expiry ?? record.expiration ?? record.expires ?? null;
  }

  function getStatus(record) {
    const rawStatus = String(record.status || "").toLowerCase();
    if (record.revoked === true || record.isRevoked === true || rawStatus === "revoked" || rawStatus === "disabled") return "revoked";
    const expiry = getExpiry(record);
    if (expiry !== null && expiry !== undefined && expiry !== "") {
      const expiryTime = parseDate(expiry);
      if (Number.isFinite(expiryTime) && expiryTime <= Date.now()) return "expired";
    }
    if (rawStatus === "expired") return "expired";
    if (["active", "valid", "used", "unused", "available", "unclaimed"].includes(rawStatus)) return "active";
    return rawStatus || (record.isActive === false ? "unknown" : "active");
  }

  function parseDate(value) {
    if (typeof value === "number") return value < 1e12 ? value * 1000 : value;
    return new Date(value).getTime();
  }

  function formatExpiry(value) {
    if (value === null || value === undefined || value === "") return "No expiry";
    const timestamp = parseDate(value);
    const date = new Date(timestamp);
    if (!Number.isFinite(date.getTime())) return String(value);
    return new Intl.DateTimeFormat(undefined, {
      dateStyle: "medium",
      timeStyle: "short",
    }).format(date);
  }

  function makeCell(row, text, className) {
    const cell = document.createElement("td");
    cell.textContent = text;
    if (className) cell.className = className;
    row.append(cell);
    return cell;
  }

  function actionButton(label, callback, danger = false) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `button button-secondary small-button${danger ? " button-danger" : ""}`;
    button.textContent = label;
    button.addEventListener("click", callback);
    return button;
  }

  function renderKeys() {
    const query = searchInput.value.trim().toLowerCase();
    const wantedStatus = statusFilter.value;
    const filtered = keys.filter((record) => {
      const value = getKeyValue(record);
      const matchesQuery = !query || value.toLowerCase().includes(query)
        || String(record.userId ?? record.username ?? "").toLowerCase().includes(query);
      return matchesQuery && (wantedStatus === "all" || getStatus(record) === wantedStatus);
    });

    keyRows.replaceChildren();
    resultCount.textContent = `${filtered.length} of ${keys.length} key${keys.length === 1 ? "" : "s"}`;
    if (filtered.length === 0) {
      const row = document.createElement("tr");
      const cell = makeCell(row, keys.length ? "No keys match these filters." : "No keys found.", "empty-state");
      cell.colSpan = 5;
      keyRows.append(row);
      return;
    }

    for (const record of filtered) {
      const key = getKeyValue(record);
      const status = getStatus(record);
      const row = document.createElement("tr");
      const keyCell = document.createElement("td");
      const value = document.createElement("span");
      value.className = "key-value";
      value.textContent = key || "Key value unavailable";
      keyCell.append(value);
      if (key) keyCell.append(actionButton("Copy", async () => {
        try {
          await navigator.clipboard.writeText(key);
          showToast("Key copied to clipboard.");
        } catch {
          showToast("Could not access the clipboard. Copy the key manually.", true);
        }
      }));
      row.append(keyCell);

      const badgeCell = document.createElement("td");
      const badge = document.createElement("span");
      badge.className = `badge badge-${["active", "expired", "revoked"].includes(status) ? status : "unknown"}`;
      badge.textContent = status;
      badgeCell.append(badge);
      row.append(badgeCell);

      makeCell(row, formatExpiry(getExpiry(record)));
      const accountCount = record.accountCount ?? record.accountsUsed ?? record.usedAccounts ?? record.userCount;
      const accountLimit = record.maxAccounts ?? record.accountLimit ?? record.maxUsers;
      const accountText = accountCount == null && accountLimit == null
        ? (record.allowMultipleAccounts === true || record.multiUse === true ? "Multiple" : "Single")
        : `${accountCount ?? 0}${accountLimit == null ? "" : ` / ${accountLimit}`}`;
      makeCell(row, accountText);

      const actionsCell = document.createElement("td");
      const actions = document.createElement("span");
      actions.className = "row-actions";
      if (key && status !== "revoked") {
        actions.append(actionButton("Extend", () => {
          selectedKey = key;
          expiryKeyLabel.textContent = key;
          expiryDialog.showModal();
        }));
        actions.append(actionButton("Revoke", async () => {
          if (!window.confirm("Revoke this key? This action may not be reversible.")) return;
          try {
            await request("/api/keys", {
              method: "DELETE",
              body: JSON.stringify({ key }),
            });
            showToast("Key revoked.");
            await loadKeys();
          } catch (error) {
            showToast(error.message, true);
          }
        }, true));
      }
      actionsCell.append(actions);
      row.append(actionsCell);
      keyRows.append(row);
    }
  }

  function renderStats() {
    document.getElementById("totalCount").textContent = String(keys.length);
    document.getElementById("activeCount").textContent = String(keys.filter((key) => getStatus(key) === "active").length);
    document.getElementById("expiredCount").textContent = String(keys.filter((key) => getStatus(key) === "expired").length);
    document.getElementById("revokedCount").textContent = String(keys.filter((key) => getStatus(key) === "revoked").length);
  }

  async function loadKeys() {
    keysError.classList.add("hidden");
    keyRows.replaceChildren();
    const loadingRow = document.createElement("tr");
    const loadingCell = makeCell(loadingRow, "Loading keys…", "empty-state");
    loadingCell.colSpan = 5;
    keyRows.append(loadingRow);
    try {
      const response = await request("/api/keys");
      keys = unwrapKeys(response);
      renderStats();
      renderKeys();
    } catch (error) {
      keys = [];
      renderStats();
      keyRows.replaceChildren();
      const row = document.createElement("tr");
      const cell = makeCell(row, "Could not load keys.", "empty-state");
      cell.colSpan = 5;
      keyRows.append(row);
      keysError.textContent = error.message;
      keysError.classList.remove("hidden");
      resultCount.textContent = "Key list unavailable";
      if (error.message.startsWith("Your session expired")) {
        showAuthenticated(false);
        loginMessage.textContent = error.message;
      }
    }
  }

  loginForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    loginMessage.textContent = "";
    const button = loginForm.querySelector("button[type=submit]");
    button.disabled = true;
    try {
      await request("/api/login", {
        method: "POST",
        body: JSON.stringify({
          username: document.getElementById("username").value,
          password: document.getElementById("password").value,
        }),
      });
      loginForm.reset();
      showAuthenticated(true);
      await loadKeys();
    } catch (error) {
      loginMessage.textContent = error.message;
    } finally {
      button.disabled = false;
    }
  });

  createForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    createMessage.textContent = "";
    createMessage.classList.remove("error-text");
    createButton.disabled = true;
    try {
      const response = await request("/api/keys", {
        method: "POST",
        body: JSON.stringify({
          count: Number(document.getElementById("keyCount").value),
          duration: document.getElementById("keyDuration").value,
          allowMultipleAccounts: document.getElementById("multiAccount").checked,
        }),
      });
      const created = response.keys ?? response.data?.keys ?? response.data;
      const createdCount = Array.isArray(created) ? created.length : Number(response.count) || Number(document.getElementById("keyCount").value);
      createMessage.textContent = `Key service accepted the request for ${createdCount} key${createdCount === 1 ? "" : "s"}.`;
      showToast("Key creation request completed.");
      await loadKeys();
    } catch (error) {
      createMessage.textContent = error.message;
      createMessage.classList.add("error-text");
    } finally {
      createButton.disabled = false;
    }
  });

  expiryForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const duration = document.getElementById("expiryDuration").value;
    if (!selectedKey || !supportedDurations.has(duration)) {
      showToast("Choose a valid expiry duration.", true);
      return;
    }
    const submitButton = expiryForm.querySelector('button[type="submit"]');
    submitButton.disabled = true;
    try {
      await request("/api/keys", {
        method: "PATCH",
        body: JSON.stringify({ key: selectedKey, duration }),
      });
      expiryDialog.close();
      showToast("Key expiry updated.");
      await loadKeys();
    } catch (error) {
      showToast(error.message, true);
    } finally {
      submitButton.disabled = false;
    }
  });

  document.getElementById("cancelExpiry").addEventListener("click", () => expiryDialog.close());
  document.getElementById("refreshButton").addEventListener("click", loadKeys);
  searchInput.addEventListener("input", renderKeys);
  statusFilter.addEventListener("change", renderKeys);

  document.getElementById("logoutButton").addEventListener("click", async () => {
    try {
      await request("/api/logout", { method: "POST" });
      keys = [];
      showAuthenticated(false);
    } catch (error) {
      showToast(error.message, true);
    }
  });

  request("/api/session")
    .then(async (result) => {
      showAuthenticated(Boolean(result.authenticated));
      if (result.authenticated) await loadKeys();
    })
    .catch((error) => {
      showAuthenticated(false);
      loginMessage.textContent = error.message;
    });
})();
