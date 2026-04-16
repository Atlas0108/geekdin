/**
 * Creates 3 men + 3 women: Firebase Auth, profile photo in Storage, Firestore `users/{uid}`.
 *
 * Images (relative to repo `lib/test_images/`):
 *   men/   — 3 files
 *   women/ — 3 files
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
import { dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";

import admin from "firebase-admin";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, "../..");
const TEST_IMAGES = join(REPO_ROOT, "lib/test_images");

const PROJECT_ID =
  process.env.FIREBASE_PROJECT_ID ||
  process.env.GCLOUD_PROJECT ||
  "geekdin-f7049";
const STORAGE_BUCKET =
  process.env.FIREBASE_STORAGE_BUCKET || "geekdin-f7049.firebasestorage.app";
const SEED_PASSWORD =
  process.env.SEED_PASSWORD || "GeekdinSeedProfiles123!";

/** @param {string} filePath */
function contentTypeFor(filePath) {
  const lower = filePath.toLowerCase();
  if (lower.endsWith(".png")) return "image/png";
  if (lower.endsWith(".webp")) return "image/webp";
  if (lower.endsWith(".avif")) return "image/avif";
  if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
  return "application/octet-stream";
}

function downloadUrl(bucketName, objectPath, token) {
  const encoded = encodeURIComponent(objectPath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encoded}?alt=media&token=${token}`;
}

/**
 * @param {import('@google-cloud/storage').Bucket} bucket
 * @param {string} uid
 * @param {string} localPath
 * @param {string} destBase e.g. seed_man_1 (extension added from local file)
 */
async function uploadProfilePhoto(bucket, uid, localPath, destBase) {
  const buffer = readFileSync(localPath);
  const ext = extname(localPath) || ".jpg";
  const destName = `${destBase}${ext}`;
  const objectPath = `users/${uid}/profile_images/${destName}`;
  const file = bucket.file(objectPath);
  const token = randomUUID();
  const contentType = contentTypeFor(localPath);
  await file.save(buffer, {
    resumable: false,
    metadata: {
      contentType,
      metadata: {
        firebaseStorageDownloadTokens: token,
      },
    },
  });
  const url = downloadUrl(bucket.name, objectPath, token);
  return { objectPath, url };
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

/** @type {{ displayName: string; email: string; imageRelative: string; bio: string; interests: string[]; city: string; latitude: number; longitude: number; gender: 'man' | 'woman'; }[]} */
const PROFILES = [
  {
    displayName: "Maya Chen",
    email: "seed.woman.1@geekdin.local",
    imageRelative: join("women", "images (1).jpeg"),
    bio: "Product designer who loves indie games and weekend hikes.",
    interests: ["design", "indie games", "hiking"],
    city: "Seattle · Washington, United States, US",
    latitude: 47.6062,
    longitude: -122.3321,
    gender: "woman",
  },
  {
    displayName: "Jordan Rivera",
    email: "seed.woman.2@geekdin.local",
    imageRelative: join("women", "download.jpeg"),
    bio: "Backend engineer, coffee snob, and sci-fi book club regular.",
    interests: ["backend", "coffee", "sci-fi"],
    city: "Austin · Texas, United States, US",
    latitude: 30.2672,
    longitude: -97.7431,
    gender: "woman",
  },
  {
    displayName: "Sam Okonkwo",
    email: "seed.woman.3@geekdin.local",
    imageRelative: join("women", "images (2).jpeg"),
    bio: "Flutter dev, board games, and volunteering at the makerspace.",
    interests: ["Flutter", "board games", "makerspace"],
    city: "Toronto · Ontario, Canada, CA",
    latitude: 43.6532,
    longitude: -79.3832,
    gender: "woman",
  },
  {
    displayName: "Chris Patel",
    email: "seed.man.1@geekdin.local",
    imageRelative: join("men", "71G18R09DwL._AC_UY1000_.jpg"),
    bio: "Mobile dev, pickup basketball, and mechanical keyboards.",
    interests: ["mobile", "basketball", "keyboards"],
    city: "Chicago · Illinois, United States, US",
    latitude: 41.8781,
    longitude: -87.6298,
    gender: "man",
  },
  {
    displayName: "Alex Morgan",
    email: "seed.man.2@geekdin.local",
    imageRelative: join("men", "hlh050121feablacksuperpower-001-1618863056.avif"),
    bio: "Data scientist, comics collector, and weekend cyclist.",
    interests: ["data", "comics", "cycling"],
    city: "Denver · Colorado, United States, US",
    latitude: 39.7392,
    longitude: -104.9903,
    gender: "man",
  },
  {
    displayName: "Riley Brooks",
    email: "seed.man.3@geekdin.local",
    imageRelative: join("men", "images (3).jpeg"),
    bio: "Game dev, D&D DM, and espresso experiments at home.",
    interests: ["game dev", "D&D", "coffee"],
    city: "Portland · Oregon, United States, US",
    latitude: 45.5152,
    longitude: -122.6784,
    gender: "man",
  },
];

async function main() {
  admin.initializeApp({
    credential: getAdminCredential(),
    projectId: PROJECT_ID,
    storageBucket: STORAGE_BUCKET,
  });

  const bucket = admin.storage().bucket(STORAGE_BUCKET);
  const db = admin.firestore();
  const FieldValue = admin.firestore.FieldValue;

  /** @type {{ uid: string; email: string; displayName: string; gender: string; profileImageUrl: string; storagePath: string; }[]} */
  const results = [];

  for (let i = 0; i < PROFILES.length; i++) {
    const row = PROFILES[i];
    const localPath = join(TEST_IMAGES, row.imageRelative);
    const user = await getOrCreateAuthUser({
      email: row.email,
      password: SEED_PASSWORD,
      displayName: row.displayName,
    });

    const slug =
      row.gender === "man"
        ? `seed_man_${PROFILES.filter((_, j) => j <= i && PROFILES[j].gender === "man").length}`
        : `seed_woman_${PROFILES.filter((_, j) => j <= i && PROFILES[j].gender === "woman").length}`;

    const { url, objectPath } = await uploadProfilePhoto(
      bucket,
      user.uid,
      localPath,
      slug,
    );

    await db
      .collection("users")
      .doc(user.uid)
      .set(
        {
          email: row.email,
          displayName: row.displayName,
          gender: row.gender,
          createdAt: FieldValue.serverTimestamp(),
          profileImageUrls: [url],
          city: row.city,
          latitude: row.latitude,
          longitude: row.longitude,
          bio: row.bio,
          interests: row.interests,
          profileUpdatedAt: FieldValue.serverTimestamp(),
          seedProfile: true,
        },
        { merge: true },
      );

    results.push({
      uid: user.uid,
      email: row.email,
      displayName: row.displayName,
      gender: row.gender,
      profileImageUrl: url,
      storagePath: objectPath,
    });

    console.log(`OK ${row.displayName} (${row.gender}) — ${user.uid}`);
    console.log(`   ${url}\n`);
  }

  const jsonPath = join(__dirname, "profile_creator.generated.json");
  writeFileSync(jsonPath, JSON.stringify(results, null, 2), "utf8");

  const mjsPath = join(__dirname, "profile_creator.generated.mjs");
  const mjsBody = `// Generated by tools/profile_creator.mjs — do not edit by hand.
export const SEEDED_PROFILES = ${JSON.stringify(results, null, 2)};

export const SEED_ACCOUNT_PASSWORD = ${JSON.stringify(SEED_PASSWORD)};
`;
  writeFileSync(mjsPath, mjsBody, "utf8");

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
