'use strict';
// Self-contained, offline HTML index. No requests, CDN, game startup or source execution.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {hashFile}=require('./source_asset_inventory.cjs');
function html(catalog,recovery,motion,locations) {
  const raw=new Map(recovery.files.map(r=>[r.sha256,r]));
  const decoded=new Map(motion.entries.map(r=>[r.raw_sha256,r]));
  const href=file=>path.relative(path.dirname(locations.output),file).split(path.sep).map(encodeURIComponent).join('/');
  const rows=catalog.records.map(r=>{
    const recovered=raw.get(r.sha256),clip=decoded.get(r.sha256);
    return {name:r.name,bank:r.top_file,kind:r.category_hint,bytes:r.size,hash:r.sha256,
      status:clip?'Decoded motion tracks (not retargeted)':recovered?'Verified raw bytes (not decoded)':r.container?'Archive directory indexed':r.size===0?'Empty metadata':'Indexed in original ISO',
      raw:recovered?href(path.resolve(path.dirname(locations.recovery),recovered.file)):null,
      decoded:clip?href(path.resolve(path.dirname(locations.motion),clip.file)):null,
      download:r.name.replaceAll('\\','/').split('/').at(-1).replace(/[^a-zA-Z0-9_.-]/g,'_') || 'asset.raw',
      seconds:clip?.duration,bones:clip?.bones};
  });
  // Even a name containing </script> must remain data, never markup/script.
  const data=JSON.stringify(rows).replaceAll('<','\\u003c');
  return `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>SOCOM II — source library</title>
<style>body{background:#11191f;color:#dce8e9;font:15px system-ui;margin:32px;max-width:1450px}h1{font-size:26px}p{max-width:950px;line-height:1.6}input,select,button{font:inherit;background:#23323c;color:#f4ffff;border:1px solid #536772;border-radius:4px;padding:10px;margin:6px 8px 12px 0}input{width:min(520px,80%)}table{width:100%;border-collapse:collapse;font-size:13px}td,th{text-align:left;padding:10px;border-bottom:1px solid #33444b;overflow-wrap:anywhere}a{color:#6de1df;margin-right:12px}small{color:#a3b9bd}td:nth-child(2){max-width:330px}</style>
<h1>SOCOM II — recovered source library</h1>
<p>${catalog.summary.disc_files} disc files indexed · ${recovery.summary.recovered_files.toLocaleString('en-US')} newly recovered payloads · ${recovery.summary.verified_existing_files.toLocaleString('en-US')} verified existing payloads · ${motion.summary.unique_decoded_clips} decoded motion payloads.</p>
<p>This is an offline source catalog, <strong>not a completed Godot port</strong>. Raw files need their format-specific decoders. Motion JSON preserves quantized tracks and source timing; it is not yet a Blender action or character-retargeted animation. Movies remain in the ISO. Existing raw-file links depend on the original map-library folder remaining in place.</p>
<input id="search" placeholder="Search original names: seal_jump, MOTION, WEAP, VAG, MP6…" aria-label="Search assets"><select id="filter" aria-label="Asset filter"><option value="all">All indexed records</option><option value="motion">Decoded motion</option><option value="VAG">VAG audio (raw)</option><option value="ZED">ZED model/texture/data</option><option value="PSS">Movies (indexed only)</option></select><button id="back">Previous</button><button id="next">Next</button><p id="count"></p>
<table><thead><tr><th>Original name</th><th>Disc file</th><th>Status</th><th>Bytes / timing</th><th>Local files</th></tr></thead><tbody id="rows"></tbody></table>
<script>const data=${data};let page=0;const size=100;const $=id=>document.getElementById(id);
function render(){const query=$('search').value.toLowerCase(),kind=$('filter').value;const found=data.filter(r=>(r.name+' '+r.bank).toLowerCase().includes(query)&&(kind==='all'||kind==='motion'&&r.decoded||r.kind===kind));const pages=Math.max(1,Math.ceil(found.length/size));page=Math.min(page,pages-1);$('count').textContent=found.length+' matches · page '+(page+1)+' / '+pages;$('rows').replaceChildren();
for(const r of found.slice(page*size,(page+1)*size)){const tr=document.createElement('tr');for(const value of [r.name,r.bank,r.status,r.bytes.toLocaleString()+(r.seconds?' · '+r.seconds.toFixed(3)+'s / '+r.bones+' bones':'')]){const td=document.createElement('td');td.textContent=value;tr.append(td);}const links=document.createElement('td');for(const [label,url] of [['Raw',r.raw],['Motion JSON',r.decoded]])if(url){const a=document.createElement('a');a.textContent=label;a.href=url;a.download=r.download+(label==='Raw'?'':'.json');links.append(a);}tr.append(links);$('rows').append(tr);}$('back').disabled=page===0;$('next').disabled=page===pages-1;}
$('search').oninput=$('filter').onchange=()=>{page=0;render();};$('back').onclick=()=>{page--;render();};$('next').onclick=()=>{page++;render();};render();</script></html>\n`;
}
if(require.main===module){
  const [catalogFile,recoveryFile,motionFile,output]=process.argv.slice(2);
  assert(catalogFile&&recoveryFile&&motionFile&&output,'usage: node tools/build_source_asset_library_index.cjs CATALOG RECOVERY MOTION_MANIFEST NEW_HTML');
  const catalog=JSON.parse(fs.readFileSync(catalogFile)),recovery=JSON.parse(fs.readFileSync(recoveryFile)),motion=JSON.parse(fs.readFileSync(motionFile));
  assert.equal(recovery.catalog_sha256,hashFile(catalogFile));assert.equal(motion.catalog_sha256,hashFile(catalogFile));
  assert(fs.existsSync(path.join(path.dirname(output),'.gdignore')),'index belongs in ignored source library');
  fs.writeFileSync(output,html(catalog,recovery,motion,{recovery:recoveryFile,motion:motionFile,output}),{flag:'wx'});
  console.log('SOURCE_LIBRARY_INDEX PASS: '+catalog.records.length+' searchable records; '+path.resolve(output));
}
module.exports={html};
