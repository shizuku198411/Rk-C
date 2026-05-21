# userd

`userd` is the userspace account database server.
It owns user, group, and password lookup requests for tools such as `login`,
`id`, `chown`, and shell builtins.

## Responsibilities

- Initialize and load `/etc/passwd`
- Initialize and load `/etc/group`
- Initialize, load, and migrate `/etc/shadow`
- Resolve users by name or UID
- Resolve groups by name or GID
- Verify login passwords
- Update password hashes for allowed callers
- Notify `svcmgtd` with a service ready ACK after startup

## Database Files

`/etc/passwd` stores public account data:

```text
<username>:<uid>:<gid>:<home_dir>
```

`/etc/group` stores group data:

```text
<groupname>:<gid>:<member1,[member2,...]>
```

`/etc/shadow` stores password hashes and is chmodded to `0600`.
The current format is PBKDF2-HMAC-SHA256:

```text
<username>:pbkdf2-sha256:<iterations>:<salt_hex>:<hash_hex>
```

Default accounts are created when the database files do not exist:

- `root`, UID 0, GID 0, home `/`
- `user`, UID 1000, GID 1000, home `/home`

## Startup Flow

1. Wait for `svcmgtd` to register the user service slot
2. Ensure `/etc/passwd` exists, then load users
3. Ensure `/etc/shadow` exists, then load password hashes
4. Migrate missing or invalid default shadow entries
5. Ensure `/etc/group` exists, then load groups
6. Send `notifyServiceReady(SysServiceKindUser)`
7. Wait for IPC packets in a receive loop

## IPC Requests

- `SysIpcOpUserResolveNameRequest`
  - Request data contains the username
  - Replies with a public passwd line
- `SysIpcOpUserResolveUidRequest`
  - `arg0` contains the UID
  - Replies with a public passwd line
- `SysIpcOpGroupResolveNameRequest`
  - Request data contains the group name
  - Replies with a group line
- `SysIpcOpGroupResolveGidRequest`
  - `arg0` contains the GID
  - Replies with a group line
- `SysIpcOpUserAuthRequest`
  - Request data contains `username\0password\0`
  - Verifies the password against `/etc/shadow`
  - Replies with the public passwd line on success
- `SysIpcOpUserSetPasswordRequest`
  - `arg0` contains the target UID
  - Request data contains the new password
  - Root may update any user
  - A non-root caller may update only its own UID

## RKX Metadata

- `stack_pages = 4`
- capabilities: none
- allowed users: root only

`userd` does not need raw kernel capabilities for account operations. It relies
on normal filesystem access and IPC sender metadata injected by the kernel.

## Boundaries and Notes

- The in-memory user and group tables are fixed size
- Unknown IPC operations are ignored
- Password verification is intentionally centralized in `userd`
- `/etc/passwd` should remain public account data only; password material belongs
  in `/etc/shadow`
- The current implementation has no account creation command yet, but the file
  formats and server flow are prepared for it

## Related Files

- `userd.nim`: server implementation
- `rkx.toml`: RKX metadata
- `src/user/lib/core/userdb.nim`: userd client helpers
- `src/user/lib/core/passwd.nim`: passwd parser and formatter
- `src/user/lib/core/group.nim`: group parser and formatter
- `src/user/lib/core/shadow.nim`: shadow parser and formatter
- `src/user/lib/core/password_hash.nim`: password hashing helpers
