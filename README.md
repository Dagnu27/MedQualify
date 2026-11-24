# MedQualify

CareAudit stores inspection drafts and completed reports in the shared server database, associated with the signed-in inspector account. Inspectors can continue their saved work from another device by signing in with the same account. Browser-only inspections from earlier versions are uploaded the next time that browser signs in.

## Persistent database storage

The app uses SQLite at `backend/server/data/careaudit.sqlite` by default. Local Docker deployments mount that directory as a volume. Production deployments must also attach persistent storage to the server and mount it at `/app/backend/server/data`; otherwise the SQLite file can be lost when the service is restarted or redeployed. If the persistent disk is mounted elsewhere, set `DATABASE_PATH` to a file on that disk.

The hosted app is available at https://medqualify.onrender.com/.

## Production deployment

Build and run the combined web/API service with Docker:

```sh
docker build -t careaudit .
docker run --rm -p 3000:3000 \
  -e NODE_ENV=production \
  -e ADMIN_USERNAME=admin \
  -e ADMIN_PASSWORD='replace-with-a-strong-password' \
  -v careaudit-data:/app/backend/server/data \
  careaudit
```

Set `DATABASE_PATH` when the SQLite file should live outside the default data directory. Mount a persistent volume or disk at the configured database location.

For Render, attach a persistent disk at `/app/backend/server/data` and configure `ADMIN_PASSWORD` before the first database initialization.

## Docker on Windows

After Docker Desktop is installed, start the complete web/API service and persistent SQLite volume:

```powershell
set ADMIN_PASSWORD=replace-with-a-strong-password
npm run docker:up
npm run docker:health
```

Docker Compose uses `restart: unless-stopped`, so the container restarts after it exits or the computer restarts. Docker Desktop must still be configured to start with Windows.

To run without Docker, register the server to start automatically at Windows boot:

```powershell
npm run server:autostart
```

The Windows scheduled task runs as `SYSTEM`, restarts after failures, and starts after Windows startup.
