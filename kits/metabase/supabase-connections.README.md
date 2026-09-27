# Supabase → Metabase (non-secret)

Read-only role: `metabase_ro` (password in gitignored `supabase-connections.env`).

## Juicd
- Pooler host: `aws-1-us-east-1.pooler.supabase.com`
- Port: `5432` (Session mode)
- Database: `postgres`
- User: `metabase_ro.hwyxtklbffqwcbtuetit`
- Role created: True

## Corvim
- Pooler host: `aws-0-us-west-2.pooler.supabase.com`
- Port: `5432`
- Database: `postgres`
- User: `metabase_ro.ptqrkpiiflihuhcfkutd`
- Role created: True

If pooler fails in Metabase, try Direct host `db.<ref>.supabase.co` with user `metabase_ro` (no ref suffix) port 5432.
