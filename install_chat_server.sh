#!/bin/bash
echo "==== Real-Time Chat Server Auto Installer ===="

# 1. Update & install prerequisites
sudo apt-get update
sudo apt-get install -y curl git build-essential

# 2. Install Node.js (v18) & PM2
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g pm2

# 3. Open port 3000
sudo ufw allow 3000
sudo ufw reload

# 4. Setup server directory
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

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const dbFile = path.join(__dirname, 'db.json');
const db = new Low(new JSONFile(dbFile));

await db.read();
if (!db.data) db.data = { messages: {}, users: [] };

const app = express();
app.use(cors());
app.use(express.json());

const http = httpModule.createServer(app);
const io = new Server(http, { cors: { origin: "*" } });

let users = {};  // socketId => userName
let messages = db.data.messages; // userName => [ { from, text, time, sender } ]

function persist() {
  db.data.messages = messages;
  db.write();
}

// Helper: send updated client list
function broadcastClients() {
  const active = Object.values(users);
  io.emit('update_clients', active);
}

io.on('connection', socket => {
  let me = null;

  socket.on('register', userName => {
    me = userName;
    users[socket.id] = userName;
    if (!messages[me]) messages[me] = [];
    persist();
    broadcastClients();
    socket.emit('chat_history', messages[me]);
  });

  socket.on('get_clients', () => broadcastClients());

  socket.on('join', userName => {
    if (!messages[userName]) messages[userName] = [];
    socket.emit('chat_history', messages[userName]);
  });

  socket.on('user_message', text => {
    if (!me) return;
    const msg = { from: me, text, time: Date.now(), sender: 'user' };
    messages[me].push(msg);
    persist();
    // to user
    socket.emit('chat_history', messages[me]);
    // notify admin(s)
    io.emit('message', { user: me, msg });
  });

  socket.on('admin_message', ({ user, text }) => {
    const msg = { from: 'Admin', text, time: Date.now(), sender: 'admin' };
    if (!messages[user]) messages[user] = [];
    messages[user].push(msg);
    persist();
    // to that user
    for (let [id,u] of Object.entries(users)) {
      if (u === user) io.to(id).emit('chat_history', messages[user]);
    }
    // notify admin(s)
    io.emit('message', { user, msg });
  });

  socket.on('disconnect', () => {
    delete users[socket.id];
    broadcastClients();
  });
});

app.get('/', (req, res) => res.send('Chat server running!'));
http.listen(3000, () => console.log('Server on port 3000'));
EOF

# 6. Init & install
npm init -y
npm install express socket.io cors lowdb
# 7. Enable ESM
sed -i '/"main":/a \  "type": "module",' package.json

# 8. Start with PM2
pm2 start server.js --name chat-server
pm2 save
pm2 startup | tail -2 | head -1 | bash

echo "==== INSTALL COMPLETE! ===="
echo "http://<YOUR_SERVER_IP>:3000"
