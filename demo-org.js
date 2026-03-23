#!/usr/bin/env node
//
// demo-org.js — Simulates an organization sending a signed message via TrustMesh
//
// Usage:
//   node demo-org.js "Your account has a suspicious login from Moscow, Russia. Click here to secure your account."
//   node demo-org.js --org "Chase Bank" --domain "chase.com" --channel email "Your wire transfer of $12,500 has been initiated."
//

const crypto = require("crypto");

const BACKEND = process.env.TRUSTMESH_URL || "https://trustmesh-production.up.railway.app";

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
  messageText = `Important: We've detected unusual activity on your account. A login attempt was made from an unrecognized device in Moscow, Russia at 3:47 AM EST. If this wasn't you, please verify your identity immediately. — ${orgName} Security Team`;
}

async function post(path, body) {
  const resp = await fetch(`${BACKEND}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return { status: resp.status, data: await resp.json() };
}

async function get(path) {
  const resp = await fetch(`${BACKEND}${path}`);
  return { status: resp.status, data: await resp.json() };
}

async function main() {
  console.log(`\n=== TrustMesh Organization Demo ===\n`);
  console.log(`Organization: ${orgName}`);
  console.log(`Domain: ${orgDomain}`);
  console.log(`Channel: ${channel}`);
  console.log(`Message: "${messageText}"\n`);

  // 1. Generate a P-256 key pair (simulating an org's server-side key)
  console.log("1. Generating P-256 key pair...");
  const { publicKey, privateKey } = crypto.generateKeyPairSync("ec", {
    namedCurve: "P-256",
    publicKeyEncoding: { type: "spki", format: "der" },
    privateKeyEncoding: { type: "pkcs8", format: "der" },
  });

  const publicKeyBase64 = Buffer.from(publicKey).toString("base64");
  const deviceID = crypto.createHash("sha256").update(publicKey).digest("hex").substring(0, 16);
  console.log(`   Device ID: ${deviceID}`);

  // 2. Register the key on the server
  console.log("2. Registering key on server...");
  const keyRes = await post("/keys", { deviceID, publicKey: publicKeyBase64 });
  console.log(`   ${keyRes.data.status}`);

  // 3. Register sender profile
  console.log("3. Registering sender profile...");
  const senderRes = await post("/senders", {
    deviceID,
    displayName: `${orgName} Security`,
    channels: [channel],
  });
  console.log(`   ${senderRes.data.status}`);

  // 4. Create the organization
  console.log("4. Creating organization...");
  const orgRes = await post("/orgs", {
    name: orgName,
    domain: orgDomain,
    deviceID,
  });
  if (orgRes.status !== 201) {
    console.log(`   Error: ${JSON.stringify(orgRes.data)}`);
    return;
  }
  const orgID = orgRes.data.orgID;
  console.log(`   Org ID: ${orgID}`);
  console.log(`   Status: ${orgRes.data.status}`);

  // 5. Build and sign the message commitment
  console.log("5. Signing message...");
  const messageHash = crypto.createHash("sha256").update(messageText).digest("hex");
  const messageId = crypto.randomUUID();
  const timestamp = Date.now();
  const nonce = crypto.randomUUID();

  const commitment = {
    channel,
    context: null,
    messageHash,
    nonce,
    orgID,
    senderID: deviceID,
    timestamp,
    version: 1,
  };

  // JSON encode with sorted keys (must match iOS verification)
  const commitmentJSON = JSON.stringify(commitment, Object.keys(commitment).sort());
  const commitmentData = Buffer.from(commitmentJSON);

  // Sign with P-256
  const signer = crypto.createSign("SHA256");
  signer.update(commitmentData);
  const signature = signer.sign({
    key: crypto.createPrivateKey({ key: privateKey, format: "der", type: "pkcs8" }),
    dsaEncoding: "der",
  });
  const signatureBase64 = signature.toString("base64");

  // 6. Post the signed message to the server
  console.log("6. Storing signed message on server...");
  const msgRes = await post("/messages", {
    messageId,
    deviceID,
    channel,
    messageHash,
    messageText,
    commitment: commitmentJSON,
    signature: signatureBase64,
    publicKeyHint: publicKeyBase64.substring(0, 16),
    orgID,
  });
  if (msgRes.status !== 201) {
    console.log(`   Error: ${JSON.stringify(msgRes.data)}`);
    return;
  }
  console.log(`   Stored! Message ID: ${messageId}`);

  const verificationURL = msgRes.data.verificationURL;

  // 7. Verify it works
  console.log("7. Verifying message (sanity check)...");
  const verifyRes = await post(`/messages/${messageId}/verify`, { receivedText: messageText });
  console.log(`   Valid: ${verifyRes.data.valid}`);
  console.log(`   Text match: ${verifyRes.data.textMatch}`);
  console.log(`   Sender: ${verifyRes.data.sender}`);
  if (verifyRes.data.organization) {
    console.log(`   Organization: ${verifyRes.data.organization.name}`);
    console.log(`   Org verified: ${verifyRes.data.organization.verified}`);
  }

  // 8. Output what to send
  console.log(`\n${"=".repeat(60)}`);
  console.log(`SEND THIS MESSAGE (via ${channel}):`);
  console.log(`${"=".repeat(60)}`);
  console.log(`\n${messageText}\n`);
  console.log(`Verify this message: ${verificationURL}\n`);
  console.log(`${"=".repeat(60)}`);
  console.log(`VERIFICATION URL (paste in app or open in browser):`);
  console.log(`${"=".repeat(60)}`);
  console.log(`\n${verificationURL}\n`);
  console.log(`Deep link: trustmesh://verify/${messageId}\n`);

  // Domain verification instructions
  console.log(`${"=".repeat(60)}`);
  console.log(`TO MARK ORG AS "VERIFIED" (optional):`);
  console.log(`${"=".repeat(60)}`);
  console.log(`Add DNS TXT record to ${orgDomain}:`);
  console.log(`  trustmesh-verify=${orgID}\n`);
}

main().catch(console.error);
