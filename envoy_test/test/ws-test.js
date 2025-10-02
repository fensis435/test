const { io } = require("socket.io-client");
const url = "http://test.dev.local";
const socket = io(url, { path: "/subweb/socket.io", transports: ["websocket"] });
socket.on("connect", () => console.log("connected", socket.id));
socket.on("connect_error", (err) => console.error("connect_error", err));
socket.on("message", (m) => console.log("msg", m));
socket.on("disconnect", (r) => console.log("disconnected", r));
