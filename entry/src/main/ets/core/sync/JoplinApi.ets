// HTTP wrapper for the Joplin Server REST API.
//
// ArkTS notes:
//  * interfaces may not declare index signatures (arkts-no-indexed-signatures),
//    so header/query maps are `Record<...>` aliases — Record *is* indexable.
//  * object literals need a declared target type, and quoted property names
//    such as 'X-API-AUTH' are rejected inside literals
//    (arkts-identifiers-as-prop-names), so those maps are filled by assignment.
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

export type QueryMap = Record<string, string>;
export type HeaderMap = Record<string, string>;

export interface ApiResponse {
  status: number;
  body: string;
}

export class ApiError extends Error {
  status: number;
  code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

interface SessionResponse {
  id?: string;
}

interface ErrorPayload {
  error?: string;
  message?: string;
}

const CONTENT_TYPE = 'Content-Type';
const API_AUTH = 'X-API-AUTH';
const JSON_MIME = 'application/json';
export const TEXT_MIME = 'text/plain';

function methodOf(method: string): http.RequestMethod {
  if (method === 'GET') {
    return http.RequestMethod.GET;
  }
  if (method === 'POST') {
    return http.RequestMethod.POST;
  }
  if (method === 'PUT') {
    return http.RequestMethod.PUT;
  }
  if (method === 'DELETE') {
    return http.RequestMethod.DELETE;
  }
  if (method === 'OPTIONS') {
    return http.RequestMethod.OPTIONS;
  }
  return http.RequestMethod.GET;
}

export function trimSlashes(s: string): string {
  return s.replace(/^\/+/, '').replace(/\/+$/, '');
}

// Joplin Server addresses items by their "root:/<id><ext>:" pseudo-path.
// The delta endpoint is `api/items/root:/:/delta` — the id is empty but the
// trailing colon is REQUIRED because the server route `api/items/:id/delta`
// matches `:id` greedily up to the last `/delta`, and the change-model parser
// expects the format to be `root:<inner-path>`. With an empty inner path the
// full id becomes "root:/:" (no extra slash).
//
// All sync items (Note / Folder / Tag / NoteTag / Resource-metadata) share the
// `<joplin-id>.md` (or `.resource`) naming convention. Body fetch/upload goes
// through the `/content` suffix; bare `:id` returns only the metadata JSON.
export const DELTA_PATH = 'api/items/root:/:/delta';
export function itemMetadataPath(name: string): string {
  return `api/items/root:/${name}:`;
}
export function itemContentPath(name: string): string {
  return `${itemMetadataPath(name)}/content`;
}

function buildUrl(base: string, path: string, query: QueryMap | null): string {
  const normBase: string = base.startsWith('http') ? base : `https://${base}`;
  let url: string = `${normBase.replace(/\/+$/, '')}/${path.replace(/^\/+/, '')}`;
  if (query !== null) {
    const qs: string[] = [];
    const keys: string[] = Object.keys(query);
    for (const k of keys) {
      qs.push(`${encodeURIComponent(k)}=${encodeURIComponent(query[k])}`);
    }
    if (qs.length > 0) {
      url += `?${qs.join('&')}`;
    }
  }
  return url;
}

function parseSession(s: string): SessionResponse {
  const empty: SessionResponse = {};
  if (!s) {
    return empty;
  }
  try {
    return JSON.parse(s) as SessionResponse;
  } catch (err) {
    return empty;
  }
}

function parseErrorPayload(s: string): ErrorPayload {
  const empty: ErrorPayload = {};
  if (!s) {
    return empty;
  }
  try {
    return JSON.parse(s) as ErrorPayload;
  } catch (err) {
    return empty;
  }
}

export class JoplinApi {
  baseUrl: string;
  sessionId: string;
  username: string;
  password: string;

  constructor(baseUrl: string) {
    this.baseUrl = trimSlashes(baseUrl);
    this.sessionId = '';
    this.username = '';
    this.password = '';
  }

  setBaseUrl(url: string): void {
    this.baseUrl = trimSlashes(url);
  }

  // POST api/sessions { email, password } -> { id: <session id> }
  async session(): Promise<void> {
    if (this.sessionId !== '') {
      return;
    }
    const payload: string = JSON.stringify(new SessionRequest(this.username, this.password));
    const res: ApiResponse = await this.exec('POST', 'api/sessions', null, payload, null);
    const json: SessionResponse = parseSession(res.body);
    const id: string = json.id ?? '';
    if (id === '') {
      throw new ApiError(res.status, 'noSession', 'Login response is missing the session id');
    }
    this.sessionId = id;
  }

  async logout(): Promise<void> {
    if (this.sessionId === '') {
      return;
    }
    try {
      await this.exec('DELETE', `api/sessions/${this.sessionId}`);
    } catch (err) {
      // Best-effort — the local session is dropped regardless.
    }
    this.sessionId = '';
  }

  async exec(
    method: string,
    path: string,
    query: QueryMap | null = null,
    body: string | null = null,
    extraHeaders: HeaderMap | null = null
  ): Promise<ApiResponse> {
    if (path !== 'api/sessions' && this.sessionId === '') {
      throw new ApiError(401, 'notAuthenticated', 'Not authenticated: call session() first');
    }
    const url: string = buildUrl(this.baseUrl, path, query);

    const headers: HeaderMap = {};
    headers[CONTENT_TYPE] = JSON_MIME;
    if (this.sessionId !== '') {
      headers[API_AUTH] = this.sessionId;
    }
    if (extraHeaders !== null) {
      const extraKeys: string[] = Object.keys(extraHeaders);
      for (const k of extraKeys) {
        headers[k] = extraHeaders[k];
      }
    }

    const opts: http.HttpRequestOptions = {
      method: methodOf(method),
      header: headers,
      connectTimeout: 15000,
      readTimeout: 30000,
      expectDataType: http.HttpDataType.STRING,
      extraData: body === null ? '' : body,
    };

    const request = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, opts);
      const status: number = response.responseCode;
      const text: string = typeof response.result === 'string' ? response.result as string : '';
      if (status >= 200 && status < 300) {
        const ok: ApiResponse = { status: status, body: text };
        return ok;
      }
      const data: ErrorPayload = parseErrorPayload(text);
      throw new ApiError(status, data.error ?? 'http', data.message ?? text);
    } catch (err) {
      if (err instanceof ApiError) {
        throw err;
      }
      const be: BusinessError = err as BusinessError;
      throw new ApiError(-1, 'network', be.message ?? 'Network request failed');
    } finally {
      request.destroy();
    }
  }
}

// A class (rather than an interface + literal) so JSON.stringify has a concrete
// instance to walk and ArkTS has a declared type for the construction site.
class SessionRequest {
  email: string;
  password: string;

  constructor(email: string, password: string) {
    this.email = email;
    this.password = password;
  }
}
