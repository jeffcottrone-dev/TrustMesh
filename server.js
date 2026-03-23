const crypto = require("crypto");
const express = require("express");
const Database = require("better-sqlite3");

const path = require("path");
const app = express();
app.set("trust proxy", true); // Railway runs behind a proxy
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

db.exec(`
  CREATE TABLE IF NOT EXISTS senders (
    deviceID      TEXT PRIMARY KEY,
    displayName   TEXT NOT NULL,
    channels      TEXT DEFAULT '[]',
    keyVersion    INTEGER DEFAULT 1,
    status        TEXT DEFAULT 'active',
    registeredAt  TEXT DEFAULT (datetime('now')),
    updatedAt     TEXT DEFAULT (datetime('now'))
  )
`);

db.exec(`
  CREATE TABLE IF NOT EXISTS signed_messages (
    messageId       TEXT PRIMARY KEY,
    deviceID        TEXT NOT NULL,
    channel         TEXT NOT NULL,
    messageHash     TEXT NOT NULL,
    messageText     TEXT,
    commitment      TEXT NOT NULL,
    signature       TEXT NOT NULL,
    publicKeyHint   TEXT,
    verificationURL TEXT,
    createdAt       TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (deviceID) REFERENCES keys(deviceID)
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

// --- Sender prepared statements ---

const upsertSender = db.prepare(`
  INSERT INTO senders (deviceID, displayName, channels)
  VALUES (?, ?, ?)
  ON CONFLICT(deviceID) DO UPDATE SET displayName = excluded.displayName, channels = excluded.channels, updatedAt = datetime('now')
`);

const lookupSender = db.prepare(
  `SELECT * FROM senders WHERE deviceID = ?`
);

// --- Message prepared statements ---

const insertMessage = db.prepare(`
  INSERT INTO signed_messages (messageId, deviceID, channel, messageHash, messageText, commitment, signature, publicKeyHint, verificationURL)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
`);

const lookupMessage = db.prepare(
  `SELECT * FROM signed_messages WHERE messageId = ?`
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

// --- Senders ---

// Register sender profile
app.post("/senders", (req, res) => {
  const { deviceID, displayName, channels } = req.body;
  if (!deviceID || !displayName) {
    return res.status(400).json({ error: "deviceID and displayName are required" });
  }
  // Verify device key exists
  const device = lookupKey.get(deviceID);
  if (!device) {
    return res.status(404).json({ error: "device not found — register key first" });
  }
  const channelJSON = JSON.stringify(channels || []);
  upsertSender.run(deviceID, displayName, channelJSON);
  res.status(201).json({ status: "registered", deviceID, displayName });
});

// Get sender profile
app.get("/senders/:deviceID", (req, res) => {
  const sender = lookupSender.get(req.params.deviceID);
  if (!sender) return res.status(404).json({ error: "sender not found" });
  res.json({
    deviceID: sender.deviceID,
    displayName: sender.displayName,
    channels: JSON.parse(sender.channels || "[]"),
    status: sender.status,
    registeredAt: sender.registeredAt,
  });
});

// --- Signed Messages ---

// Store signed message artifact
app.post("/messages", (req, res) => {
  const { messageId, deviceID, channel, messageHash, messageText, commitment, signature, publicKeyHint } = req.body;
  if (!messageId || !deviceID || !channel || !messageHash || !commitment || !signature) {
    return res.status(400).json({ error: "messageId, deviceID, channel, messageHash, commitment, and signature are required" });
  }
  // Verify device key exists
  const device = lookupKey.get(deviceID);
  if (!device) {
    return res.status(404).json({ error: "device not found — register key first" });
  }
  const verificationURL = `${req.protocol}://${req.get("host")}/v/${messageId}`;
  const commitmentJSON = typeof commitment === "string" ? commitment : JSON.stringify(commitment);
  insertMessage.run(messageId, deviceID, channel, messageHash, messageText || null, commitmentJSON, signature, publicKeyHint || null, verificationURL);
  res.status(201).json({ messageId, verificationURL, status: "stored" });
});

// Retrieve message artifact
app.get("/messages/:messageId", (req, res) => {
  const msg = lookupMessage.get(req.params.messageId);
  if (!msg) return res.status(404).json({ error: "message not found" });
  res.json({
    messageId: msg.messageId,
    deviceID: msg.deviceID,
    channel: msg.channel,
    messageHash: msg.messageHash,
    messageText: msg.messageText,
    commitment: JSON.parse(msg.commitment),
    signature: msg.signature,
    publicKeyHint: msg.publicKeyHint,
    verificationURL: msg.verificationURL,
    createdAt: msg.createdAt,
  });
});

// Server-side P-256 verification of a signed message
app.post("/messages/:messageId/verify", (req, res) => {
  const { receivedText } = req.body;
  const msg = lookupMessage.get(req.params.messageId);
  if (!msg) return res.status(404).json({ error: "message not found" });

  // Step 1: Compare received text hash to signed messageHash
  if (!receivedText) {
    return res.status(400).json({ error: "receivedText is required — paste the message you received" });
  }

  const receivedHash = crypto.createHash("sha256").update(receivedText).digest("hex");
  if (receivedHash !== msg.messageHash) {
    return res.json({
      valid: false,
      textMatch: false,
      reason: "Message text does not match what was signed — it was tampered with",
    });
  }

  // Step 2: Verify P-256 signature on the commitment
  const device = lookupKey.get(msg.deviceID);
  if (!device) return res.status(404).json({ error: "device key not found" });

  try {
    const keyObject = crypto.createPublicKey({
      key: Buffer.from(device.publicKey, "base64"),
      format: "der",
      type: "spki",
    });

    const commitmentBytes = Buffer.from(msg.commitment);
    const isValid = crypto.verify(
      "sha256",
      commitmentBytes,
      keyObject,
      Buffer.from(msg.signature, "base64")
    );

    const sender = lookupSender.get(msg.deviceID);

    res.json({
      valid: isValid,
      textMatch: true,
      messageId: msg.messageId,
      channel: msg.channel,
      sender: sender ? sender.displayName : null,
      deviceID: msg.deviceID,
      messageText: msg.messageText,
      createdAt: msg.createdAt,
    });
  } catch (err) {
    res.json({ valid: false, textMatch: true, error: err.message });
  }
});

// Web verification page (for non-app users)
app.get("/v/:messageId", (req, res) => {
  const msg = lookupMessage.get(req.params.messageId);
  if (!msg) {
    return res.status(404).send(`
      <!DOCTYPE html>
      <html><head><title>TrustMesh - Not Found</title>
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>body{font-family:-apple-system,system-ui,sans-serif;background:#1c2949;color:#fff;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;text-align:center}
      .card{background:rgba(255,255,255,0.08);border-radius:16px;padding:40px;max-width:400px}</style></head>
      <body><div class="card"><h1>Message Not Found</h1><p style="color:#bec3cf">This verification link is invalid or expired.</p></div></body></html>
    `);
  }

  // Verify signature
  const device = lookupKey.get(msg.deviceID);
  let sigValid = false;
  try {
    if (device) {
      const keyObject = crypto.createPublicKey({
        key: Buffer.from(device.publicKey, "base64"),
        format: "der",
        type: "spki",
      });
      const commitmentBytes = Buffer.from(msg.commitment);
      sigValid = crypto.verify("sha256", commitmentBytes, keyObject, Buffer.from(msg.signature, "base64"));
    }
  } catch { /* sigValid = false */ }

  const sender = lookupSender.get(msg.deviceID);
  const senderName = sender ? sender.displayName : `Device ${msg.deviceID.substring(0, 8)}...`;
  const channelLabel = msg.channel.charAt(0).toUpperCase() + msg.channel.slice(1);
  const timestamp = new Date(msg.createdAt).toLocaleString();
  const sigColor = sigValid ? "#34c759" : "#ff3b30";

  res.send(`<!DOCTYPE html>
<html><head><title>TrustMesh Verification</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body{font-family:-apple-system,system-ui,sans-serif;background:#1c2949;color:#fff;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;padding:16px;box-sizing:border-box}
  .card{background:rgba(255,255,255,0.08);border-radius:16px;padding:32px;max-width:420px;width:100%;text-align:center}
  .sig-status{font-size:14px;color:${sigColor};margin-bottom:8px;font-weight:600}
  .details{text-align:left;margin-top:16px;background:rgba(255,255,255,0.06);border-radius:10px;padding:16px}
  .row{display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid rgba(255,255,255,0.08)}
  .row:last-child{border-bottom:none}
  .label{color:#bec3cf;font-size:13px}
  .value{color:#fff;font-size:13px;font-family:monospace;max-width:60%;text-align:right;word-break:break-all}
  .verify-section{margin-top:24px;text-align:left}
  .verify-section label{display:block;color:#bec3cf;font-size:13px;margin-bottom:8px}
  .verify-section textarea{width:100%;min-height:80px;background:rgba(255,255,255,0.06);border:1px solid rgba(255,255,255,0.15);border-radius:8px;color:#fff;font-size:14px;padding:12px;box-sizing:border-box;resize:vertical;font-family:inherit}
  .verify-section textarea:focus{outline:none;border-color:#4a80c2}
  .verify-btn{display:block;width:100%;margin-top:12px;padding:14px;border:none;border-radius:10px;background:#4a80c2;color:#fff;font-size:16px;font-weight:600;cursor:pointer}
  .verify-btn:hover{background:#3a6faa}
  .result-box{margin-top:16px;padding:20px;border-radius:10px;text-align:center}
  .result-box.match{background:rgba(52,199,89,0.15);border:1px solid #34c759}
  .result-box.tampered{background:rgba(255,59,48,0.15);border:1px solid #ff3b30}
  .result-icon{font-size:48px}
  .result-text{font-size:18px;font-weight:700;margin-top:8px;letter-spacing:1px}
  .result-sub{font-size:13px;color:#bec3cf;margin-top:4px}
  .deeplink{margin-top:20px}
  .deeplink a{color:#4a80c2;text-decoration:none;font-size:14px}
  .logo{font-size:13px;color:#bec3cf;margin-top:24px}
</style></head>
<body><div class="card">
  <h2 style="margin:0 0 4px">Verify Message</h2>
  <div class="sig-status">Signature: ${sigValid ? "Valid" : "INVALID"}</div>
  <div class="details">
    <div class="row"><span class="label">Sender</span><span class="value">${senderName}</span></div>
    <div class="row"><span class="label">Channel</span><span class="value">${channelLabel}</span></div>
    <div class="row"><span class="label">Time</span><span class="value">${timestamp}</span></div>
    <div class="row"><span class="label">Device</span><span class="value">${msg.deviceID.substring(0, 12)}...</span></div>
  </div>
  <div class="verify-section">
    <label>Paste the message you received:</label>
    <textarea id="receivedText" placeholder="Paste the exact text from the email or message you received..."></textarea>
    <button class="verify-btn" onclick="verifyText()">Verify Message</button>
    <div id="result"></div>
  </div>
  <div class="deeplink"><a href="trustmesh://verify/${msg.messageId}">Open in TrustMesh App</a></div>
  <div class="logo">TrustMesh &mdash; Hardware-Attested Verification</div>
</div>
<script>
  const storedHash = "${msg.messageHash}";
  async function verifyText() {
    const text = document.getElementById("receivedText").value;
    if (!text.trim()) return;
    const encoder = new TextEncoder();
    const data = encoder.encode(text);
    const hashBuffer = await crypto.subtle.digest("SHA-256", data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const hashHex = hashArray.map(b => b.toString(16).padStart(2, "0")).join("");
    const el = document.getElementById("result");
    if (hashHex === storedHash) {
      el.innerHTML = '<div class="result-box match"><div class="result-icon">&#10003;</div><div class="result-text" style="color:#34c759">VERIFIED</div><div class="result-sub">Message is authentic — exactly what the sender signed</div></div>';
    } else {
      el.innerHTML = '<div class="result-box tampered"><div class="result-icon">&#10007;</div><div class="result-text" style="color:#ff3b30">TAMPERED</div><div class="result-sub">Message does not match what was signed — it has been modified</div></div>';
    }
  }
</script>
</body></html>`);
});

// Health check
app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`TrustMesh API listening on :${port}`));
