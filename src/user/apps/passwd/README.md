# passwd

`passwd` updates a user's password through `userd`.

## Usage

```text
passwd <user>
passwd --help
```

The command prompts for the new password twice. If both inputs match, it sends
the update request to `userd`, which hashes and stores the password in
`/etc/shadow`.

Root can update any account. Non-root users can update only their own account.
