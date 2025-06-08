#!/bin/bash
echo "==== Real-Time Chat Server Auto Installer ===="

# 1. Update & prerequisites
sudo apt-get update
sudo apt-get install -y curl git build-essential

# 2. Node.js & PM2
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g pm2

# 3. Open port 3000
sudo ufw allow 3000
sudo ufw reload

# 4. Setup directory
mkdir -p ~/chat-server
cd ~/chat-server

# 5. Write server.js
cat << 'EOF' > server.js
import express from 'express';
import httpModule from 'http';
import { Server } from 'socket.io';
import cors from 'cors';
import { Low, JSONFile } from 'lowdb';
import path from 'path';
import { fileURLToPath } from 'url';

// Boilerplate for __dirname in ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname  = path.dirname(__filename);

const db = new Low(new JSONFile(path.join(__dirname, 'db.json')));
await db.read();
if (!db.data) db.data = { messages: {}, users: [] };

const app = express();
app.use(cors());
app.use(express.json());

const http = httpModule.createServer(app);
const io   = new Server(http, { cors: { origin: "*" } });

let users    = {};     // socketId -> userName
let messages = db.data.messages; // userName -> [msg]

// Persist helper
async function save() {
  db.data.messages = messages;
  await db.write();
}

// Broadcast both active & historical users
function broadcastClients() {
  const active = Object.values(users);
  const all    = db.data.users;
  io.emit('update_clients', { active, all });
}

io.on('connection', socket => {
  let me = null;

  socket.on('register', async userName => {
    me = userName;
    users[socket.id] = me;

    // track history
    if (!db.data.users.find(u => u.name === me)) {
      db.data.users.push({ name: me, firstSeen: Date.now() });
    }
    if (!messages[me]) messages[me] = [];
    await save();

    // tell admin and client
    broadcastClients();
    socket.emit('chat_history', messages[me]);
  });

  socket.on('get_clients', () => broadcastClients());

  socket.on('join', userName => {
    socket.emit('chat_history', messages[userName] || []);
  });

  socket.on('user_message', async text => {
    if (!me) return;
    const msg = { from: me, text, time: Date.now(), sender: 'user' };
    messages[me].push(msg);
    await save();
    socket.emit('chat_history', messages[me]);
    io.emit('new_message', { user: me, msg });
  });

  socket.on('admin_message', async ({ user, text }) => {
    const msg = { from: 'Admin', text, time: Date.now(), sender: 'admin' };
    if (!messages[user]) messages[user] = [];
    messages[user].push(msg);
    await save();
    // to that user
    for (let [id,u] of Object.entries(users)) {
      if (u === user) io.to(id).emit('chat_history', messages[user]);
    }
    io.emit('new_message', { user, msg });
  });

  socket.on('disconnect', () => {
    delete users[socket.id];
    broadcastClients();
  });
});

app.get('/', (_,res) => res.send('Chat server running!'));
http.listen(3000, () => console.log('Server listening on 3000'));
EOF

# 6. Install & enable modules
npm init -y
npm install express socket.io cors lowdb
sed -i '/"main":/a \  "type": "module",' package.json

# 7. Start with PM2
pm2 start server.js --name chat-server
pm2 save
pm2 startup | tail -2 | head -1 | bash

echo "=== INSTALL COMPLETE! Visit http://YOUR_SERVER_IP:3000 ==="
