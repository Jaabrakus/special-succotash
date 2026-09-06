import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import net from 'node:net';
import { createGateway } from '../deploy/server/http_gateway.mjs';
const godot = process.env.GODOT_BIN || '/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot';
const root = new URL('../', import.meta.url).pathname;
const reserve = net.createServer(); reserve.listen(0, '127.0.0.1'); await once(reserve, 'listening');
const backendPort = reserve.address().port; await new Promise(r => reserve.close(r));
const args = ['--headless', '--path', root, '--script', 'res://tools/http_gateway_peer_regression.gd'];
const backend = spawn(godot, [...args, '--log-file', '/private/tmp/141-gateway-backend.log', '--', String(backendPort)], { env: {...process.env, SOCOM_SERVER_BIND_ADDRESS:'127.0.0.1'} });
let output = ''; backend.stdout.on('data', d => {output += d;}); backend.stderr.on('data', d => {output += d;});
const gateway = createGateway(0, backendPort);
try {
  for (let i=0; !output.includes('GATEWAY_BACKEND_READY') && i<100; i++) await new Promise(r=>setTimeout(r,50));
  assert.match(output, /GATEWAY_BACKEND_READY/);
  gateway.listen(); await once(gateway.server, 'listening');
  const port = gateway.server.address().port;
  const url = `http://127.0.0.1:${port}`;
  for (const path of ['/', '/healthz', '/', '/healthz']) assert.equal((await fetch(url+path)).status, 200);
  assert.equal((await fetch(url+'/project.godot')).status, 404);
  const client = spawn(godot, [...args, '--log-file', '/private/tmp/141-gateway-client.log', '--', '--client', String(port)]);
  let result = ''; client.stdout.on('data', d=>{result += d;}); client.stderr.on('data', d=>{result += d;});
  const [code] = await once(client, 'exit'); assert.equal(code,0,result); assert.match(result,/GATEWAY_GODOT_ROUNDTRIP_PASS/);
  backend.kill('SIGTERM'); await once(backend,'exit');
  assert.equal((await fetch(url+'/healthz')).status, 503);
  assert.doesNotMatch(output, /Not enough response headers/);
  console.log('HTTP_GATEWAY_PASS: HTTP 200, unknown path 404, Godot binary roundtrip, backend down 503, no header errors');
} finally { backend.kill('SIGTERM'); await gateway.close(); }

async function freePort() {
  const server = net.createServer(); server.listen(0, '127.0.0.1'); await once(server,'listening');
  const port = server.address().port; await new Promise(r=>server.close(r)); return port;
}
const publicPort = await freePort();
const internalPort = await freePort();
const supervisor = spawn(process.execPath, [root+'deploy/server/http_gateway.mjs', godot, ...args,
  '--log-file','/private/tmp/141-gateway-supervisor.log','--',String(internalPort)], {
  env: {...process.env, SOCOM_SERVER_PORT:String(publicPort), SOCOM_INTERNAL_PORT:String(internalPort), SOCOM_SERVER_BIND_ADDRESS:'127.0.0.1'}, stdio:'ignore'
});
try {
  let ready = false;
  for (let i=0; i<50 && !ready; i++) {
    try { ready = (await fetch(`http://127.0.0.1:${publicPort}/healthz`)).status===200; } catch {}
    if (!ready) await new Promise(r=>setTimeout(r,100));
  }
  assert.equal(ready,true,'supervised Godot must become ready');
  const exited = once(supervisor,'exit'); supervisor.kill('SIGTERM');
  assert.equal((await exited)[0],0,'SIGTERM exits cleanly');
  await assert.rejects(fetch(`http://127.0.0.1:${publicPort}/healthz`));
  const backendClosed = await new Promise(resolve=>{
    const socket=net.connect(internalPort,'127.0.0.1');
    socket.on('connect',()=>{socket.destroy();resolve(false);});
    socket.on('error',()=>resolve(true));
  });
  assert.equal(backendClosed,true,'shutdown must stop Godot too');
  console.log('HTTP_GATEWAY_SUPERVISOR_PASS: SIGTERM closes public and internal listeners');
} finally { supervisor.kill('SIGTERM'); }
