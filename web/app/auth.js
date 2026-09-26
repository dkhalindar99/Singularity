// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// Who you are in the web app. The server says which kind of sign-in it
// expects (/config.json): Firebase on a real deployment — a friend without an
// account is signed in anonymously, which the host can refuse — or dev tokens
// on a developer's machine.

import { uuid } from "/src/core/uuid.js";

const FIREBASE_SDK = "https://www.gstatic.com/firebasejs/11.10.0";

function stored(key, make) {
  try {
    let value = localStorage.getItem(key);
    if (!value) {
      value = make();
      localStorage.setItem(key, value);
    }
    return value;
  } catch {
    return make();
  }
}

export const deviceId = stored("spacenotes-live-device", () => `web-${uuid().slice(0, 8).toLowerCase()}`);

/** Returns `getToken(name) => Promise<string>`. */
export async function makeAuth(config) {
  if (config.auth === "firebase") {
    const [{ initializeApp }, { getAuth, signInAnonymously, onAuthStateChanged }] = await Promise.all([
      import(`${FIREBASE_SDK}/firebase-app.js`),
      import(`${FIREBASE_SDK}/firebase-auth.js`),
    ]);
    const app = initializeApp(config.firebase);
    const auth = getAuth(app);
    await new Promise((resolve) => onAuthStateChanged(auth, resolve));
    return async () => {
      if (!auth.currentUser) await signInAnonymously(auth);
      return auth.currentUser.getIdToken();
    };
  }
  const uid = stored("spacenotes-live-dev-uid", () => `u${uuid().replaceAll("-", "").slice(0, 12).toLowerCase()}`);
  return async (name = "") => `dev:${uid}:${name.replace(/[:\n]/g, " ").slice(0, 60)}`;
}
