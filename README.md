[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/kanidm?utm_medium=integration&utm_source=button&utm_campaign=kanidm)

# Kanidm on Railway

A one-click [Railway](https://railway.com) template for [Kanidm](https://kanidm.com), the open-source identity management server (users, groups, passkeys, OAuth2/OpenID Connect, LDAP, RADIUS).

- **Kanidm:** 1.12.1, official image `kanidm/server:1.12.1@sha256:77198131f28116203e105d2e42214203757d113a694f35de545669e75db5c96f`
- **Proxy:** Caddy 2.11.9 (`caddy:2.11.9@sha256:4e2425f6009577e7c651010f16679c28f7d12df3e7b1914f941a7a3370746b3c`)
- **Shell:** static BusyBox 1.37.0 (the official Kanidm image has no shell)

## What it deploys

One service, built from this repo's `Dockerfile`, with a volume at `/data` (database, backups, config).

Kanidm only serves HTTPS, and Railway's edge talks to services over plain HTTP. So the container runs:

- `kanidmd`, listening on `127.0.0.1:8443` with a self-signed certificate that is regenerated on every boot (that hop never leaves the container);
- Caddy, listening on `PORT` (8080) and proxying to Kanidm. Railway's edge serves the public HTTPS certificate.

Railway's health check uses `/status`.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `KANIDM_DOMAIN` | `${{RAILWAY_PUBLIC_DOMAIN}}` | Kanidm's domain. WebAuthn/passkeys, OAuth2 and user names (`alice@YOUR-DOMAIN`) depend on it. |
| `PORT` | `8080` | Port Caddy listens on (the domain's target port). |

Optional: `KANIDM_ORIGIN` (defaults to `https://KANIDM_DOMAIN`), `KANIDM_LOG_LEVEL` (`info`), `KANIDM_BACKUP_SCHEDULE` (`00 22 * * *`, UTC), `KANIDM_BACKUP_VERSIONS` (`7`).

**Pick the domain before you add users.** If you want a custom domain, add it in Railway, set `KANIDM_DOMAIN` to it and redeploy *before* creating accounts. Changing the domain later invalidates passkeys and OAuth2 tokens and needs `kanidmd domain rename` (see the [Kanidm book](https://kanidm.github.io/kanidm/stable/)).

## First login

On first boot the start script gives the two built-in admin accounts random passwords and prints them **once** in the deploy logs:

- `admin`: server configuration;
- `idm_admin`: people and groups.

There are no default passwords. Then, on your computer, install the [Kanidm client tools](https://kanidm.github.io/kanidm/stable/installing_client_tools.html) and run:

```sh
kanidm login -H https://YOUR-DOMAIN -D idm_admin
kanidm person create alice "Alice" -H https://YOUR-DOMAIN -D idm_admin
kanidm person credential create-reset-token alice -H https://YOUR-DOMAIN -D idm_admin
```

The person opens the reset link to set a password or passkey, then signs in at `https://YOUR-DOMAIN/ui`.

Lost a password? Reset it from the Railway CLI: `railway ssh -- kanidmd recover-account idm_admin` (or `admin`).

## LDAPS (optional)

LDAP is off. To use it, set `KANIDM_LDAPBINDADDRESS=0.0.0.0:3636` and add a Railway TCP proxy to port 3636. LDAPS then uses the container's self-signed certificate, which is regenerated on every boot, so LDAP clients must skip certificate verification. Treat it as an evaluation feature.

## Updates

This template builds from this repository. When a new Kanidm release is tested, the pinned image is bumped on `main` and Railway shows an "update available" notice in your project; you choose when to apply it. Read `CHANGELOG.md` before you do. Kanidm upgrades one minor version at a time, so don't skip releases.

## Licence

The wrapper files are MIT. Kanidm is MPL-2.0.
