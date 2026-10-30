// Shared by the link pages. Everything read from the URL goes into the page as text, never HTML.

/** Where "Get Kedro" points: the TestFlight public link now, the App Store later. Until it's set,
 *  the pages say Kedro is in a private beta and to ask the host for an invite. */
export const INSTALL_URL = null

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/** The path segment after `/t/`, `/s/` or `/claim/`. */
export function pathPart(index) {
  return decodeURIComponent(location.pathname.split('/').filter(Boolean)[index] ?? '')
}

export function query(name) {
  return new URLSearchParams(location.search).get(name)?.trim() || null
}

export const isGameID = (value) => UUID.test(value)

export function setText(id, text) {
  document.getElementById(id).textContent = text
}

export function show(id, visible = true) {
  document.getElementById(id).hidden = !visible
}

/** Fills the "get the app" block: a button when there's an install link, the beta line otherwise.
 *  `host` names who to ask ("Noah"), or null for "whoever's hosting". */
export function setUpInstall(host) {
  if (INSTALL_URL) {
    const button = document.getElementById('install')
    button.href = INSTALL_URL
    button.hidden = false
  } else {
    setText('beta', `Kedro is in a private beta on iPhone. Ask ${host ?? "whoever's hosting"} for an invite.`)
    show('beta')
  }
}
