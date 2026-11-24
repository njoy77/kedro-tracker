import { describe, expect, test } from 'bun:test';
import { claimAlias } from '../src/lib/claims.js';

const me = { id: 'p:000000aa-0000-4000-8000-000000000001' };
const rhysGuest = '00000000-0000-4000-8000-0000000000aa';
const rhysoroni = '000000aa-0000-4000-8000-000000000002';
const myGuest = '00000000-0000-4000-8000-0000000000bb';

describe('claimAlias', () => {
  test("a friend's claimed web-era guest counts as their account", () => {
    const alias = claimAlias({ claims: { [rhysGuest]: rhysoroni }, ownGuestIds: new Set(), me });
    expect(alias(`g:${rhysGuest}`)).toBe(`p:${rhysoroni}`);
  });

  test("the user's own claim counts as the user, listed by the server or not yet", () => {
    expect(claimAlias({ ownGuestIds: new Set([myGuest]), me })(`g:${myGuest}`)).toBe(me.id);
    expect(claimAlias({ claims: { [myGuest]: me.id.slice(2) }, me })(`g:${myGuest}`)).toBe(me.id);
  });

  test('unclaimed guests, accounts and an older server (no claims) keep their own key', () => {
    const alias = claimAlias({ claims: undefined, ownGuestIds: new Set(), me });
    expect(alias(`g:${rhysGuest}`)).toBe(`g:${rhysGuest}`);
    expect(alias(`p:${rhysoroni}`)).toBe(`p:${rhysoroni}`);
    expect(claimAlias()(`g:${rhysGuest}`)).toBe(`g:${rhysGuest}`);
  });
});
