#!/bin/bash

echo "Updating system..."
sudo apt-get update

echo "Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs git

echo "Installing PM2 (process manager)..."
sudo npm install -g pm2

echo "Creating chat-server directory..."
mkdir -p ~/chat-server
cd ~/chat-server

echo "Writing server.js..."
cat << 'EOF' > server.js
const express = require('express');
const app = express();
const http = require('http').createServer(app);
const io = require('socket.io')(http, { cors: { origin: "*" } });
const cors = require('cors');

app.use(cors());
app.use(express.json());

let users = {}; // { socketId: {name, id} }
let messages = {}; // { userId: [ {from, text, time} ] }

io.on('connection', (socket) => {
    let currentUser = null;

    socket.on('register', (name) => {
        currentUser = { id: socket.id, name: name || ("User" + Date.now()) };
        users[socket.id] = currentUser;
        if (!messages[currentUser.id]) messages[currentUser.id] = [];
        io.emit('update_clients', Object.values(users));
        socket.emit('chat_history', messages[currentUser.id]);
    });

    socket.on('get_clients', () => {
        socket.emit('update_clients', Object.values(users));
    });

    socket.on('user_message', (msg) => {
        if (!currentUser) return;
        const message = { from: currentUser.name, text: msg, time: Date.now(), sender: "user" };
        if (!messages[currentUser.id]) messages[currentUser.id] = [];
        messages[currentUser.id].push(message);
        io.to(currentUser.id).emit('chat_history', messages[currentUser.id]);
        io.emit('alert_admin', currentUser.name); // Alert for admin
    });

    socket.on('admin_message', ({userId, text}) => {
        const message = { from: "Admin", text, time: Date.now(), sender: "admin" };
        if (!messages[userId]) messages[userId] = [];
        messages[userId].push(message);
        io.to(userId).emit('chat_history', messages[userId]);
    });

    socket.on('join_chat', (userId) => {
        socket.join(userId);
        socket.emit('chat_history', messages[userId] || []);
    });

    socket.on('disconnect', () => {
        if (currentUser) {
            delete users[socket.id];
            io.emit('update_clients', Object.values(users));
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

echo "Installing Node.js modules..."
npm init -y
npm install express socket.io cors

echo "Starting server with PM2..."
pm2 start server.js --name chat-server
pm2 save
pm2 startup

echo ""
echo "ALL DONE! Your real-time chat server is running on port 3000."
echo "You may need to open port 3000 on your DigitalOcean droplet firewall."
echo "To view logs: pm2 logs chat-server"
