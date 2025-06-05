#!/bin/bash

echo "==== Real-Time Chat Server Auto Installer ===="

# 1. Update system
echo "Updating system..."
sudo apt-get update

# 2. Install Node.js
echo "Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs git

# 3. Install PM2 (process manager)
echo "Installing PM2 (process manager)..."
sudo npm install -g pm2

# 4. Open port 3000 in firewall (UFW)
echo "Opening port 3000 in firewall..."
sudo ufw allow 3000
sudo ufw reload

# 5. Create chat-server directory
echo "Creating chat-server directory..."
mkdir -p ~/chat-server
cd ~/chat-server

# 6. Write server.js
echo "Writing server.js..."
cat << 'EOF' > server.js
const express = require('express');
const app = express();
const http = require('http').createServer(app);
const io = require('socket.io')(http, { cors: { origin: "*" } });
const cors = require('cors');

// --- Add LowDB for persistence ---
const { Low, JSONFile } = require('lowdb');
const path = require('path');
const dbPath = path.join(__dirname, 'db.json');
const db = new Low(new JSONFile(dbPath));

app.use(cors());
app.use(express.json());

let users = {}; // socketId -> {name, id}
let allUsers = []; // {name, lastSeen, lastSocketId}
let messages = {}; // { userName: [ {from, text, time, sender} ] }

// --- Load from DB at startup ---
(async () => {
    await db.read();
    db.data ||= { messages: {}, users: [] };
    messages = db.data.messages || {};
    allUsers = db.data.users || [];

    // ====== REST OF SERVER CODE (everything using io, app, etc) =======
    io.on('connection', (socket) => {
        // ...all your socket handlers here...
    });

    app.get('/', (req, res) => {
        res.send("Chat server running!");
    });

    http.listen(3000, () => {
        console.log('Server running on port 3000');
    });
})();


function saveDB() {
    db.data.messages = messages;
    db.data.users = allUsers;
    db.write();
}

io.on('connection', (socket) => {
    let currentUser = null;

    socket.on('register', async (name) => {
        // Reload from disk (handles concurrent writes)
        await db.read();
        messages = db.data.messages || {};
        allUsers = db.data.users || {};

        currentUser = { id: socket.id, name: name || ("User" + Date.now()) };
        users[socket.id] = currentUser;

        // Track all unique user names
        let existing = allUsers.find(u => u.name === name);
        if (!existing) {
            allUsers.push({ name, lastSeen: Date.now(), lastSocketId: socket.id });
        } else {
            existing.lastSeen = Date.now();
            existing.lastSocketId = socket.id;
        }
        if (!messages[currentUser.name]) messages[currentUser.name] = [];
        saveDB();

        // Send all user info to admin, and user chat history to user
        io.emit('update_clients', {
            active: Object.values(users).map(u => u.name),
            all: allUsers
        });
        socket.emit('chat_history', messages[currentUser.name]);
    });

    socket.on('get_clients', () => {
        io.emit('update_clients', {
            active: Object.values(users).map(u => u.name),
            all: allUsers
        });
    });

    socket.on('user_message', (msg) => {
        if (!currentUser) return;
        const message = { from: currentUser.name, text: msg, time: Date.now(), sender: "user" };
        if (!messages[currentUser.name]) messages[currentUser.name] = [];
        messages[currentUser.name].push(message);
        saveDB();
        io.to(socket.id).emit('chat_history', messages[currentUser.name]);
        io.emit('new_message', { userName: currentUser.name, message }); // Notify all admins in real time
    });

    socket.on('admin_message', ({ userName, text }) => {
        const message = { from: "Admin", text, time: Date.now(), sender: "admin" };
        if (!messages[userName]) messages[userName] = [];
        messages[userName].push(message);
        saveDB();
        // Find current socket for that user, if online
        let userSocket = Object.keys(users).find(id => users[id].name === userName);
        if (userSocket) {
            io.to(userSocket).emit('chat_history', messages[userName]);
        }
    });

    socket.on('join_chat', (userName) => {
        socket.emit('chat_history', messages[userName] || []);
    });

    socket.on('disconnect', () => {
        if (currentUser) {
            delete users[socket.id];
            let existing = allUsers.find(u => u.name === currentUser.name);
            if (existing) existing.lastSeen = Date.now();
            io.emit('update_clients', {
                active: Object.values(users).map(u => u.name),
                all: allUsers
            });
            saveDB();
        }
    });
});

app.get('/', (req, res) => {
    res.send("Chat server running!");
});

http.listen(3000, () => {
    console.log('Server running on port 3000');
});
EOF

# 7. Install Node.js modules (add lowdb for persistence!)
echo "Installing Node.js modules..."
npm init -y
npm install express socket.io cors lowdb

# 8. Start server with PM2
echo "Starting server with PM2..."
pm2 start server.js --name chat-server || pm2 restart chat-server
pm2 save

# 9. PM2 startup for reboot persistence
echo "Setting up PM2 to restart on reboot..."
pm2 startup | tail -2 | head -1 | bash

echo ""
echo "==== INSTALLATION COMPLETE! ===="
echo "Your real-time chat server is now running on port 3000."
echo "Access test: http://YOUR_SERVER_IP:3000"
echo "To view logs: pm2 logs chat-server"
echo "To stop:     pm2 stop chat-server"
echo "To restart:  pm2 restart chat-server"
echo "You can safely close SSH, server will run in background!"
echo ""
echo "If you want to change code, go to ~/chat-server and edit server.js"
echo ""
echo "Admin will see ALL users (old/new), all messages, even after server restarts."
