#!/usr/bin/env node
//
// demo-org.js — Simulates an organization sending a signed message via TrustMesh
//
// Usage:
//   node demo-org.js
//   node demo-org.js "Your wire transfer of $12,500 has been initiated."
//   node demo-org.js --org "Chase Bank" --domain "chase.com" --channel sms "Your card ending 4821 was charged $847."
//
// Outputs:
//   - QR code image (qr.png) to scan with the TrustMesh app
//   - Mock email HTML (demo-email.html) showing what the consumer receives
//   - Opens the mock email in your browser automatically
//

const crypto = require("crypto");
const QRCode = require("qrcode");
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const BACKEND = process.env.TRUSTMESH_URL || "https://trustmesh-production.up.railway.app";
const OUT_DIR = path.join(__dirname, "demo-output");

// Parse args
const args = process.argv.slice(2);
let orgName = "Bank of America";
let orgDomain = "bankofamerica.com";
let channel = "email";
let messageText = "";

for (let i = 0; i < args.length; i++) {
  if (args[i] === "--org" && args[i + 1]) { orgName = args[++i]; continue; }
  if (args[i] === "--domain" && args[i + 1]) { orgDomain = args[++i]; continue; }
  if (args[i] === "--channel" && args[i + 1]) { channel = args[++i]; continue; }
  messageText = args[i];
}

if (!messageText) {
  messageText = `Important: We've detected unusual activity on your account. A login attempt was made from an unrecognized device in Moscow, Russia at 3:47 AM EST.\n\nIf this wasn't you, please verify your identity immediately by calling 1-800-432-1000.\n\nThis message has been cryptographically signed by ${orgName}. Scan the QR code below with the TrustMesh app to verify this message is authentic.`;
}

async function post(urlPath, body) {
  const resp = await fetch(`${BACKEND}${urlPath}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return { status: resp.status, data: await resp.json() };
}

async function main() {
  console.log(`\n  TrustMesh Organization Demo\n`);

  // 1. Generate P-256 key pair
  const { publicKey, privateKey } = crypto.generateKeyPairSync("ec", {
    namedCurve: "P-256",
    publicKeyEncoding: { type: "spki", format: "der" },
    privateKeyEncoding: { type: "pkcs8", format: "der" },
  });
  const publicKeyBase64 = Buffer.from(publicKey).toString("base64");
  const deviceID = crypto.createHash("sha256").update(publicKey).digest("hex").substring(0, 16);

  // 2. Register key + sender + org on the server
  console.log(`  Registering ${orgName}...`);
  await post("/keys", { deviceID, publicKey: publicKeyBase64 });
  await post("/senders", { deviceID, displayName: `${orgName}`, channels: [channel] });
  const orgRes = await post("/orgs", { name: orgName, domain: orgDomain, deviceID });
  if (orgRes.status !== 201) {
    console.log(`  Error: ${JSON.stringify(orgRes.data)}`);
    return;
  }
  const orgID = orgRes.data.orgID;
  console.log(`  Org registered: ${orgID}`);

  // 3. Sign the message
  const messageHash = crypto.createHash("sha256").update(messageText).digest("hex");
  const messageId = crypto.randomUUID();
  const timestamp = Date.now();
  const nonce = crypto.randomUUID();

  const commitment = { channel, context: null, messageHash, nonce, orgID, senderID: deviceID, timestamp, version: 1 };
  const commitmentJSON = JSON.stringify(commitment, Object.keys(commitment).sort());

  const signer = crypto.createSign("SHA256");
  signer.update(Buffer.from(commitmentJSON));
  const signature = signer.sign({
    key: crypto.createPrivateKey({ key: privateKey, format: "der", type: "pkcs8" }),
    dsaEncoding: "der",
  });

  // 4. Store on server
  const msgRes = await post("/messages", {
    messageId, deviceID, channel, messageHash, messageText,
    commitment: commitmentJSON, signature: signature.toString("base64"),
    publicKeyHint: publicKeyBase64.substring(0, 16), orgID,
  });
  if (msgRes.status !== 201) {
    console.log(`  Error: ${JSON.stringify(msgRes.data)}`);
    return;
  }
  const verificationURL = msgRes.data.verificationURL;
  console.log(`  Message signed and stored`);

  // 5. Sanity check
  const verifyRes = await post(`/messages/${messageId}/verify`, {});
  console.log(`  Verification: ${verifyRes.data.valid ? "VALID" : "FAILED"}`);
  if (verifyRes.data.organization) {
    console.log(`  Organization: ${verifyRes.data.organization.name}`);
  }

  // 6. Generate QR code
  if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR);
  const qrPath = path.join(OUT_DIR, "qr.png");
  await QRCode.toFile(qrPath, verificationURL, {
    width: 300, margin: 2,
    color: { dark: "#1c2949", light: "#ffffff" },
  });
  console.log(`  QR code: ${qrPath}`);

  // 7. Generate mock email HTML
  const emailHTML = generateEmailHTML(orgName, orgDomain, messageText, verificationURL, qrPath, channel);
  const htmlPath = path.join(OUT_DIR, "demo-email.html");
  fs.writeFileSync(htmlPath, emailHTML);
  console.log(`  Mock email: ${htmlPath}`);

  // 8. Generate QR as base64 for inline display
  const qrDataURL = await QRCode.toDataURL(verificationURL, {
    width: 300, margin: 2,
    color: { dark: "#1c2949", light: "#ffffff" },
  });
  const emailHTMLInline = generateEmailHTML(orgName, orgDomain, messageText, verificationURL, null, channel, qrDataURL);
  fs.writeFileSync(htmlPath, emailHTMLInline);

  // 9. Open in browser
  console.log(`\n  Opening mock email in browser...\n`);
  try { execSync(`open "${htmlPath}"`); } catch {}

  console.log(`  To scan: point your phone's TrustMesh app at the QR code on screen\n`);
}

function generateEmailHTML(orgName, domain, message, verifyURL, qrFile, channel, qrDataURL) {
  const msgHTML = message.replace(/\n/g, "<br>");
  const date = new Date().toLocaleDateString("en-US", { weekday: "long", year: "numeric", month: "long", day: "numeric" });
  const time = new Date().toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
  const qrSrc = qrDataURL || `file://${qrFile}`;
  const channelLabel = channel === "sms" ? "SMS" : channel === "email" ? "Email" : channel.charAt(0).toUpperCase() + channel.slice(1);

  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${orgName} — Verified Message</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, 'Helvetica Neue', Arial, sans-serif; background: #f0f2f5; padding: 40px 20px; color: #1a1a1a; }
  .email-container { max-width: 600px; margin: 0 auto; background: #fff; border-radius: 12px; overflow: hidden; box-shadow: 0 2px 20px rgba(0,0,0,0.08); }
  .header { background: linear-gradient(135deg, #1c2949 0%, #2a3f6f 100%); padding: 28px 32px; display: flex; align-items: center; gap: 16px; }
  .header-icon { width: 48px; height: 48px; background: rgba(255,255,255,0.15); border-radius: 12px; display: flex; align-items: center; justify-content: center; font-size: 24px; }
  .header-text { color: #fff; }
  .header-text h1 { font-size: 20px; font-weight: 700; }
  .header-text .subtitle { font-size: 13px; color: rgba(255,255,255,0.7); margin-top: 2px; }
  .trust-badge { margin: 0 32px; padding: 14px 20px; background: #f0faf4; border: 1px solid #c6f0d5; border-radius: 10px; display: flex; align-items: center; gap: 12px; margin-top: -1px; }
  .trust-badge .shield { font-size: 28px; }
  .trust-badge .badge-text { font-size: 13px; color: #15803d; font-weight: 600; }
  .trust-badge .badge-sub { font-size: 11px; color: #6b7280; margin-top: 2px; }
  .body-content { padding: 28px 32px; }
  .meta-line { font-size: 12px; color: #9ca3af; margin-bottom: 20px; }
  .message-text { font-size: 15px; line-height: 1.7; color: #374151; }
  .qr-section { padding: 24px 32px; text-align: center; border-top: 1px solid #f0f0f0; background: #fafbfc; }
  .qr-section img { width: 200px; height: 200px; }
  .qr-label { font-size: 13px; font-weight: 600; color: #1c2949; margin-bottom: 12px; }
  .qr-hint { font-size: 11px; color: #9ca3af; margin-top: 12px; }
  .footer { padding: 20px 32px; border-top: 1px solid #f0f0f0; text-align: center; }
  .footer a { color: #4a80c2; text-decoration: none; font-size: 13px; font-weight: 500; }
  .footer .fine { font-size: 11px; color: #9ca3af; margin-top: 8px; }
  .context-bar { font-size: 11px; color: #6b7280; background: #f9fafb; padding: 12px 32px; border-bottom: 1px solid #f0f0f0; text-align: center; }
</style>
</head>
<body>
<div class="email-container">
  <div class="header">
    <div class="header-icon">&#x1F3E6;</div>
    <div class="header-text">
      <h1>${orgName}</h1>
      <div class="subtitle">${domain} &middot; ${channelLabel} &middot; ${date}</div>
    </div>
  </div>

  <div class="trust-badge">
    <div class="shield">&#x1F6E1;&#xFE0F;</div>
    <div>
      <div class="badge-text">Verified by TrustMesh</div>
      <div class="badge-sub">This message was cryptographically signed by ${orgName}</div>
    </div>
  </div>

  <div class="body-content">
    <div class="meta-line">${date} at ${time}</div>
    <div class="message-text">${msgHTML}</div>
  </div>

  <div class="qr-section">
    <div class="qr-label">Scan to verify this message</div>
    <img src="${qrSrc}" alt="TrustMesh Verification QR Code">
    <div class="qr-hint">Open the TrustMesh app and scan this QR code to cryptographically<br>verify this message was sent by ${orgName}</div>
  </div>

  <div class="footer">
    <a href="${verifyURL}">Verify online at TrustMesh &rarr;</a>
    <div class="fine">${orgName} &middot; This message is protected by TrustMesh hardware-attested verification</div>
  </div>
</div>

<div style="text-align:center;margin-top:24px;font-size:11px;color:#9ca3af;">
  This is a demo of TrustMesh verified communication. In production, this badge and QR code<br>
  would be embedded directly in the ${channelLabel.toLowerCase()} from ${orgName}.
</div>
</body>
</html>`;
}

main().catch(console.error);
