// Sign-in. Production: Google through Supabase Auth (the same accounts the API verifies, and the
// provider the future Android app will use). Local development against `dev:seed` can also sign in
// as a seeded test account, whose token is "dev:<uuid>" (apps/api KEDRO_DEV_AUTH).

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
