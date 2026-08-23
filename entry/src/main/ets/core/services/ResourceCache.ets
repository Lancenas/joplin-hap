// Resource blob 本地缓存与预览解析。
//
// Joplin 的附件（图片 / PDF / 文件）以 Resource（jop_type=4）形式同步：
//   - 元数据（title/mime/size）在 `<id>.md`，随 delta 同步进 resources 表
//   - 二进制 blob 在 `.resource/<id>`，按需从这里下载并缓存到 filesDir/resources/
//
// 预览时把 markdown 里的 `![](:/<id>)` 渲染成 base64 data URI，内嵌进 HTML，
// 避免给 Web 组件配自定义 scheme / 拦截器。
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { getAppContext } from '../db/Database';
import { JoplinApi } from '../sync/JoplinApi';
import { resourceRepo, settingsRepo } from './Repositories';
import { Resource } from '../models/Entities';
import { KEY_SYNC_URL, KEY_SYNC_USER, KEY_SYNC_PASSWORD } from '../../viewmodel/AppStore';

const CACHE_DIR_NAME = 'resources';

function cacheDir(): string {
  const ctx: Context = getAppContext();
  return `${ctx.filesDir}/${CACHE_DIR_NAME}`;
}

function cachePath(resourceId: string): string {
  return `${cacheDir()}/${resourceId}`;
}

function ensureCacheDir(): void {
  const dir: string = cacheDir();
  if (!fs.accessSync(dir)) {
    fs.mkdirSync(dir, true);
  }
}

// 从设置重建一个带 session 的 JoplinApi，用于按需下载 blob。
// 缓存复用同一个 session，避免一篇笔记里多张图片每张都重新登录。
let cachedApi: JoplinApi | null = null;

async function buildApi(): Promise<JoplinApi> {
  if (cachedApi !== null && cachedApi.sessionId !== '') {
    return cachedApi;
  }
  const url: string = await settingsRepo.getOr(KEY_SYNC_URL, '');
  const user: string = await settingsRepo.getOr(KEY_SYNC_USER, '');
  const pass: string = await settingsRepo.getOr(KEY_SYNC_PASSWORD, '');
  const api: JoplinApi = new JoplinApi(url);
  api.username = user;
  api.password = pass;
  await api.session();
  cachedApi = api;
  return api;
}

// 根据 resource 元数据 / 扩展名猜一个 mime，预览 data URI 用。
function guessMime(res: Resource | null, resourceId: string): string {
  if (res !== null && res.mime !== '') {
    return res.mime;
  }
  const ext: string = (res !== null ? res.fileExtension : '').toLowerCase();
  if (ext === 'png') {
    return 'image/png';
  }
  if (ext === 'jpg' || ext === 'jpeg') {
    return 'image/jpeg';
  }
  if (ext === 'gif') {
    return 'image/gif';
  }
  if (ext === 'webp') {
    return 'image/webp';
  }
  if (ext === 'svg') {
    return 'image/svg+xml';
  }
  if (ext === 'pdf') {
    return 'application/pdf';
  }
  // 笔记里 `![](:/id)` 绝大多数是图片，默认按 png 处理。
  return 'image/png';
}

function isImageMime(mime: string): boolean {
  return mime.startsWith('image/');
}

// 读取缓存的 blob；没有则下载并写缓存。返回 base64 字符串。
async function loadBlobBase64(resourceId: string): Promise<string> {
  ensureCacheDir();
  const path: string = cachePath(resourceId);
  let buffer: ArrayBuffer | null = null;

  if (fs.accessSync(path)) {
    try {
      const stat = fs.statSync(path);
      const buf: ArrayBuffer = new ArrayBuffer(stat.size);
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      buffer = buf;
    } catch (e) {
      buffer = null;
    }
  }

  if (buffer === null) {
    console.info(`[resource] cache miss, downloading blob: ${resourceId}`);
    const api: JoplinApi = await buildApi();
    const downloaded: ArrayBuffer = await api.getResourceBlob(resourceId);
    console.info(`[resource] downloaded ${resourceId}: ${downloaded.byteLength} bytes`);
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, downloaded);
      fs.closeSync(file);
    } catch (e) {
      console.warn(`[resource] cache write failed for ${resourceId}: ${(e as Error).message}`);
    }
    buffer = downloaded;
  } else {
    console.info(`[resource] cache hit ${resourceId}: ${buffer.byteLength} bytes`);
  }

  const base64Helper = new util.Base64Helper();
  const bytes: Uint8Array = new Uint8Array(buffer);
  const b64: string = base64Helper.encodeToStringSync(bytes);
  console.info(`[resource] base64 ${resourceId}: ${b64.length} chars`);
  return b64;
}

// 返回可直接放进 <img src="..."> 的 data URI；失败返回 ''。
export async function getResourceDataUri(resourceId: string): Promise<string> {
  try {
    const res: Resource | null = await resourceRepo.get(resourceId);
    const mime: string = guessMime(res, resourceId);
    console.info(`[resource] dataUri ${resourceId}: mime=${mime} meta=${res === null ? 'MISSING' : 'ok'}`);
    if (!isImageMime(mime)) {
      // 非图片（PDF 等）不内嵌，由预览层单独处理成附件卡片。
      return '';
    }
    const base64: string = await loadBlobBase64(resourceId);
    const uri: string = `data:${mime};base64,${base64}`;
    console.info(`[resource] dataUri ${resourceId}: ready, ${uri.length} chars`);
    return uri;
  } catch (e) {
    console.warn(`[resource] dataUri failed for ${resourceId}: ${(e as Error).message}`);
    return '';
  }
}

// 返回资源的人类可读信息（文件名 + mime），用于附件卡片。无元数据时给空标题。
export async function getResourceInfo(resourceId: string): Promise<Resource | null> {
  try {
    return await resourceRepo.get(resourceId);
  } catch (e) {
    return null;
  }
}

// 把 markdownToHtml 产出的 `<img data-resource-id="X" alt="Y"/>` 替换成可显示内容：
//   - 图片 → `<img src="data:<mime>;base64,..."/>`（内嵌，Web 直接渲染）
//   - 非图片附件（PDF 等）→ `<div class="attachment">` 卡片
// ArkTS 的 String.replace 不支持回调重载，所以手写扫描器逐个替换。
export async function resolveImagesInHtml(html: string): Promise<string> {
  const marker: string = '<img data-resource-id="';
  let out: string = html;
  let idx: number = out.indexOf(marker);
  let guard: number = 0;
  let found: number = 0;
  let images: number = 0;
  while (idx >= 0 && guard < 500) {
    guard += 1;
    found += 1;
    const idStart: number = idx + marker.length;
    const idEnd: number = out.indexOf('"', idStart);
    if (idEnd < 0) {
      break;
    }
    const resourceId: string = out.substring(idStart, idEnd);
    console.info(`[resource] resolve #${found}: id=${resourceId}`);
    const tagEnd: number = out.indexOf('/>', idEnd);
    if (tagEnd < 0) {
      break;
    }
    const fullTag: string = out.substring(idx, tagEnd + 2);

    // 提取 alt 文本作为附件名的兜底
    let alt: string = '';
    const altMarker: string = 'alt="';
    const altStart: number = fullTag.indexOf(altMarker);
    if (altStart >= 0) {
      const altEnd: number = fullTag.indexOf('"', altStart + altMarker.length);
      if (altEnd > altStart) {
        alt = fullTag.substring(altStart + altMarker.length, altEnd);
      }
    }

    const dataUri: string = await getResourceDataUri(resourceId);
    let replacement: string;
    if (dataUri !== '') {
      images += 1;
      replacement = `<img src="${dataUri}" alt="${alt}"/>`;
    } else {
      const info: Resource | null = await getResourceInfo(resourceId);
      let name: string = alt;
      if (info !== null && info.title !== '') {
        name = info.title;
      }
      if (name === '') {
        name = '附件';
      }
      replacement = `<div class="attachment">📎 ${name}</div>`;
    }
    out = out.substring(0, idx) + replacement + out.substring(tagEnd + 2);
    idx = out.indexOf(marker, idx + replacement.length);
  }
  console.info(`[resource] resolve done: ${found} img tag(s), ${images} embedded as image, ${found - images} as attachment card`);
  return out;
}
