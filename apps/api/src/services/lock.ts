// Serializes work per key within this process (one game's ingest at a time), so the status
// checks and the re-projection see each other's writes. Across instances the op log stays correct
// regardless (inserts are idempotent and every projection is rebuilt from the whole log); only the
// finished-game admission check could race, and the fold refuses such late ops anyway.

export class KeyedLock {
  private readonly tails = new Map<string, Promise<unknown>>()

  async run<T>(key: string, work: () => Promise<T>): Promise<T> {
    const previous = this.tails.get(key) ?? Promise.resolve()
    const current = previous.catch(() => {}).then(work)
    const tail = current.catch(() => {})
    this.tails.set(key, tail)
    try {
      return await current
    } finally {
      if (this.tails.get(key) === tail) this.tails.delete(key)
    }
  }
}
