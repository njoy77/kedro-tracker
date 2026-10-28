import { describe, expect, test } from 'bun:test'
import { knockOutcome, knockerScore, ordered, rankLabel, ranks, roundScores, totals, winners } from '../src/index.ts'
import { sampleRounds, seats } from './fixtures/sampleGame.ts'

describe('roundScores (PRD §2.6)', () => {
  test('knocker strictly lowest scores −10 flat', () => {
    expect(roundScores({ A: 4, B: 7, C: 9 }, 'A')).toEqual({ A: -10, B: 7, C: 9 })
    expect(knockOutcome({ A: 4, B: 7, C: 9 }, 'A')).toBe('landed')
  })

  test('knocker tied for lowest scores their hand', () => {
    expect(roundScores({ A: 4, B: 4, C: 9 }, 'A')).toEqual({ A: 4, B: 4, C: 9 })
    expect(knockOutcome({ A: 4, B: 4, C: 9 }, 'A')).toBe('tied')
  })

  test('beaten knocker scores hand + 10', () => {
    expect(roundScores({ A: 6, B: 3, C: 9 }, 'A')).toEqual({ A: 16, B: 3, C: 9 })
    expect(knockOutcome({ A: 6, B: 3, C: 9 }, 'A')).toBe('failed')
  })

  test('the landed score ignores the hand, even a negative one', () => {
    expect(roundScores({ A: -2, B: 0, C: 5 }, 'A').A).toBe(-10)
    expect(roundScores({ A: 0, B: 0, C: 5 }, 'A').A).toBe(0)
    expect(roundScores({ A: 0, B: -1, C: 5 }, 'A').A).toBe(10)
  })

  test('a knocker without a hand leaves the hands unchanged', () => {
    expect(roundScores({ B: 3, C: 9 } as Record<string, number>, 'A')).toEqual({ B: 3, C: 9 })
    expect(knockOutcome({ B: 3 } as Record<string, number>, 'A')).toBeNull()
  })

  test('a knocker alone always lands', () => {
    expect(knockOutcome({ A: 30 }, 'A')).toBe('landed')
  })

  test('knockerScore', () => {
    expect(knockerScore(9, 'landed')).toBe(-10)
    expect(knockerScore(9, 'tied')).toBe(9)
    expect(knockerScore(9, 'failed')).toBe(19)
  })
})

describe('the §17 sample game', () => {
  const expectedRoundScores = [
    [9, -10, 12, 7, 15],
    [6, 11, 5, 5, 20],
    [18, 3, 14, 10, 9],
    [3, 16, 7, 12, -1],
    [-10, 9, 6, 11, 4],
    [7, 2, 9, 8, -10],
    [5, 2, 2, 6, 12],
    [-10, 1, 12, 6, 21],
  ]
  const outcomes = ['landed', 'tied', 'failed', 'failed', 'landed', 'landed', 'tied', 'landed']
  const order = [seats.noah, seats.ana, seats.ben, seats.cleo, seats.sam]

  test('every round scores as in the table', () => {
    sampleRounds.forEach((round, index) => {
      const scores = roundScores(round.hands, round.knocker)
      expect(order.map((seat) => scores[seat])).toEqual(expectedRoundScores[index])
      expect(knockOutcome(round.hands, round.knocker)).toBe(outcomes[index] as never)
    })
  })

  const scoresThrough = (count: number) =>
    totals(sampleRounds.slice(0, count).map((round) => roundScores(round.hands, round.knocker)))

  test('after R4: 36, 20, 38, 34, 43', () => {
    const after = scoresThrough(4)
    expect(order.map((seat) => after[seat])).toEqual([36, 20, 38, 34, 43])
  })

  test('after R5: Noah 26, Ana 29, Ben 44, Cleo 45, Sam 47', () => {
    const after = scoresThrough(5)
    expect(order.map((seat) => after[seat])).toEqual([26, 29, 44, 45, 47])
  })

  test('finals: Noah 28, Ana 34, Cleo 65, Ben 67, Sam 70', () => {
    const final = scoresThrough(8)
    expect(ordered(final, order)).toEqual([seats.noah, seats.ana, seats.cleo, seats.ben, seats.sam])
    expect(ordered(final, order).map((seat) => final[seat])).toEqual([28, 34, 65, 67, 70])
    expect([...winners(final)]).toEqual([seats.noah])
  })

  test('after R3 Noah was 4th (33): a comeback', () => {
    const after = scoresThrough(3)
    expect(after[seats.noah]).toBe(33)
    expect(ranks(after)[seats.noah].position).toBe(4)
  })
})

describe('standings helpers', () => {
  test('competition ranking shares positions', () => {
    const result = ranks({ a: 26, b: 29, c: 29, d: 44 })
    expect(rankLabel(result.a)).toBe('1')
    expect(rankLabel(result.b)).toBe('2=')
    expect(rankLabel(result.c)).toBe('2=')
    expect(rankLabel(result.d)).toBe('4')
  })

  test('ties share the win', () => {
    expect(winners({ a: 10, b: 10, c: 12 })).toEqual(new Set(['a', 'b']))
    expect(winners({})).toEqual(new Set())
  })

  test('ordered keeps tie order', () => {
    expect(ordered({ a: 5, b: 3, c: 5 }, ['c', 'b', 'a'])).toEqual(['b', 'c', 'a'])
  })
})
