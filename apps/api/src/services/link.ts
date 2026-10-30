// Identity on the table link (design §5.3). A hub admits a phone without Ask to Sit when the
// person is already seated or is someone its owner has played with, so the person a phone claims
// to be has to be proven: the server signs a short-lived attestation that an account owns a
// device key, and the joining phone signs its hello with that key. Hubs check both offline
// against the server's public key (GET /link/key), so it works at a table with no internet.

import { createPrivateKey, createPublicKey, generateKeyPairSync, sign, type KeyObject } from 'node:crypto'
import { isoSeconds, type LinkAttestationResponse, type UUID } from '@kedro/shared'

/** A week: phones refresh it whenever they're online, and a table is often offline. */
export const LINK_ATTESTATION_TTL_MS = 7 * 24 * 60 * 60 * 1000

export class LinkAttestor {
  private readonly privateKey: KeyObject
  readonly publicKey: string

  /**
   * @param signingKey Base64 PKCS#8 DER of an Ed25519 private key (KEDRO_LINK_SIGNING_KEY). Without
   *   one, a key is generated per process (fine locally; attestations die with the process).
   */
  constructor(
    signingKey: string | undefined,
    private readonly now: () => number = Date.now,
  ) {
    this.privateKey = signingKey
      ? createPrivateKey({ key: Buffer.from(signingKey, 'base64'), format: 'der', type: 'pkcs8' })
      : generateKeyPairSync('ed25519').privateKey
    if (this.privateKey.asymmetricKeyType !== 'ed25519') throw new Error('KEDRO_LINK_SIGNING_KEY must be an Ed25519 key')
    const jwk = createPublicKey(this.privateKey).export({ format: 'jwk' })
    if (typeof jwk.x !== 'string') throw new Error('Could not export the link public key')
    this.publicKey = jwk.x
  }

  /** `<payload>.<signature>`: payload is base64url JSON `{p, d, k, e}`; the signature covers the payload's ASCII. */
  issue(playerId: UUID, deviceId: UUID, devicePublicKey: string): LinkAttestationResponse {
    const expiresAtMs = this.now() + LINK_ATTESTATION_TTL_MS
    const payload = Buffer.from(JSON.stringify({ p: playerId.toLowerCase(), d: deviceId.toLowerCase(), k: devicePublicKey, e: expiresAtMs })).toString('base64url')
    const signature = sign(null, Buffer.from(payload, 'utf8'), this.privateKey).toString('base64url')
    return { attestation: `${payload}.${signature}`, expiresAt: isoSeconds(expiresAtMs) }
  }
}
