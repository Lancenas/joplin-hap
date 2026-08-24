const { createCanvas } = require('@napi-rs/canvas');
const fs = require('fs');

const MEDIA = '/Users/lixiao/WorkBuddy/joplin-hap/AppScope/resources/base/media';

// Joplin 品牌蓝
const BLUE = '#1F58B8';
const BLUE_DARK = '#1746A0';
const WHITE = '#FFFFFF';

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

// 1) background.png —— 圆角蓝色方块（288x288，layered 背景层）
function makeBackground(size = 288) {
  const canvas = createCanvas(size, size);
  const ctx = canvas.getContext('2d');
  const pad = size * 0.04;
  const r = size * 0.20;
  // 渐变
  const g = ctx.createLinearGradient(0, 0, size, size);
  g.addColorStop(0, BLUE);
  g.addColorStop(1, BLUE_DARK);
  roundRect(ctx, pad, pad, size - pad * 2, size - pad * 2, r);
  ctx.fillStyle = g;
  ctx.fill();
  return canvas;
}

// 2) foreground.png —— 透明背景上的白色 "JH"（288x288，layered 前景层）
function makeForeground(size = 288) {
  const canvas = createCanvas(size, size);
  const ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, size, size);
  drawJH(ctx, size, WHITE);
  return canvas;
}

// 3) 单体图标 app_icon.png / startIcon.png —— 蓝底白字 "JH"（216x216）
function makeFlatIcon(size = 216) {
  const canvas = createCanvas(size, size);
  const ctx = canvas.getContext('2d');
  const pad = size * 0.04;
  const r = size * 0.20;
  const g = ctx.createLinearGradient(0, 0, size, size);
  g.addColorStop(0, BLUE);
  g.addColorStop(1, BLUE_DARK);
  roundRect(ctx, pad, pad, size - pad * 2, size - pad * 2, r);
  ctx.fillStyle = g;
  ctx.fill();
  drawJH(ctx, size, WHITE);
  return canvas;
}

// 绘制 JH 字母组合
function drawJH(ctx, size, color) {
  ctx.save();
  ctx.fillStyle = color;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';

  const fontSize = size * 0.52;
  ctx.font = `700 ${fontSize}px sans-serif`;
  // 字间距稍微收紧，使 "JH" 视觉成一个整体
  const text = 'JH';
  const w = ctx.measureText(text).width;
  const cx = size / 2;
  const cy = size / 2;
  // 微调基线，因 J 顶部较高，整体略下沉更平衡
  ctx.fillText(text, cx, cy + size * 0.02);
  ctx.restore();
}

function save(canvas, path) {
  const buf = canvas.toBuffer('image/png');
  fs.writeFileSync(path, buf);
  console.log('wrote', path, buf.length, 'bytes');
}

save(makeBackground(288), `${MEDIA}/background.png`);
save(makeForeground(288), `${MEDIA}/foreground.png`);
save(makeFlatIcon(216), `${MEDIA}/app_icon.png`);
save(makeFlatIcon(216), `${MEDIA}/startIcon.png`);
console.log('done');
