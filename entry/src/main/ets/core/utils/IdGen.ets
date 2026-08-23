// ID + timestamp helpers matching Joplin's conventions.
//
// Joplin ids are 32-char lowercase hex strings (a UUID v4 with the dashes
// stripped); timestamps on the wire are UTC ISO-8601 with millisecond
// precision and a literal `Z` suffix, while locally we keep epoch millis.
//
// `@ohos.util` exposes `util` as a default export, so the namespace has to be
// imported as a whole — `import { generateRandomUUID }` is not valid.
import util from '@ohos.util';

export function newId(): string {
  const uuid: string = util.generateRandomUUID(false);
  return uuid.replace(/-/g, '').toLowerCase();
}

export function nowMs(): number {
  return new Date().getTime();
}

function pad(value: number, width: number): string {
  let s: string = String(value);
  while (s.length < width) {
    s = `0${s}`;
  }
  return s;
}

// 2026-08-23T04:21:18.123Z — Joplin parses this with moment(v) so any valid
// ISO-8601 works, but we emit exactly what the JS clients emit.
export function toJoplinTime(ms: number): string {
  if (!ms) {
    return '';
  }
  const d: Date = new Date(ms);
  const year: string = pad(d.getUTCFullYear(), 4);
  const month: string = pad(d.getUTCMonth() + 1, 2);
  const day: string = pad(d.getUTCDate(), 2);
  const hour: string = pad(d.getUTCHours(), 2);
  const minute: string = pad(d.getUTCMinutes(), 2);
  const second: string = pad(d.getUTCSeconds(), 2);
  const millis: string = pad(d.getUTCMilliseconds(), 3);
  return `${year}-${month}-${day}T${hour}:${minute}:${second}.${millis}Z`;
}

export function fromJoplinTime(value: string): number {
  if (!value) {
    return 0;
  }
  const parsed: number = Date.parse(value);
  if (Number.isNaN(parsed)) {
    // Some older Joplin revisions wrote raw epoch millis into these fields.
    const asNumber: number = Number(value);
    return Number.isNaN(asNumber) ? 0 : asNumber;
  }
  return parsed;
}
