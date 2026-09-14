// Offline compact observation data only. Never rewrites original animations.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const input = process.argv[2];
if (!input) throw Error('Usage: node tools/build_source_camera_channels.cjs <decoded motion directory>');
const clips = {};
for (const name of fs.readdirSync(input).filter(n => n.endsWith('.json') && n !== 'manifest.json').sort()) {
  const bytes = fs.readFileSync(path.join(input, name));
  const data = JSON.parse(bytes);
  if (!Array.isArray(data.tracks)) continue;
  const track = data.tracks.find(t => t.name === 'skel_root');
  if (!track || !track.positions_raw?.length) continue;
  if (!(data.duration > 0 && data.frames > 0) || !track.positions_raw.every(p => p.length === 3 && p.every(Number.isFinite))) throw Error(name);
  clips[name.slice(0,-5)] = {sha256:crypto.createHash('sha256').update(bytes).digest('hex'),duration:data.duration,frames:data.frames,positions_raw:track.positions_raw};
}
const document = {schema_version:1,position_divisor:256,channel:'skel_root',space:'decoded model-local source units; runtime extraction applied by camera policy',clips};
const output = path.join(root,'config/source_camera_channels.json');
fs.writeFileSync(output,JSON.stringify(document)+'\n');
console.log('SOURCE_CAMERA_CHANNELS_BUILD',Object.keys(clips).length,'channels',fs.statSync(output).size,'bytes');
