# BravoAdmin

BravoAdmin is a standalone Roblox administration interface. It uses the dark navy, blue, and mint visual direction of the supplied website files, rebuilt as a responsive Roblox GUI. It does not contain BravoHack, ESP, aimbot, or other cheat features.

## Important: installation and security

Roblox does not support `loadstring(game:HttpGet(...))()` as a normal in-experience client loader. That pattern depends on an external script executor; it cannot securely install server scripts or grant permissions. BravoAdmin deliberately does not provide an executor loader. A client-only script must never be treated as an authority for moderation.

Install both scripts in Roblox Studio:

1. Copy `Server/BravoAdminServer.server.lua` into **ServerScriptService** as a normal **Script**.
2. Copy `Main.lua` into **StarterPlayer > StarterPlayerScripts** as a **LocalScript**.
3. In `BravoAdminServer.server.lua`, add trusted Roblox account IDs to `OwnerUserIds` and/or `UserRoles`. Use numeric user IDs, not usernames. The experience creator automatically has the Owner role when the experience is owned by an individual account.
4. Publish the experience and enable **Game Settings > Security > Enable Studio Access to API Services** when testing DataStore bans in Studio. In a live server, DataStore access is required for ban and unban actions.
5. Test first in a private test experience. Keep the server script and role list under control of trusted developers.

The server creates the `ReplicatedStorage.BravoAdminRemotes` remotes itself. It authorizes every snapshot and action on the server, validates arguments, and rate-limits requests. Editing or invoking the client interface does not grant a role.

## Admin roles

Configure these in the server script:

| Role | Permissions |
| --- | --- |
| Owner | View dashboard, kick, ban, unban, view logs, change server settings |
| Admin | View dashboard, kick, ban, unban, view logs |
| Moderator | View dashboard, kick, view logs |

Example configuration:

```lua
OwnerUserIds = { 123456789 },
UserRoles = {
    [987654321] = "Admin",
    [456789123] = "Moderator",
},
```

The experience creator receives Owner automatically for user-owned experiences. For group-owned experiences, add trusted users explicitly. Roles are server configuration, not editable by clients.
Moderators and administrators cannot kick or ban themselves or a peer/higher role; an administrator may moderate lower roles.

## Interface and commands

- **Dashboard:** live player count, server uptime, place/job IDs, recent actions.
- **Players:** searchable online-player list; kick; ban or unban by Roblox user ID.
- **Commands:** `!help`, `!server`, `!kick <player> [reason]`, `!ban <userId> [reason]`, `!unban <userId>`.
- **Settings:** owner-only switch for moderation notices (resets when the server restarts) and role permission reference.
- **Logs:** latest 100 moderation/settings actions for the current server session.

Ban records are stored in the `BravoAdminBans_v1` DataStore and survive server restarts. If the ban store cannot be checked when a player joins, the server denies entry until the ban status can be verified; this is intentionally fail-closed. Action logs and the broadcast-notice setting are server-session-only.

To close the interface, use the **×** button. Starting the LocalScript again first unloads its prior interface and event connections.

## Source / loadstring

`Main.lua` is the client entry point, but it must run as a Roblox `LocalScript`; the server script must be installed separately in `ServerScriptService`. A raw GitHub URL or client loadstring cannot install or secure the server component. Do not use a client executor to run it.

## Validation status

The project is source code intended to be copied into Roblox Studio. No live Roblox place, DataStore, or multiplayer server was available in this repository environment.

- Checked against the supplied archive’s admin page and theme for relevant copy/style direction.
- Verified the design and action paths are split between client UI and server permission checks by inspection.
- Both Lua files passed syntax compilation with the official Luau compiler.
- Multiplayer permission tests, DataStore ban/unban tests, and device/resolution checks still need to be run in Roblox Studio.