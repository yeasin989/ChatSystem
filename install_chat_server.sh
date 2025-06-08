#!/bin/bash

echo "==== Real-Time Chat Server Auto Installer ===="

# 1. Update system
echo "Updating system..."
sudo apt-get update

# 2. Install Node.js & git
echo "Installing Node.js & git..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs git

# 3. Install PM2
echo "Installing PM2..."
sudo npm install -g pm2

# 4. Open port 3000
echo "Opening port 3000..."
sudo ufw allow 3000
sudo ufw reload

# 5. Create server directory
echo "Setting up chat-server directory..."
mkdir -p ~/chat-server
cd ~/chat-server

# 6. Write server.js
echo "Writing server.js..."
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
const db = new Low(new JSONFile(path.join(__dirname, 'db.json')));

const app = express();
app.use(cors());
app.use(express.json());

const http = httpModule.createServer(app);
const io = new Server(http, { cors: { origin: "*" } });

let users = {};      // socketId -> {name}
let messages = {};   // userName -> [message objects]

async function saveDB() {
  db.data.messages = messages;
  await db.write();
}

(async () => {
  await db.read();
  if (!db.data) db.data = { messages: {} };
  messages = db.data.messages;

  io.on('connection', socket => {
    let currentUser = null;

    socket.on('register', async name => {
      currentUser = name;
      users[socket.id] = name;
      if (!messages[name]) messages[name] = [];
      // send full history on connect
      socket.emit('chat_history', messages[name]);
    });

    socket.on('user_message', async text => {
      if (!currentUser) return;
      const msg = { from: currentUser, text, time: Date.now(), sender: 'user' };
      messages[currentUser].push(msg);
      await saveDB();
      // update this user
      socket.emit('chat_history', messages[currentUser]);
      // notify admin(s)
      io.emit('new_message', { userName: currentUser, message: msg });
    });

    socket.on('admin_message', async ({ userName, text }) => {
      const msg = { from: 'Admin', text, time: Date.now(), sender: 'admin' };
      if (!messages[userName]) messages[userName] = [];
      messages[userName].push(msg);
      await saveDB();
      // send to that user
      for (const [id, name] of Object.entries(users)) {
        if (name === userName) {
          io.to(id).emit('chat_history', messages[userName]);
          break;
        }
      }
      // notify all admins
      io.emit('new_message', { userName, message: msg });
    });

    socket.on('disconnect', () => {
      delete users[socket.id];
    });
  });

  app.get('/', (req, res) => res.send('Chat server running!'));
  http.listen(3000, () => console.log('Server on port 3000'));
})();
EOF

# 7. Install dependencies
echo "Installing Node.js modules..."
npm init -y
npm install express socket.io cors lowdb

# 8. Enable ES modules
echo "Enabling ES modules..."
sed -i '/"main":/a \  "type": "module",' package.json

# 9. Start with PM2
echo "Starting with PM2..."
pm2 start server.js --name chat-server
pm2 save

# 10. Auto-start on reboot
echo "Configuring PM2 startup..."
pm2 startup | tail -2 | head -1 | bash

echo ""
echo "=== INSTALL COMPLETE ==="
echo "Visit http://<YOUR_SERVER_IP>:3000 to test."
