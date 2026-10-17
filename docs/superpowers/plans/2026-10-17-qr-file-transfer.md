# QR 文件传输工具 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现单文件 `qr-transfer.html`——发送端把文件编码为二维码序列循环播放，接收端通过抓屏解码重组文件，零外部依赖，完全内网可用。

**架构：** 唯一交付物 `qr-transfer.html`，四段式：内联 qrcode-generator（编码库）+ 内联 jsQR（解码库）+ 样式 + 应用代码。应用代码分五层：协议帧编解码（纯函数）→ 传输管线（gzip/SHA-256/分片/重组）→ QR 图像层（渲染/解码）→ 双模式 UI（`#send`/`#receive`）→ 页内自测（`#test`）。规格见 `docs/superpowers/specs/2026-10-17-qr-file-transfer-design.md`。

**技术栈：** 原生 HTML/JS（无构建步骤）、qrcode-generator 1.4.4、jsQR 1.4.0（均一次性内联）、浏览器内置 CompressionStream / WebCrypto / getDisplayMedia。测试通过无头 Chrome/Edge 打开 `#test` 锚点运行。

**规格确认的关键约束：**
- 完全离线：运行时禁止任何外部请求
- 不加密（用户明确选择）
- QR 一律字节模式；小文件（整帧 ≤ 500B）走单张静态 `A` 帧，否则 `H` 头帧 + `D` 数据帧循环
- 接收端必须安全上下文（`file://` / `localhost` / https）；内网 `http://裸IP` 不可用，需在 UI 中提示

---

## 文件结构

| 文件 | 职责 |
|---|---|
| `qr-transfer.html` | **唯一交付物**。内联两库 + CSS + 全部应用代码 + 自测用例 |
| `test/run-tests.sh` | 开发用：无头浏览器跑 `#test` 自测并判定通过/失败（非交付物） |
| `vendor/qrcode.js` | qrcode-generator 1.4.4 原始存档（仅来源留存，任务 1 一次性内联进 HTML） |
| `vendor/jsQR.js` | jsQR 1.4.0 原始存档（同上） |
| `README.md` | 用法说明（任务 7） |

`qr-transfer.html` 内部以注释锚点分区，后续任务用精确替换向锚点处添加代码：

```
<script>/* LIB: qrcode-generator */（内联库代码）</script>
<script>/* LIB: jsQR */（内联库代码）</script>
<style>…</style>
<body>…四个 view…</body>
<script>
  /* 测试框架 */
  // __PROTOCOL__   ← 任务 2
  // __PIPELINE__   ← 任务 3
  // __QRIMAGE__    ← 任务 4
  // __SENDER__     ← 任务 5
  // __RECEIVER__   ← 任务 6
  // __ROUTER__     ← 任务 5（路由）+ 任务 7（页内说明在 view-home 中）
  // __TESTS__      ← 各任务在其前方插入本任务的测试，并保留锚点
</script>
```

**测试运行方式（全计划统一）：**

```bash
bash test/run-tests.sh
```

预期输出最后一行 `PASS`（全部通过）或 `FAIL`（有失败，输出中含失败用例名）。

---

### 任务 1：脚手架——vendor 库、HTML 骨架、测试运行器

**文件：**
- 创建：`vendor/qrcode.js`、`vendor/jsQR.js`
- 创建：`qr-transfer.html`
- 创建：`test/run-tests.sh`

- [ ] **步骤 1：下载库到 vendor/**

```bash
mkdir -p vendor test
curl -L -o vendor/qrcode.js https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.js
curl -L -o vendor/jsQR.js https://cdn.jsdelivr.net/npm/jsqr@1.4.0/dist/jsQR.js
grep -c "qrcode" vendor/qrcode.js   # 预期 > 0
grep -c "jsQR" vendor/jsQR.js       # 预期 > 0
```

- [ ] **步骤 2：创建 HTML 骨架（含库占位行、四个 view、测试框架、路由）**

创建 `qr-transfer.html`，内容如下（`__LIB_QRCODE__` / `__LIB_JSQR__` 两占位行在步骤 3 中被库代码整体替换）：

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>QR 文件传输</title>
<script>
/* ==== LIB: qrcode-generator 1.4.4（https://github.com/kazuhikoarase/qrcode-generator，MIT）==== */
__LIB_QRCODE__
</script>
<script>
/* ==== LIB: jsQR 1.4.0（https://github.com/cozmo/jsQR，Apache-2.0）==== */
__LIB_JSQR__
</script>
<style>
body { font-family: system-ui, "Microsoft YaHei", sans-serif; margin: 0; background: #f5f5f5; color: #222; }
header { display: flex; align-items: baseline; gap: 16px; padding: 10px 20px; background: #222; color: #fff; }
header h1 { font-size: 18px; margin: 0; }
nav a { color: #9cf; margin-right: 12px; text-decoration: none; }
main { padding: 20px; max-width: 900px; margin: 0 auto; }
#qr-canvas { background: #fff; display: block; margin: 16px auto; box-shadow: 0 0 0 1px #ccc; }
#drop-zone { border: 2px dashed #999; padding: 24px; text-align: center; border-radius: 8px; background: #fff; }
#drop-zone.drag { border-color: #06c; background: #eef6ff; }
.status { margin-top: 12px; font-family: ui-monospace, Consolas, monospace; white-space: pre-wrap; }
.controls { margin: 12px 0; display: flex; gap: 16px; align-items: center; flex-wrap: wrap; }
#chunk-grid { margin-top: 8px; line-height: 0; }
#chunk-grid i { display: inline-block; width: 10px; height: 10px; margin: 1px; background: #ccc; }
#chunk-grid i.got { background: #2a2; }
.pass { color: #080; } .fail { color: #c00; }
video { max-width: 320px; background: #000; }
.note { color: #666; font-size: 13px; }
</style>
</head>
<body>
<header>
  <h1>QR 文件传输</h1>
  <nav>
    <a href="#send">发送</a>
    <a href="#receive">接收</a>
    <a href="#home">说明</a>
  </nav>
</header>
<main>
  <section id="view-home">
    <h2>用法</h2>
    <p>发送端（隔离虚拟机）：打开本页 →「发送」→ 选择文件 → 开始播放。</p>
    <p>接收端（宿主机）：打开本页 →「接收」→ 开始抓屏 → 选择虚拟机窗口。</p>
    <p class="note">接收端必须以 file:// 双击、localhost 或 https 方式打开；内网 http://裸IP 访问时浏览器会禁止抓屏。</p>
  </section>
  <section id="view-send" style="display:none">
    <div id="drop-zone">拖放文件到这里，或 <input type="file" id="file-input"></div>
    <div class="controls">
      <label>帧率 <input type="range" id="opt-fps" min="2" max="10" value="5"> <b id="opt-fps-val">5</b> fps</label>
      <label>分片 <select id="opt-chunk">
        <option value="300">300</option>
        <option value="600" selected>600</option>
        <option value="1000">1000</option>
      </select> B</label>
      <button id="btn-send-start" disabled>开始</button>
      <button id="btn-send-pause" disabled>暂停</button>
    </div>
    <canvas id="qr-canvas"></canvas>
    <div id="send-status" class="status">未选择文件</div>
  </section>
  <section id="view-receive" style="display:none">
    <div class="controls">
      <button id="btn-capture">开始抓屏</button>
      <button id="btn-recv-reset" disabled>重置</button>
    </div>
    <video id="capture-video" autoplay muted playsinline></video>
    <div id="recv-status" class="status">等待抓屏</div>
    <progress id="recv-progress" value="0" max="1" style="width:100%"></progress>
    <div id="chunk-grid"></div>
    <div id="recv-result"></div>
  </section>
  <section id="view-test" style="display:none"></section>
</main>
<script>
'use strict';
/* ===== 测试框架 ===== */
const tests = [];
function test(name, fn) { tests.push({ name, fn }); }
function assert(cond, msg) { if (!cond) throw new Error(msg || '断言失败'); }
function assertEq(a, b, msg) { if (a !== b) throw new Error((msg || 'assertEq') + '：' + JSON.stringify(a) + ' !== ' + JSON.stringify(b)); }
function assertBytesEq(a, b, msg) {
  assertEq(a.length, b.length, (msg || 'bytes') + ' 长度');
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) throw new Error((msg || 'bytes') + ' 第 ' + i + ' 字节不同');
}
function escHtml(s) { return s.replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c])); }
async function runAllTests() {
  const el = document.getElementById('view-test');
  const lines = [];
  let pass = 0;
  for (const t of tests) {
    try { await t.fn(); pass++; lines.push('<div class="pass">✔ ' + escHtml(t.name) + '</div>'); }
    catch (e) { lines.push('<div class="fail">✘ ' + escHtml(t.name) + ' — ' + escHtml(String((e && e.message) || e)) + '</div>'); }
  }
  const summary = pass === tests.length ? 'ALL PASS (' + pass + '/' + tests.length + ')' : 'FAIL (' + pass + '/' + tests.length + ')';
  el.innerHTML = '<h2>自测</h2><div id="test-summary">TEST-SUMMARY: ' + summary + '</div>' + lines.join('');
  document.title = summary;
}
/* ===== 协议层 ===== */
// __PROTOCOL__
/* ===== 传输管线 ===== */
// __PIPELINE__
/* ===== QR 图像层 ===== */
// __QRIMAGE__
/* ===== 发送端 ===== */
// __SENDER__
/* ===== 接收端 ===== */
// __RECEIVER__
/* ===== 路由 ===== */
function route() {
  const mode = (location.hash || '#home').slice(1);
  for (const v of ['home', 'send', 'receive', 'test']) {
    document.getElementById('view-' + v).style.display = v === mode ? '' : 'none';
  }
  if (mode === 'test') runAllTests();
}
window.addEventListener('hashchange', route);
route();
/* ===== 测试用例 ===== */
// __TESTS__
test('库已加载', () => {
  assert(typeof qrcode === 'function', 'qrcode-generator 未加载');
  assert(typeof jsQR === 'function', 'jsQR 未加载');
});
</script>
</body>
</html>
```

- [ ] **步骤 3：把库代码内联进占位行**

```bash
awk '
/^__LIB_QRCODE__$/ { while ((getline line < "vendor/qrcode.js") > 0) print line; next }
/^__LIB_JSQR__$/    { while ((getline line < "vendor/jsQR.js") > 0) print line; next }
{ print }
' qr-transfer.html > qr-transfer.html.tmp && mv qr-transfer.html.tmp qr-transfer.html
grep -c "__LIB_" qr-transfer.html   # 预期 0
```

- [ ] **步骤 4：创建测试运行器**

创建 `test/run-tests.sh`：

```bash
#!/usr/bin/env bash
# 无头浏览器运行 qr-transfer.html 的 #test 自测
set -u
CHROME="${CHROME:-}"
if [ -z "$CHROME" ]; then
  for p in \
    "/c/Program Files/Google/Chrome/Application/chrome.exe" \
    "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" \
    "/c/Program Files/Microsoft/Edge/Application/msedge.exe" \
    "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"; do
    [ -f "$p" ] && CHROME="$p" && break
  done
fi
if [ -z "$CHROME" ]; then
  echo "未找到 Chrome/Edge，请设置 CHROME 环境变量，或手动打开 qr-transfer.html#test"
  exit 2
fi
DIR="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
OUT="$("$CHROME" --headless=new --disable-gpu --virtual-time-budget=20000 --dump-dom "file:///${DIR}/qr-transfer.html#test" 2>/dev/null)"
echo "$OUT" | grep -oE 'TEST-SUMMARY: [^<]*' || echo "未找到 TEST-SUMMARY（页面可能未运行）"
echo "$OUT" | grep -oE '<div class="fail">[^<]*' || true
if echo "$OUT" | grep -q 'ALL PASS'; then echo "PASS"; exit 0; else echo "FAIL"; exit 1; fi
```

- [ ] **步骤 5：运行测试确认冒烟通过**

运行：`bash test/run-tests.sh`
预期：输出 `TEST-SUMMARY: ALL PASS (1/1)` 与 `PASS`
（若无头模式异常，手动双击打开 `qr-transfer.html#test` 核对，再排查 run-tests.sh 的 CHROME 路径。）

- [ ] **步骤 6：Commit**

```bash
git add -A
git commit -m "feat: 脚手架——内联 QR 库、页面骨架、自测运行器"
```

---

### 任务 2：协议层——帧编解码纯函数

**文件：**
- 修改：`qr-transfer.html`（`// __PROTOCOL__` 与 `// __TESTS__` 锚点处）

- [ ] **步骤 1：编写失败的测试**

把 `// __TESTS__` 这一行替换为以下内容（注意末尾保留锚点）：

```js
// __TESTS__
test('头帧编解码回环（UTF-8 文件名）', () => {
  const meta = { name: '报告 2026.txt', size: 123, csize: 100, comp: 'gzip', chunks: 3, sha256: 'ab'.repeat(32) };
  const f = decodeFrame(encodeHeaderFrame(meta, 7));
  assertEq(f.type, 0x48); assertEq(f.tid, 7);
  assertEq(f.meta.name, '报告 2026.txt'); assertEq(f.meta.chunks, 3); assertEq(f.meta.sha256, meta.sha256);
});
test('数据帧编解码回环（全字节值）', () => {
  const chunk = new Uint8Array(256); for (let i = 0; i < 256; i++) chunk[i] = i;
  const f = decodeFrame(encodeDataFrame(65535, chunk, 200));
  assertEq(f.type, 0x44); assertEq(f.tid, 200); assertEq(f.seq, 65535);
  assertBytesEq(f.chunk, chunk);
});
test('整包帧编解码回环', () => {
  const meta = { name: 'a.bin', size: 4, csize: 4, comp: 'none', chunks: 1, sha256: '00'.repeat(32) };
  const data = new Uint8Array([1, 2, 3, 4]);
  const f = decodeFrame(encodeAllInOneFrame(meta, data, 9));
  assertEq(f.type, 0x41); assertEq(f.meta.name, 'a.bin'); assertBytesEq(f.data, data);
});
test('坏帧返回 null', () => {
  assertEq(decodeFrame(null), null);
  assertEq(decodeFrame(new Uint8Array([])), null);
  assertEq(decodeFrame(new Uint8Array([0x99, 0, 1, 2])), null, '未知类型');
  assertEq(decodeFrame(new Uint8Array([0x44, 0, 1])), null, '数据帧过短');
  assertEq(decodeFrame(new Uint8Array([0x48, 0, 0xff, 0xfe])), null, 'JSON 损坏');
});
test('切片与拼接', () => {
  const data = new Uint8Array(7); for (let i = 0; i < 7; i++) data[i] = i;
  const chunks = sliceChunks(data, 3);
  assertEq(chunks.length, 3); assertEq(chunks[2].length, 1);
  assertBytesEq(concatBytes(chunks), data);
});
```

- [ ] **步骤 2：运行测试验证失败**

运行：`bash test/run-tests.sh`
预期：`FAIL`，失败用例含「头帧编解码回环」，报 `encodeHeaderFrame is not defined` 之类。

- [ ] **步骤 3：实现协议层**

把 `// __PROTOCOL__` 这一行替换为：

```js
const FRAME = { HEADER: 0x48, DATA: 0x44, ALL: 0x41 };
const te = new TextEncoder();
const td = new TextDecoder();

function encodeHeaderFrame(meta, tid) {
  const json = te.encode(JSON.stringify(meta));
  const out = new Uint8Array(2 + json.length);
  out[0] = FRAME.HEADER; out[1] = tid; out.set(json, 2);
  return out;
}
function encodeDataFrame(seq, chunk, tid) {
  const out = new Uint8Array(4 + chunk.length);
  out[0] = FRAME.DATA; out[1] = tid;
  out[2] = seq & 0xff; out[3] = (seq >> 8) & 0xff;
  out.set(chunk, 4);
  return out;
}
function encodeAllInOneFrame(meta, data, tid) {
  const json = te.encode(JSON.stringify(meta));
  const out = new Uint8Array(4 + json.length + data.length);
  out[0] = FRAME.ALL; out[1] = tid;
  out[2] = json.length & 0xff; out[3] = (json.length >> 8) & 0xff;
  out.set(json, 4); out.set(data, 4 + json.length);
  return out;
}
function decodeFrame(bytes) {
  if (!bytes || bytes.length < 2) return null;
  const type = bytes[0], tid = bytes[1];
  try {
    if (type === FRAME.HEADER) {
      return { type, tid, meta: JSON.parse(td.decode(bytes.subarray(2))) };
    }
    if (type === FRAME.DATA) {
      if (bytes.length < 4) return null;
      return { type, tid, seq: bytes[2] | (bytes[3] << 8), chunk: bytes.slice(4) };
    }
    if (type === FRAME.ALL) {
      if (bytes.length < 4) return null;
      const jsonLen = bytes[2] | (bytes[3] << 8);
      if (bytes.length < 4 + jsonLen) return null;
      const meta = JSON.parse(td.decode(bytes.subarray(4, 4 + jsonLen)));
      return { type, tid, meta, data: bytes.slice(4 + jsonLen) };
    }
    return null;
  } catch (e) { return null; }
}
function sliceChunks(data, size) {
  const chunks = [];
  for (let i = 0; i < data.length; i += size) chunks.push(data.subarray(i, i + size));
  return chunks;
}
function concatBytes(arrays) {
  const total = arrays.reduce((n, a) => n + a.length, 0);
  const out = new Uint8Array(total);
  let off = 0;
  for (const a of arrays) { out.set(a, off); off += a.length; }
  return out;
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`bash test/run-tests.sh`
预期：`ALL PASS (7/7)`、`PASS`

- [ ] **步骤 5：Commit**

```bash
git add qr-transfer.html
git commit -m "feat: 协议帧编解码（H/D/A 帧 + 切片拼接）"
```

---

### 任务 3：传输管线——压缩、校验、组帧、重组

**文件：**
- 修改：`qr-transfer.html`（`// __PIPELINE__` 与 `// __TESTS__` 锚点处）

- [ ] **步骤 1：编写失败的测试**

把 `// __TESTS__` 这一行替换为（末尾保留锚点）：

```js
// __TESTS__
test('小文件走 A 帧且自动解压还原', async () => {
  const text = 'hello world 你好'.repeat(10);
  const data = te.encode(text);
  const t = await prepareTransfer('小.txt', data, 600);
  assertEq(t.frames.length, 1, '应为单帧');
  const asm = new Assembler();
  const r = await asm.feed(t.frames[0]);
  assertEq(r.kind, 'complete');
  assertBytesEq(r.data, data);
  assertEq(r.meta.comp, 'gzip', '重复文本应可压缩');
});
test('多片随机数据走 H/D 帧，乱序+重复也能收齐', async () => {
  const data = crypto.getRandomValues(new Uint8Array(2000));
  const t = await prepareTransfer('rand.bin', data, 600);
  assertEq(t.meta.comp, 'none', '随机数据不可压缩');
  assertEq(t.frames.length, 1 + Math.ceil(2000 / 600));
  const asm = new Assembler();
  // 乱序投喂：先数据帧（应 ignored），再头帧，再倒序数据帧（含重复）
  let r = await asm.feed(t.frames[1]);
  assertEq(r.kind, 'ignored');
  r = await asm.feed(t.frames[0]);
  assertEq(r.kind, 'header');
  let completed = null;
  for (let i = t.frames.length - 1; i >= 1; i--) {
    const r1 = await asm.feed(t.frames[i]);   // 倒序
    const r2 = await asm.feed(t.frames[i]);   // 重复投喂
    if (r1.kind === 'complete') completed = r1;
    if (r2.kind === 'complete') completed = r2;
  }
  assert(completed, '应收齐完成');
  assertBytesEq(completed.data, data);
  // 完成后再收到同 tid 帧应忽略
  const after = await asm.feed(t.frames[1]);
  assertEq(after.kind, 'ignored');
});
test('tid 不匹配的数据帧被忽略', async () => {
  const data = crypto.getRandomValues(new Uint8Array(800));
  const t = await prepareTransfer('a.bin', data, 600);
  const asm = new Assembler();
  await asm.feed(t.frames[0]);
  const foreign = encodeDataFrame(0, new Uint8Array(100), (t.tid + 1) % 256);
  const r = await asm.feed(foreign);
  assertEq(r.kind, 'ignored');
  assertEq(asm.received, 0);
});
test('数据损坏导致哈希不符', async () => {
  const data = crypto.getRandomValues(new Uint8Array(800));
  const t = await prepareTransfer('a.bin', data, 600);
  const asm = new Assembler();
  await asm.feed(t.frames[0]);
  // 篡改最后一片
  const last = decodeFrame(t.frames[t.frames.length - 1]);
  last.chunk[0] ^= 0xff;
  let r;
  for (let i = 1; i < t.frames.length - 1; i++) r = await asm.feed(t.frames[i]);
  r = await asm.feed(encodeDataFrame(last.seq, last.chunk, t.tid));
  assertEq(r.kind, 'hash-error');
});
test('分片数超 65535 拒绝', async () => {
  let threw = false;
  try { await prepareTransfer('big.bin', new Uint8Array(70000), 1); }
  catch (e) { threw = true; }
  assert(threw, '应抛异常');
});
```

- [ ] **步骤 2：运行测试验证失败**

运行：`bash test/run-tests.sh`
预期：`FAIL`，报 `prepareTransfer is not defined` 之类。

- [ ] **步骤 3：实现传输管线**

把 `// __PIPELINE__` 这一行替换为：

```js
const ALL_IN_ONE_MAX = 500;   // 整帧 ≤ 500B 时走 A 帧
const MAX_CHUNKS = 65535;

async function compressGzip(data) {
  const s = new Blob([data]).stream().pipeThrough(new CompressionStream('gzip'));
  return new Uint8Array(await new Response(s).arrayBuffer());
}
async function decompressGzip(data) {
  const s = new Blob([data]).stream().pipeThrough(new DecompressionStream('gzip'));
  return new Uint8Array(await new Response(s).arrayBuffer());
}
async function sha256Hex(data) {
  const d = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, '0')).join('');
}

// 返回 { meta, tid, frames: Uint8Array[] }；frames[0] 为 H 帧（或唯一 A 帧）
async function prepareTransfer(name, fileData, chunkSize) {
  const sha256 = await sha256Hex(fileData);
  const gz = await compressGzip(fileData);
  const comp = gz.length < fileData.length ? 'gzip' : 'none';
  const data = comp === 'gzip' ? gz : fileData;
  const tid = Math.floor(Math.random() * 256);
  const base = { name, size: fileData.length, csize: data.length, comp, sha256 };
  const aFrame = encodeAllInOneFrame({ ...base, chunks: 1 }, data, tid);
  if (aFrame.length <= ALL_IN_ONE_MAX) {
    return { meta: { ...base, chunks: 1 }, tid, frames: [aFrame] };
  }
  const chunks = sliceChunks(data, chunkSize);
  if (chunks.length > MAX_CHUNKS) throw new Error('文件过大：分片数超过 ' + MAX_CHUNKS);
  const meta = { ...base, chunks: chunks.length };
  const frames = [encodeHeaderFrame(meta, tid)];
  for (let i = 0; i < chunks.length; i++) frames.push(encodeDataFrame(i, chunks[i], tid));
  return { meta, tid, frames };
}

class Assembler {
  constructor() { this.reset(); }
  reset() {
    this.meta = null; this.tid = null; this.chunks = null;
    this.received = 0; this.badFrames = 0; this.doneFlag = false;
  }
  // 返回 { kind: 'header'|'header-repeat'|'progress'|'complete'|'hash-error'|'ignored'|'bad', ... }
  async feed(bytes) {
    const f = decodeFrame(bytes);
    if (!f) { this.badFrames++; return { kind: 'bad' }; }
    if (this.doneFlag) {
      // 传输已完成：仅新 tid 的头帧/整包帧可开启新传输，其余忽略
      if (f.type === FRAME.DATA || f.tid === this.tid) return { kind: 'ignored' };
    }
    if (f.type === FRAME.ALL) {
      if (this.meta && f.tid !== this.tid) this.reset();
      return this.finish(f.meta, f.data);
    }
    if (f.type === FRAME.HEADER) {
      if (!this.meta || f.tid !== this.tid) {
        this.reset();
        this.meta = f.meta; this.tid = f.tid;
        this.chunks = new Array(f.meta.chunks).fill(null);
        return { kind: 'header', meta: f.meta };
      }
      return { kind: 'header-repeat' };
    }
    // FRAME.DATA
    if (!this.meta || f.tid !== this.tid) return { kind: 'ignored' };
    if (f.seq >= this.meta.chunks || f.chunk.length === 0) { this.badFrames++; return { kind: 'bad' }; }
    if (this.chunks[f.seq] === null) { this.chunks[f.seq] = f.chunk; this.received++; }
    if (this.received === this.meta.chunks) {
      return this.finish(this.meta, concatBytes(this.chunks));
    }
    return { kind: 'progress', received: this.received, total: this.meta.chunks };
  }
  async finish(meta, packed) {
    let data = packed;
    if (meta.comp === 'gzip') data = await decompressGzip(packed);
    const hash = await sha256Hex(data);
    if (hash !== meta.sha256) return { kind: 'hash-error', meta };
    this.doneFlag = true;
    return { kind: 'complete', meta, data };
  }
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`bash test/run-tests.sh`
预期：`ALL PASS (12/12)`、`PASS`

- [ ] **步骤 5：Commit**

```bash
git add qr-transfer.html
git commit -m "feat: 传输管线（gzip/SHA-256/组帧/Assembler 重组）"
```

---

### 任务 4：QR 图像层——渲染与 jsQR 解码回环

**文件：**
- 修改：`qr-transfer.html`（`// __QRIMAGE__` 与 `// __TESTS__` 锚点处）

- [ ] **步骤 1：编写失败的测试**

把 `// __TESTS__` 这一行替换为（末尾保留锚点）：

```js
// __TESTS__
test('QR 渲染→jsQR 解码回环（三种帧）', async () => {
  const data = crypto.getRandomValues(new Uint8Array(400));
  const t = await prepareTransfer('img.bin', data, 600);
  for (const frame of t.frames) {
    const canvas = document.createElement('canvas');
    renderFrameToCanvas(frame, canvas, 600);
    const decoded = decodeQRFromCanvas(canvas);
    assert(decoded, 'jsQR 未识别');
    assertBytesEq(decoded, frame);
  }
});
test('最大分片（1000B）可渲染可解码', () => {
  const chunk = crypto.getRandomValues(new Uint8Array(1000));
  const frame = encodeDataFrame(3, chunk, 1);
  const canvas = document.createElement('canvas');
  renderFrameToCanvas(frame, canvas, 700);
  assertBytesEq(decodeQRFromCanvas(canvas), frame);
});
```

- [ ] **步骤 2：运行测试验证失败**

运行：`bash test/run-tests.sh`
预期：`FAIL`，报 `renderFrameToCanvas is not defined`。

- [ ] **步骤 3：实现图像层**

把 `// __QRIMAGE__` 这一行替换为：

```js
// 二进制 → latin1 字符串（qrcode-generator 的 Byte 模式按 charCodeAt & 0xff 处理）
function bytesToLatin1(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) {
    s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  }
  return s;
}
function buildQrModel(frame) {
  const qr = qrcode(0, 'M');        // 0 = 版本号自动，M = 纠错 15%
  qr.addData(bytesToLatin1(frame), 'Byte');
  qr.make();
  return qr;
}
function drawQrModel(qr, canvas, maxPx) {
  const count = qr.getModuleCount();
  const quiet = 4;
  const total = count + quiet * 2;
  const px = Math.max(2, Math.floor(maxPx / total));
  const size = total * px;
  canvas.width = canvas.height = size;
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, size, size);
  ctx.fillStyle = '#000';
  for (let r = 0; r < count; r++) {
    for (let c = 0; c < count; c++) {
      if (qr.isDark(r, c)) ctx.fillRect((c + quiet) * px, (r + quiet) * px, px, px);
    }
  }
}
function renderFrameToCanvas(frame, canvas, maxPx) {
  drawQrModel(buildQrModel(frame), canvas, maxPx);
}
// 从 canvas 解码；返回 Uint8Array 或 null
function decodeQRFromCanvas(canvas) {
  const ctx = canvas.getContext('2d');
  const img = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const res = jsQR(img.data, img.width, img.height);
  return res ? new Uint8Array(res.binaryData) : null;
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`bash test/run-tests.sh`
预期：`ALL PASS (14/14)`、`PASS`

- [ ] **步骤 5：Commit**

```bash
git add qr-transfer.html
git commit -m "feat: QR 渲染与 jsQR 解码（图像层回环验证）"
```

---

### 任务 5：发送端 UI

**文件：**
- 修改：`qr-transfer.html`（`// __SENDER__` 锚点处）

- [ ] **步骤 1：实现发送端**

把 `// __SENDER__` 这一行替换为：

```js
const sender = {
  transfer: null,      // { meta, tid, frames }
  qrModels: null,
  timer: null,
  idx: 0,
  loops: 0,
  async setFile(file) {
    this.pause();
    const chunkSize = +document.getElementById('opt-chunk').value;
    const data = new Uint8Array(await file.arrayBuffer());
    try {
      this.transfer = await prepareTransfer(file.name, data, chunkSize);
    } catch (e) {
      setSendStatus('错误：' + e.message);
      return;
    }
    this.qrModels = null; this.idx = 0; this.loops = 0;
    const m = this.transfer.meta;
    setSendStatus(
      '文件：' + m.name + '（' + m.size + ' B' +
      (m.comp === 'gzip' ? '，gzip 后 ' + m.csize + ' B' : '，不可压缩') + '）\n' +
      (this.transfer.frames.length === 1
        ? '整包帧：单张静态二维码'
        : '共 ' + m.chunks + ' 片（' + (this.transfer.frames.length) + ' 帧/圈）')
    );
    document.getElementById('btn-send-start').disabled = false;
    // 未开始播放时先静态显示首帧，便于确认窗口
    renderFrameToCanvas(this.transfer.frames[0], document.getElementById('qr-canvas'), qrMaxPx());
  },
  start() {
    if (!this.transfer || this.timer) return;
    if (!this.qrModels) this.qrModels = this.transfer.frames.map(buildQrModel);
    const fps = +document.getElementById('opt-fps').value;
    const n = this.transfer.frames.length;
    const canvas = document.getElementById('qr-canvas');
    this.timer = setInterval(() => {
      drawQrModel(this.qrModels[this.idx], canvas, qrMaxPx());
      this.idx++;
      if (this.idx >= n) { this.idx = 0; this.loops++; }
      updateSendProgress();
    }, Math.round(1000 / fps));
    document.getElementById('btn-send-start').disabled = true;
    document.getElementById('btn-send-pause').disabled = false;
  },
  pause() {
    if (this.timer) { clearInterval(this.timer); this.timer = null; }
    document.getElementById('btn-send-pause').disabled = true;
    if (this.transfer) document.getElementById('btn-send-start').disabled = false;
  },
};
function qrMaxPx() {
  return Math.max(200, Math.min(window.innerWidth, window.innerHeight) - 80);
}
function setSendStatus(s) { document.getElementById('send-status').textContent = s; }
function updateSendProgress() {
  const n = sender.transfer.frames.length;
  const fps = +document.getElementById('opt-fps').value;
  const label = n === 1 ? '静态帧' : (sender.idx === 0 ? '头帧' : '数据帧 ' + sender.idx + '/' + (n - 1));
  setSendStatus(
    '播放中：' + label + '｜' + fps + ' fps｜已循环 ' + sender.loops + ' 圈｜每圈约 ' + (n / fps).toFixed(1) + ' s'
  );
}
function initSender() {
  const dz = document.getElementById('drop-zone');
  const fi = document.getElementById('file-input');
  fi.addEventListener('change', () => fi.files[0] && sender.setFile(fi.files[0]));
  dz.addEventListener('dragover', e => { e.preventDefault(); dz.classList.add('drag'); });
  dz.addEventListener('dragleave', () => dz.classList.remove('drag'));
  dz.addEventListener('drop', e => {
    e.preventDefault(); dz.classList.remove('drag');
    if (e.dataTransfer.files[0]) sender.setFile(e.dataTransfer.files[0]);
  });
  document.getElementById('btn-send-start').addEventListener('click', () => sender.start());
  document.getElementById('btn-send-pause').addEventListener('click', () => sender.pause());
  document.getElementById('opt-fps').addEventListener('input', e => {
    document.getElementById('opt-fps-val').textContent = e.target.value;
    if (sender.timer) { sender.pause(); sender.start(); }   // 播放中调速即时生效
  });
}
initSender();
```

- [ ] **步骤 2：回归测试 + 人工验证**

运行：`bash test/run-tests.sh` → 预期 `ALL PASS (14/14)`（UI 未改协议，测试不应回归）。

人工验证（记录结果即可）：
1. 浏览器打开 `qr-transfer.html#send`，拖入一个文本文件 → 状态区显示文件信息与帧数，canvas 显示首帧。
2. 点「开始」→ QR 开始闪烁切换；点「暂停」→ 停止。
3. 拖动帧率滑块 → 播放速度变化。
4. 换 300/1000 分片重新选文件 → 帧数变化。

- [ ] **步骤 3：Commit**

```bash
git add qr-transfer.html
git commit -m "feat: 发送端 UI（拖放/播放控制/状态显示）"
```

---

### 任务 6：接收端 UI

**文件：**
- 修改：`qr-transfer.html`（`// __RECEIVER__` 锚点处）

- [ ] **步骤 1：实现接收端**

把 `// __RECEIVER__` 这一行替换为：

```js
const receiver = {
  stream: null,
  timer: null,
  asm: new Assembler(),
  done: false,
  async startCapture() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getDisplayMedia) {
      setRecvStatus('当前环境不支持抓屏：请以 file://、localhost 或 https 打开本页（内网 http://裸IP 不可用）。');
      return;
    }
    try {
      this.stream = await navigator.mediaDevices.getDisplayMedia({ video: true });
    } catch (e) {
      setRecvStatus('抓屏被拒绝：' + e.message + '\n提示：需 file://、localhost 或 https 环境。');
      return;
    }
    const video = document.getElementById('capture-video');
    video.srcObject = this.stream;
    this.stream.getVideoTracks()[0].addEventListener('ended', () => this.stopCapture('抓屏已结束'));
    this.timer = setInterval(() => this.tick(), 150);
    document.getElementById('btn-capture').disabled = true;
    document.getElementById('btn-recv-reset').disabled = false;
    setRecvStatus('解码中：等待头帧…（请确认发送端在播放且窗口未被遮挡）');
  },
  stopCapture(msg) {
    if (this.timer) { clearInterval(this.timer); this.timer = null; }
    if (this.stream) { this.stream.getTracks().forEach(t => t.stop()); this.stream = null; }
    document.getElementById('btn-capture').disabled = false;
    if (msg) setRecvStatus(msg);
  },
  reset() {
    this.asm.reset(); this.done = false;
    document.getElementById('chunk-grid').innerHTML = '';
    document.getElementById('recv-result').innerHTML = '';
    document.getElementById('recv-progress').value = 0;
    setRecvStatus(this.timer ? '解码中：等待头帧…' : '等待抓屏');
  },
  scratch: null,
  tick() {
    const video = document.getElementById('capture-video');
    if (video.readyState < 2 || !video.videoWidth) return;
    if (!this.scratch) this.scratch = document.createElement('canvas');
    const c = this.scratch;
    c.width = video.videoWidth; c.height = video.videoHeight;
    c.getContext('2d').drawImage(video, 0, 0);
    const bytes = decodeQRFromCanvas(c);
    if (!bytes) {
      if (!this.asm.meta && !this.done) setRecvStatus('未检测到二维码：请确认发送端在播放且窗口未被遮挡');
      return;
    }
    this.asm.feed(bytes).then(r => this.onFrame(r));
  },
  onFrame(r) {
    const asm = this.asm;
    switch (r.kind) {
      case 'bad':
        setRecvStatus(asm.meta
          ? '接收中：' + asm.received + '/' + asm.meta.chunks + ' 片｜坏帧 ' + asm.badFrames
          : '等待头帧…（坏帧 ' + asm.badFrames + '）');
        break;
      case 'header-repeat':   // 循环播放时每圈重复出现的同 tid 头帧
      case 'ignored':
        break;
      case 'header': {
        this.done = false;
        const m = r.meta;
        document.getElementById('recv-progress').value = 0;
        const grid = document.getElementById('chunk-grid');
        grid.innerHTML = '';
        for (let i = 0; i < m.chunks; i++) grid.appendChild(document.createElement('i'));
        setRecvStatus('接收中：' + m.name + '（' + m.size + ' B，' + m.chunks + ' 片）');
        break;
      }
      case 'progress': {
        document.getElementById('recv-progress').value = r.received / r.total;
        const cells = document.getElementById('chunk-grid').children;
        for (let i = 0; i < asm.chunks.length; i++) {
          if (asm.chunks[i] !== null) cells[i].classList.add('got');
        }
        setRecvStatus('接收中：' + r.received + '/' + r.total + ' 片｜坏帧 ' + asm.badFrames);
        break;
      }
      case 'complete': {
        if (this.done) break;         // 循环播放会反复 complete，只处理一次
        this.done = true;
        document.getElementById('recv-progress').value = 1;
        const m = r.meta;
        setRecvStatus('完成：' + m.name + '（' + m.size + ' B）✔ SHA-256 校验通过');
        const btn = document.createElement('button');
        btn.textContent = '重新下载 ' + m.name;
        btn.addEventListener('click', () => downloadBlob(m.name, r.data));
        const res = document.getElementById('recv-result');
        res.innerHTML = ''; res.appendChild(btn);
        downloadBlob(m.name, r.data);
        break;
      }
      case 'hash-error':
        setRecvStatus('错误：SHA-256 校验不符。请让发送端重新发送，或降低帧率/分片后重试（本端继续接收中）。');
        break;
    }
  },
};
function setRecvStatus(s) { document.getElementById('recv-status').textContent = s; }
function downloadBlob(name, data) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([data]));
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 10000);
}
function initReceiver() {
  document.getElementById('btn-capture').addEventListener('click', () => receiver.startCapture());
  document.getElementById('btn-recv-reset').addEventListener('click', () => receiver.reset());
}
initReceiver();
```

- [ ] **步骤 2：回归测试**

运行：`bash test/run-tests.sh` → 预期 `ALL PASS (14/14)`。

- [ ] **步骤 3：人工 E2E 验证（本机两窗口互抓）**

1. 窗口 A：`qr-transfer.html#send`，选一个 ~2KB 文本文件，开始播放。
2. 窗口 B：`qr-transfer.html#receive`，开始抓屏，选择窗口 A。
3. 预期：B 显示头帧信息、进度条前进、数秒后自动下载文件；比对下载文件内容一致。
4. 再测一个 ~100B 小文件：A 显示静态单帧，B 收 1 片即完成。
5. 把帧率调到 10fps、分片 1000 重测，观察坏帧计数是否上升。

- [ ] **步骤 4：Commit**

```bash
git add qr-transfer.html
git commit -m "feat: 接收端 UI（抓屏/进度位图/自动下载）"
```

---

### 任务 7：README 与收尾

**文件：**
- 创建：`README.md`

- [ ] **步骤 1：创建 README.md**

```markdown
# QR 文件传输

单文件工具：通过二维码动画在隔离虚拟机与宿主机之间传输小文件。零依赖、完全离线。

## 使用

交付物只有一个文件：`qr-transfer.html`，拷到两边机器上双击打开即可。

- **发送端（虚拟机内）**：打开 `qr-transfer.html#send` → 拖入文件 → 开始。
- **接收端（宿主机）**：打开 `qr-transfer.html#receive` → 开始抓屏 → 选中虚拟机窗口 → 收齐自动下载。

## 限制

- 单向传输，明文（任何能看到屏幕者均可截获）。
- 接收端必须以 file:// / localhost / https 打开；内网 http://裸IP 会被浏览器禁止抓屏。
- 吞吐约 3KB/s（默认 600B/片、5fps），适合 KB 级小文件。

## 开发

- 页面内自测：打开 `qr-transfer.html#test`。
- 命令行跑自测：`bash test/run-tests.sh`（需本机 Chrome/Edge）。
- 应用代码在 `qr-transfer.html` 尾部 `<script>` 内，按锚点分区：`__PROTOCOL__`（帧编解码）、`__PIPELINE__`（压缩/校验/重组）、`__QRIMAGE__`（QR 渲染/解码）、`__SENDER__`、`__RECEIVER__`、`__TESTS__`（自测用例）。
- `vendor/` 是两个内联库的原始存档，仅作来源留存，不被页面引用。

设计规格：`docs/superpowers/specs/2026-10-17-qr-file-transfer-design.md`
```

- [ ] **步骤 2：最终全量验证**

运行：`bash test/run-tests.sh` → 预期 `ALL PASS (14/14)`、`PASS`。

- [ ] **步骤 3：Commit**

```bash
git add -A
git commit -m "docs: README 用法说明"
```
