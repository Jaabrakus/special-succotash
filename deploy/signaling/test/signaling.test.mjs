import assert from "node:assert/strict";
import test from "node:test";
import { WebSocket } from "ws";
import { createSignalingService } from "../server.mjs";

function openSocket(url) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    socket.once("open", () => resolve(socket));
    socket.once("error", reject);
  });
}

function nextMessage(socket, expectedType) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`Timed out waiting for ${expectedType}`)), 2000);
    socket.once("message", (data) => {
      clearTimeout(timeout);
      const message = JSON.parse(data.toString());
      try {
        assert.equal(message.type, expectedType);
        resolve(message);
      } catch (error) {
        reject(error);
      }
    });
  });
}

test("creates a four-player room and relays only WebRTC negotiation", async () => {
  const service = createSignalingService({ port: 0, maxRoomPeers: 4 });
  const address = await service.listen();
  const url = `ws://127.0.0.1:${address.port}/signal`;
  const sockets = [];
  try {
    const host = await openSocket(url);
    sockets.push(host);
    const hostRoomMessage = nextMessage(host, "room");
    host.send(JSON.stringify({ type: "create", protocol: 1, room: "" }));
    const hostRoom = await hostRoomMessage;
    assert.match(hostRoom.room, /^P2P-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{6}$/);
    assert.equal(hostRoom.peer_id, 1);
    assert.equal(hostRoom.host, true);

    const client = await openSocket(url);
    sockets.push(client);
    const clientRoomMessage = nextMessage(client, "room");
    const peerJoinedMessage = nextMessage(host, "peer_joined");
    client.send(JSON.stringify({ type: "join", protocol: 1, room: hostRoom.room }));
    const [clientRoom, peerJoined] = await Promise.all([clientRoomMessage, peerJoinedMessage]);
    assert.equal(clientRoom.peer_id, 2);
    assert.equal(peerJoined.peer_id, 2);

    const offerMessage = nextMessage(client, "offer");
    host.send(JSON.stringify({
      type: "offer",
      protocol: 1,
      target: 2,
      room: hostRoom.room,
      sdp: "host-offer",
    }));
    const offer = await offerMessage;
    assert.deepEqual(
      { peer_id: offer.peer_id, sdp: offer.sdp },
      { peer_id: 1, sdp: "host-offer" },
    );

    const answerMessage = nextMessage(host, "answer");
    client.send(JSON.stringify({
      type: "answer",
      protocol: 1,
      target: 1,
      room: hostRoom.room,
      sdp: "client-answer",
    }));
    const answer = await answerMessage;
    assert.deepEqual(
      { peer_id: answer.peer_id, sdp: answer.sdp },
      { peer_id: 2, sdp: "client-answer" },
    );

    const candidateMessage = nextMessage(client, "candidate");
    host.send(JSON.stringify({
      type: "candidate",
      protocol: 1,
      target: 2,
      room: hostRoom.room,
      media: "0",
      index: 0,
      sdp: "candidate-data",
    }));
    const candidate = await candidateMessage;
    assert.equal(candidate.sdp, "candidate-data");

    for (const expectedPeerId of [3, 4]) {
      const addedClient = await openSocket(url);
      sockets.push(addedClient);
      const addedRoomMessage = nextMessage(addedClient, "room");
      const addedPeerMessage = nextMessage(host, "peer_joined");
      addedClient.send(JSON.stringify({ type: "join", protocol: 1, room: hostRoom.room }));
      const [addedRoom, addedPeer] = await Promise.all([addedRoomMessage, addedPeerMessage]);
      assert.equal(addedRoom.peer_id, expectedPeerId);
      assert.equal(addedPeer.peer_id, expectedPeerId);
    }

    const overflowClient = await openSocket(url);
    sockets.push(overflowClient);
    const roomFullMessage = nextMessage(overflowClient, "error");
    overflowClient.send(JSON.stringify({ type: "join", protocol: 1, room: hostRoom.room }));
    assert.equal((await roomFullMessage).code, "room_full");

    const pongMessage = nextMessage(client, "pong");
    client.send(JSON.stringify({ type: "ping", protocol: 1 }));
    await pongMessage;
  } finally {
    for (const socket of sockets) socket.close();
    await service.close();
  }
});

test("rejects unknown room codes", async () => {
  const service = createSignalingService({ port: 0 });
  const address = await service.listen();
  const socket = await openSocket(`ws://127.0.0.1:${address.port}/signal`);
  try {
    const errorMessage = nextMessage(socket, "error");
    socket.send(JSON.stringify({ type: "join", protocol: 1, room: "P2P-AAAAAA" }));
    const message = await errorMessage;
    assert.equal(message.code, "room_not_found");
  } finally {
    socket.close();
    await service.close();
  }
});

test("automatically fills 32-player tournament rooms with a server relay topology", async () => {
  const service = createSignalingService({ port: 0, maxTournamentPeers: 4 });
  const address = await service.listen();
  const url = `ws://127.0.0.1:${address.port}/signal`;
  const sockets = [];
  try {
    const host = await openSocket(url);
    sockets.push(host);
    const hostRoomMessage = nextMessage(host, "room");
    host.send(JSON.stringify({ type: "join_tournament", protocol: 1 }));
    const hostRoom = await hostRoomMessage;
    assert.match(hostRoom.room, /^TOUR-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{6}$/);
    assert.equal(hostRoom.peer_id, 1);
    assert.equal(hostRoom.host, true);
    assert.equal(hostRoom.tournament, true);
    assert.equal(hostRoom.max_peers, 4);

    for (const expectedPeerId of [2, 3, 4]) {
      const client = await openSocket(url);
      sockets.push(client);
      const clientRoomMessage = nextMessage(client, "room");
      const peerJoinedMessage = nextMessage(host, "peer_joined");
      client.send(JSON.stringify({ type: "join_tournament", protocol: 1 }));
      const [clientRoom, peerJoined] = await Promise.all([
        clientRoomMessage,
        peerJoinedMessage,
      ]);
      assert.equal(clientRoom.room, hostRoom.room);
      assert.equal(clientRoom.peer_id, expectedPeerId);
      assert.equal(clientRoom.host, false);
      assert.equal(clientRoom.tournament, true);
      assert.equal(peerJoined.peer_id, expectedPeerId);
    }

    const nextTournamentHost = await openSocket(url);
    sockets.push(nextTournamentHost);
    const nextTournamentMessage = nextMessage(nextTournamentHost, "room");
    nextTournamentHost.send(JSON.stringify({ type: "join_tournament", protocol: 1 }));
    const nextTournament = await nextTournamentMessage;
    assert.notEqual(nextTournament.room, hostRoom.room);
    assert.equal(nextTournament.peer_id, 1);
    assert.equal(nextTournament.host, true);
    assert.equal(nextTournament.tournament, true);
  } finally {
    for (const socket of sockets) socket.close();
    await service.close();
  }
});
