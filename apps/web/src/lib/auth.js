// Sign-in. Production: Apple or Google through Supabase Auth (the same accounts the API verifies).
// Apple is the iPhone app's provider; Google is for Android people (and the future Android app).
// Local development against `dev:seed` can also sign in as a seeded test account, whose token is
// "dev:<uuid>" (apps/api KEDRO_DEV_AUTH).

import { supabase } from './supabase';

const DEV_ACCOUNT_KEY = 'kedro_dev_account';

export const devSignInAvailable = import.meta.env.DEV;

function devAccountId() {
  if (!devSignInAvailable) return null;
  try { return localStorage.getItem(DEV_ACCOUNT_KEY); } catch { return null; }
}

export async function getAccessToken() {
  const devId = devAccountId();
  if (devId) return `dev:${devId}`;
  const { data } = await supabase.auth.getSession();
  return data.session?.access_token ?? null;
}

/** True when a token is available (a Supabase session or a dev account). */
export async function isSignedIn() {
  return (await getAccessToken()) !== null;
}

export function signInWithGoogle() {
  return supabase.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: window.location.origin } });
}

/** The iPhone app's provider: the same Apple ID gives the same account here as in the app. */
export function signInWithApple() {
  return supabase.auth.signInWithOAuth({ provider: 'apple', options: { redirectTo: window.location.origin } });
}

// A claim link (playkedro.com/claim/<code> → "Claim on the web" → /?claim=<code>). Kept for this
// tab through sign-in, which leaves for Google or Apple and comes back, and redeemed once in.
const PENDING_CLAIM_KEY = 'kedro_pending_claim';

/** Moves `?claim=` out of the address bar into the tab's storage. */
export function stashClaimFromURL() {
  const url = new URL(window.location.href);
  const code = url.searchParams.get('claim');
  if (!code) return;
  try { sessionStorage.setItem(PENDING_CLAIM_KEY, code); } catch {}
  url.searchParams.delete('claim');
  window.history.replaceState(null, '', url);
}

/** The stashed claim code, removed so it's redeemed once. */
export function takePendingClaim() {
  try {
    const code = sessionStorage.getItem(PENDING_CLAIM_KEY);
    sessionStorage.removeItem(PENDING_CLAIM_KEY);
    return code;
  } catch {
    return null;
  }
}

export function signInAsDevAccount(id) {
  localStorage.setItem(DEV_ACCOUNT_KEY, id);
}

export async function signOut() {
  try { localStorage.removeItem(DEV_ACCOUNT_KEY); } catch {}
  await supabase.auth.signOut();
}

/** Calls back when the Supabase session changes (sign-in after the Google redirect, sign-out). */
export function onAuthChange(callback) {
  const { data } = supabase.auth.onAuthStateChange((event) => callback(event));
  return () => data.subscription.unsubscribe();
}
