import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { FBXLoader } from "three/addons/loaders/FBXLoader.js";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";

import operatorFbxUrl from "../../../assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx?url";
import operatorTextureUrl from "../../../assets/characters/ps1_gas_mask_soldier/trooper.png?url";
import defaultAnimationUrl from "../../../assets/animations/mixamo/Rifle Aiming Idle.fbx?url";
import {
  createReviewContract,
  validateReviewContract,
} from "./review-contract.js";
import "./styles.css";

const CANONICAL_ASSET_PATH =
  "res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx";
const TARGET_OPERATOR_HEIGHT = 1.78;
const TIMELINE_FPS = 30;

const elements = Object.fromEntries(
  [
    "viewport",
    "asset-name",
    "model-input",
    "animation-input",
    "clip-select",
    "play-toggle",
    "restart",
    "speed-select",
    "bone-search",
    "bone-list",
    "selected-bone",
    "bone-position",
    "bone-rotation",
    "event-type",
    "add-marker",
    "marker-list",
    "export-review",
    "review-input",
    "contract-status",
    "timeline",
    "timeline-markers",
    "time-readout",
    "frame-readout",
    "duration-readout",
    "status",
    "drop-hint",
  ].map((id) => [id, document.getElementById(id)]),
);

const viewportShell = document.querySelector(".viewport-shell");
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x0b1010);
scene.fog = new THREE.FogExp2(0x0b1010, 0.032);

const camera = new THREE.PerspectiveCamera(34, 1, 0.01, 250);
camera.position.set(3.15, 1.95, 4.6);

const renderer = new THREE.WebGLRenderer({
  canvas: elements.viewport,
  antialias: true,
  alpha: false,
  powerPreference: "high-performance",
});
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFShadowMap;
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;

const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.target.set(0, 0.92, 0);
controls.minDistance = 1.7;
controls.maxDistance = 10;
controls.maxPolarAngle = Math.PI * 0.52;

scene.add(new THREE.HemisphereLight(0xa9bac0, 0x171c18, 1.65));
const keyLight = new THREE.DirectionalLight(0xffd9ad, 3.8);
keyLight.position.set(-3.5, 5.5, 3.0);
keyLight.castShadow = true;
keyLight.shadow.mapSize.set(2048, 2048);
scene.add(keyLight);
const rimLight = new THREE.DirectionalLight(0x7ab0b8, 2.1);
rimLight.position.set(4, 3, -4);
scene.add(rimLight);

const floor = new THREE.Mesh(
  new THREE.CircleGeometry(3.5, 96),
  new THREE.MeshStandardMaterial({ color: 0x252b28, roughness: 0.92, metalness: 0.05 }),
);
floor.rotation.x = -Math.PI * 0.5;
floor.receiveShadow = true;
scene.add(floor);

const reviewRoot = new THREE.Group();
scene.add(reviewRoot);
const selectionMarker = new THREE.Mesh(
  new THREE.SphereGeometry(0.018, 16, 12),
  new THREE.MeshBasicMaterial({ color: 0xe05a35, depthTest: false }),
);
selectionMarker.renderOrder = 100;
selectionMarker.visible = false;
scene.add(selectionMarker);

const fbxLoader = new FBXLoader();
const gltfLoader = new GLTFLoader();
const textureLoader = new THREE.TextureLoader();
let previousFrameTime = performance.now();

let operator = null;
let skeletonHelper = null;
let mixer = null;
let clips = [];
let activeAction = null;
let activeClip = null;
let selectedBone = null;
let bones = [];
let markers = [];
let markerSequence = 0;
let playing = false;
let timelineDragging = false;
let currentAssetPath = CANONICAL_ASSET_PATH;
let currentAssetName = "PS1 Gas Mask Operator";

function setStatus(message, tone = "normal") {
  elements.status.textContent = message;
  elements.status.style.color = tone === "error" ? "#ed856c" : "#8bc5ae";
}

function clearObject(object) {
  if (!object) return;
  object.traverse((child) => {
    if (child.geometry) child.geometry.dispose?.();
    if (Array.isArray(child.material)) child.material.forEach((material) => material.dispose?.());
    else child.material?.dispose?.();
  });
  object.removeFromParent();
}

function applyOperatorTexture(object, texture) {
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.flipY = false;
  texture.magFilter = THREE.NearestFilter;
  texture.minFilter = THREE.NearestMipmapNearestFilter;
  object.traverse((child) => {
    if (!child.isMesh && !child.isSkinnedMesh) return;
    const materials = Array.isArray(child.material) ? child.material : [child.material];
    materials.filter(Boolean).forEach((material) => {
      material.map = texture;
      material.roughness = 0.94;
      material.metalness = 0.02;
      material.needsUpdate = true;
    });
    child.castShadow = true;
    child.receiveShadow = true;
    child.frustumCulled = false;
  });
}

function normalizeOperator(object) {
  object.updateMatrixWorld(true);
  const initialBox = new THREE.Box3().setFromObject(object);
  const size = initialBox.getSize(new THREE.Vector3());
  if (size.y > 0.0001) object.scale.multiplyScalar(TARGET_OPERATOR_HEIGHT / size.y);
  object.updateMatrixWorld(true);
  const fittedBox = new THREE.Box3().setFromObject(object);
  const center = fittedBox.getCenter(new THREE.Vector3());
  object.position.x -= center.x;
  object.position.z -= center.z;
  object.position.y -= fittedBox.min.y;
  object.updateMatrixWorld(true);
}

function setOperator(nextOperator, nextClips = [], assetName = "Local operator", assetPath = "local://operator") {
  if (mixer) mixer.stopAllAction();
  mixer = null;
  activeAction = null;
  activeClip = null;
  clips = [];
  markers = [];
  renderMarkers();
  if (skeletonHelper) clearObject(skeletonHelper);
  skeletonHelper = null;
  if (operator) clearObject(operator);
  operator = nextOperator;
  currentAssetName = assetName;
  currentAssetPath = assetPath;
  elements["asset-name"].textContent = assetName;
  normalizeOperator(operator);
  reviewRoot.add(operator);
  bones = [];
  operator.traverse((child) => {
    if (child.isBone) bones.push(child);
    if (child.isMesh || child.isSkinnedMesh) {
      child.castShadow = true;
      child.receiveShadow = true;
      child.frustumCulled = false;
    }
  });
  bones.sort((left, right) => left.name.localeCompare(right.name));
  skeletonHelper = new THREE.SkeletonHelper(operator);
  skeletonHelper.material.color.set(0x8bc5ae);
  skeletonHelper.material.opacity = 0.28;
  skeletonHelper.material.transparent = true;
  scene.add(skeletonHelper);
  selectedBone = null;
  selectionMarker.visible = false;
  renderBones();
  fitCameraToOperator();
  setClips(nextClips);
  setStatus(`Loaded ${assetName} · ${bones.length} bones`);
}

function fitCameraToOperator() {
  if (!operator) return;
  const box = new THREE.Box3().setFromObject(operator);
  const center = box.getCenter(new THREE.Vector3());
  controls.target.set(center.x, center.y * 0.92, center.z);
  camera.position.set(center.x + 3.1, center.y + 0.45, center.z + 4.4);
  controls.update();
}

function setClips(nextClips) {
  clips = nextClips
    .filter((clip) => clip && clip.duration > 0)
    .map((clip) => {
      const compatibleClip = clip.clone();
      compatibleClip.tracks = compatibleClip.tracks.filter((track) => {
        try {
          const binding = THREE.PropertyBinding.parseTrackName(track.name);
          return Boolean(THREE.PropertyBinding.findNode(operator, binding.nodeName));
        } catch {
          return false;
        }
      });
      compatibleClip.resetDuration();
      return compatibleClip;
    })
    .filter((clip) => clip.tracks.length > 0 && clip.duration > 0);
  elements["clip-select"].replaceChildren();
  if (!clips.length) {
    const option = new Option("No animation in this asset", "");
    elements["clip-select"].add(option);
    elements["clip-select"].disabled = true;
    elements["play-toggle"].disabled = true;
    elements.restart.disabled = true;
    elements.timeline.disabled = true;
    elements["add-marker"].disabled = true;
    updateTimeline(0, 0);
    return;
  }
  clips.forEach((clip, index) => elements["clip-select"].add(new Option(clip.name || `Take ${index + 1}`, String(index))));
  elements["clip-select"].disabled = false;
  elements["play-toggle"].disabled = false;
  elements.restart.disabled = false;
  elements.timeline.disabled = false;
  elements["add-marker"].disabled = false;
  activateClip(0);
}

function activateClip(index) {
  if (!operator || !clips[index]) return;
  mixer?.stopAllAction();
  mixer = new THREE.AnimationMixer(operator);
  activeClip = clips[index];
  activeAction = mixer.clipAction(activeClip);
  activeAction.setLoop(THREE.LoopRepeat, Infinity);
  activeAction.enabled = true;
  activeAction.paused = !playing;
  activeAction.play();
  mixer.setTime(0);
  elements.timeline.max = String(activeClip.duration);
  elements.timeline.value = "0";
  elements["clip-select"].value = String(index);
  renderMarkers();
  updateTimeline(0, activeClip.duration);
  setStatus(`Reviewing ${activeClip.name || `Take ${index + 1}`}`);
}

function mergeAnimationClips(nextClips, sourceName) {
  if (!operator || !nextClips.length) {
    setStatus(`${sourceName} contains no animation clips`, "error");
    return;
  }
  setClips(nextClips);
  setStatus(`Loaded ${nextClips.length} animation take${nextClips.length === 1 ? "" : "s"} from ${sourceName}`);
}

function renderBones() {
  const query = elements["bone-search"].value.trim().toLowerCase();
  const fragment = document.createDocumentFragment();
  bones
    .filter((bone) => !query || bone.name.toLowerCase().includes(query))
    .forEach((bone) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = `bone-item${bone === selectedBone ? " selected" : ""}`;
      button.textContent = bone.name || "Unnamed bone";
      button.role = "option";
      button.addEventListener("click", () => selectBone(bone));
      fragment.append(button);
    });
  elements["bone-list"].replaceChildren(fragment);
}

function selectBone(bone) {
  selectedBone = bone;
  selectionMarker.visible = true;
  elements["selected-bone"].textContent = bone.name || "Unnamed bone";
  renderBones();
  updateBoneReadout();
}

function updateBoneReadout() {
  if (!selectedBone) return;
  const position = selectedBone.getWorldPosition(new THREE.Vector3());
  const rotation = new THREE.Euler().setFromQuaternion(selectedBone.getWorldQuaternion(new THREE.Quaternion()), "YXZ");
  selectionMarker.position.copy(position);
  elements["bone-position"].textContent = vectorText(position, 3);
  elements["bone-rotation"].textContent = vectorText(
    new THREE.Vector3(
      THREE.MathUtils.radToDeg(rotation.x),
      THREE.MathUtils.radToDeg(rotation.y),
      THREE.MathUtils.radToDeg(rotation.z),
    ),
    1,
    "°",
  );
}

function vectorText(vector, digits, suffix = "") {
  return `X ${vector.x.toFixed(digits)}${suffix}  Y ${vector.y.toFixed(digits)}${suffix}  Z ${vector.z.toFixed(digits)}${suffix}`;
}

function addMarker() {
  if (!activeClip) return;
  markerSequence += 1;
  markers.push({
    id: `marker-${markerSequence}`,
    type: elements["event-type"].value,
    time_seconds: Number(elements.timeline.value),
    bone: selectedBone?.name || "",
    note: "",
  });
  markers.sort((left, right) => left.time_seconds - right.time_seconds);
  renderMarkers();
}

function removeMarker(id) {
  markers = markers.filter((marker) => marker.id !== id);
  renderMarkers();
}

function renderMarkers() {
  const rows = document.createDocumentFragment();
  markers.forEach((marker) => {
    const row = document.createElement("div");
    row.className = "marker-row";
    const label = document.createElement("span");
    label.textContent = marker.type.replaceAll("_", " ");
    const time = document.createElement("span");
    time.textContent = formatTime(marker.time_seconds);
    const remove = document.createElement("button");
    remove.type = "button";
    remove.textContent = "×";
    remove.ariaLabel = `Remove ${marker.type} marker`;
    remove.addEventListener("click", () => removeMarker(marker.id));
    row.append(label, time, remove);
    rows.append(row);
  });
  elements["marker-list"].replaceChildren(rows);

  const dots = document.createDocumentFragment();
  const duration = activeClip?.duration || 0;
  if (duration > 0) {
    markers.forEach((marker) => {
      const dot = document.createElement("span");
      dot.className = "timeline-dot";
      dot.style.left = `${THREE.MathUtils.clamp(marker.time_seconds / duration, 0, 1) * 100}%`;
      dot.title = marker.type;
      dots.append(dot);
    });
  }
  elements["timeline-markers"].replaceChildren(dots);
}

function updateTimeline(time, duration) {
  elements["time-readout"].textContent = formatTime(time);
  elements["duration-readout"].textContent = `/ ${formatTime(duration)}`;
  elements["frame-readout"].textContent = `FRAME ${String(Math.round(time * TIMELINE_FPS)).padStart(4, "0")}`;
}

function formatTime(seconds) {
  const safe = Math.max(0, Number(seconds) || 0);
  const minutes = Math.floor(safe / 60);
  const remainder = safe - minutes * 60;
  return `${String(minutes).padStart(2, "0")}:${remainder.toFixed(3).padStart(6, "0")}`;
}

function currentReviewDocument() {
  return createReviewContract({
    assetPath: currentAssetPath,
    assetName: currentAssetName,
    clipName: activeClip?.name || "NO_ANIMATION",
    durationSeconds: activeClip?.duration || 0,
    markers,
    boneCount: bones.length,
  });
}

function exportReview() {
  const reviewDocument = currentReviewDocument();
  const result = validateReviewContract(reviewDocument);
  if (!result.valid) {
    showContractStatus(result.errors.join(" "), false);
    return;
  }
  const blob = new Blob([`${JSON.stringify(reviewDocument, null, 2)}\n`], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `${safeFilename(activeClip?.name || "operator-review")}.review.json`;
  link.click();
  URL.revokeObjectURL(url);
  showContractStatus("Validated review exported. Gameplay remains unchanged.", true);
}

function safeFilename(value) {
  return value.toLowerCase().replace(/[^a-z0-9_-]+/g, "-").replace(/^-|-$/g, "") || "operator-review";
}

function showContractStatus(message, valid) {
  elements["contract-status"].textContent = message;
  elements["contract-status"].className = `contract-status ${valid ? "valid" : "invalid"}`;
}

async function inspectReviewFile(file) {
  try {
    const parsed = JSON.parse(await file.text());
    const result = validateReviewContract(parsed);
    if (!result.valid) {
      showContractStatus(`Rejected: ${result.errors.join(" ")}`, false);
      return;
    }
    markers = parsed.markers.map((marker) => ({ ...marker }));
    markerSequence = markers.length;
    renderMarkers();
    showContractStatus(`Validated ${file.name}. Review markers loaded; gameplay unchanged.`, true);
  } catch (error) {
    showContractStatus(`Rejected: ${error.message}`, false);
  }
}

async function loadLocalModel(file) {
  const extension = file.name.split(".").pop()?.toLowerCase();
  const buffer = await file.arrayBuffer();
  if (extension === "fbx") {
    const object = fbxLoader.parse(buffer, "");
    setOperator(object, object.animations || [], file.name, `local://${file.name}`);
    return;
  }
  if (extension === "glb") {
    const gltf = await new Promise((resolve, reject) => gltfLoader.parse(buffer, "", resolve, reject));
    setOperator(gltf.scene, gltf.animations || [], file.name, `local://${file.name}`);
    return;
  }
  throw new Error("Use an FBX or GLB file.");
}

async function loadLocalAnimation(file) {
  const extension = file.name.split(".").pop()?.toLowerCase();
  const buffer = await file.arrayBuffer();
  if (extension === "fbx") {
    const object = fbxLoader.parse(buffer, "");
    mergeAnimationClips(object.animations || [], file.name);
    return;
  }
  if (extension === "glb") {
    const gltf = await new Promise((resolve, reject) => gltfLoader.parse(buffer, "", resolve, reject));
    mergeAnimationClips(gltf.animations || [], file.name);
    return;
  }
  throw new Error("Use an FBX or GLB animation file.");
}

async function loadCanonicalOperator() {
  try {
    const [object, texture] = await Promise.all([
      fbxLoader.loadAsync(operatorFbxUrl),
      textureLoader.loadAsync(operatorTextureUrl),
    ]);
    applyOperatorTexture(object, texture);
    setOperator(object, object.animations || [], "PS1 Gas Mask Operator", CANONICAL_ASSET_PATH);
    try {
      const animationObject = await fbxLoader.loadAsync(defaultAnimationUrl);
      mergeAnimationClips(animationObject.animations || [], "Rifle Aiming Idle.fbx");
    } catch (animationError) {
      setStatus(`Operator loaded; default animation failed: ${animationError.message}`, "error");
    }
  } catch (error) {
    setStatus(`Canonical operator failed to load: ${error.message}`, "error");
  }
}

function togglePlayback() {
  if (!activeAction) return;
  playing = !playing;
  activeAction.paused = !playing;
  elements["play-toggle"].textContent = playing ? "Pause" : "Play";
}

function resizeRenderer() {
  const width = Math.max(1, elements.viewport.clientWidth);
  const height = Math.max(1, elements.viewport.clientHeight);
  if (elements.viewport.width !== Math.round(width * renderer.getPixelRatio()) || elements.viewport.height !== Math.round(height * renderer.getPixelRatio())) {
    renderer.setSize(width, height, false);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
  }
}

function animate() {
  requestAnimationFrame(animate);
  resizeRenderer();
  const frameTime = performance.now();
  const delta = Math.min((frameTime - previousFrameTime) / 1000, 0.05);
  previousFrameTime = frameTime;
  if (mixer && playing && !timelineDragging) {
    mixer.update(delta * Number(elements["speed-select"].value));
    const time = activeAction?.time || 0;
    elements.timeline.value = String(time);
    updateTimeline(time, activeClip?.duration || 0);
  }
  updateBoneReadout();
  controls.update();
  renderer.render(scene, camera);
}

elements["play-toggle"].addEventListener("click", togglePlayback);
elements.restart.addEventListener("click", () => {
  if (!mixer || !activeClip) return;
  mixer.setTime(0);
  elements.timeline.value = "0";
  updateTimeline(0, activeClip.duration);
});
elements["clip-select"].addEventListener("change", (event) => activateClip(Number(event.target.value)));
elements["bone-search"].addEventListener("input", renderBones);
elements["add-marker"].addEventListener("click", addMarker);
elements["export-review"].addEventListener("click", exportReview);
elements.timeline.addEventListener("pointerdown", () => { timelineDragging = true; });
elements.timeline.addEventListener("pointerup", () => { timelineDragging = false; });
elements.timeline.addEventListener("input", () => {
  if (!mixer || !activeClip) return;
  const time = Number(elements.timeline.value);
  mixer.setTime(time);
  updateTimeline(time, activeClip.duration);
});
elements["model-input"].addEventListener("change", async (event) => {
  const file = event.target.files?.[0];
  if (!file) return;
  try { await loadLocalModel(file); } catch (error) { setStatus(error.message, "error"); }
  event.target.value = "";
});
elements["animation-input"].addEventListener("change", async (event) => {
  const file = event.target.files?.[0];
  if (!file) return;
  try { await loadLocalAnimation(file); } catch (error) { setStatus(error.message, "error"); }
  event.target.value = "";
});
elements["review-input"].addEventListener("change", async (event) => {
  const file = event.target.files?.[0];
  if (file) await inspectReviewFile(file);
  event.target.value = "";
});

for (const eventName of ["dragenter", "dragover"]) {
  viewportShell.addEventListener(eventName, (event) => {
    event.preventDefault();
    viewportShell.classList.add("dragging");
  });
}
for (const eventName of ["dragleave", "drop"]) {
  viewportShell.addEventListener(eventName, (event) => {
    event.preventDefault();
    viewportShell.classList.remove("dragging");
  });
}
viewportShell.addEventListener("drop", async (event) => {
  const file = event.dataTransfer?.files?.[0];
  if (!file) return;
  try { await loadLocalModel(file); } catch (error) { setStatus(error.message, "error"); }
});

window.addEventListener("keydown", (event) => {
  if (event.code === "Space" && event.target === document.body) {
    event.preventDefault();
    togglePlayback();
  }
});

loadCanonicalOperator();
animate();
