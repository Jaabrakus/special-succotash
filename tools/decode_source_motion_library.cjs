'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {hashFile, freshOutput} = require('./source_asset_inventory.cjs');
const sha = b => crypto.createHash('sha256').update(b).digest('hex');

function candidates(catalog) {
  const banks = catalog.records.filter(r => /(?:^|[\\/])MOTION_[PS]\.ZAR$/i.test(r.name));
  const ids = new Set(banks.map(r => r.directory_alias_of || r.id));
  return {banks, clips: catalog.records.filter(r => ids.has(r.parent) && r.size > 0 && !r.container)};
}
function validateMotion(decoded) {
  assert(decoded.version === 5 && decoded.duration > 0 && Number.isFinite(decoded.duration), 'invalid motion duration/version');
  assert(Number.isInteger(decoded.samples) && decoded.samples === decoded.frames + 1, 'sample count mismatch');
  assert(decoded.tracks.length === decoded.bone_count && decoded.bone_count > 0, 'bone count mismatch');
  assert(new Set(decoded.tracks.map(t => t.name)).size === decoded.bone_count, 'duplicate bone names');
  for (const track of decoded.tracks) {
    for (const [key, width] of [['positions_raw', 3], ['rotations_raw', 4]]) {
      const values = track[key];
      assert(values.length === 1 || values.length === decoded.samples, 'track sample count mismatch');
      for (const value of values) assert(value.length === width && value.every(n => Number.isInteger(n) && n >= -32768 && n <= 32767), 'invalid quantized track');
    }
  }
}
function decode(catalogFile, recoveryFile, decoderFile, output) {
  assert(!fs.existsSync(output), 'output already exists');
  const catalog = JSON.parse(fs.readFileSync(catalogFile, 'utf8'));
  const recovery = JSON.parse(fs.readFileSync(recoveryFile, 'utf8'));
  assert.equal(recovery.catalog_sha256, hashFile(catalogFile), 'recovery catalog mismatch');
  assert.equal(recovery.source_sha256, catalog.source.sha256, 'recovery source mismatch');
  const {motion} = require(path.resolve(decoderFile)); // Explicit, reviewed local converter; never disc executable data.
  assert.equal(typeof motion, 'function');
  const files = new Map(recovery.files.map(r => [r.sha256, r]));
  const {banks, clips} = candidates(catalog), unique = new Map(), deferred = [];
  for (const record of clips) {
    if (unique.has(record.sha256)) {unique.get(record.sha256).sources.push({id: record.id, name: record.name, bank: record.parent}); continue;}
    const recovered = files.get(record.sha256);
    assert(recovered, 'missing recovered clip ' + record.id);
    const file = path.resolve(path.dirname(recoveryFile), recovered.file);
    assert.equal(hashFile(file), record.sha256, 'raw clip hash mismatch');
    const raw = fs.readFileSync(file);
    let decoded;
    try {decoded = motion(raw); validateMotion(decoded);}
    catch (error) {deferred.push({id: record.id, name: record.name, sha256: record.sha256, reason: error.message}); continue;}
    const data = JSON.stringify(decoded) + '\n';
    unique.set(record.sha256, {raw_sha256: record.sha256, decoded_sha256: sha(data),
      sources: [{id: record.id, name: record.name, bank: record.parent}], duration: decoded.duration,
      samples: decoded.samples, bones: decoded.bone_count, file: record.sha256 + '.json', data});
  }
  const bytes = [...unique.values()].reduce((n,r) => n + Buffer.byteLength(r.data), 0);
  assert(bytes <= 128 * 1024 * 1024, 'decoded motion batch exceeds 128 MiB cap');
  const dir = freshOutput(output, bytes + 4 * 1024 * 1024);
  for (const entry of unique.values()) fs.writeFileSync(path.join(dir, entry.file), entry.data, {flag:'wx'});
  const entries = [...unique.values()].map(({data,...entry}) => entry);
  const report = {schema_version: 1, status: 'decoded_quantized_tracks_not_retargeted_or_runtime_replacements',
    catalog_sha256: hashFile(catalogFile), recovery_sha256: hashFile(recoveryFile), source_sha256: catalog.source.sha256,
    decoder: {file: path.resolve(decoderFile), sha256: hashFile(decoderFile)},
    summary: {motion_banks: banks.length, indexed_clip_records: clips.length, unique_decoded_clips: unique.size,
      decoded_bytes: bytes, deferred_records: deferred.length, newly_retargeted: 0, newly_recreated_in_blender: 0, newly_integrated: 0},
    limitations: ['Original integer tracks preserved; source transform units, skeleton and game blending are separate contracts.',
      'Existing Blender workbenches and gameplay resources were not overwritten.', 'Bone decoding does not establish original mesh/skin deformation or executable game behavior.'],
    banks: banks.map(r => ({id:r.id, name:r.name, top_file:r.top_file, directory_alias_of:r.directory_alias_of || null})), entries, deferred};
  fs.writeFileSync(path.join(dir,'manifest.json'), JSON.stringify(report,null,2) + '\n',{flag:'wx'});
  return report;
}
if (require.main === module) {
  const [catalog,recovery,decoder,output] = process.argv.slice(2);
  assert(catalog && recovery && decoder && output, 'usage: node tools/decode_source_motion_library.cjs CATALOG RECOVERY REVIEWED_DECODER_CJS NEW_OUTPUT');
  console.log('SOURCE_MOTION_LIBRARY ' + JSON.stringify(decode(catalog,recovery,decoder,output).summary));
}
module.exports = {candidates, validateMotion, decode};
