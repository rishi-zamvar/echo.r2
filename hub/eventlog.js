export class EventLog {
  #ring = [];
  #bytes = 0;
  #seq = 0;
  #subs = new Set();
  constructor({ maxBytes = 2 * 1024 * 1024 } = {}) { this.maxBytes = maxBytes; }

  get seq() { return this.#seq; }
  get floor() { return this.#ring.length ? this.#ring[0].event.seq : this.#seq + 1; }

  append(kind, payload) {
    const event = { v: 1, seq: ++this.#seq, kind, ...payload };
    const bytes = JSON.stringify(event).length;
    this.#ring.push({ event, bytes });
    this.#bytes += bytes;
    // always keep the newest entry even if it alone exceeds the cap
    while (this.#bytes > this.maxBytes && this.#ring.length > 1) this.#bytes -= this.#ring.shift().bytes;
    for (const fn of this.#subs) fn(event);
    return event;
  }

  since(n) {
    const reset = n < this.floor - 1;
    const events = this.#ring.map((r) => r.event).filter((e) => reset || e.seq > n);
    return { reset, events };
  }

  subscribe(fn) {
    this.#subs.add(fn);
    return () => this.#subs.delete(fn);
  }
}
