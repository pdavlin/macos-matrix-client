// Matrix .well-known delegation for davlin.io (contract §11, S-17).
// Served at the Cloudflare edge so the website deploy pipeline stays out of
// the Matrix trust path. The TARGET below is the only value that changes on
// failover/migration (see docs/SYNAPSE-MIGRATION-PLAN.md).
const TARGET = "davlin-matrix.exe.xyz";

const SERVER = JSON.stringify({ "m.server": `${TARGET}:443` });
const CLIENT = JSON.stringify({ "m.homeserver": { "base_url": `https://${TARGET}` } });

function json(body, cors) {
  const headers = { "content-type": "application/json" };
  if (cors) headers["access-control-allow-origin"] = "*";
  return new Response(body, { headers });
}

export default {
  fetch(request) {
    const { pathname } = new URL(request.url);
    if (pathname === "/.well-known/matrix/server") return json(SERVER, false);
    if (pathname === "/.well-known/matrix/client") return json(CLIENT, true);
    return new Response("not found", { status: 404 });
  },
};
