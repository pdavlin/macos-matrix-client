# davlin.io Matrix well-known Worker

Serves the two delegation files for the Matrix server name `davlin.io`
(decided S-17, contract §11): `/.well-known/matrix/server` and `/client`
(the client file carries CORS `*`). The deployed values MUST match this
repo — the S-21 drift probe alerts on divergence.

Deploy (needs Cloudflare access to the davlin.io zone):

    cd infra/wellknown-worker
    npx wrangler deploy

Failover: change `TARGET` in `src/index.js`, redeploy. That is the
"repoint delegation" step in docs/SYNAPSE-MIGRATION-PLAN.md.

Verify after deploy, from any machine:

    curl https://davlin.io/.well-known/matrix/server
    curl -i https://davlin.io/.well-known/matrix/client   # expect CORS header
