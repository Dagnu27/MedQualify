# MedQualify

CareAudit stores inspection drafts and completed reports in the shared server database, associated with the signed-in inspector account. Inspectors can continue their saved work from another device by signing in with the same account. Browser-only inspections from earlier versions are uploaded the next time that browser signs in.

## Persistent database storage

The app uses SQLite at `backend/server/data/careaudit.sqlite` by default. Local Docker deployments mount that directory as a volume. Production deployments must also attach persistent storage to the server and mount it at `/app/backend/server/data`; otherwise the SQLite file can be lost when the service is restarted or redeployed. If the persistent disk is mounted elsewhere, set `DATABASE_PATH` to a file on that disk.

The hosted app is available at https://medqualify.onrender.com/.
