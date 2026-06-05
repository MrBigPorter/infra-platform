// ==========================================
// Grafana Auth Proxy — JWT Token Validation Service
// ==========================================
// Nginx auth_request calls this endpoint to validate signed tokens.
// If valid → returns 200 + email in header
// If invalid/expired → returns 401
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

// Health check for Nginx / Docker
app.get('/health', (_req, res) => {
  res.json({ status: 'ok' });
});

// Token validation endpoint — called by Nginx auth_request
app.get('/validate-token', (req, res) => {
  const token = req.query.token;

  if (!token) {
    return res.sendStatus(401);
  }

  try {
    const decoded = jwt.verify(token, SECRET);
    // Pass the email back to Nginx via response header
    res.set('X-Email', decoded.email);
    res.json({ email: decoded.email });
  } catch {
    // Token invalid, expired, or wrong secret → deny
    res.sendStatus(401);
  }
});

app.listen(PORT, () => {
  console.log(`Auth service listening on port ${PORT}`);
});
