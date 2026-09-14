'use strict';
// Offline source-data generation only. No animation or model file is modified.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const ROOT = path.resolve(__dirname, '..');
const SOURCE = '/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/output';
const SKELETON_SHA = '26e991e38bb09147c54ce3062116466fef3225e76b5e6771da619d56e625c551';
const NAMES = ['seal_stand', 'seal_stand_alert01', 'seal_stand_alert02',
  'seal_crouch', 'seal_crouch_alert01', 'seal_crouch_alert02', 'seal_prone',
  'seal_p_stand', 'seal_p_crouch', 'seal_p_prone', 'seal_fp_stand',
  'seal_fp_crouch', 'seal_fp_prone', 'seal_pfp_stand', 'seal_pfp_crouch',
  'seal_pfp_prone', 'seal_recoil', 'seal_crouch_recoil', 'seal_prone_recoil',
  'seal_p_recoil', 'seal_p_prone_recoil'];
const BASES = {seal_pfp_crouch: 'seal_crouch', seal_pfp_prone: 'seal_prone'};
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
function requireThat(value, label) { if (!value) throw new Error(label); }
function original(name) {
  const bytes = fs.readFileSync(path.join(SOURCE, 'motion', `${name}.json`));
  const data = JSON.parse(bytes);
  requireThat(Number.isFinite(data.duration) && data.duration > 0 && Number.isInteger(data.frames)
    && data.frames > 0 && data.samples === data.frames + 1, `Invalid source timeline ${name}`);
  return {data, sha: hash(bytes)};
}
function value(track, kind, index, count, width) {
  const values = track[kind];
  requireThat(Array.isArray(values) && (values.length === 1 || values.length === count), 'Invalid channel count');
  const row = values.length === 1 ? values[0] : values[index];
  requireThat(Array.isArray(row) && row.length === width && row.every(Number.isFinite), 'Invalid finite channel vector');
  return row;
}
function hipHeight(data, index) {
  const root = data.tracks.find(t => t.name === 'skel_root');
  const hip = data.tracks.find(t => t.name === 'hips');
  requireThat(root && hip, 'No original root/hips pair');
  const rp = value(root, 'positions_raw', index, data.samples, 3).map(x => x / 256);
  const hp = value(hip, 'positions_raw', index, data.samples, 3).map(x => x / 256);
  const raw = value(root, 'rotations_raw', index, data.samples, 4);
  const norm = Math.hypot(...raw);
  requireThat(norm > 0, 'Zero source quaternion');
  const [x, y, z, w] = raw.map(x => x / norm);
  // Source local hip rotated by its original root quaternion, then translated.
  const rotatedY = 2 * (x*y + z*w) * hp[0] + (1-2*(x*x+z*z))*hp[1] + 2*(y*z-x*w)*hp[2];
  const result = rp[1] + rotatedY;
  requireThat(Number.isFinite(result), 'Non-finite source height');
  return result;
}
function build() {
  const bytes = fs.readFileSync(path.join(SOURCE, 'seal-skeleton.json'));
  requireThat(hash(bytes) === SKELETON_SHA, 'Original skeleton hash changed');
  const skeleton = JSON.parse(bytes);
  requireThat(skeleton.position_divisor === 256, 'Unexpected source units');
  const root = skeleton.nodes.find(n => n.name === 'skel_root');
  const hips = skeleton.nodes.find(n => n.name === 'hips');
  const parent = skeleton.nodes.find(n => n.name === root.parent);
  requireThat(hips.parent === 'skel_root' && parent.parent === null &&
    parent.matrix_column_major.every((x,i) => x === (i % 5 === 0 ? 1 : 0)), 'Unverified source parent transform');
  const clips = {};
  for (const name of NAMES) {
    const upper = original(name), baseName = BASES[name] || name;
    const source = baseName === name ? upper : original(baseName);
    if (baseName !== name) requireThat(!upper.data.tracks.some(t => t.name === 'skel_root' || t.name === 'hips'), 'Composite unexpectedly owns root');
    clips[name] = {source_sha256: upper.sha, source_duration: upper.data.duration,
      height_source_name: baseName, height_source_sha256: source.sha,
      height_source_duration: source.data.duration, height_source_frames: source.data.frames,
      hip_y_source: Array.from({length: source.data.samples}, (_, i) => hipHeight(source.data, i))};
  }
  return {schema_version: 1, enabled: true, skeleton_sha256: SKELETON_SHA,
    unit_contract: 'iso_proportions.metres_per_source_unit divided by original builder outer scale62',
    scope: 'Explicit stationary grounded source takes only; no locomotion, jump, traversal, ladder or reload height changes',
    clips};
}
if (require.main === module) {
  const arg = process.argv.find(x => x.startsWith('--out='));
  const out = arg && path.resolve(arg.slice(6));
  requireThat(out && (out === path.join(ROOT, 'config/source_pose_heights.json') || out.startsWith('/private/tmp/')) && !fs.existsSync(out), 'Fresh approved --out path required');
  const data = build();
  fs.writeFileSync(out, JSON.stringify(data, null, 2) + '\n', {flag: 'wx'});
  console.log(`SOURCE_POSE_HEIGHT_DATA PASS clips=${Object.keys(data.clips).length} output=${out} sha256=${hash(fs.readFileSync(out))}`);
}
module.exports = {build, hipHeight};
