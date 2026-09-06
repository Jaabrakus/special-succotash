// Deployment-only HTTP boundary. No gameplay packets are interpreted here.
import http from 'node:http';
import { randomBytes } from 'node:crypto';
import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';

export function createGateway(port, backendPort) {
  const sockets = new Set();
  const options = { hostname: '127.0.0.1', port: backendPort, agent: false };
  let healthPending;
  function healthy() {
    if (healthPending) return healthPending;
    healthPending = new Promise(resolve => {
      const request = http.request({ ...options, path: '/', headers: {
        Connection: 'Upgrade', Upgrade: 'websocket',
        'Sec-WebSocket-Version': '13', 'Sec-WebSocket-Key': randomBytes(16).toString('base64'),
      }});
      const timer = setTimeout(() => { request.destroy(); resolve(false); }, 2000);
      const finish = value => { clearTimeout(timer); resolve(value); };
      request.on('error', () => finish(false));
      request.on('response', response => { response.resume(); finish(false); });
      request.on('upgrade', (_response, socket) => {
        socket.on('error', () => {});
        // Masked, empty RFC6455 close frame; never send a multiplayer action.
        socket.end(Buffer.from([0x88, 0x80, 0, 0, 0, 0]));
        socket.setTimeout(500, () => socket.destroy());
        finish(true);
      });
      request.end();
    }).finally(() => { healthPending = null; });
    return healthPending;
  }
  const server = http.createServer({ maxHeaderSize: 8192 }, async (request, response) => {
    if (!['GET', 'HEAD'].includes(request.method) || !['/', '/healthz'].includes(request.url)) {
      response.writeHead(404); response.end(); return;
    }
    const ready = await healthy();
    response.writeHead(ready ? 200 : 503, { 'Content-Type': 'text/plain', 'Cache-Control': 'no-store' });
    response.end(ready ? 'ready\n' : 'unavailable\n');
  });
  server.headersTimeout = 5000;
  server.requestTimeout = 5000;
  server.maxConnections = 256;
  server.on('connection', socket => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
    socket.on('error', () => {});
  });
  server.on('upgrade', (request, client, head) => {
    if (request.method !== 'GET' || !['/', '/game'].includes(request.url)
        || request.headers.upgrade?.toLowerCase() !== 'websocket'
        || request.headers['sec-websocket-version'] !== '13'
        || !/^[A-Za-z0-9+/]{22}==$/.test(request.headers['sec-websocket-key'] || '')) {
      client.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n'); return;
    }
    client.pause();
    const upstream = http.request({ ...options, path: request.url, headers: request.headers });
    const timer = setTimeout(() => { upstream.destroy(); client.destroy(); }, 4000);
    client.on('close', () => { clearTimeout(timer); upstream.destroy(); });
    upstream.on('error', () => { clearTimeout(timer); client.destroy(); });
    upstream.on('response', response => { response.resume(); clearTimeout(timer); client.end('HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n'); });
    upstream.on('upgrade', (response, backend, backendHead) => {
      clearTimeout(timer);
      backend.on('error', () => client.destroy());
      backend.on('close', () => client.destroy());
      client.on('close', () => backend.destroy());
      client.setTimeout(0);
      backend.setTimeout(0);
      client.setNoDelay(true); backend.setNoDelay(true);
      let headers = 'HTTP/1.1 101 Switching Protocols\r\n';
      for (let i = 0; i < response.rawHeaders.length; i += 2) headers += `${response.rawHeaders[i]}: ${response.rawHeaders[i + 1]}\r\n`;
      client.write(headers + '\r\n');
      if (backendHead.length) client.write(backendHead);
      if (head.length) backend.write(head);
      client.pipe(backend); backend.pipe(client); client.resume();
    });
    upstream.end();
  });
  return { server, listen: () => server.listen(port, '0.0.0.0'), close: () => {
    for (const socket of sockets) socket.destroy();
    return new Promise(resolve => server.close(resolve));
  }};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.env.SOCOM_SERVER_PORT);
  const backendPort = Number(process.env.SOCOM_INTERNAL_PORT);
  if (![port, backendPort].every(p => Number.isInteger(p) && p > 0 && p <= 65535) || port === backendPort || !process.argv[2]) {
    throw new Error('Invalid gateway ports or missing Godot command');
  }
  const gateway = createGateway(port, backendPort);
  const child = spawn(process.argv[2], process.argv.slice(3), { stdio: 'inherit' });
  let stopping = false;
  function stop(code) {
    if (stopping) return;
    stopping = true;
    gateway.close();
    child.kill('SIGTERM');
    const deadline = setTimeout(() => { child.kill('SIGKILL'); process.exit(code); }, 5000);
    if (child.exitCode !== null || child.signalCode !== null) { clearTimeout(deadline); process.exit(code); }
    else child.once('exit', () => { clearTimeout(deadline); process.exit(code); });
  }
  child.on('error', () => stop(1));
  child.on('exit', () => stop(1));
  gateway.server.on('error', () => stop(1));
  process.on('SIGTERM', () => stop(0));
  process.on('SIGINT', () => stop(0));
  gateway.listen();
  console.log(`HTTP/WebSocket gateway listening on ${port}; Godot loopback ${backendPort}`);
}
