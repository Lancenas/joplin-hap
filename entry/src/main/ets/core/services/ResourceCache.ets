// Resource blob 本地缓存、预览解析与系统打开。
//
// Joplin 的附件（图片 / PDF / 文件）以 Resource（jop_type=4）形式同步：
//   - 元数据（title/mime/size/fileExtension）在 `<id>.md`，随 delta 同步进 resources 表
//   - 二进制 blob 在 `.resource/<id>`，按需从这里下载并缓存到 filesDir/resources/<id>.<ext>
//
// 图片：预览时把 `![](:/<id>)` 渲染成 base64 data URI 内嵌进 HTML。
// 文件（PDF 等）：在编辑器里以附件卡片呈现，点击后保存带扩展名的本地文件，
//   用 `ohos.want.action.viewData` + fileUri 拉起系统默认查看器打开。
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common, Want, wantConstant } from '@kit.AbilityKit';
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

function ensureCacheDir(): void {
  const dir: string = cacheDir();
  if (!fs.accessSync(dir)) {
    fs.mkdirSync(dir, true);
  }
}

// 从设置重建一个带 session 的 JoplinApi，用于按需下载 blob。
// 缓存复用同一个 session，避免一篇笔记里多个附件每个都重新登录。
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

// 取附件的扩展名（小写、不带点），用于缓存文件名与 mime 推断。
function resourceExt(res: Resource | null): string {
  if (res !== null && res.fileExtension !== '') {
    return res.fileExtension.toLowerCase();
  }
  if (res !== null && res.mime === 'application/pdf') {
    return 'pdf';
  }
  return 'bin';
}

// 根据 resource 元数据 / 扩展名猜一个 mime，预览 data URI 与系统打开都用。
function guessMime(res: Resource | null): string {
  if (res !== null && res.mime !== '') {
    return res.mime;
  }
  const ext: string = resourceExt(res);
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

// 确保 blob 已下载到本地缓存（带扩展名），返回文件路径；失败返回 ''。
// 这是图片 base64 与文件系统打开共用的唯一缓存入口。
export async function ensureResourceFile(resourceId: string): Promise<string> {
  try {
    ensureCacheDir();
    const res: Resource | null = await resourceRepo.get(resourceId);
    const ext: string = resourceExt(res);
    const path: string = `${cacheDir()}/${resourceId}.${ext}`;

    if (fs.accessSync(path)) {
      console.info(`[resource] cache hit ${resourceId}.${ext}`);
      return path;
    }

    console.info(`[resource] cache miss, downloading blob: ${resourceId}`);
    const api: JoplinApi = await buildApi();
    const downloaded: ArrayBuffer = await api.getResourceBlob(resourceId);
    console.info(`[resource] downloaded ${resourceId}: ${downloaded.byteLength} bytes`);

    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, downloaded);
    fs.closeSync(file);
    return path;
  } catch (e) {
    console.warn(`[resource] ensureResourceFile failed for ${resourceId}: ${(e as Error).message}`);
    return '';
  }
}

function readFileBase64(path: string): string {
  const stat = fs.statSync(path);
  const buf: ArrayBuffer = new ArrayBuffer(stat.size);
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  fs.readSync(file.fd, buf);
  fs.closeSync(file);
  const base64Helper = new util.Base64Helper();
  return base64Helper.encodeToStringSync(new Uint8Array(buf));
}

// 返回可直接放进 <img src="..."> 的 data URI；非图片或失败返回 ''。
export async function getResourceDataUri(resourceId: string): Promise<string> {
  try {
    const res: Resource | null = await resourceRepo.get(resourceId);
    const mime: string = guessMime(res);
    if (!isImageMime(mime)) {
      // 非图片（PDF 等）不内嵌，由预览层单独处理成附件卡片。
      return '';
    }
    const path: string = await ensureResourceFile(resourceId);
    if (path === '') {
      return '';
    }
    const base64: string = readFileBase64(path);
    return `data:${mime};base64,${base64}`;
  } catch (e) {
    console.warn(`[resource] dataUri failed for ${resourceId}: ${(e as Error).message}`);
    return '';
  }
}

// 返回资源的元数据（无则 null），用于附件卡片。
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

// ─── 附件列表与系统打开 ───

export interface AttachmentInfo {
  id: string;
  title: string;
  mime: string;
  isImage: boolean;
}

// 从笔记正文扫描 `](​:/<id>)` 资源引用（图片语法 `![](:/id)` 与链接语法 `[x](:/id)` 都覆盖）。
export function extractResourceIds(body: string): string[] {
  const ids: string[] = [];
  const marker: string = '(:/';
  let idx: number = body.indexOf(marker);
  let guard: number = 0;
  while (idx >= 0 && guard < 200) {
    guard += 1;
    const start: number = idx + marker.length;
    const end: number = body.indexOf(')', start);
    if (end < 0) {
      break;
    }
    const id: string = body.substring(start, end).trim();
    if (id !== '' && ids.indexOf(id) < 0) {
      ids.push(id);
    }
    idx = body.indexOf(marker, end);
  }
  return ids;
}

// 列出笔记的所有附件（含 mime 与是否图片）。
export async function getNoteAttachments(body: string): Promise<AttachmentInfo[]> {
  const ids: string[] = extractResourceIds(body);
  const out: AttachmentInfo[] = [];
  for (const id of ids) {
    const res: Resource | null = await resourceRepo.get(id);
    const mime: string = guessMime(res);
    let title: string = '附件';
    if (res !== null && res.title !== '') {
      title = res.title;
    } else if (res !== null && res.filename !== '') {
      title = res.filename;
    }
    const info: AttachmentInfo = {
      id: id,
      title: title,
      mime: mime,
      isImage: mime.startsWith('image/'),
    };
    out.push(info);
  }
  return out;
}

// 下载附件（若未缓存）并用系统默认查看器打开。返回 '' 成功，否则返回错误信息。
export async function openResourceWithSystem(resourceId: string, context: Context): Promise<string> {
  try {
    const res: Resource | null = await resourceRepo.get(resourceId);
    const mime: string = guessMime(res);
    const path: string = await ensureResourceFile(resourceId);
    if (path === '') {
      return '附件下载失败';
    }
    const uri: string = fileUri.getUriFromPath(path);
    console.info(`[resource] openWithSystem ${resourceId}: uri=${uri} mime=${mime}`);
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: uri,
      type: mime,
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION | wantConstant.Flags.FLAG_AUTH_WRITE_URI_PERMISSION,
    };
    const uiContext = context as common.UIAbilityContext;
    await uiContext.startAbility(want);
    return '';
  } catch (e) {
    console.warn(`[resource] openWithSystem failed for ${resourceId}: ${(e as Error).message}`);
    return (e as Error).message;
  }
}
