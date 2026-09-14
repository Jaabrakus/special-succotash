'use strict';
// Consumer of the saved offline catalog. Does not import or execute source files.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {openIso} = require('./extract_iso_camera_reference.cjs');
const {range, hashRange, hashFile, freshOutput, policy} = require('./source_asset_inventory.cjs');

function selection(catalog, scope = 'nonmovie') {
  assert(catalog.schema_version === 1 && Array.isArray(catalog.records), 'invalid catalog');
  assert(['nonmovie', 'motions'].includes(scope), 'unsupported recovery scope');
  const motionIds = scope === 'motions' ? new Set(require('./decode_source_motion_library.cjs').candidates(catalog).clips.map(r => r.id)) : null;
  const unique = new Map();
  for (const record of catalog.records) {
    assert(typeof record.top_file === 'string' && typeof record.id === 'string', 'invalid identity');
    range(record.offset, record.size, catalog.source.size);
    assert(/^[a-f0-9]{64}$/.test(record.sha256), 'invalid hash/output name');
    if (motionIds && !motionIds.has(record.id)) continue;
    if (!record.size || record.container || /\.PSS$/i.test(record.top_file)) continue;
    if (!unique.has(record.sha256)) unique.set(record.sha256, record);
  }
  return [...unique.values()];
}
function recover(catalogFile, output, progress = () => {}, scope = 'nonmovie') {
  const catalog = JSON.parse(fs.readFileSync(catalogFile, 'utf8'));
  const candidates = selection(catalog, scope), existing = [], missing = [];
  assert(!fs.existsSync(output), 'output already exists');
  for (const r of candidates) {
    // Recheck now: a stale manifest is not proof that a usable copy still exists.
    if (r.existing_raw_file && fs.existsSync(r.existing_raw_file) &&
      fs.statSync(r.existing_raw_file).size === r.size && hashFile(r.existing_raw_file) === r.sha256) existing.push(r);
    else missing.push(r);
  }
  const bytes = missing.reduce((n,r) => n + r.size, 0);
  assert(bytes <= policy.max_recovery_bytes, 'recovery byte cap exceeded; use a reviewed smaller batch');
  const iso = openIso(catalog.source.iso);
  let directoryPath;
  try {
    assert.equal(iso.size, catalog.source.size, 'source size changed');
    assert.equal(hashRange(iso, 0, iso.size), catalog.source.sha256, 'source hash changed');
    // Validate all selected ranges BEFORE creating any output.
    for (const r of missing) assert.equal(hashRange(iso, r.offset, r.size), r.sha256, 'catalog range hash mismatch: ' + r.id);
    directoryPath = freshOutput(output, bytes + 16 * 1024 * 1024);
    const files = existing.map(r => ({sha256: r.sha256, size: r.size, source_id: r.id, file: r.existing_raw_file, status: 'verified_existing_raw'}));
    for (const [index, r] of missing.entries()) {
      const disk = fs.statfsSync(directoryPath);
      assert(disk.bavail * disk.bsize - r.size >= policy.minimum_free_bytes, 'free-space reserve changed; stopped before next payload');
      const filename = r.sha256 + '.raw', target = path.join(directoryPath, filename);
      const fd = fs.openSync(target, 'wx');
      try {
        for (let done = 0; done < r.size; done += policy.chunk_bytes) {
          const b = iso.readRange(r.offset + done, Math.min(policy.chunk_bytes, r.size - done));
          let written = 0;
          while (written < b.length) {
            const count = fs.writeSync(fd, b, written, b.length - written);
            assert(count > 0, 'short output write'); written += count;
          }
        }
      } finally { fs.closeSync(fd); }
      assert.equal(hashFile(target), r.sha256, 'recovered file hash mismatch');
      files.push({sha256: r.sha256, size: r.size, source_id: r.id, file: filename, status: 'recovered_raw_not_decoded'});
      if (index % 1000 === 0) progress(`Recovered ${index + 1}/${missing.length} unique payloads`);
    }
    const report = {schema_version: 1, scope, status: 'complete_selected_scope_raw_recovery_not_full_disc_recreation',
      catalog: path.resolve(catalogFile), catalog_sha256: hashFile(catalogFile), source_sha256: catalog.source.sha256,
      summary: {recovered_files: missing.length, recovered_bytes: bytes, verified_existing_files: existing.length,
        indexed_in_place_movies: catalog.records.filter(r => !r.parent && /\.PSS$/i.test(r.top_file)).length,
        opaque_containers_not_decoded: catalog.issues.length,
        newly_decoded_assets: 0, newly_recreated_assets: 0, newly_integrated_assets: 0}, files};
    fs.writeFileSync(path.join(directoryPath, 'recovery.json'), JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
    return report;
  } catch (error) {
    if (directoryPath) fs.writeFileSync(path.join(directoryPath, 'INCOMPLETE.json'), JSON.stringify({error: error.message, note: 'Partial files preserved; no success manifest. Retry into a fresh directory after review.'}, null, 2), {flag: 'wx'});
    throw error;
  } finally { iso.close(); }
}
if (require.main === module) {
  const [catalog, output, scope = 'nonmovie'] = process.argv.slice(2);
  assert(catalog && output, 'usage: node tools/recover_source_assets.cjs CATALOG_JSON NEW_OUTPUT_DIRECTORY [nonmovie|motions]');
  console.log('SOURCE_ASSET_RECOVERY ' + JSON.stringify(recover(catalog, output, console.log, scope).summary));
}
module.exports = {selection, recover};
