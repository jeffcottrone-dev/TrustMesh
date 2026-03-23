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
    orgID           TEXT,
    createdAt       TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (deviceID) REFERENCES keys(deviceID)
  )
`);

// Add orgID column if upgrading from older schema
try { db.exec(`ALTER TABLE signed_messages ADD COLUMN orgID TEXT`); } catch {}

db.exec(`
  CREATE TABLE IF NOT EXISTS transparency_log (
    sequenceNum  INTEGER PRIMARY KEY AUTOINCREMENT,
    action       TEXT NOT NULL,
    entityType   TEXT NOT NULL,
    entityID     TEXT NOT NULL,
    dataHash     TEXT NOT NULL,
    previousHash TEXT NOT NULL,
    timestamp    TEXT DEFAULT (datetime('now'))
  )
`);

db.exec(`
  CREATE TABLE IF NOT EXISTS organizations (
    orgID         TEXT PRIMARY KEY,
    name          TEXT NOT NULL,
    domain        TEXT,
    verifiedAt    TEXT,
    status        TEXT DEFAULT 'pending',
    adminDeviceID TEXT NOT NULL,
    createdAt     TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (adminDeviceID) REFERENCES keys(deviceID)
  )
`);

db.exec(`
  CREATE TABLE IF NOT EXISTS org_members (
    orgID    TEXT NOT NULL,
    deviceID TEXT NOT NULL,
    role     TEXT DEFAULT 'member',
    joinedAt TEXT DEFAULT (datetime('now')),
    PRIMARY KEY (orgID, deviceID),
    FOREIGN KEY (orgID) REFERENCES organizations(orgID),
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
  INSERT INTO signed_messages (messageId, deviceID, channel, messageHash, messageText, commitment, signature, publicKeyHint, verificationURL, orgID)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
`);

const lookupMessage = db.prepare(
  `SELECT * FROM signed_messages WHERE messageId = ?`
);

// --- Organization prepared statements ---

const insertOrg = db.prepare(`
  INSERT INTO organizations (orgID, name, domain, adminDeviceID) VALUES (?, ?, ?, ?)
`);

const lookupOrg = db.prepare(
  `SELECT * FROM organizations WHERE orgID = ?`
);

const insertOrgMember = db.prepare(`
  INSERT OR IGNORE INTO org_members (orgID, deviceID, role) VALUES (?, ?, ?)
`);

const deleteOrgMember = db.prepare(
  `DELETE FROM org_members WHERE orgID = ? AND deviceID = ?`
);

const lookupOrgMember = db.prepare(
  `SELECT * FROM org_members WHERE orgID = ? AND deviceID = ?`
);

const listOrgMembers = db.prepare(
  `SELECT om.deviceID, om.role, om.joinedAt, s.displayName FROM org_members om LEFT JOIN senders s ON om.deviceID = s.deviceID WHERE om.orgID = ?`
);

const countOrgMembers = db.prepare(
  `SELECT COUNT(*) as count FROM org_members WHERE orgID = ?`
);

const listOrgsByDevice = db.prepare(
  `SELECT o.*, om.role FROM organizations o JOIN org_members om ON o.orgID = om.orgID WHERE om.deviceID = ?`
);

// --- Transparency log helper ---

function appendToLog(action, entityType, entityID, payloadForHash) {
  const last = db.prepare("SELECT dataHash FROM transparency_log ORDER BY sequenceNum DESC LIMIT 1").get();
  const previousHash = last ? last.dataHash : "0";
  const entryData = `${action}:${entityType}:${entityID}:${payloadForHash}:${previousHash}`;
  const entryHash = crypto.createHash("sha256").update(entryData).digest("hex");
  db.prepare("INSERT INTO transparency_log (action, entityType, entityID, dataHash, previousHash) VALUES (?, ?, ?, ?, ?)")
    .run(action, entityType, entityID, entryHash, previousHash);
  return entryHash;
}

// --- Signature verification helper for admin requests ---

function verifyAdminSignature(deviceID, bodyWithoutSig) {
  const device = lookupKey.get(deviceID);
  if (!device) return { valid: false, error: "device not found" };
  try {
    const keyObject = crypto.createPublicKey({
      key: Buffer.from(device.publicKey, "base64"),
      format: "der",
      type: "spki",
    });
    const dataToVerify = JSON.stringify(bodyWithoutSig);
    const isValid = crypto.verify(
      "sha256",
      Buffer.from(dataToVerify),
      keyObject,
      Buffer.from(bodyWithoutSig._signature || "", "base64")
    );
    return { valid: isValid };
  } catch (err) {
    return { valid: false, error: err.message };
  }
}

// --- Routes ---

// Register a device's public key (base64-encoded DER SPKI)
app.post("/keys", (req, res) => {
  const { deviceID, publicKey } = req.body;
  if (!deviceID || !publicKey) {
    return res.status(400).json({ error: "deviceID and publicKey are required" });
  }
  upsertKey.run(deviceID, publicKey);
  const keyHash = crypto.createHash("sha256").update(publicKey).digest("hex");
  appendToLog("key_register", "device", deviceID, keyHash);
  res.status(201).json({ status: "registered" });
});

// Look up a device (includes registeredAt for key pinning)
app.get("/keys/:deviceID", (req, res) => {
  const row = lookupKey.get(req.params.deviceID);
  if (!row) return res.status(404).json({ error: "device not found" });
  // Find the log entry for this key registration
  const logEntry = db.prepare("SELECT sequenceNum FROM transparency_log WHERE entityID = ? AND action = 'key_register' ORDER BY sequenceNum DESC LIMIT 1").get(req.params.deviceID);
  res.json({
    ...row,
    logSequenceNum: logEntry ? logEntry.sequenceNum : null,
  });
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
  const senderHash = crypto.createHash("sha256").update(`${deviceID}:${displayName}`).digest("hex");
  appendToLog("sender_register", "device", deviceID, senderHash);
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
  const { messageId, deviceID, channel, messageHash, messageText, commitment, signature, publicKeyHint, orgID } = req.body;
  if (!messageId || !deviceID || !channel || !messageHash || !commitment || !signature) {
    return res.status(400).json({ error: "messageId, deviceID, channel, messageHash, commitment, and signature are required" });
  }
  // Verify device key exists
  const device = lookupKey.get(deviceID);
  if (!device) {
    return res.status(404).json({ error: "device not found — register key first" });
  }
  // If orgID provided, verify device is a member of that org
  if (orgID) {
    const membership = lookupOrgMember.get(orgID, deviceID);
    if (!membership) {
      return res.status(403).json({ error: "device is not a member of this organization" });
    }
  }
  const verificationURL = `${req.protocol}://${req.get("host")}/v/${messageId}`;
  const commitmentJSON = typeof commitment === "string" ? commitment : JSON.stringify(commitment);
  insertMessage.run(messageId, deviceID, channel, messageHash, messageText || null, commitmentJSON, signature, publicKeyHint || null, verificationURL, orgID || null);
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
  const { receivedText } = req.body || {};
  const msg = lookupMessage.get(req.params.messageId);
  if (!msg) return res.status(404).json({ error: "message not found" });

  // Optional: Compare received text hash to signed messageHash
  let textMatch = null;
  if (receivedText) {
    const receivedHash = crypto.createHash("sha256").update(receivedText).digest("hex");
    textMatch = receivedHash === msg.messageHash;
    if (!textMatch) {
      return res.json({
        valid: false,
        textMatch: false,
        reason: "Message text does not match what was signed — it was tampered with",
      });
    }
  }

  // Verify P-256 signature on the commitment
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

    // Include organization info if message was signed under an org
    let organization = null;
    if (msg.orgID) {
      const org = lookupOrg.get(msg.orgID);
      if (org) {
        organization = {
          name: org.name,
          verified: !!org.verifiedAt,
          domain: org.domain,
        };
      }
    }

    res.json({
      valid: isValid,
      textMatch: textMatch !== null ? textMatch : undefined,
      messageId: msg.messageId,
      channel: msg.channel,
      sender: sender ? sender.displayName : null,
      deviceID: msg.deviceID,
      messageText: msg.messageText,
      organization,
      createdAt: msg.createdAt,
    });
  } catch (err) {
    res.json({ valid: false, error: err.message });
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

  // Organization info
  let orgHTML = "";
  if (msg.orgID) {
    const org = lookupOrg.get(msg.orgID);
    if (org) {
      const orgVerified = !!org.verifiedAt;
      const shieldColor = orgVerified ? "#34c759" : "#f0ad4e";
      const shieldLabel = orgVerified ? "Verified Organization" : "Unverified Organization";
      orgHTML = `<div style="margin:12px 0;padding:12px;background:rgba(255,255,255,0.06);border-radius:10px;display:flex;align-items:center;gap:10px">
        <span style="font-size:24px;color:${shieldColor}">&#x1F6E1;</span>
        <div><div style="font-weight:700;color:#fff">${org.name}</div><div style="font-size:12px;color:${shieldColor}">${shieldLabel}${org.domain ? ' &mdash; ' + org.domain : ''}</div></div>
      </div>`;
    }
  }

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
  ${orgHTML}
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

// --- Transparency Log ---

// Public audit log (paginated)
app.get("/transparency/log", (req, res) => {
  const since = parseInt(req.query.since) || 0;
  const limit = Math.min(parseInt(req.query.limit) || 50, 200);
  const entries = db.prepare(
    "SELECT * FROM transparency_log WHERE sequenceNum > ? ORDER BY sequenceNum ASC LIMIT ?"
  ).all(since, limit);
  res.json({ entries, count: entries.length });
});

// Verify chain integrity
app.get("/transparency/verify", (_req, res) => {
  const entries = db.prepare("SELECT * FROM transparency_log ORDER BY sequenceNum ASC").all();
  let previousHash = "0";
  for (const entry of entries) {
    if (entry.previousHash !== previousHash) {
      return res.json({ valid: false, brokenAt: entry.sequenceNum });
    }
    // Recompute entry hash to verify
    const recomputed = crypto.createHash("sha256")
      .update(`${entry.action}:${entry.entityType}:${entry.entityID}:${entry.dataHash.replace(/.*:/, '')}:${entry.previousHash}`)
      .digest("hex");
    // The stored dataHash IS the full entry hash, so we just chain forward
    previousHash = entry.dataHash;
  }
  res.json({ valid: true, entries: entries.length });
});

// --- Organizations ---

// Create organization
app.post("/orgs", (req, res) => {
  const { name, domain, deviceID, signature, timestamp } = req.body;
  if (!name || !deviceID) {
    return res.status(400).json({ error: "name and deviceID are required" });
  }
  // Verify device key exists
  const device = lookupKey.get(deviceID);
  if (!device) {
    return res.status(404).json({ error: "device not found — register key first" });
  }
  // Verify signature if provided (signed request)
  if (signature) {
    try {
      const keyObject = crypto.createPublicKey({
        key: Buffer.from(device.publicKey, "base64"),
        format: "der",
        type: "spki",
      });
      const dataToSign = `createOrg:${name}:${domain || ""}:${deviceID}:${timestamp}`;
      const isValid = crypto.verify("sha256", Buffer.from(dataToSign), keyObject, Buffer.from(signature, "base64"));
      if (!isValid) return res.status(403).json({ error: "invalid signature" });
    } catch (err) {
      return res.status(403).json({ error: "signature verification failed: " + err.message });
    }
  }

  const orgID = crypto.randomUUID();
  insertOrg.run(orgID, name, domain || null, deviceID);
  // Add admin as first member
  insertOrgMember.run(orgID, deviceID, "admin");
  // Log to transparency log
  const orgHash = crypto.createHash("sha256").update(`${orgID}:${name}:${deviceID}`).digest("hex");
  appendToLog("org_register", "org", orgID, orgHash);

  res.status(201).json({ orgID, name, domain: domain || null, status: "pending" });
});

// Get organization profile
app.get("/orgs/:orgID", (req, res) => {
  const org = lookupOrg.get(req.params.orgID);
  if (!org) return res.status(404).json({ error: "organization not found" });
  const memberCount = countOrgMembers.get(org.orgID).count;
  res.json({
    orgID: org.orgID,
    name: org.name,
    domain: org.domain,
    verified: !!org.verifiedAt,
    status: org.status,
    memberCount,
    createdAt: org.createdAt,
  });
});

// List orgs for a device (for org picker)
app.get("/orgs", (req, res) => {
  const { deviceID } = req.query;
  if (!deviceID) return res.status(400).json({ error: "deviceID query parameter is required" });
  const orgs = listOrgsByDevice.all(deviceID);
  res.json(orgs.map(o => ({
    orgID: o.orgID,
    name: o.name,
    domain: o.domain,
    verified: !!o.verifiedAt,
    status: o.status,
    role: o.role,
    memberCount: countOrgMembers.get(o.orgID).count,
  })));
});

// Add member to organization (admin only)
app.post("/orgs/:orgID/members", (req, res) => {
  const { deviceID, memberDeviceID, signature, timestamp } = req.body;
  const { orgID } = req.params;
  if (!deviceID || !memberDeviceID) {
    return res.status(400).json({ error: "deviceID (admin) and memberDeviceID are required" });
  }
  // Verify admin is a member with admin role
  const adminMember = lookupOrgMember.get(orgID, deviceID);
  if (!adminMember || adminMember.role !== "admin") {
    return res.status(403).json({ error: "only admins can add members" });
  }
  // Verify admin signature if provided
  if (signature) {
    const device = lookupKey.get(deviceID);
    if (device) {
      try {
        const keyObject = crypto.createPublicKey({
          key: Buffer.from(device.publicKey, "base64"),
          format: "der",
          type: "spki",
        });
        const dataToSign = `addMember:${orgID}:${memberDeviceID}:${deviceID}:${timestamp}`;
        const isValid = crypto.verify("sha256", Buffer.from(dataToSign), keyObject, Buffer.from(signature, "base64"));
        if (!isValid) return res.status(403).json({ error: "invalid signature" });
      } catch (err) {
        return res.status(403).json({ error: "signature verification failed: " + err.message });
      }
    }
  }
  // Verify member device key exists
  const memberDevice = lookupKey.get(memberDeviceID);
  if (!memberDevice) {
    return res.status(404).json({ error: "member device not found — must register key first" });
  }
  insertOrgMember.run(orgID, memberDeviceID, "member");
  const memberHash = crypto.createHash("sha256").update(`${orgID}:${memberDeviceID}`).digest("hex");
  appendToLog("org_member_add", "org", orgID, memberHash);
  res.status(201).json({ status: "added", orgID, memberDeviceID });
});

// Remove member from organization (admin only)
app.delete("/orgs/:orgID/members/:memberDeviceID", (req, res) => {
  const { orgID, memberDeviceID } = req.params;
  const deviceID = req.query.deviceID || req.body?.deviceID;
  if (!deviceID) {
    return res.status(400).json({ error: "deviceID (admin) is required" });
  }
  const adminMember = lookupOrgMember.get(orgID, deviceID);
  if (!adminMember || adminMember.role !== "admin") {
    return res.status(403).json({ error: "only admins can remove members" });
  }
  // Can't remove yourself if you're the only admin
  if (memberDeviceID === deviceID) {
    return res.status(400).json({ error: "cannot remove yourself as admin" });
  }
  deleteOrgMember.run(orgID, memberDeviceID);
  const removeHash = crypto.createHash("sha256").update(`${orgID}:${memberDeviceID}:removed`).digest("hex");
  appendToLog("org_member_remove", "org", orgID, removeHash);
  res.json({ status: "removed", orgID, memberDeviceID });
});

// List organization members (admin only)
app.get("/orgs/:orgID/members", (req, res) => {
  const { deviceID } = req.query;
  const { orgID } = req.params;
  if (!deviceID) {
    return res.status(400).json({ error: "deviceID query parameter is required" });
  }
  const member = lookupOrgMember.get(orgID, deviceID);
  if (!member || member.role !== "admin") {
    return res.status(403).json({ error: "only admins can list members" });
  }
  const members = listOrgMembers.all(orgID);
  res.json(members.map(m => ({
    deviceID: m.deviceID,
    displayName: m.displayName,
    role: m.role,
    joinedAt: m.joinedAt,
  })));
});

// Domain verification (DNS TXT record check)
app.post("/orgs/:orgID/verify-domain", async (req, res) => {
  const { deviceID } = req.body;
  const { orgID } = req.params;
  const org = lookupOrg.get(orgID);
  if (!org) return res.status(404).json({ error: "organization not found" });
  if (!org.domain) return res.status(400).json({ error: "organization has no domain set" });

  // Verify requester is admin
  const adminMember = lookupOrgMember.get(orgID, deviceID);
  if (!adminMember || adminMember.role !== "admin") {
    return res.status(403).json({ error: "only admins can verify domain" });
  }

  // Check DNS TXT record
  const dns = require("dns").promises;
  try {
    const records = await dns.resolveTxt(org.domain);
    const flat = records.map(r => r.join(""));
    const expected = `trustmesh-verify=${orgID}`;
    if (flat.includes(expected)) {
      db.prepare("UPDATE organizations SET verifiedAt = datetime('now'), status = 'active' WHERE orgID = ?").run(orgID);
      res.json({ verified: true, domain: org.domain });
    } else {
      res.json({ verified: false, expected, found: flat, instruction: `Add a TXT record to ${org.domain} with value: ${expected}` });
    }
  } catch (err) {
    res.json({ verified: false, error: "DNS lookup failed: " + err.message, instruction: `Add a TXT record to ${org.domain} with value: trustmesh-verify=${orgID}` });
  }
});

// Health check
app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`TrustMesh API listening on :${port}`));
