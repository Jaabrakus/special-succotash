import { createServer } from "node:http";
import { randomInt } from "node:crypto";
import { fileURLToPath } from "node:url";
import { WebSocket, WebSocketServer } from "ws";

const PROTOCOL_VERSION = 1;
const DEFAULT_PORT = 10000;
const DEFAULT_MAX_PRIVATE_PEERS = 4;
const DEFAULT_MAX_TOURNAMENT_PEERS = 32;
const MAX_MESSAGE_BYTES = 256 * 1024;
const RATE_WINDOW_MS = 10_000;
const RATE_LIMIT_MESSAGES = 180;
const ROOM_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";

function normalizeRoomCode(value) {
  return String(value ?? "").trim().toUpperCase().replaceAll(" ", "");
}

function createRoomCode(rooms) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    let suffix = "";
    for (let index = 0; index < 6; index += 1) {
      suffix += ROOM_ALPHABET[randomInt(ROOM_ALPHABET.length)];
    }
    const roomCode = `P2P-${suffix}`;
    if (!rooms.has(roomCode)) return roomCode;
  }
  throw new Error("Could not allocate a unique room code");
}

function send(socket, message) {
  if (socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(message));
  }
}

function error(socket, code, message) {
  send(socket, { type: "error", code, message, protocol: PROTOCOL_VERSION });
}

function nextPeerId(room) {
  for (let peerId = 2; peerId <= room.maxPeers; peerId += 1) {
    if (!room.peers.has(peerId)) return peerId;
  }
  return 0;
}

export function createSignalingService(options = {}) {
  const port = Number(options.port ?? process.env.PORT ?? DEFAULT_PORT);
  const maxPrivatePeers = Math.max(
    2,
    Math.min(4, Number(options.maxPrivatePeers ?? options.maxRoomPeers ?? DEFAULT_MAX_PRIVATE_PEERS)),
  );
  const maxTournamentPeers = Math.max(
    4,
    Math.min(
      32,
      Number(
        options.maxTournamentPeers
        ?? process.env.SOCOM_WEBRTC_MAX_TOURNAMENT_PEERS
        ?? DEFAULT_MAX_TOURNAMENT_PEERS
      ),
    ),
  );
  const rooms = new Map();
  const clients = new Map();

  const httpServer = createServer((request, response) => {
    if (request.url === "/healthz") {
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({
        ok: true,
        service: "socom-141-webrtc-signaling",
        protocol: PROTOCOL_VERSION,
        rooms: rooms.size,
        clients: clients.size,
        tournament_capacity: maxTournamentPeers,
      }));
      return;
    }
    response.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
    response.end("SOCOM-141 WebRTC signaling is online.\n");
  });

  const websocketServer = new WebSocketServer({
    noServer: true,
    maxPayload: MAX_MESSAGE_BYTES,
    perMessageDeflate: false,
  });

  httpServer.on("upgrade", (request, socket, head) => {
    const requestUrl = new URL(request.url ?? "/", "http://localhost");
    if (requestUrl.pathname !== "/signal") {
      socket.destroy();
      return;
    }
    websocketServer.handleUpgrade(request, socket, head, (websocket) => {
      websocketServer.emit("connection", websocket, request);
    });
  });

  function leaveRoom(socket) {
    const state = clients.get(socket);
    if (!state?.roomCode) return;
    const room = rooms.get(state.roomCode);
    if (!room) return;
    room.peers.delete(state.peerId);
    if (state.peerId === 1) {
      for (const [peerId, peerSocket] of room.peers) {
        send(peerSocket, { type: "host_left", peer_id: 1, protocol: PROTOCOL_VERSION });
        clients.set(peerSocket, { ...clients.get(peerSocket), roomCode: "", peerId: 0 });
      }
      rooms.delete(state.roomCode);
    } else {
      send(room.peers.get(1), {
        type: "peer_left",
        peer_id: state.peerId,
        protocol: PROTOCOL_VERSION,
      });
      if (room.peers.size === 0) rooms.delete(state.roomCode);
    }
    clients.set(socket, { ...state, roomCode: "", peerId: 0 });
  }

  function createRoom(socket) {
    const state = clients.get(socket);
    if (state.roomCode) {
      error(socket, "already_joined", "Leave the current room before creating another.");
      return;
    }
    const roomCode = createRoomCode(rooms);
    const room = {
      host: socket,
      kind: "private",
      maxPeers: maxPrivatePeers,
      peers: new Map([[1, socket]]),
    };
    rooms.set(roomCode, room);
    clients.set(socket, { ...state, roomCode, peerId: 1 });
    send(socket, {
      type: "room",
      room: roomCode,
      peer_id: 1,
      host: true,
      max_peers: room.maxPeers,
      tournament: false,
      protocol: PROTOCOL_VERSION,
    });
  }

  function joinRoom(socket, requestedRoomCode) {
    const state = clients.get(socket);
    if (state.roomCode) {
      error(socket, "already_joined", "Leave the current room before joining another.");
      return;
    }
    const roomCode = normalizeRoomCode(requestedRoomCode);
    const room = rooms.get(roomCode);
    if (!room) {
      error(socket, "room_not_found", "That P2P room does not exist.");
      return;
    }
    const peerId = nextPeerId(room);
    if (peerId === 0) {
      error(socket, "room_full", "That private 2v2 room is full.");
      return;
    }
    room.peers.set(peerId, socket);
    clients.set(socket, { ...state, roomCode, peerId });
    send(socket, {
      type: "room",
      room: roomCode,
      peer_id: peerId,
      host: false,
      max_peers: room.maxPeers,
      tournament: room.kind === "tournament",
      protocol: PROTOCOL_VERSION,
    });
    send(room.host, {
      type: "peer_joined",
      peer_id: peerId,
      protocol: PROTOCOL_VERSION,
    });
  }

  function joinTournament(socket) {
    const state = clients.get(socket);
    if (state.roomCode) {
      error(socket, "already_joined", "Leave the current room before joining a tournament.");
      return;
    }
    let roomCode = "";
    let room = null;
    for (const [candidateCode, candidateRoom] of rooms) {
      if (
        candidateRoom.kind === "tournament"
        && candidateRoom.peers.size < candidateRoom.maxPeers
      ) {
        roomCode = candidateCode;
        room = candidateRoom;
        break;
      }
    }
    if (room === null) {
      roomCode = createRoomCode(rooms).replace("P2P-", "TOUR-");
      room = {
        host: socket,
        kind: "tournament",
        maxPeers: maxTournamentPeers,
        peers: new Map([[1, socket]]),
      };
      rooms.set(roomCode, room);
      clients.set(socket, { ...state, roomCode, peerId: 1 });
      send(socket, {
        type: "room",
        room: roomCode,
        peer_id: 1,
        host: true,
        max_peers: room.maxPeers,
        tournament: true,
        protocol: PROTOCOL_VERSION,
      });
      return;
    }
    joinRoom(socket, roomCode);
  }

  function relay(socket, message) {
    const state = clients.get(socket);
    const room = rooms.get(state?.roomCode);
    if (!room || !state.peerId) {
      error(socket, "not_joined", "Join a room before sending WebRTC negotiation data.");
      return;
    }
    const target = Number(message.target);
    const type = String(message.type ?? "");
    const validDirection = (
      (type === "offer" && state.peerId === 1 && target > 1)
      || (type === "answer" && state.peerId > 1 && target === 1)
      || (type === "candidate" && (state.peerId === 1 || target === 1))
    );
    if (!validDirection || !room.peers.has(target)) {
      error(socket, "invalid_target", "The WebRTC negotiation target is invalid.");
      return;
    }
    const relayed = {
      type,
      peer_id: state.peerId,
      protocol: PROTOCOL_VERSION,
    };
    if (type === "candidate") {
      relayed.media = String(message.media ?? "");
      relayed.index = Number(message.index ?? 0);
      relayed.sdp = String(message.sdp ?? "");
    } else {
      relayed.sdp = String(message.sdp ?? "");
    }
    send(room.peers.get(target), relayed);
  }

  function handleMessage(socket, data) {
    const state = clients.get(socket);
    const now = Date.now();
    if (now - state.rateWindowStartedAt >= RATE_WINDOW_MS) {
      state.rateWindowStartedAt = now;
      state.rateCount = 0;
    }
    state.rateCount += 1;
    if (state.rateCount > RATE_LIMIT_MESSAGES) {
      socket.close(1008, "rate limit exceeded");
      return;
    }
    let message;
    try {
      message = JSON.parse(data.toString());
    } catch {
      error(socket, "invalid_json", "Signaling messages must be valid JSON.");
      return;
    }
    if (Number(message.protocol) !== PROTOCOL_VERSION) {
      error(socket, "protocol_mismatch", "The signaling protocol version does not match.");
      return;
    }
    switch (message.type) {
      case "create": createRoom(socket); break;
      case "join": joinRoom(socket, message.room); break;
      case "join_tournament": joinTournament(socket); break;
      case "offer":
      case "answer":
      case "candidate": relay(socket, message); break;
      case "leave": leaveRoom(socket); break;
      case "ping": send(socket, { type: "pong", protocol: PROTOCOL_VERSION }); break;
      default: error(socket, "unknown_message", "Unknown signaling message type.");
    }
  }

  websocketServer.on("connection", (socket) => {
    clients.set(socket, {
      roomCode: "",
      peerId: 0,
      rateWindowStartedAt: Date.now(),
      rateCount: 0,
    });
    socket.on("message", (data) => handleMessage(socket, data));
    socket.on("close", () => {
      leaveRoom(socket);
      clients.delete(socket);
    });
    socket.on("error", () => {
      leaveRoom(socket);
      clients.delete(socket);
    });
  });

  return {
    httpServer,
    websocketServer,
    rooms,
    clients,
    async listen() {
      await new Promise((resolve, reject) => {
        httpServer.once("error", reject);
        httpServer.listen(port, "0.0.0.0", resolve);
      });
      return httpServer.address();
    },
    async close() {
      for (const socket of clients.keys()) socket.close(1001, "service shutdown");
      await new Promise((resolve) => websocketServer.close(resolve));
      await new Promise((resolve) => httpServer.close(resolve));
    },
  };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const service = createSignalingService();
  service.listen().then((address) => {
    console.log(`SOCOM_WEBRTC_SIGNALING_READY port=${address.port} protocol=${PROTOCOL_VERSION}`);
  }).catch((startupError) => {
    console.error(startupError);
    process.exitCode = 1;
  });
}
