const express = require('express');
const Database = require('better-sqlite3');

const app = express();
app.use(express.json());

const db = new Database('trustmesh.db');
db.pragma('journal_mode = WAL');
db.exec(`
  CREATE TABLE IF NOT EXISTS keys (
    deviceID TEXT PRIMARY KEY,
    publicKey TEXT NOT NULL,
    registeredAt TEXT NOT NULL DEFAULT (datetime('now'))
  )
`);

const insertKey = db.prepare(
  'INSERT OR REPLACE INTO keys (deviceID, publicKey) VALUES (?, ?)'
);
const getKey = db.prepare('SELECT deviceID, publicKey, registeredAt FROM keys WHERE deviceID = ?');

app.post('/keys', (req, res) => {
  const { deviceID, publicKey } = req.body;
  if (!deviceID || !publicKey) {
    return res.status(400).json({ error: 'deviceID and publicKey are required' });
  }
  insertKey.run(deviceID, publicKey);
  res.json({ status: 'registered' });
});

app.get('/keys/:deviceID', (req, res) => {
  const row = getKey.get(req.params.deviceID);
  if (!row) {
    return res.status(404).json({ error: 'Device not found' });
  }
  res.json(row);
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`TrustMesh API listening on port ${PORT}`);
});
