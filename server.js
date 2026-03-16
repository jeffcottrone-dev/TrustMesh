const crypto = require("crypto");
const express = require("express");
const Database = require("better-sqlite3");

const app = express();
app.use(express.json());

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

// Health check
app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`TrustMesh API listening on :${port}`));
