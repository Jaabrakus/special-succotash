import * as THREE from "three";
import { FBXLoader } from "three/addons/loaders/FBXLoader.js";

import operatorUrl from "../../../assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx?url";
import operatorTextureUrl from "../../../assets/characters/ps1_gas_mask_soldier/trooper.png?url";
import rifleUrl from "../../../assets/weapons/ps1_ak47/source/ak-47.fbx?url";
import rifleTextureUrl from "../../../assets/weapons/ps1_ak47/textures/AK-47TextureMap.png?url";
import idleUrl from "../../../assets/animations/mixamo/Rifle Aiming Idle.fbx?url";
import runUrl from "../../../assets/animations/mixamo/Rifle Run.fbx?url";
import crouchUrl from "../../../assets/animations/mixamo/Rifle 8-Way Locomotion Pack/idle crouching aiming.fbx?url";
import proneUrl from "../../../assets/animations/mixamo/Prone Firing Rifle.fbx?url";

import { CAMERA, GRENADE, MOVEMENT, WEAPON } from "./gameplay-config.js";
import {
  blastDamage,
  bloomAfterShot,
  grenadeSpeed,
  moveToward,
  recoverBloom,
  resolveAxis,
  spreadDegrees,
} from "./simulation.js";
import "./styles.css";

const canvas = document.getElementById("game");
const ui = Object.fromEntries(
  [
    "deploy", "deploy-button", "loading", "message", "reticle", "health", "magazine",
    "reserve", "grenades", "stance", "targets-left", "weapon-state", "grenade-charge",
  ].map((id) => [id, document.getElementById(id)]),
);

const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: "high-performance" });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFShadowMap;
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.08;

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x313943);
scene.fog = new THREE.FogExp2(0x313943, 0.018);

const camera = new THREE.PerspectiveCamera(CAMERA.fov, 1, CAMERA.near, 260);
const loader = new FBXLoader();
const textureLoader = new THREE.TextureLoader();
const raycaster = new THREE.Raycaster();
const clock = { previous: performance.now() };

const obstacles = [];
const obstacleMeshes = [];
const targetHitMeshes = [];
const targets = [];
const projectiles = [];
const effects = [];

const keys = new Set();
const input = { fire: false, yaw: 0, pitch: -0.08, grenadeStart: -1 };
let gameActive = false;
let embeddedMouseLook = false;
const player = {
  position: new THREE.Vector3(0, 0, 9),
  velocity: new THREE.Vector3(),
  grounded: true,
  posture: "STANDING",
  health: 100,
  group: new THREE.Group(),
  visual: null,
  mixer: null,
  actions: {},
  currentAction: "",
  weapon: null,
};
const combat = {
  magazine: WEAPON.magazineCapacity,
  reserve: WEAPON.reserveAmmo,
  grenades: GRENADE.count,
  bloom: 0,
  nextShotAt: 0,
  reloadingUntil: 0,
  reticleGap: WEAPON.reticleBaseGapPx,
};

scene.add(player.group);
buildLighting();
buildRange();
const trajectory = buildTrajectory();

function buildLighting() {
  scene.add(new THREE.HemisphereLight(0x9eb5c1, 0x29231d, 1.7));
  const sun = new THREE.DirectionalLight(0xffd0a0, 3.2);
  sun.position.set(-15, 24, 9);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  sun.shadow.camera.left = -35;
  sun.shadow.camera.right = 35;
  sun.shadow.camera.top = 35;
  sun.shadow.camera.bottom = -35;
  scene.add(sun);

  const warning = new THREE.PointLight(0xd54a2c, 16, 18, 2);
  warning.position.set(-8, 2.4, -12);
  scene.add(warning);
}

function material(color, roughness = 0.86, metalness = 0.04) {
  return new THREE.MeshStandardMaterial({ color, roughness, metalness });
}

function addBox(name, position, size, color, collidable = true) {
  const mesh = new THREE.Mesh(new THREE.BoxGeometry(size.x, size.y, size.z), material(color));
  mesh.name = name;
  mesh.position.copy(position);
  mesh.castShadow = true;
  mesh.receiveShadow = true;
  scene.add(mesh);
  if (collidable) {
    obstacles.push({
      min: { x: position.x - size.x / 2, y: position.y - size.y / 2, z: position.z - size.z / 2 },
      max: { x: position.x + size.x / 2, y: position.y + size.y / 2, z: position.z + size.z / 2 },
    });
    obstacleMeshes.push(mesh);
  }
  return mesh;
}

function buildRange() {
  const ground = new THREE.Mesh(new THREE.PlaneGeometry(90, 90), material(0x48463f, 0.98));
  ground.rotation.x = -Math.PI / 2;
  ground.receiveShadow = true;
  scene.add(ground);

  const grid = new THREE.GridHelper(90, 90, 0x6c6252, 0x4f4d47);
  grid.position.y = 0.006;
  grid.material.opacity = 0.18;
  grid.material.transparent = true;
  scene.add(grid);

  addBox("west-wall", new THREE.Vector3(-12, 2.2, -8), new THREE.Vector3(1, 4.4, 33), 0x4b4d49);
  addBox("east-wall", new THREE.Vector3(12, 2.2, -8), new THREE.Vector3(1, 4.4, 33), 0x4b4d49);
  addBox("rear-wall", new THREE.Vector3(0, 2.2, -24), new THREE.Vector3(25, 4.4, 1), 0x414642);
  addBox("cover-a", new THREE.Vector3(-4.2, 0.7, 1), new THREE.Vector3(3.4, 1.4, 1), 0x716553);
  addBox("cover-b", new THREE.Vector3(4.5, 1.05, -5), new THREE.Vector3(1.2, 2.1, 4.5), 0x615b4f);
  addBox("cover-c", new THREE.Vector3(-5, 1.2, -11), new THREE.Vector3(5, 2.4, 1), 0x595b55);
  addBox("tower", new THREE.Vector3(7.5, 2.8, -16), new THREE.Vector3(5.5, 5.6, 4), 0x505652);
  addBox("catwalk", new THREE.Vector3(0, 3.2, -19), new THREE.Vector3(18, 0.35, 2.2), 0x5b5145);

  for (let i = 0; i < 7; i += 1) {
    const lamp = new THREE.PointLight(i % 2 ? 0xe3a45f : 0x78a9a8, 8, 9, 2);
    lamp.position.set(i % 2 ? -10.5 : 10.5, 2.2, 7 - i * 4.3);
    scene.add(lamp);
  }

  createTarget("T-01", new THREE.Vector3(-2.5, 0, -4));
  createTarget("T-02", new THREE.Vector3(3.2, 0, -10));
  createTarget("T-03", new THREE.Vector3(-7.2, 0, -17));
  createTarget("T-04", new THREE.Vector3(3.4, 3.4, -19));
}

function createTarget(name, position) {
  const root = new THREE.Group();
  root.name = name;
  root.position.copy(position);
  const bodyMaterial = material(0x715e4b, 0.74, 0.12);
  const accentMaterial = material(0xa53e2c, 0.72, 0.08);
  const body = new THREE.Mesh(new THREE.BoxGeometry(0.62, 1.05, 0.28), bodyMaterial);
  body.position.y = 1.04;
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.24, 16, 12), accentMaterial);
  head.position.y = 1.78;
  const stand = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.72, 0.12), material(0x292c2b, 0.6, 0.45));
  stand.position.y = 0.36;
  for (const mesh of [body, head, stand]) {
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    root.add(mesh);
  }
  const target = { name, root, body, head, health: 100, alive: true };
  body.userData = { target, zone: "body" };
  head.userData = { target, zone: "head" };
  targetHitMeshes.push(body, head);
  targets.push(target);
  scene.add(root);
}

function buildTrajectory() {
  const geometry = new THREE.BufferGeometry();
  const line = new THREE.Line(
    geometry,
    new THREE.LineDashedMaterial({ color: 0xe5d66f, dashSize: 0.22, gapSize: 0.14, transparent: true, opacity: 0.85 }),
  );
  line.visible = false;
  line.frustumCulled = false;
  scene.add(line);
  return line;
}

function normalizeModel(object, targetHeight) {
  object.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(object);
  const height = box.max.y - box.min.y;
  if (height > 0.0001) object.scale.multiplyScalar(targetHeight / height);
  object.updateMatrixWorld(true);
  const fitted = new THREE.Box3().setFromObject(object);
  const center = fitted.getCenter(new THREE.Vector3());
  object.position.x -= center.x;
  object.position.z -= center.z;
  object.position.y -= fitted.min.y;
}

function applyTexture(object, texture, pixelated = true) {
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.flipY = false;
  if (pixelated) {
    texture.magFilter = THREE.NearestFilter;
    texture.minFilter = THREE.NearestMipmapNearestFilter;
  }
  object.traverse((child) => {
    if (!child.isMesh && !child.isSkinnedMesh) return;
    const materials = Array.isArray(child.material) ? child.material : [child.material];
    for (const current of materials.filter(Boolean)) {
      current.map = texture;
      current.roughness = 0.9;
      current.metalness = 0.04;
      current.needsUpdate = true;
    }
    child.castShadow = true;
    child.receiveShadow = true;
    child.frustumCulled = false;
  });
}

function compatibleClip(source, object) {
  const clip = source.clone();
  clip.tracks = clip.tracks.filter((track) => {
    try {
      const binding = THREE.PropertyBinding.parseTrackName(track.name);
      if (!THREE.PropertyBinding.findNode(object, binding.nodeName)) return false;
      return !(binding.nodeName?.toLowerCase().includes("hips") && binding.propertyName === "position");
    } catch {
      return false;
    }
  });
  clip.resetDuration();
  return clip;
}

async function loadOperator() {
  try {
    const [operator, operatorTexture, rifle, rifleTexture, idleSource, runSource, crouchSource, proneSource] = await Promise.all([
      loader.loadAsync(operatorUrl),
      textureLoader.loadAsync(operatorTextureUrl),
      loader.loadAsync(rifleUrl),
      textureLoader.loadAsync(rifleTextureUrl),
      loader.loadAsync(idleUrl),
      loader.loadAsync(runUrl),
      loader.loadAsync(crouchUrl),
      loader.loadAsync(proneUrl),
    ]);

    applyTexture(operator, operatorTexture);
    normalizeModel(operator, 1.78);
    operator.rotation.y = Math.PI;
    player.visual = operator;
    player.group.add(operator);

    player.mixer = new THREE.AnimationMixer(operator);
    const sources = { idle: idleSource, run: runSource, crouch: crouchSource, prone: proneSource };
    for (const [name, source] of Object.entries(sources)) {
      const sourceClip = source.animations?.[0];
      if (!sourceClip) continue;
      const clip = compatibleClip(sourceClip, operator);
      if (!clip.tracks.length) continue;
      const action = player.mixer.clipAction(clip);
      action.enabled = true;
      action.setLoop(THREE.LoopRepeat, Infinity);
      action.play();
      action.setEffectiveWeight(name === "idle" ? 1 : 0);
      player.actions[name] = action;
    }
    player.currentAction = "idle";

    applyTexture(rifle, rifleTexture);
    player.weapon = normalizeWeapon(rifle);
    scene.add(player.weapon);
  } catch (error) {
    showMessage(`ASSET LOAD FAILED · ${error.message}`, 5000);
  } finally {
    ui.loading.classList.add("hidden");
  }
}

function normalizeWeapon(object) {
  const container = new THREE.Group();
  container.add(object);
  object.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(object);
  const size = box.getSize(new THREE.Vector3());
  const longest = Math.max(size.x, size.y, size.z);
  if (longest > 0.0001) object.scale.multiplyScalar(0.82 / longest);
  object.updateMatrixWorld(true);
  const fitted = new THREE.Box3().setFromObject(object);
  const center = fitted.getCenter(new THREE.Vector3());
  object.position.sub(center);
  if (size.x >= size.y && size.x >= size.z) object.rotation.y = -Math.PI / 2;
  else if (size.y >= size.x && size.y >= size.z) object.rotation.x = Math.PI / 2;
  return container;
}

function setAnimation(name) {
  if (!player.mixer || !player.actions[name] || player.currentAction === name) return;
  const previous = player.actions[player.currentAction];
  const next = player.actions[name];
  next.reset().setEffectiveTimeScale(1).setEffectiveWeight(1).fadeIn(0.16).play();
  previous?.fadeOut(0.16);
  player.currentAction = name;
}

function aimDirection() {
  const cosine = Math.cos(input.pitch);
  return new THREE.Vector3(
    Math.sin(input.yaw) * cosine,
    Math.sin(input.pitch),
    -Math.cos(input.yaw) * cosine,
  ).normalize();
}

function horizontalForward() {
  return new THREE.Vector3(Math.sin(input.yaw), 0, -Math.cos(input.yaw));
}

function updatePlayer(delta) {
  const forwardAmount = (keys.has("KeyW") ? 1 : 0) - (keys.has("KeyS") ? 1 : 0);
  const rightAmount = (keys.has("KeyD") ? 1 : 0) - (keys.has("KeyA") ? 1 : 0);
  const forward = horizontalForward();
  const right = new THREE.Vector3(-forward.z, 0, forward.x);
  const desiredDirection = forward.multiplyScalar(forwardAmount).add(right.multiplyScalar(rightAmount));
  if (desiredDirection.lengthSq() > 1) desiredDirection.normalize();

  const speed = player.posture === "PRONE" ? MOVEMENT.proneSpeed :
    player.posture === "CROUCHED" ? MOVEMENT.crouchSpeed : MOVEMENT.moveSpeed;
  const desiredX = desiredDirection.x * speed;
  const desiredZ = desiredDirection.z * speed;
  const currentDotTarget = player.velocity.x * desiredX + player.velocity.z * desiredZ;
  const hasInput = desiredDirection.lengthSq() > 0.001;
  const acceleration = !hasInput ? MOVEMENT.brakingAcceleration :
    currentDotTarget < -0.01 ? MOVEMENT.reversalAcceleration : MOVEMENT.acceleration;
  player.velocity.x = moveToward(player.velocity.x, desiredX, acceleration * delta);
  player.velocity.z = moveToward(player.velocity.z, desiredZ, acceleration * delta);

  if (player.grounded && keys.has("Space") && player.posture !== "PRONE") {
    player.velocity.y = MOVEMENT.jumpVelocity;
    player.grounded = false;
    keys.delete("Space");
  }
  if (!player.grounded) player.velocity.y -= MOVEMENT.gravity * delta;

  const proposed = player.position.clone();
  proposed.x += player.velocity.x * delta;
  proposed.x = resolveAxis(proposed, MOVEMENT.playerRadius, obstacles, "x");
  proposed.z += player.velocity.z * delta;
  proposed.z = resolveAxis(proposed, MOVEMENT.playerRadius, obstacles, "z");
  proposed.y += player.velocity.y * delta;
  if (proposed.y <= 0) {
    proposed.y = 0;
    player.velocity.y = 0;
    player.grounded = true;
  }
  player.position.copy(proposed);
  player.group.position.copy(player.position);
  player.group.rotation.y = input.yaw;

  const horizontalSpeed = Math.hypot(player.velocity.x, player.velocity.z);
  if (player.posture === "PRONE") setAnimation("prone");
  else if (player.posture === "CROUCHED") setAnimation("crouch");
  else setAnimation(horizontalSpeed > 0.25 ? "run" : "idle");
  player.mixer?.update(delta * (horizontalSpeed > 0.25 && player.currentAction === "run" ? Math.max(0.65, horizontalSpeed / MOVEMENT.moveSpeed) : 1));

  const postureHeight = player.posture === "PRONE" ? 0.62 : player.posture === "CROUCHED" ? 1.05 : 1.34;
  if (player.weapon) {
    const direction = aimDirection();
    const weaponRight = new THREE.Vector3().crossVectors(direction, new THREE.Vector3(0, 1, 0)).normalize().negate();
    player.weapon.position.copy(player.position)
      .addScaledVector(direction, 0.42)
      .addScaledVector(weaponRight, 0.1)
      .add(new THREE.Vector3(0, postureHeight, 0));
    player.weapon.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, -1), direction);
  }
}

function updateCamera() {
  const direction = aimDirection();
  const anchorHeight = player.posture === "PRONE" ? 0.8 : player.posture === "CROUCHED" ? 1.45 : CAMERA.height;
  const anchor = player.position.clone().add(new THREE.Vector3(0, anchorHeight, 0));
  const desired = anchor.clone().addScaledVector(direction, -CAMERA.distance);
  const castDirection = desired.clone().sub(anchor);
  const castDistance = castDirection.length();
  raycaster.set(anchor, castDirection.normalize());
  const hit = raycaster.intersectObjects(obstacleMeshes, false)[0];
  if (hit && hit.distance < castDistance) desired.copy(anchor).addScaledVector(castDirection, Math.max(0.25, hit.distance - CAMERA.collisionRadius));
  camera.position.lerp(desired, 0.32);
  const lookOrigin = player.position.clone().add(new THREE.Vector3(0, player.posture === "PRONE" ? 0.62 : CAMERA.lookHeight, 0));
  camera.lookAt(lookOrigin.addScaledVector(direction, 14));
}

function currentSpread() {
  const speedRatio = Math.min(1, Math.hypot(player.velocity.x, player.velocity.z) / MOVEMENT.moveSpeed);
  return spreadDegrees({ speedRatio, crouched: player.posture === "CROUCHED", bloom: combat.bloom }, WEAPON);
}

function updateCombat(delta, now) {
  combat.bloom = recoverBloom(combat.bloom, WEAPON.bloomRecoveryDegPerSecond, delta);
  if (combat.reloadingUntil > 0 && now >= combat.reloadingUntil) finishReload();
  if (input.fire && now >= combat.nextShotAt && combat.reloadingUntil === 0) fire(now);

  const spread = currentSpread();
  const normalized = Math.min(1, spread / (WEAPON.fullGaitSpreadDeg + WEAPON.maxBloomDeg));
  const desiredGap = WEAPON.reticleBaseGapPx + (WEAPON.reticleMaxGapPx - WEAPON.reticleBaseGapPx) * normalized;
  combat.reticleGap += (desiredGap - combat.reticleGap) * Math.min(1, WEAPON.reticleResponse * delta);
  ui.reticle.style.setProperty("--gap", `${combat.reticleGap.toFixed(1)}px`);
}

function fire(now) {
  if (combat.magazine <= 0) {
    beginReload(now);
    return;
  }
  combat.magazine -= 1;
  combat.nextShotAt = now + 60000 / WEAPON.fireRateRpm;
  combat.bloom = bloomAfterShot(combat.bloom, player.posture === "CROUCHED", WEAPON);
  const direction = camera.getWorldDirection(new THREE.Vector3());
  const spreadRadians = THREE.MathUtils.degToRad(currentSpread());
  const randomRadius = Math.sqrt(Math.random()) * Math.tan(spreadRadians);
  const randomAngle = Math.random() * Math.PI * 2;
  const right = new THREE.Vector3().crossVectors(direction, camera.up).normalize();
  const up = new THREE.Vector3().crossVectors(right, direction).normalize();
  direction.addScaledVector(right, Math.cos(randomAngle) * randomRadius)
    .addScaledVector(up, Math.sin(randomAngle) * randomRadius)
    .normalize();
  raycaster.set(camera.position, direction);
  raycaster.far = 220;
  const hit = raycaster.intersectObjects([...targetHitMeshes, ...obstacleMeshes], false)[0];
  const end = hit ? hit.point : camera.position.clone().addScaledVector(direction, 120);
  createTracer(player.weapon?.position || player.position, end);
  if (hit?.object.userData.target?.alive) {
    const target = hit.object.userData.target;
    const damage = WEAPON.damage * (hit.object.userData.zone === "head" ? WEAPON.headshotMultiplier : 1);
    damageTarget(target, damage, hit.object.userData.zone === "head" ? "HEADSHOT" : "HIT");
  }
  if (combat.magazine === 0 && combat.reserve > 0) beginReload(now + 30);
  syncHud();
}

function createTracer(start, end) {
  const geometry = new THREE.BufferGeometry().setFromPoints([start.clone(), end.clone()]);
  const line = new THREE.Line(geometry, new THREE.LineBasicMaterial({ color: 0xffd67a, transparent: true, opacity: 0.88 }));
  scene.add(line);
  effects.push({ object: line, age: 0, life: 0.055 });
}

function beginReload(now = performance.now()) {
  if (combat.reloadingUntil > 0 || combat.magazine >= WEAPON.magazineCapacity || combat.reserve <= 0) return;
  combat.reloadingUntil = now + WEAPON.reloadSeconds * 1000;
  ui["weapon-state"].textContent = "RELOADING";
}

function finishReload() {
  const needed = WEAPON.magazineCapacity - combat.magazine;
  const moved = Math.min(needed, combat.reserve);
  combat.magazine += moved;
  combat.reserve -= moved;
  combat.reloadingUntil = 0;
  ui["weapon-state"].textContent = "RIFLE READY";
  syncHud();
}

function damageTarget(target, amount, label) {
  if (!target.alive) return;
  target.health -= amount;
  if (target.health <= 0) {
    target.alive = false;
    target.root.rotation.z = -1.35;
    target.root.position.y = 0.08;
    showMessage(`${label} · ${target.name} DOWN`);
  } else {
    showMessage(`${label} · ${Math.ceil(target.health)} REMAINING`, 650);
  }
  syncHud();
}

function updateGrenadePreview(now) {
  if (input.grenadeStart < 0 || combat.grenades <= 0) {
    trajectory.visible = false;
    ui["grenade-charge"].classList.add("hidden");
    return;
  }
  const charge = Math.min(1, (now - input.grenadeStart) / (GRENADE.chargeSeconds * 1000));
  ui["grenade-charge"].classList.remove("hidden");
  ui["grenade-charge"].querySelector("b").style.width = `${charge * 100}%`;
  const { origin, velocity } = grenadeLaunch(charge);
  const points = [];
  const position = origin.clone();
  const previewVelocity = velocity.clone();
  for (let i = 0; i < 46; i += 1) {
    points.push(position.clone());
    previewVelocity.y -= MOVEMENT.gravity * 0.065;
    position.addScaledVector(previewVelocity, 0.065);
    if (position.y <= GRENADE.radius) {
      position.y = GRENADE.radius;
      points.push(position.clone());
      break;
    }
  }
  trajectory.geometry.dispose();
  trajectory.geometry = new THREE.BufferGeometry().setFromPoints(points);
  trajectory.computeLineDistances();
  trajectory.visible = true;
}

function grenadeLaunch(charge) {
  const direction = aimDirection();
  const elevation = THREE.MathUtils.clamp(
    THREE.MathUtils.radToDeg(input.pitch),
    GRENADE.minimumElevationDeg,
    GRENADE.maximumElevationDeg,
  );
  const horizontal = horizontalForward();
  const launchDirection = horizontal.multiplyScalar(Math.cos(THREE.MathUtils.degToRad(elevation)))
    .add(new THREE.Vector3(0, Math.sin(THREE.MathUtils.degToRad(elevation)), 0))
    .normalize();
  const origin = player.position.clone().add(new THREE.Vector3(0, player.posture === "PRONE" ? 0.55 : 1.25, 0)).addScaledVector(direction, 0.42);
  return { origin, velocity: launchDirection.multiplyScalar(grenadeSpeed(charge, GRENADE)) };
}

function throwGrenade(now) {
  if (input.grenadeStart < 0 || combat.grenades <= 0) return;
  const charge = Math.min(1, (now - input.grenadeStart) / (GRENADE.chargeSeconds * 1000));
  input.grenadeStart = -1;
  const launch = grenadeLaunch(charge);
  const mesh = new THREE.Mesh(
    new THREE.SphereGeometry(GRENADE.radius, 12, 8),
    material(0x394838, 0.92, 0.12),
  );
  mesh.position.copy(launch.origin);
  mesh.castShadow = true;
  scene.add(mesh);
  projectiles.push({ mesh, velocity: launch.velocity, age: 0 });
  combat.grenades -= 1;
  syncHud();
}

function updateProjectiles(delta) {
  for (let index = projectiles.length - 1; index >= 0; index -= 1) {
    const grenade = projectiles[index];
    grenade.age += delta;
    grenade.velocity.y -= MOVEMENT.gravity * delta;
    const previous = grenade.mesh.position.clone();
    grenade.mesh.position.addScaledVector(grenade.velocity, delta);
    if (grenade.mesh.position.y < GRENADE.radius) {
      grenade.mesh.position.y = GRENADE.radius;
      grenade.velocity.y = Math.abs(grenade.velocity.y) * GRENADE.restitution;
      grenade.velocity.x *= 0.76;
      grenade.velocity.z *= 0.76;
    }
    for (const box of obstacles) {
      const point = grenade.mesh.position;
      const inside = point.x > box.min.x - GRENADE.radius && point.x < box.max.x + GRENADE.radius &&
        point.y > box.min.y - GRENADE.radius && point.y < box.max.y + GRENADE.radius &&
        point.z > box.min.z - GRENADE.radius && point.z < box.max.z + GRENADE.radius;
      if (!inside) continue;
      grenade.mesh.position.copy(previous);
      const movement = grenade.velocity.clone().multiplyScalar(delta);
      if (Math.abs(movement.x) > Math.abs(movement.z)) grenade.velocity.x *= -GRENADE.restitution;
      else grenade.velocity.z *= -GRENADE.restitution;
    }
    grenade.mesh.rotation.x += grenade.velocity.z * delta;
    grenade.mesh.rotation.z -= grenade.velocity.x * delta;
    if (grenade.age >= GRENADE.fuseSeconds) {
      explode(grenade.mesh.position);
      scene.remove(grenade.mesh);
      grenade.mesh.geometry.dispose();
      grenade.mesh.material.dispose();
      projectiles.splice(index, 1);
    }
  }
}

function explode(position) {
  const sphere = new THREE.Mesh(
    new THREE.SphereGeometry(0.5, 18, 12),
    new THREE.MeshBasicMaterial({ color: 0xff8b42, transparent: true, opacity: 0.88, depthWrite: false }),
  );
  sphere.position.copy(position);
  scene.add(sphere);
  const light = new THREE.PointLight(0xff6a32, 90, 16, 2);
  light.position.copy(position);
  scene.add(light);
  effects.push({ object: sphere, light, age: 0, life: 0.42, expand: true });
  for (const target of targets) {
    if (!target.alive) continue;
    const distance = target.root.position.distanceTo(position);
    const damage = blastDamage(distance, GRENADE);
    if (damage > 0) damageTarget(target, damage, "FRAG");
  }
}

function updateEffects(delta) {
  for (let index = effects.length - 1; index >= 0; index -= 1) {
    const effect = effects[index];
    effect.age += delta;
    const amount = Math.min(1, effect.age / effect.life);
    if (effect.expand) effect.object.scale.setScalar(1 + amount * GRENADE.blastRadius * 1.7);
    if (effect.object.material) effect.object.material.opacity = 1 - amount;
    if (effect.light) effect.light.intensity = 90 * (1 - amount);
    if (effect.age >= effect.life) {
      scene.remove(effect.object);
      if (effect.light) scene.remove(effect.light);
      effect.object.geometry?.dispose();
      effect.object.material?.dispose();
      effects.splice(index, 1);
    }
  }
}

function syncHud() {
  ui.health.textContent = String(Math.max(0, Math.ceil(player.health)));
  ui.magazine.textContent = String(combat.magazine).padStart(2, "0");
  ui.reserve.textContent = String(combat.reserve);
  ui.grenades.textContent = String(combat.grenades);
  ui.stance.textContent = player.posture;
  ui["targets-left"].textContent = String(targets.filter((target) => target.alive).length);
}

let messageTimer = 0;
function showMessage(text, duration = 1200) {
  ui.message.textContent = text;
  ui.message.classList.add("visible");
  clearTimeout(messageTimer);
  messageTimer = setTimeout(() => ui.message.classList.remove("visible"), duration);
}

function resize() {
  const width = Math.max(1, canvas.clientWidth);
  const height = Math.max(1, canvas.clientHeight);
  const pixelRatio = renderer.getPixelRatio();
  if (canvas.width !== Math.round(width * pixelRatio) || canvas.height !== Math.round(height * pixelRatio)) {
    renderer.setSize(width, height, false);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
  }
}

function animate() {
  requestAnimationFrame(animate);
  resize();
  const now = performance.now();
  const delta = Math.min(0.033, (now - clock.previous) / 1000);
  clock.previous = now;
  updatePlayer(delta);
  updateCamera();
  updateCombat(delta, now);
  updateGrenadePreview(now);
  updateProjectiles(delta);
  updateEffects(delta);
  renderer.render(scene, camera);
}

function togglePosture(posture) {
  player.posture = player.posture === posture ? "STANDING" : posture;
  syncHud();
}

function activateGame() {
  gameActive = true;
  ui.deploy.classList.add("hidden");
  canvas.focus();
  enableEmbeddedMouseLook();
}

function enableEmbeddedMouseLook() {
  embeddedMouseLook = true;
  showMessage("EMBEDDED MODE · HOLD RIGHT MOUSE AND DRAG TO AIM", 3200);
}

ui["deploy-button"].addEventListener("click", activateGame);
document.addEventListener("pointerlockchange", () => {
  if (document.pointerLockElement === canvas) {
    gameActive = true;
    embeddedMouseLook = false;
    ui.deploy.classList.add("hidden");
    return;
  }
  if (gameActive) enableEmbeddedMouseLook();
  input.fire = false;
});
document.addEventListener("mousemove", (event) => {
  const locked = document.pointerLockElement === canvas;
  const draggingInEmbeddedMode = gameActive && embeddedMouseLook && (event.buttons & 2) !== 0;
  if (!locked && !draggingInEmbeddedMode) return;
  input.yaw -= event.movementX * CAMERA.sensitivity;
  input.pitch -= event.movementY * CAMERA.sensitivity;
  input.pitch = THREE.MathUtils.clamp(
    input.pitch,
    THREE.MathUtils.degToRad(CAMERA.pitchMin),
    THREE.MathUtils.degToRad(CAMERA.pitchMax),
  );
});
document.addEventListener("mousedown", (event) => {
  if (event.button === 0 && gameActive) input.fire = true;
});
document.addEventListener("mouseup", (event) => {
  if (event.button === 0) input.fire = false;
});
document.addEventListener("keydown", (event) => {
  keys.add(event.code);
  if (event.repeat) return;
  if (event.code === "KeyR") beginReload();
  if (event.code === "KeyC") togglePosture("CROUCHED");
  if (event.code === "KeyZ") togglePosture("PRONE");
  if (event.code === "KeyG" && input.grenadeStart < 0 && combat.grenades > 0) input.grenadeStart = performance.now();
});
document.addEventListener("keyup", (event) => {
  keys.delete(event.code);
  if (event.code === "KeyG") throwGrenade(performance.now());
});
window.addEventListener("blur", () => {
  keys.clear();
  input.fire = false;
});
canvas.addEventListener("contextmenu", (event) => event.preventDefault());

syncHud();
loadOperator();
updateCamera();
animate();
