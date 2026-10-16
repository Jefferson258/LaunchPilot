# Supabase → Metabase (non-secret notes)

Create a read-only role (for example `metabase_ro`) in each Supabase project and
put its credentials in gitignored `supabase-connections.env` (template:
`supabase-connections.env.example`). Use one prefix per product; the prefix must
match `env_prefix` in `dashboards.local.json`.

Typical Session-pooler settings:

- Pooler host: `aws-0-<region>.pooler.supabase.com`
- Port: `5432` (Session mode)
- Database: `postgres`
- User: `metabase_ro.<project-ref>`
- SSL: required

If the pooler fails in Metabase, try the direct host `db.<project-ref>.supabase.co`
with user `metabase_ro` (no ref suffix) on port 5432.
