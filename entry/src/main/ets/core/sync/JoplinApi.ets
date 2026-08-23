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
// Resource 二进制 blob 独立存放在 `.resource/<id>` 路径下（与 <id>.md 元数据分开）。
export function resourceBlobPath(resourceId: string): string {
  return `api/items/root:/.resource/${resourceId}:/content`;
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

  // 下载 Resource 二进制 blob（图片 / PDF / 附件）。与 exec 不同，响应用
  // ARRAY_BUFFER 而非 STRING，避免二进制被当文本解码损坏。
  async getResourceBlob(resourceId: string): Promise<ArrayBuffer> {
    if (this.sessionId === '') {
      throw new ApiError(401, 'notAuthenticated', 'Not authenticated: call session() first');
    }
    const url: string = buildUrl(this.baseUrl, resourceBlobPath(resourceId), null);
    const headers: HeaderMap = {};
    headers[API_AUTH] = this.sessionId;
    const opts: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: 15000,
      readTimeout: 60000,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
    };
    const request = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, opts);
      const status: number = response.responseCode;
      if (status >= 200 && status < 300) {
        const buf = response.result as ArrayBuffer;
        return buf;
      }
      throw new ApiError(status, 'http', `Resource blob fetch failed: HTTP ${status}`);
    } catch (err) {
      if (err instanceof ApiError) {
        throw err;
      }
      const be: BusinessError = err as BusinessError;
      throw new ApiError(-1, 'network', `getResourceBlob ${resourceId}: ${be.message ?? 'Network request failed'}`);
    } finally {
      try {
        request.destroy();
      } catch (e) {
        // ignore
      }
    }
  }

  // 上传 Resource 二进制 blob 到 `.resource/<id>`（Content-Type:
  // application/octet-stream，服务端 formidable 按文件接收）。metadata 另走
  // `PUT <id>.md`（见 Synchronizer.uploadItem）。
  async putResourceBlob(resourceId: string, blob: ArrayBuffer): Promise<void> {
    if (this.sessionId === '') {
      throw new ApiError(401, 'notAuthenticated', 'Not authenticated: call session() first');
    }
    const url: string = buildUrl(this.baseUrl, resourceBlobPath(resourceId), null);
    const headers: HeaderMap = {};
    headers[API_AUTH] = this.sessionId;
    headers[CONTENT_TYPE] = 'application/octet-stream';
    const opts: http.HttpRequestOptions = {
      method: http.RequestMethod.PUT,
      header: headers,
      connectTimeout: 15000,
      readTimeout: 120000,
      expectDataType: http.HttpDataType.STRING,
      extraData: blob,
    };
    const request = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, opts);
      const status: number = response.responseCode;
      if (status >= 200 && status < 300) {
        console.info(`[sync] putResourceBlob ${resourceId}: ${blob.byteLength}B → ${status}`);
        return;
      }
      const text: string = typeof response.result === 'string' ? response.result as string : '';
      throw new ApiError(status, 'http', `blob upload failed: HTTP ${status} ${text.slice(0, 120)}`);
    } catch (err) {
      if (err instanceof ApiError) {
        throw err;
      }
      const be: BusinessError = err as BusinessError;
      throw new ApiError(-1, 'network', `putResourceBlob ${resourceId}: ${be.message ?? 'Network request failed'}`);
    } finally {
      try {
        request.destroy();
      } catch (e) {
        // ignore
      }
    }
  }

  async exec(
    method: string,
    path: string,
    query: QueryMap | null = null,
    body: string | null = null,
    extraHeaders: HeaderMap | null = null,
    retries: number = 0,
    retryDelayMs: number = 500
  ): Promise<ApiResponse> {
    if (path !== 'api/sessions' && this.sessionId === '') {
      throw new ApiError(401, 'notAuthenticated', 'Not authenticated: call session() first');
    }
    const url: string = buildUrl(this.baseUrl, path, query);

    const headers: HeaderMap = {};
    // Only advertise a Content-Type when we actually have a body or the caller
    // asked for a specific one — sending `application/json` on a GET can be
    // rejected by stricter server middleware.
    if (body !== null || extraHeaders !== null) {
      headers[CONTENT_TYPE] = JSON_MIME;
    }
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

    const maxAttempts: number = 1 + (retries > 0 ? retries : 0);
    let attempt: number = 0;
    let lastErr: ApiError | null = null;
    while (attempt < maxAttempts) {
      attempt += 1;
      const request = http.createHttp();
      try {
        const response: http.HttpResponse = await request.request(url, opts);
        const status: number = response.responseCode;
        const text: string = typeof response.result === 'string' ? response.result as string : '';
        if (status >= 200 && status < 300) {
          if (attempt > 1) {
            console.info(`[net] ${method} ${path} recovered on attempt ${attempt}/${maxAttempts}`);
          }
          const ok: ApiResponse = { status: status, body: text };
          return ok;
        }
        // Non-2xx HTTP responses are explicit server answers — do NOT retry,
        // surface them to the user as-is.
        const data: ErrorPayload = parseErrorPayload(text);
        throw new ApiError(status, data.error ?? 'http', data.message ?? text);
      } catch (err) {
        if (err instanceof ApiError) {
          throw err;
        }
        // Transport-level failure (TLS, connection reset, read failure, …) —
        // these can be transient, so retry with linear backoff.
        const be: BusinessError = err as BusinessError;
        const beCode: string = String(be.code ?? '?');
        const beMsg: string = be.message ?? 'Network request failed';
        lastErr = new ApiError(-1, 'network', `${method} ${path}: ${beMsg}`);
        console.warn(`[net] ${method} ${path} attempt ${attempt}/${maxAttempts} failed: code=${beCode} msg=${beMsg}`);
        if (attempt < maxAttempts) {
          await delay(retryDelayMs * attempt);
        }
      } finally {
        try {
          request.destroy();
        } catch (e) {
          // The request object may already be invalid; nothing to do.
        }
      }
    }
    throw lastErr ?? new ApiError(-1, 'network', `${method} ${path} failed after ${maxAttempts} attempts`);
  }
}

// Local Promise-based sleep used between HTTP retries.
function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
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
