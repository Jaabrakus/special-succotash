// Extract every clip in the primary motion archive to a NEW offline directory.
// Audit references, not gameplay equivalence. Never overwrites runtime assets.
const fs = require('node:fs'), path = require('node:path');
const assert = require('node:assert/strict'), crypto = require('node:crypto');
const {openIso} = require('./extract_iso_camera_reference.cjs');
const sha = data => crypto.createHash('sha256').update(data).digest('hex');

function audit(isoFile, decoderDirectory, project) {
  const {archive, motion} = require(path.resolve(decoderDirectory, 'extract.cjs'));
  const iso = openIso(isoFile);
  let source;
  try { source = iso.find('RUN/MOTION_P.ZAR'); } finally { iso.close(); }
  const reference = JSON.parse(fs.readFileSync(path.join(project, 'assets/animations/seal_reference/manifest.json')));
  const firing = JSON.parse(fs.readFileSync(path.join(project, 'assets/animations/seal_firing_reference/manifest.json'))).entries;
  const retargets = new Map(reference.clips.map(c => [c.name, [c.path]]));
  for (const [name, entry] of Object.entries(firing)) retargets.set(name, [entry.path, entry.composed_path].filter(Boolean));
  const gameplay = JSON.parse(fs.readFileSync(path.join(project, 'assets/animations/seal_gameplay/manifest.json'))).states;
  const decoded = [], consumers = new Map(), visited = new Set();
  function add(name, route) { if (!consumers.has(name)) consumers.set(name, new Set()); consumers.get(name).add(route); }
  function scan(value, route) {
    if (Array.isArray(value)) {value.forEach((v,i) => scan(v, route + '/' + i)); return;}
    if (value && typeof value === 'object') {for (const [key,v] of Object.entries(value)) scan(v, route + '/' + key); return;}
    if (typeof value !== 'string' || !value.startsWith('res://assets/animations/') || !value.endsWith('.tres')) return;
    const key = route + ':' + value;
    if (visited.has(key)) return;
    visited.add(key);
    const text = fs.readFileSync(path.join(project, value.slice(6)), 'utf8');
    for (const match of text.matchAll(/(?:metadata\/source_name|resource_name) = "([^"]+)"/g)) add(match[1], route);
    for (const entry of Object.values(gameplay)) if (entry.path === value) add(entry.source, route);
    for (const [name, entry] of Object.entries(firing)) if ([entry.path, entry.composed_path].includes(value)) {
      add(name, route); if (entry.base) add(entry.base, route + '/composition_base');
    }
    // source_asset chains are tracked separately to avoid an infinite malformed cycle.
    followSources(text, route, new Set([value]));
  }
  function followSources(text, route, ancestors) {
    for (const match of text.matchAll(/metadata\/source_asset = "(res:\/\/assets\/animations\/[^\"]+\.tres)"/g)) {
      const resource = match[1]; assert(!ancestors.has(resource), 'cyclic source_asset');
      const sourceText = fs.readFileSync(path.join(project, resource.slice(6)), 'utf8');
      for (const name of sourceText.matchAll(/(?:metadata\/source_name|resource_name) = "([^"]+)"/g)) add(name[1], route + '/source_asset');
      followSources(sourceText, route, new Set([...ancestors,resource]));
    }
  }
  scan(JSON.parse(fs.readFileSync(path.join(project, 'config/operator_animation_map.json'))), 'operator_profile');
  const entries = archive(source.bytes).entries;
  const clips = entries.map(entry => {
    const bytes = source.bytes.subarray(entry.offset, entry.offset + entry.size), data = motion(bytes);
    assert(/^[\w.-]+$/.test(entry.name), 'unsafe output name');
    let maxQuaternionNormError = 0;
    for (const track of data.tracks) for (const q of track.rotations_raw) {
      const norm = Math.hypot(...q) / 32768;
      assert(norm > 0 && Number.isFinite(norm), 'invalid quaternion');
      maxQuaternionNormError = Math.max(maxQuaternionNormError, Math.abs(1 - norm));
    }
    decoded.push({name: entry.name, bytes, data});
    const paths = retargets.get(entry.name) || [];
    for (const p of paths) assert(fs.existsSync(path.join(project, p.slice(6))), 'missing retarget: ' + p);
    return {name: entry.name, offset: entry.offset, size: entry.size, source_sha256: sha(bytes), decoded_sha256: sha(JSON.stringify(data)), duration: data.duration, samples: data.samples, bones: data.bone_count,
      max_quaternion_norm_error: maxQuaternionNormError, retarget_paths: paths,
      saved_profile_dependencies: [...(consumers.get(entry.name) || [])].sort(),
      status: paths.length ? 'retarget_present_not_runtime_parity_verified' : 'decoded_not_retargeted',
      identical_in_game: false};
  });
  return {decoded, report: {schema_version: 1, archive: 'RUN/MOTION_P.ZAR', archive_sha256: sha(source.bytes), archive_sector: source.sector,
    summary: {decoded: clips.length, seal_clips: clips.filter(c=>c.name.startsWith('seal_')).length, retarget_present: clips.filter(c=>c.retarget_paths.length).length, saved_profile_dependencies: clips.filter(c=>c.saved_profile_dependencies.length).length, runtime_parity_verified_by_this_audit: 0},
    limitations: ['Covers primary MOTION_P archive, not every mission-specific ZDB motion bank.', 'Saved-profile dependencies are not proof a clip plays in a runtime state.', 'Retargeted proportions, stripped root motion, blends, timing and procedural overrides preclude an identical-runtime claim.', 'MPZANIM/EXTZANIM contain dialog/control tables; they are not decoded as skeletal motion here.'], clips}};
}

if (require.main === module) {
  const [iso, decoder, project, output] = process.argv.slice(2);
  assert(iso && decoder && project && output, 'usage: node tools/audit_iso_motion_coverage.cjs ISO DECODER_DIR PROJECT NEW_OUTPUT_DIR');
  const {decoded, report} = audit(iso, decoder, project);
  // All validation happens before output creation. A pre-existing directory is refused.
  fs.mkdirSync(output);
  fs.mkdirSync(path.join(output, 'motion'));
  for (const clip of decoded) {
    fs.writeFileSync(path.join(output, 'motion', clip.name + '.bin'), clip.bytes, {flag: 'wx'});
    fs.writeFileSync(path.join(output, 'motion', clip.name + '.json'), JSON.stringify(clip.data), {flag: 'wx'});
  }
  fs.writeFileSync(path.join(output, 'coverage.json'), JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
  console.log(JSON.stringify({output, ...report.summary}));
}
module.exports = {audit};
