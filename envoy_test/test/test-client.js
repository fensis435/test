const { io } = require("socket.io-client");
const ip = process.env.IP || "127.0.0.1";
const url = `http://test.${ip}.nip.io`;
const socket = io(url, { path: "/subweb/socket.io" });

socket.on("connect", () => console.log("connected", socket.id));
socket.on("connect_error", (err) => console.error("connect_error", err));
socket.on("message", (m) => console.log("msg", m));
socket.on("disconnect", (reason) => console.log("disconnected", reason));
