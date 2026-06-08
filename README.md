# Remote Desktop Gateway

This directory stores the deployment files used for the self-hosted browser RDP gateway.

Current server-side adaptation:

- `Apache Guacamole + guacd + PostgreSQL` run in Docker
- `Caddy` provides HTTPS on `443`
- Existing `nginx.service` remains in place for the blog and still exposes `/guacamole/` over HTTP
- Guacamole is exposed through Nginx at `/guacamole/` and through Caddy on HTTPS
- Caddy root `/` now serves a custom access portal page from `portal/`
- Guacamole web binds to `127.0.0.1:8081`
- Reverse SSH tunnel ports stay on server loopback only

## Local structure

- `docker-compose.yml`: gateway container orchestration
- `caddy/Caddyfile`: HTTPS and reverse proxy rules
- `portal/index.html`: custom browser entry page
- `portal/styles.css`: portal visual styles

## Frontend entry

- `http://<server-ip>/gateway/` serves the public custom access portal page through Nginx
- `http://<server-ip>/guacamole/` opens the public Guacamole login
- `https://<server-ip>/` is still tied to the Caddy deployment, but the current stable public entry is the Nginx path above
- The portal is intentionally a branded entry layer; credential verification still happens in Guacamole
