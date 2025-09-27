const { io } = require("socket.io-client");
const socket = io("http://test.${IP}.nip.io", { path: "/subweb/socket.io" });
socket.on("connect", () => console.log("connected", socket.id));
socket.on("message", m => console.log("msg", m));
