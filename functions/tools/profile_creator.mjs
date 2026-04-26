/**
 * Creates 100 demo accounts (50 men + 50 women): Firebase Auth, profile photos
 * in Storage, Firestore `users/{uid}`.
 *
 * Photos are **downloaded from the public RandomUser API** (random people / faces
 * by gender). No local `lib/test_images` files are used.
 *
 * Prerequisites (Firebase Auth Admin needs a **service account key**):
 *   • Put `*-firebase-adminsdk-*.json` under `lib/services/` (auto-detected), or
 *   • export GOOGLE_APPLICATION_CREDENTIALS="/path/to/key.json"
 *
 *   `gcloud auth application-default login` alone usually fails with auth/insufficient-permission
 *   when creating users. To force ADC anyway: ALLOW_IMPLICIT_ADC=1
 *
 * Optional env: FIREBASE_PROJECT_ID, FIREBASE_STORAGE_BUCKET, SEED_PASSWORD
 *
 * Run:
 *   cd functions && node tools/profile_creator.mjs
 *   npm run profile:creator
 *
 * Outputs:
 *   tools/profile_creator.generated.json
 *   tools/profile_creator.generated.mjs
 */

import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";

import admin from "firebase-admin";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, "../..");

const PROJECT_ID =
  process.env.FIREBASE_PROJECT_ID ||
  process.env.GCLOUD_PROJECT ||
  "geekdin-f7049";
const STORAGE_BUCKET =
  process.env.FIREBASE_STORAGE_BUCKET || "geekdin-f7049.firebasestorage.app";
const SEED_PASSWORD =
  process.env.SEED_PASSWORD || "GeekdinSeedProfiles123!";
const KEEP_EMAIL = "sean@geekdin.com";
const MIN_SEED_AGE = 18;
const MAX_SEED_AGE = 100;
const PHOTO_COUNT_PER_PROFILE = 3;
const MEN_COUNT = 50;
const WOMEN_COUNT = 50;
/** @type {`https://${string}`} */
const RANDOM_USER_API = "https://randomuser.me/api/";

const BIO_TEMPLATES = [
  "Weekend hiker, coffee, and a shelf full of half-finished side projects.",
  "Into games, live music, and good typography.",
  "Remote-first worker; loves bookstores and bouldering gyms.",
  "Collects old cameras and new hot sauces.",
  "Data by day, board games and pizza by night.",
  "Loves art museums, long runs, and quiet mornings.",
  "Comics, sci-fi, and mechanical keyboards (sorry).",
  "Cooks a lot, bikes when the weather allows.",
  "Travel buff; always looking for a good ramen spot nearby.",
  "Music-first: playlists, vinyl, and too many concert tickets.",
];

const INTERESTS_POOLS = [
  ["photography", "hiking", "indie music"],
  ["cooking", "pickleball", "podcasts"],
  ["reading", "coffee", "running"],
  ["film", "bouldering", "travel"],
  ["design", "cycling", "museums"],
  ["Flutter", "board games", "local food"],
  ["backend", "sci-fi", "dungeons & dragons"],
  ["mobile", "basketball", "mechanical keyboards"],
  ["data", "cycling", "comics"],
  ["painting", "jazz", "camping"],
];

function downloadUrl(bucketName, objectPath, token) {
  const encoded = encodeURIComponent(objectPath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encoded}?alt=media&token=${token}`;
}

/** @param {string} contentType */
function extForContentType(contentType) {
  const lower = (contentType || "").toLowerCase();
  if (lower.includes("png")) return ".png";
  if (lower.includes("webp")) return ".webp";
  if (lower.includes("avif")) return ".avif";
  if (lower.includes("jpeg") || lower.includes("jpg")) return ".jpg";
  return ".jpg";
}

/**
 * @param {import('@google-cloud/storage').Bucket} bucket
 * @param {string} uid
 * @param {string} destBase
 * @param {Buffer} buffer
 * @param {string} contentType
 */
async function uploadImageBuffer(bucket, uid, destBase, buffer, contentType) {
  const ext = extForContentType(contentType);
  const destName = `${destBase}${ext}`;
  const objectPath = `users/${uid}/profile_images/${destName}`;
  const file = bucket.file(objectPath);
  const token = randomUUID();
  await file.save(buffer, {
    resumable: false,
    metadata: {
      contentType: contentType || "image/jpeg",
      metadata: {
        firebaseStorageDownloadTokens: token,
      },
    },
  });
  return { objectPath, url: downloadUrl(bucket.name, objectPath, token) };
}

/**
 * @param {string} url
 * @param {number} [attempts]
 */
async function downloadImageWithRetry(url, attempts = 3) {
  let lastErr;
  for (let a = 0; a < attempts; a++) {
    try {
      const res = await fetch(url, {
        headers: { "user-agent": "geekdin-profile-creator/1.0" },
        redirect: "follow",
      });
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      const ab = await res.arrayBuffer();
      const buffer = Buffer.from(ab);
      const type = (res.headers.get("content-type") || "image/jpeg").split(";")[0].trim();
      return { buffer, contentType: type };
    } catch (e) {
      lastErr = e;
      if (a < attempts - 1) {
        await new Promise((r) => setTimeout(r, 400 * (a + 1)));
      }
    }
  }
  throw lastErr ?? new Error("downloadImage failed");
}

/**
 * Fetches 3 users of the given Firestore gender to get 3 different portrait URLs.
 * @param {'man' | 'woman'} firestoreGender
 */
async function fetchRandomUserTriple(firestoreGender) {
  const apiGender = firestoreGender === "man" ? "male" : "female";
  const params = new URLSearchParams({
    results: String(PHOTO_COUNT_PER_PROFILE),
    gender: apiGender,
    noinfo: "1",
    nat: "us,gb,ca,au,de,fr,es,ie",
  });
  const url = `${RANDOM_USER_API}?${params.toString()}`;

  let lastErr;
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      const res = await fetch(url, { headers: { "user-agent": "geekdin-profile-creator/1.0" } });
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      const data = await res.json();
      const list = data?.results;
      if (!Array.isArray(list) || list.length < PHOTO_COUNT_PER_PROFILE) {
        throw new Error("randomuser: unexpected payload");
      }
      return list.slice(0, PHOTO_COUNT_PER_PROFILE);
    } catch (e) {
      lastErr = e;
      await new Promise((r) => setTimeout(r, 500 * (attempt + 1)));
    }
  }
  throw lastErr ?? new Error("fetchRandomUserTriple failed");
}

/**
 * Picks the main profile row (name + city) from the first result; uses all three for images.
 * @param {any[]} triple
 * @param {number} seedIndex
 */
function profileFromRandomUser(triple, seedIndex) {
  const u0 = triple[0];
  const n = u0.name;
  const displayName = `${n.first} ${n.last}`.replace(/\b\w/g, (c) => c.toUpperCase());
  const loc = u0.location;
  const statePart = loc.state ? `${loc.state}, ` : "";
  const city = `${loc.city} · ${statePart}${loc.country}`.replace(/\s+,/g, ",");
  const rawLat = loc.coordinates?.latitude ?? loc.coordinates?.lat;
  const rawLng = loc.coordinates?.longitude ?? loc.coordinates?.lon;
  const lat = parseFloat(String(rawLat ?? "NaN"));
  const lng = parseFloat(String(rawLng ?? "NaN"));
  let latitude = Number.isFinite(lat) ? lat : 40.7128;
  let longitude = Number.isFinite(lng) ? lng : -74.006;
  if (latitude === 0 && longitude === 0) {
    latitude = 40.7128;
    longitude = -74.006;
  }
  const bio = BIO_TEMPLATES[seedIndex % BIO_TEMPLATES.length];
  const interests = INTERESTS_POOLS[seedIndex % INTERESTS_POOLS.length];
  return { displayName, city, latitude, longitude, bio, interests };
}

/** @param {number} minInclusive @param {number} maxInclusive */
function randomInt(minInclusive, maxInclusive) {
  return (
    Math.floor(Math.random() * (maxInclusive - minInclusive + 1)) + minInclusive
  );
}

function randomBirthdateBetweenAges(minAge, maxAge) {
  const now = new Date();
  const latestDob = new Date(
    Date.UTC(now.getUTCFullYear() - minAge, now.getUTCMonth(), now.getUTCDate()),
  );
  const earliestDob = new Date(
    Date.UTC(
      now.getUTCFullYear() - (maxAge + 1),
      now.getUTCMonth(),
      now.getUTCDate() + 1,
    ),
  );
  const atMs = randomInt(earliestDob.getTime(), latestDob.getTime());
  const d = new Date(atMs);
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}

function calculateAgeFromBirthdate(birthdate) {
  const now = new Date();
  let age = now.getUTCFullYear() - birthdate.getUTCFullYear();
  const hadBirthdayThisYear =
    now.getUTCMonth() > birthdate.getUTCMonth() ||
    (now.getUTCMonth() === birthdate.getUTCMonth() &&
      now.getUTCDate() >= birthdate.getUTCDate());
  if (!hadBirthdayThisYear) {
    age -= 1;
  }
  return age;
}

async function listAllAuthUsers() {
  const all = [];
  let pageToken = undefined;
  do {
    const page = await admin.auth().listUsers(1000, pageToken);
    all.push(...page.users);
    pageToken = page.pageToken;
  } while (pageToken);
  return all;
}

/**
 * Removes all users except KEEP_EMAIL from Auth/Firestore/Storage.
 * @param {import('firebase-admin/firestore').Firestore} db
 * @param {import('@google-cloud/storage').Bucket} bucket
 */
async function purgeUsersExceptKeep(db, bucket) {
  const allUsers = await listAllAuthUsers();
  const keepAuthUser = allUsers.find(
    (u) => (u.email || "").toLowerCase() === KEEP_EMAIL.toLowerCase(),
  );
  const keepUid = keepAuthUser?.uid ?? null;

  const authDeleteUids = allUsers
    .filter((u) => u.uid !== keepUid)
    .map((u) => u.uid);
  if (authDeleteUids.length > 0) {
    const chunks = [];
    for (let i = 0; i < authDeleteUids.length; i += 1000) {
      chunks.push(authDeleteUids.slice(i, i + 1000));
    }
    for (const chunk of chunks) {
      await admin.auth().deleteUsers(chunk);
    }
  }

  const usersSnap = await db.collection("users").get();
  const deletedFirestoreUids = [];
  for (const doc of usersSnap.docs) {
    if (doc.id === keepUid) {
      continue;
    }
    if (typeof db.recursiveDelete === "function") {
      await db.recursiveDelete(doc.ref);
    } else {
      await doc.ref.delete();
    }
    deletedFirestoreUids.push(doc.id);
  }

  const storageDeleteUids = new Set([
    ...authDeleteUids,
    ...deletedFirestoreUids.filter((uid) => uid !== keepUid),
  ]);
  for (const uid of storageDeleteUids) {
    try {
      await bucket.deleteFiles({ prefix: `users/${uid}/` });
    } catch (_) {
      // Ignore missing objects or per-object delete errors and continue purge.
    }
  }

  return {
    keepUid,
    deletedAuthUsers: authDeleteUids.length,
    deletedFirestoreUsers: deletedFirestoreUids.length,
    deletedStorageUserFolders: storageDeleteUids.size,
  };
}

/** First `*-firebase-adminsdk-*.json` in repo `lib/services/`, if any. */
function findDefaultServiceAccountJson() {
  const dir = join(REPO_ROOT, "lib/services");
  if (!existsSync(dir)) {
    return null;
  }
  const names = readdirSync(dir).filter(
    (n) => n.endsWith(".json") && n.includes("firebase-adminsdk"),
  );
  names.sort();
  if (names.length === 0) {
    return null;
  }
  return join(dir, names[0]);
}

function getAdminCredential() {
  if (process.env.ALLOW_IMPLICIT_ADC === "1") {
    console.warn(
      "ALLOW_IMPLICIT_ADC=1: using application default credentials (may lack Firebase Auth admin).",
    );
    return admin.credential.applicationDefault();
  }

  const fromEnv = process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim();
  if (fromEnv && !existsSync(fromEnv)) {
    console.warn(
      `WARN: GOOGLE_APPLICATION_CREDENTIALS is set but file not found (ignoring, will try lib/services/):\n  ${fromEnv}\n` +
        `Unset it in this shell if it was a mistake: unset GOOGLE_APPLICATION_CREDENTIALS\n`,
    );
  }

  const keyPath =
    fromEnv && existsSync(fromEnv) ? fromEnv : findDefaultServiceAccountJson();

  if (!keyPath) {
    console.error(`
profile_creator: no service account JSON found.

Either:
  • Save your Firebase key as lib/services/<project>-firebase-adminsdk-<suffix>.json
    (this repo auto-detects that pattern), or
  • export GOOGLE_APPLICATION_CREDENTIALS="/real/path/to/key.json"

Download a key:
  https://console.firebase.google.com/project/${PROJECT_ID}/settings/serviceaccounts/adminsdk
`);
    process.exit(1);
  }

  if (!fromEnv) {
    console.log(
      `profile_creator: using service account (override with GOOGLE_APPLICATION_CREDENTIALS):\n  ${keyPath}\n`,
    );
  }

  const json = JSON.parse(readFileSync(keyPath, "utf8"));
  return admin.credential.cert(json);
}

async function getOrCreateAuthUser({ email, password, displayName }) {
  try {
    return await admin.auth().createUser({
      email,
      password,
      displayName,
      emailVerified: true,
    });
  } catch (e) {
    if (e?.errorInfo?.code === "auth/email-already-exists") {
      const user = await admin.auth().getUserByEmail(email);
      await admin.auth().updateUser(user.uid, { displayName, password });
      return user;
    }
    throw e;
  }
}

/**
 * 50 women (seed.woman.1..50) + 50 men (seed.man.1..50) for stable logins.
 * @returns {{ displayName: string; email: string; bio: string; interests: string[]; city: string; latitude: number; longitude: number; gender: 'man' | 'woman'; slugOrdinal: number; }[]}
 */
function buildSeedRows() {
  const rows = [];
  for (let i = 1; i <= WOMEN_COUNT; i++) {
    rows.push({
      email: `seed.woman.${i}@geekdin.local`,
      gender: "woman",
      slugOrdinal: i,
    });
  }
  for (let i = 1; i <= MEN_COUNT; i++) {
    rows.push({
      email: `seed.man.${i}@geekdin.local`,
      gender: "man",
      slugOrdinal: i,
    });
  }
  return rows;
}

async function main() {
  admin.initializeApp({
    credential: getAdminCredential(),
    projectId: PROJECT_ID,
    storageBucket: STORAGE_BUCKET,
  });

  const bucket = admin.storage().bucket(STORAGE_BUCKET);
  const db = admin.firestore();
  const FieldValue = admin.firestore.FieldValue;

  const purge = await purgeUsersExceptKeep(db, bucket);
  console.log(
    `Purge complete: kept ${KEEP_EMAIL}${purge.keepUid ? ` (${purge.keepUid})` : " (not found)"}; deleted auth=${purge.deletedAuthUsers}, firestore=${purge.deletedFirestoreUsers}, storageFolders=${purge.deletedStorageUserFolders}`,
  );
  console.log();

  const PROFILES = buildSeedRows();
  /** @type {{ uid: string; email: string; displayName: string; gender: string; genderPreference: string; age: number; birthdate: string; profileImageUrls: string[]; storagePaths: string[]; }[]} */
  const results = [];

  for (let i = 0; i < PROFILES.length; i++) {
    const row = PROFILES[i];
    const isMan = row.gender === "man";
    const genderPreference = isMan ? "women" : "men";
    const slug = isMan
      ? `seed_man_${row.slugOrdinal}`
      : `seed_woman_${row.slugOrdinal}`;

    const triple = await fetchRandomUserTriple(row.gender);
    const meta = profileFromRandomUser(triple, i);
    const user = await getOrCreateAuthUser({
      email: row.email,
      password: SEED_PASSWORD,
      displayName: meta.displayName,
    });

    const profileImageUrls = [];
    const storagePaths = [];
    for (let photoIndex = 0; photoIndex < triple.length; photoIndex++) {
      const imageUrl = triple[photoIndex].picture?.large;
      if (!imageUrl) {
        throw new Error("randomuser: missing picture.large");
      }
      const { buffer, contentType } = await downloadImageWithRetry(imageUrl);
      const { url, objectPath } = await uploadImageBuffer(
        bucket,
        user.uid,
        `${slug}_${photoIndex + 1}`,
        buffer,
        contentType,
      );
      profileImageUrls.push(url);
      storagePaths.push(objectPath);
    }

    const birthdate = randomBirthdateBetweenAges(MIN_SEED_AGE, MAX_SEED_AGE);
    const age = calculateAgeFromBirthdate(birthdate);

    await db
      .collection("users")
      .doc(user.uid)
      .set(
        {
          email: row.email,
          displayName: meta.displayName,
          gender: row.gender,
          genderPreference,
          agePreference: { min: MIN_SEED_AGE, max: MAX_SEED_AGE },
          distance: 50,
          isGlobal: false,
          preferenceUpdatedAt: FieldValue.serverTimestamp(),
          birthdate: admin.firestore.Timestamp.fromDate(birthdate),
          createdAt: FieldValue.serverTimestamp(),
          profileImageUrls,
          city: meta.city,
          latitude: meta.latitude,
          longitude: meta.longitude,
          bio: meta.bio,
          interests: meta.interests,
          profileUpdatedAt: FieldValue.serverTimestamp(),
          seedProfile: true,
        },
        { merge: true },
      );

    results.push({
      uid: user.uid,
      email: row.email,
      displayName: meta.displayName,
      gender: row.gender,
      genderPreference,
      age,
      birthdate: birthdate.toISOString().slice(0, 10),
      profileImageUrls,
      storagePaths,
    });

    if ((i + 1) % 10 === 0 || i === 0) {
      console.log(
        `Progress ${i + 1}/${PROFILES.length} — ${row.email} (${row.gender}, age ${age})`,
      );
    }
  }

  const jsonPath = join(__dirname, "profile_creator.generated.json");
  writeFileSync(jsonPath, JSON.stringify(results, null, 2), "utf8");

  const mjsPath = join(__dirname, "profile_creator.generated.mjs");
  const mjsBody = `// Generated by tools/profile_creator.mjs — do not edit by hand.
export const SEEDED_PROFILES = ${JSON.stringify(results, null, 2)};

export const SEED_ACCOUNT_PASSWORD = ${JSON.stringify(SEED_PASSWORD)};
`;
  writeFileSync(mjsPath, mjsBody, "utf8");

  console.log();
  console.log(`Wrote ${jsonPath}`);
  console.log(`Wrote ${mjsPath}`);
}

main().catch((err) => {
  console.error(err);
  if (err?.errorInfo?.code === "auth/insufficient-permission") {
    console.error(`
auth/insufficient-permission: the credential cannot manage Firebase Authentication.

Fix:
  • Prefer a **service account JSON** from Firebase Console (see header comment in this file)
    and set GOOGLE_APPLICATION_CREDENTIALS to that file.
  • If you already use a JSON key, open Google Cloud Console → IAM and ensure that service
    account has a role that includes Firebase Auth admin (e.g. "Firebase Authentication Admin"
    or "Editor" on the project).
`);
  }
  process.exit(1);
});
