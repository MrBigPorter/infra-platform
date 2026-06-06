// ==========================================
// Grafana Auth Proxy — JWT Token Validation Service
// ==========================================
// Nginx auth_request calls this endpoint to validate signed tokens.
// If valid → returns 200 + email in header
// If invalid/expired → returns 401
//
// Two routes supported:
//   1. GET /auth/validate-token/:token  — token in URL path (primary, for Nginx auth_request)
//   2. GET /auth/validate-token         — token via X-Token header (for direct testing)
// ==========================================

const express = require('express');
const jwt = require('jsonwebtoken');

const app = express();
const PORT = 3002;
const SECRET = process.env.GRAFANA_AUTH_SECRET;

if (!SECRET) {
  console.error('FATAL: GRAFANA_AUTH_SECRET environment variable is required');
  process.exit(1);
}

// Add request logging middleware
app.use((req, _res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.path} | headers:`, JSON.stringify({
    'x-token': req.headers['x-token'] ? `${req.headers['x-token'].substring(0, 30)}...` : undefined,
    params: req.params,
    host: req.headers.host,
  }));
  next();
});

// Health check for Nginx / Docker
app.get('/health', (_req, res) => {
  res.json({ status: 'ok' });
});

// ---- Primary: Token in URL path (for Nginx auth_request subrequest) ----
// Nginx regex location captures JWT in path, proxy_pass (without URI) forwards the
// full path to this service. No Nginx variable scoping issues.
app.get('/auth/validate-token/:token', (req, res) => {
  const token = req.params.token;

  if (!token) {
    console.log('  => No token param, returning 401');
    return res.sendStatus(401);
  }

  try {
    const decoded = jwt.verify(token, SECRET);
    console.log(`  => Valid token (path) for email: ${decoded.email}`);
    res.set('X-Email', decoded.email);
    res.json({ email: decoded.email });
  } catch (err) {
    console.log(`  => Invalid token (path): ${err.message}`);
    res.sendStatus(401);
  }
});

// ---- Secondary: Token via query string or X-Token header ----
app.get('/auth/validate-token', (req, res) => {
  const token = req.query.token || req.headers['x-token'];

  if (!token) {
    console.log('  => No token (query or header), returning 401');
    return res.sendStatus(401);
  }

  try {
    const decoded = jwt.verify(token, SECRET);
    const source = req.query.token ? 'query' : 'header';
    console.log(`  => Valid token (${source}) for email: ${decoded.email}`);
    res.set('X-Email', decoded.email);
    res.json({ email: decoded.email });
  } catch (err) {
    console.log(`  => Invalid token: ${err.message}`);
    res.sendStatus(401);
  }
});

app.listen(PORT, () => {
  console.log(`Auth service listening on port ${PORT}`);
});
