const crypto = require("crypto");
const express = require("express");
const Database = require("better-sqlite3");

const path = require("path");
const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

const db = new Database(process.env.DB_PATH || "trustmesh.db");
db.pragma("journal_mode = WAL");

db.exec(`
  CREATE TABLE IF NOT EXISTS keys (
    deviceID     TEXT PRIMARY KEY,
    publicKey    TEXT NOT NULL,
    registeredAt TEXT NOT NULL DEFAULT (datetime('now'))
  )
`);

db.exec(`
  CREATE TABLE IF NOT EXISTS challenges (
    deviceID  TEXT PRIMARY KEY,
    challenge TEXT NOT NULL,
    createdAt TEXT NOT NULL DEFAULT (datetime('now'))
  )
`);

db.exec(`
  CREATE TABLE IF NOT EXISTS seen_sessions (
    sessionID    TEXT PRIMARY KEY,
    deviceID     TEXT NOT NULL,
    firstSeenAt  TEXT NOT NULL DEFAULT (datetime('now'))
  )
`);

db.exec(`
  CREATE TABLE IF NOT EXISTS sessions (
    code            TEXT PRIMARY KEY,
    creatorDeviceID TEXT NOT NULL,
    joinerDeviceID  TEXT,
    creatorReceipt  TEXT,
    joinerReceipt   TEXT,
    actionText      TEXT,
    status          TEXT NOT NULL DEFAULT 'waiting',
    createdAt       TEXT NOT NULL DEFAULT (datetime('now'))
  )
`);

// --- Prepared statements ---

const upsertKey = db.prepare(`
  INSERT INTO keys (deviceID, publicKey)
  VALUES (?, ?)
  ON CONFLICT(deviceID) DO UPDATE SET publicKey = excluded.publicKey, registeredAt = datetime('now')
`);

const lookupKey = db.prepare(
  `SELECT deviceID, publicKey, registeredAt FROM keys WHERE deviceID = ?`
);

const upsertChallenge = db.prepare(
  `INSERT INTO challenges (deviceID, challenge) VALUES (?, ?)
   ON CONFLICT(deviceID) DO UPDATE SET challenge = excluded.challenge, createdAt = datetime('now')`
);

const lookupChallenge = db.prepare(
  `SELECT challenge, createdAt FROM challenges WHERE deviceID = ?`
);

const deleteChallenge = db.prepare(
  `DELETE FROM challenges WHERE deviceID = ?`
);

const checkSession = db.prepare(
  `SELECT 1 FROM seen_sessions WHERE sessionID = ?`
);

const insertSession = db.prepare(
  `INSERT INTO seen_sessions (sessionID, deviceID) VALUES (?, ?)`
);

const createSession = db.prepare(
  `INSERT INTO sessions (code, creatorDeviceID, actionText) VALUES (?, ?, ?)`
);

const lookupSession = db.prepare(
  `SELECT * FROM sessions WHERE code = ?`
);

const joinSession = db.prepare(
  `UPDATE sessions SET joinerDeviceID = ?, status = 'joined' WHERE code = ? AND joinerDeviceID IS NULL`
);

const submitCreatorReceipt = db.prepare(
  `UPDATE sessions SET creatorReceipt = ?, status = CASE WHEN joinerReceipt IS NOT NULL THEN 'complete' ELSE status END WHERE code = ? AND creatorDeviceID = ?`
);

const submitJoinerReceipt = db.prepare(
  `UPDATE sessions SET joinerReceipt = ?, status = CASE WHEN creatorReceipt IS NOT NULL THEN 'complete' ELSE status END WHERE code = ? AND joinerDeviceID = ?`
);

// --- Routes ---

// Register a device's public key (base64-encoded DER SPKI)
app.post("/keys", (req, res) => {
  const { deviceID, publicKey } = req.body;
  if (!deviceID || !publicKey) {
    return res.status(400).json({ error: "deviceID and publicKey are required" });
  }
  upsertKey.run(deviceID, publicKey);
  res.status(201).json({ status: "registered" });
});

// Look up a device
app.get("/keys/:deviceID", (req, res) => {
  const row = lookupKey.get(req.params.deviceID);
  if (!row) return res.status(404).json({ error: "device not found" });
  res.json(row);
});

// Issue a challenge for a registered device
app.post("/challenge", (req, res) => {
  const { deviceID } = req.body;
  if (!deviceID) {
    return res.status(400).json({ error: "deviceID is required" });
  }
  const device = lookupKey.get(deviceID);
  if (!device) {
    return res.status(404).json({ error: "device not found — register first" });
  }
  const challenge = crypto.randomBytes(32).toString("hex");
  upsertChallenge.run(deviceID, challenge);
  res.json({ challenge });
});

// Verify a signed challenge (P256 ECDSA — matches iPhone Secure Enclave)
app.post("/verify", (req, res) => {
  const { deviceID, signature, sessionID } = req.body;
  if (!deviceID || !signature) {
    return res.status(400).json({ error: "deviceID and signature are required" });
  }

  const device = lookupKey.get(deviceID);
  if (!device) {
    return res.status(404).json({ error: "device not found" });
  }

  // Replay prevention (optional sessionID)
  if (sessionID) {
    if (checkSession.get(sessionID)) {
      return res.status(409).json({ error: "session already used (replay rejected)" });
    }
  }

  const pending = lookupChallenge.get(deviceID);
  if (!pending) {
    return res.status(400).json({ error: "no pending challenge — call POST /challenge first" });
  }

  // Consume the challenge regardless of outcome
  deleteChallenge.run(deviceID);

  try {
    const keyObject = crypto.createPublicKey({
      key: Buffer.from(device.publicKey, "base64"),
      format: "der",
      type: "spki",
    });

    const isValid = crypto.verify(
      "sha256",
      Buffer.from(pending.challenge),
      keyObject,
      Buffer.from(signature, "base64")
    );

    if (isValid && sessionID) {
      insertSession.run(sessionID, deviceID);
    }

    res.json({ verified: isValid });
  } catch (err) {
    res.json({ verified: false, error: err.message });
  }
});

// --- Shared Sessions (P2P) ---

// Create a new session
app.post("/sessions", (req, res) => {
  const { deviceID, actionText } = req.body;
  if (!deviceID) {
    return res.status(400).json({ error: "deviceID is required" });
  }

  // Generate unique 6-digit code (retry on collision)
  let code;
  for (let i = 0; i < 10; i++) {
    code = String(Math.floor(100000 + Math.random() * 900000));
    const existing = lookupSession.get(code);
    if (!existing) break;
    if (i === 9) return res.status(500).json({ error: "could not generate unique code" });
  }

  createSession.run(code, deviceID, actionText || null);
  res.status(201).json({ code, status: "waiting" });
});

// Join an existing session
app.post("/sessions/:code/join", (req, res) => {
  const { deviceID } = req.body;
  const { code } = req.params;
  if (!deviceID) {
    return res.status(400).json({ error: "deviceID is required" });
  }

  const session = lookupSession.get(code);
  if (!session) {
    return res.status(404).json({ error: "session not found" });
  }
  if (session.creatorDeviceID === deviceID) {
    return res.json({ status: session.status, role: "creator", actionText: session.actionText || null });
  }
  if (session.joinerDeviceID && session.joinerDeviceID !== deviceID) {
    return res.status(409).json({ error: "session already has two participants" });
  }
  if (!session.joinerDeviceID) {
    joinSession.run(deviceID, code);
  }
  res.json({ status: "joined", role: "joiner", actionText: session.actionText || null });
});

// Submit a receipt to a session
app.post("/sessions/:code/receipt", (req, res) => {
  const { deviceID, receipt } = req.body;
  const { code } = req.params;
  if (!deviceID || !receipt) {
    return res.status(400).json({ error: "deviceID and receipt are required" });
  }

  const session = lookupSession.get(code);
  if (!session) {
    return res.status(404).json({ error: "session not found" });
  }

  const receiptJSON = JSON.stringify(receipt);

  if (session.creatorDeviceID === deviceID) {
    submitCreatorReceipt.run(receiptJSON, code, deviceID);
  } else if (session.joinerDeviceID === deviceID) {
    submitJoinerReceipt.run(receiptJSON, code, deviceID);
  } else {
    return res.status(403).json({ error: "device is not part of this session" });
  }

  // Fetch updated session
  const updated = lookupSession.get(code);
  res.json({
    status: updated.status,
    creatorReceipt: updated.creatorReceipt ? JSON.parse(updated.creatorReceipt) : null,
    joinerReceipt: updated.joinerReceipt ? JSON.parse(updated.joinerReceipt) : null,
  });
});

// Get session status
app.get("/sessions/:code", (req, res) => {
  const session = lookupSession.get(req.params.code);
  if (!session) {
    return res.status(404).json({ error: "session not found" });
  }
  res.json({
    code: session.code,
    status: session.status,
    actionText: session.actionText || null,
    creatorDeviceID: session.creatorDeviceID,
    joinerDeviceID: session.joinerDeviceID,
    creatorReceipt: session.creatorReceipt ? JSON.parse(session.creatorReceipt) : null,
    joinerReceipt: session.joinerReceipt ? JSON.parse(session.joinerReceipt) : null,
    createdAt: session.createdAt,
  });
});

// Health check
app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`TrustMesh API listening on :${port}`));
