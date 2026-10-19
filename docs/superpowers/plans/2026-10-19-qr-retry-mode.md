# QR 文件传输「补充模式」实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 接收端导出缺失分片序号（紧凑文本 + 校验码），用户带回发送端粘贴/手打，发送端仅循环重发 `[头帧, …缺失帧…]`，免去等待完整循环。

**架构：** 协议层零改动——补发即重播原始帧字节（tid/seq 不变），接收端 `Assembler` 自动兼容。新增 6 个纯函数（文本格式化/解析、补发序列构造、可用性判断、缺失提取）+ 两端各一小块 UI；`sender` 播放循环由「帧下标」泛化为「播放序列」。

**技术栈：** 单文件 `qr-transfer.html`（原生 JS，无构建）；页面内自测 `#test`（`test()/assert/assertEq/assertBytesEq`，结果含 `TEST-SUMMARY:` 标记）；命令行 `bash test/run-tests.sh`（无头 Chrome/Edge 抓 DOM 判定）。

**规格：** `docs/superpowers/specs/2026-10-19-qr-retry-mode-design.md`

**执行前：** 按 superpowers:using-git-worktrees 建立隔离工作区再执行本计划。

---

## 文件结构

| 文件 | 改动 | 职责 |
|---|---|---|
| `qr-transfer.html` | 修改 | 唯一交付物。纯函数加入 `__PIPELINE__` 区末尾（约 12709 行 `Assembler` 类之后）；发送端状态机与 UI 在 `__SENDER__` 区；接收端导出在 `__RECEIVER__` 区；DOM 加在 `#view-send`/`#view-receive`；测试加在 `__TESTS__` 区 |
| `README.md` | 修改 | 新增「补充模式」使用说明 |
| `docs/superpowers/plans/2026-10-19-qr-retry-mode.md` | 本计划 | — |

现有用例 29 个，全部保持通过；本计划新增 9 个（任务 1 ×4、任务 2 ×2、任务 4 ×2、任务 5 ×1），完成后共 38 个。

---

### 任务 1：缺失序号文本格式化与解析（纯函数）

**文件：**
- 修改：`qr-transfer.html` `__PIPELINE__` 区末尾（`Assembler` 类结束、`/* ===== QR 图像层 ===== */` 注释之前）追加 3 个函数
- 测试：`qr-transfer.html` `__TESTS__` 区（现有用例之后、`runAllTests` 之前的位置追加用例，下同）

- [ ] **步骤 1：编写失败的测试**

在 `__TESTS__` 区末尾（最后一个 `test(...)` 调用之后）追加：

```js
test('formatMissingSeqs：连续合并区间、单片直书、空集返回空串', () => {
  assertEq(formatMissingSeqs([3, 4, 5, 7]), '#3-5,7;C' + retryChecksum([3, 4, 5, 7]));
  assertEq(formatMissingSeqs([9]), '#9;C' + retryChecksum([9]));
  assertEq(formatMissingSeqs([]), '');
});
test('parseRetryList：分隔符/区间符号/#前缀宽容，格式化-解析往返一致', () => {
  const seqs = [3, 4, 5, 7, 15, 16];
  const r = parseRetryList(formatMissingSeqs(seqs), 100);
  assertEq(r.seqs.join(','), seqs.join(','));
  assertEq(r.checksumOk, true);
  assertEq(r.ignored, 0);
  const r2 = parseRetryList('#3~5，7 15-16；c' + retryChecksum(seqs), 100);
  assertEq(r2.seqs.join(','), seqs.join(','));
  assertEq(r2.checksumOk, true);
});
test('parseRetryList：篡改序号被校验拦截；无校验段放行且标记 absent', () => {
  const cs = retryChecksum([3, 7]);
  assertEq(parseRetryList('#4,7;C' + cs, 100).checksumOk, false);
  const noCs = parseRetryList('3,7', 100);
  assertEq(noCs.checksumOk, 'absent');
  assertEq(noCs.seqs.join(','), '3,7');
});
test('parseRetryList：区间写反交换、坏段忽略计数、越界计数、空输入空集', () => {
  let r = parseRetryList('#7-3,x,99', 10);
  assertEq(r.seqs.join(','), '3,4,5,6,7,99');
  assertEq(r.ignored, 1);
  assertEq(r.outOfRange, 1);
  r = parseRetryList('', 10);
  assertEq(r.seqs.length, 0);
  assertEq(r.ignored, 0);
});
```

- [ ] **步骤 2：运行测试验证失败**

运行：`bash test/run-tests.sh`
预期：`FAIL (29/33)`，失败行含 `formatMissingSeqs is not defined`（或 `retryChecksum is not defined`）。

- [ ] **步骤 3：编写实现**

在 `__PIPELINE__` 区末尾（`Assembler` 类的 `}` 之后）追加。注意实现放在源码中 `__TESTS__` 之前，且 `runAllTests` 执行时函数已定义（同层 `<script>`，顶层声明全局可见）：

```js
/* ===== 补充模式：缺失序号文本 ===== */
// 位置加权校验：h = (h*31 + seq) & 0xFFFF，能拦截等和替换（3,7 → 4,6）与漏打/多打
function retryChecksum(seqs) {
  let h = 0;
  for (const s of seqs) h = (h * 31 + s) & 0xffff;
  return h.toString(16).toUpperCase().padStart(4, '0');
}
// 升序序号 → '#3-5,7;C9F27'；输入自行排序去重，空集返回 ''
function formatMissingSeqs(seqs) {
  const sorted = [...new Set(seqs)].sort((a, b) => a - b);
  if (!sorted.length) return '';
  const parts = [];
  let start = sorted[0], prev = sorted[0];
  for (let i = 1; i <= sorted.length; i++) {
    const s = sorted[i];
    if (s !== prev + 1) {                       // 区间断开（含末尾 s === undefined）
      parts.push(start === prev ? String(start) : start + '-' + prev);
      start = s;
    }
    prev = s;
  }
  return '#' + parts.join(',') + ';C' + retryChecksum(sorted);
}
// 文本 → { seqs(去重升序，含越界), ignored, checksumOk: true|false|'absent', outOfRange }
// 校验对象 = 全部解析出的序号（含越界）：生成端不产越界，故「相符」基本排除错打
function parseRetryList(text, chunks) {
  const out = { seqs: [], ignored: 0, checksumOk: 'absent', outOfRange: 0 };
  let s = String(text == null ? '' : text).trim();
  if (s.startsWith('#')) s = s.slice(1).trim();
  const m = s.match(/[;；][Cc]([0-9a-fA-F]{4})$/);   // 仅文本末尾识别校验段
  if (m) { s = s.slice(0, m.index).trim(); }
  for (const seg of s.split(/[,，;；\s]+/)) {
    if (!seg) continue;
    const r = seg.match(/^(\d+)\s*(?:[-~]\s*(\d+))?$/);
    if (!r) { out.ignored++; continue; }
    let a = +r[1], b = r[2] === undefined ? a : +r[2];
    if (a > b) { const t2 = a; a = b; b = t2; }       // 区间写反自动交换
    for (let i = a; i <= b; i++) out.seqs.push(i);
  }
  out.seqs = [...new Set(out.seqs)].sort((a, b) => a - b);
  for (const q of out.seqs) if (q >= chunks) out.outOfRange++;
  if (m) out.checksumOk = retryChecksum(out.seqs) === m[1].toUpperCase();
  return out;
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`bash test/run-tests.sh`
预期：`TEST-SUMMARY: ALL PASS (33/33)` 与 `PASS`。

- [ ] **步骤 5：Commit**

```bash
git add qr-transfer.html
git commit -m "feat: 补充模式文本格式——缺失序号区间压缩与位置加权校验的生成/解析"
```

---

### 任务 2：发送端播放序列状态机

**文件：**
- 修改：`qr-transfer.html` `__SENDER__` 区——`sender` 对象（`start()`、`setFile()` 成功路径）、`updateSendProgress()`；`__PIPELINE__` 区末尾追加 `buildRetryPlaySeq`/`canRetry`
- 测试：`qr-transfer.html` `__TESTS__` 区

- [ ] **步骤 1：编写失败的测试**

```js
test('canRetry：多帧可补发，单帧整包与空 transfer 不可', async () => {
  const big = await prepareTransfer('big.bin', crypto.getRandomValues(new Uint8Array(1200)), 600);
  assertEq(canRetry(big), true);
  const small = await prepareTransfer('small.bin', new Uint8Array(10), 600);
  assertEq(canRetry(small), false);
  assertEq(canRetry(null), false);
});
test('buildRetryPlaySeq：头帧领衔、seq 映射帧下标 +1、越界过滤', () => {
  assertEq(buildRetryPlaySeq([3, 7], 10).join(','), '0,4,8');
  assertEq(buildRetryPlaySeq([0, 10], 10).join(','), '0,1');   // 10 越界被过滤
});
```

- [ ] **步骤 2：运行测试验证失败**

运行：`bash test/run-tests.sh`
预期：`FAIL (33/35)`，失败行含 `canRetry is not defined`。

- [ ] **步骤 3：编写实现**

3a. `__PIPELINE__` 区末尾（任务 1 的 `parseRetryList` 之后）追加：

```js
// 补发播放序列：[头帧, …seq+1…]；输入约定为 parseRetryList 输出的去重升序 seqs
function buildRetryPlaySeq(seqs, chunks) {
  const play = [0];
  for (const s of seqs) if (s < chunks) play.push(s + 1);
  return play;
}
// 仅多帧传输（H + 数据帧）可补发；A 帧单帧无补发意义
function canRetry(transfer) {
  return !!(transfer && transfer.frames && transfer.frames.length > 1);
}
```

3b. `sender` 对象字面量开头（`transfer: null,` 一行附近）增加两个字段：

```js
  mode: 'full',        // 'full' | 'retry'
  playSeq: null,       // 播放帧下标序列；null = 全量 [0..n)
```

3c. 改写 `start()`：帧数与取帧按 `playSeq` 泛化（`playSeq === null` 时行为与现状完全一致）：

```js
  start() {
    if (!this.transfer || this.timer) return;
    const fps = +document.getElementById('opt-fps').value;
    const seq = this.playSeq;                              // null = 全量
    const n = seq ? seq.length : this.transfer.frames.length;
    const canvas = document.getElementById('qr-canvas');
    this.loopStart = performance.now(); this.renderMs = 0; this.rendered = 0;
    slog('开始', {
      模式: this.mode, fps, 帧间隔ms: Math.round(1000 / fps), 帧数: n, 分片: this.transfer.meta.chunks,
      QR版本: this.qrVersion, 画布: canvas.width + '×' + canvas.height,
      屏幕: window.screen.width + '×' + window.screen.height,
      窗口: window.innerWidth + '×' + window.innerHeight,
      DPR: window.devicePixelRatio
    });
    this.timer = setInterval(() => {
      const t0 = performance.now();
      // 按需构建当前帧：不预建全量模型（大文件几千帧会冻结 UI 并耗费数 GB 内存）
      const fi = seq ? seq[this.idx] : this.idx;
      drawQrModel(buildQrModel(this.transfer.frames[fi], this.qrVersion), canvas, qrMaxPx());
      this.renderMs += performance.now() - t0;
      this.rendered++;
      this.idx++;
      if (this.idx >= n) {
        this.idx = 0; this.loops++;
        const now = performance.now();
        slog('循环', {
          圈: this.loops,
          平均渲染ms: +(this.renderMs / this.rendered).toFixed(1),
          实际圈耗时s: +((now - this.loopStart) / 1000).toFixed(2),
          目标圈耗时s: +(n / fps).toFixed(2)
        });
        this.loopStart = now; this.renderMs = 0; this.rendered = 0;
      }
      updateSendProgress();
    }, Math.round(1000 / fps));
    document.getElementById('btn-send-start').disabled = true;
    document.getElementById('btn-send-pause').disabled = false;
  },
```

3d. `sender` 对象内 `pause()` 之后追加两个方法：

```js
  // 补发入口：解析文本 → 校验 → 仅循环 [头帧, …缺失帧]；返回 { ok, msg } 供 UI 显示
  startRetry(text) {
    if (!canRetry(this.transfer)) return { ok: false, msg: '当前无多帧传输（整包单帧无需补发）' };
    const r = parseRetryList(text, this.transfer.meta.chunks);
    if (!r.seqs.length) return { ok: false, msg: '未解析到任何有效序号' + (r.ignored ? '（忽略 ' + r.ignored + ' 个无效段）' : '') };
    if (r.checksumOk === false) return { ok: false, msg: '校验不符，请核对文本（尤其手打场景）' };
    this.pause();
    this.mode = 'retry';
    this.playSeq = buildRetryPlaySeq(r.seqs, this.transfer.meta.chunks);
    this.idx = 0; this.loops = 0;
    this.start();
    const extra = (r.outOfRange ? '，忽略越界 ' + r.outOfRange + ' 个' : '') + (r.checksumOk === 'absent' ? '，无校验码' : '');
    return { ok: true, msg: this.playSeq.length - 1 + ' 片' + extra };
  },
  // 任意状态回到全量播放
  startFull() {
    if (!this.transfer) return;
    this.pause();
    this.mode = 'full'; this.playSeq = null;
    this.idx = 0; this.loops = 0;
    this.start();
  },
```

3e. `setFile()` 成功路径（`this.qrVersion = pickQrVersion(...)` 一行附近）追加模式重置：

```js
    this.mode = 'full'; this.playSeq = null;
```

3f. 改写 `updateSendProgress()`（补发模式下帧下标无意义，只显示片数与圈数）：

```js
function updateSendProgress() {
  const n = sender.playSeq ? sender.playSeq.length : sender.transfer.frames.length;
  const fps = +document.getElementById('opt-fps').value;
  if (sender.mode === 'retry') {
    setSendStatus('补发中：' + (n - 1) + ' 片｜' + fps + ' fps｜已循环 ' + sender.loops + ' 圈｜每圈约 ' + (n / fps).toFixed(1) + ' s');
    return;
  }
  const label = n === 1 ? '静态帧' : (sender.idx === 0 ? '头帧' : '数据帧 ' + sender.idx + '/' + (n - 1));
  setSendStatus(
    '播放中：' + label + '｜' + fps + ' fps｜已循环 ' + sender.loops + ' 圈｜每圈约 ' + (n / fps).toFixed(1) + ' s'
  );
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`bash test/run-tests.sh`
预期：`TEST-SUMMARY: ALL PASS (35/35)` 与 `PASS`（含原有 29 例——`start()` 泛化在 `playSeq === null` 时行为不变）。

- [ ] **步骤 5：Commit**

```bash
git add qr-transfer.html
git commit -m "feat: 发送端播放序列状态机——startRetry/startFull，全量模式行为不变"
```

---

### 任务 3：发送端补充模式 UI

**文件：**
- 修改：`qr-transfer.html`——`#view-send` 区 DOM（`<canvas id="qr-canvas">` 与 `<div id="send-status">` 之间插入区块）；`__SENDER__` 区 `setFile()` 成功路径与 `initSender()`
- 测试：无新单测（DOM 交互），靠任务 2 纯函数测试 + 全量回归 + 手测清单

- [ ] **步骤 1：添加 DOM**

在 `<canvas id="qr-canvas"></canvas>` 之后、`<div id="send-status" ...>` 之前插入：

```html
    <div class="controls" id="retry-box" style="display:none">
      <button id="btn-retry-start" disabled>仅补发这些帧</button>
      <button id="btn-retry-full" disabled>恢复全量播放</button>
      <input id="retry-input" placeholder="粘贴缺失序号，如 #3-7,15;C9F27（支持手打，区间 3-7 或 3~7）" style="flex:1; min-width:260px; font-size:12px">
    </div>
    <div id="retry-status" class="note" style="display:none"></div>
```

- [ ] **步骤 2：`setFile()` 成功路径接线（区块显隐与重置）**

在任务 2 步骤 3e 追加的 `this.mode = 'full'; this.playSeq = null;` 之后（`prep.value = 100;` 一行附近）追加：

```js
    const retryOk = canRetry(this.transfer);
    document.getElementById('retry-box').style.display = retryOk ? '' : 'none';
    document.getElementById('btn-retry-start').disabled = !retryOk;
    document.getElementById('btn-retry-full').disabled = !retryOk;
    document.getElementById('retry-input').value = '';
    document.getElementById('retry-status').style.display = 'none';
```

- [ ] **步骤 3：`initSender()` 末尾追加事件接线**

```js
  document.getElementById('btn-retry-start').addEventListener('click', () => {
    const r = sender.startRetry(document.getElementById('retry-input').value);
    const st = document.getElementById('retry-status');
    st.style.display = '';
    st.textContent = r.ok ? '补发已启动：' + r.msg : '未启动：' + r.msg;
  });
  document.getElementById('btn-retry-full').addEventListener('click', () => {
    sender.startFull();
    const st = document.getElementById('retry-status');
    st.style.display = ''; st.textContent = '已恢复全量播放';
  });
```

- [ ] **步骤 4：运行回归验证**

运行：`bash test/run-tests.sh`
预期：`TEST-SUMMARY: ALL PASS (35/35)` 与 `PASS`。

- [ ] **步骤 5：手测（可选，双窗口模拟）**

浏览器开两个窗口：A 开 `qr-transfer.html#send` 载入 >1KB 文件；B 开 `#receive` 抓 A 窗口。等部分收齐后 A 暂停 → B 记下缺失 → 把缺失文本粘进 A 的补充模式框 → 点「仅补发这些帧」→ 观察状态栏显示 `补发中：N 片…`、B 收齐自动下载 → 点「恢复全量播放」回全量。A 帧小文件（<400B）时补充模式区块应隐藏。

- [ ] **步骤 6：Commit**

```bash
git add qr-transfer.html
git commit -m "feat: 发送端补充模式 UI——粘贴/手打序号、仅补发缺失帧、恢复全量"
```

---

### 任务 4：接收端缺失导出

**文件：**
- 修改：`qr-transfer.html`——`#view-receive` 区 DOM（`<div id="chunk-grid"></div>` 之后插入一行）；`__RECEIVER__` 区 `listMissingChunks()` 改为复用、新增 `missingSeqsOf()`（放其上方）、`receiver` 对象新增 `refreshMissing()`/`copyMissing()`、`onFrame()` 与 `reset()` 调用刷新、`initReceiver()` 接线
- 测试：`qr-transfer.html` `__TESTS__` 区

- [ ] **步骤 1：编写失败的测试**

```js
test('missingSeqsOf 返回全部缺失序号，listMissingChunks 复用一致', async () => {
  const data = crypto.getRandomValues(new Uint8Array(1200));
  const t = await prepareTransfer('miss.bin', data, 600);
  const asm = new Assembler();
  await asm.feed(t.frames[0]);
  await asm.feed(t.frames[1]);   // seq 0
  await asm.feed(t.frames[3]);   // seq 2
  assertEq(missingSeqsOf(asm).join(','), '1');
  const lm = listMissingChunks(asm, 50);
  assertEq(lm.total, 1);
  assertEq(lm.first.join(','), '1');
});
test('接收端缺失文本随分片进度刷新，收齐显示无缺失', async () => {
  const data = crypto.getRandomValues(new Uint8Array(800));
  const t = await prepareTransfer('ui.bin', data, 600);
  const origDownload = downloadBlob;
  downloadBlob = () => {};
  try {
    receiver.asm = new Assembler(); receiver.done = false;
    await receiver.asm.feed(t.frames[0]);
    receiver.onFrame({ kind: 'header', meta: t.meta });
    await receiver.asm.feed(t.frames[1]);
    receiver.onFrame({ kind: 'progress', received: 1, total: t.meta.chunks, seq: 0, isNew: true });
    const box = document.getElementById('missing-text');
    assert(box.value.startsWith('缺失 1 片：#1;'), '实际：' + box.value);
    receiver.onFrame(await receiver.asm.feed(t.frames[2]));
    assertEq(box.value, '无缺失');
  } finally { downloadBlob = origDownload; }
});
```

- [ ] **步骤 2：运行测试验证失败**

运行：`bash test/run-tests.sh`
预期：`FAIL (35/37)`，失败行含 `missingSeqsOf is not defined` 或 `Cannot read properties of null (reading 'value')`（`#missing-text` 尚不存在）。

- [ ] **步骤 3：编写实现**

3a. DOM：`<div id="chunk-grid"></div>` 之后插入：

```html
    <div class="controls">
      <button id="btn-copy-missing" disabled>复制缺失序号</button>
      <input id="missing-text" readonly placeholder="缺失序号将显示在这里，可手动选中复制" style="flex:1; min-width:200px; font-size:12px">
    </div>
```

3b. `__RECEIVER__` 区：`listMissingChunks` 上方新增 `missingSeqsOf`，并把 `listMissingChunks` 改为复用（对齐 DRY，现有 `header-repeat` 日志行为不变）：

```js
// 全部缺失分片序号（升序）；A 帧路径 chunks 为 null 返回 []
function missingSeqsOf(asm) {
  const out = [];
  if (asm.chunks) for (let i = 0; i < asm.chunks.length; i++) if (asm.chunks[i] === null) out.push(i);
  return out;
}
// 缺失分片序号：total 为缺失总数，first 最多取 limit 个（日志用）
function listMissingChunks(asm, limit) {
  const all = missingSeqsOf(asm);
  return { total: all.length, first: all.slice(0, limit) };
}
```

3c. `receiver` 对象内（`onFrame` 之前）新增两个方法：

```js
  // 刷新缺失序号文本框与按钮可用性；分片状态变化、reset 时调用
  refreshMissing() {
    const box = document.getElementById('missing-text');
    const btn = document.getElementById('btn-copy-missing');
    if (!box) return;
    if (!this.asm.chunks && !this.asm.meta) {          // 未知总片数（A 帧整包除外，见下）
      btn.disabled = true;
      box.value = '（等待头帧或首个数据帧…）';
      return;
    }
    if (!this.asm.chunks) {                            // A 帧整包：无分片概念
      btn.disabled = true;
      box.value = '（整包传输，无分片）';
      return;
    }
    const seqs = missingSeqsOf(this.asm);
    btn.disabled = false;
    box.value = seqs.length ? '缺失 ' + seqs.length + ' 片：' + formatMissingSeqs(seqs) : '无缺失';
  },
  copyMissing() {
    const seqs = missingSeqsOf(this.asm);
    if (!seqs.length) return;
    const text = formatMissingSeqs(seqs);
    const done = () => setRecvStatus('已复制缺失序号（' + seqs.length + ' 片），请带到发送端「补充模式」粘贴');
    const fail = () => setRecvStatus('复制失败：请手动选中文本框内容复制');
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, fail);
    else fail();
  },
```

3d. 调用点：`onFrame(r)` 方法体开头（`const asm = this.asm;` 之后）加一行 `this.refreshMissing();`；`reset()` 方法体内（`setRecvStatus(...)` 之前）加一行 `this.refreshMissing();`。

3e. `initReceiver()` 内追加：

```js
  document.getElementById('btn-copy-missing').addEventListener('click', () => receiver.copyMissing());
```

- [ ] **步骤 4：运行测试验证通过**

运行：`bash test/run-tests.sh`
预期：`TEST-SUMMARY: ALL PASS (37/37)` 与 `PASS`。

- [ ] **步骤 5：Commit**

```bash
git add qr-transfer.html
git commit -m "feat: 接收端缺失序号导出——实时缺失文本与一键复制（含剪贴板降级）"
```

---

### 任务 5：全链路补发测试 + README + 收尾回归

**文件：**
- 修改：`qr-transfer.html` `__TESTS__` 区；`README.md`
- 测试：`qr-transfer.html` `__TESTS__` 区

- [ ] **步骤 1：编写失败的测试（规格 §8.6 端到端）**

```js
test('补充模式全链路：缺失导出→解析→仅重播补发帧→收齐且数据一致', async () => {
  const data = crypto.getRandomValues(new Uint8Array(3000));
  const t = await prepareTransfer('retry-e2e.bin', data, 600);   // 5 片，frames = H + D0..D4
  const asm = new Assembler();
  await asm.feed(t.frames[0]);
  const missSet = new Set([1, 3, 4]);                             // 模拟漏 3 片
  for (let i = 1; i < t.frames.length; i++) {
    if (missSet.has(i - 1)) continue;
    await asm.feed(t.frames[i]);
  }
  assertEq(asm.received, t.meta.chunks - 3);
  const seqs = missingSeqsOf(asm);
  assertEq(seqs.join(','), '1,3,4');
  const parsed = parseRetryList(formatMissingSeqs(seqs), t.meta.chunks);
  assertEq(parsed.checksumOk, true);
  assertEq(buildRetryPlaySeq(parsed.seqs, t.meta.chunks).join(','), '0,2,4,5');
  let last;
  for (const fi of [0, 2, 4, 5]) last = await asm.feed(t.frames[fi]);   // 补发即重播原始帧字节
  assertEq(last.kind, 'complete');
  assertBytesEq(last.data, data);
});
```

- [ ] **步骤 2：运行测试验证通过**

运行：`bash test/run-tests.sh`
预期：`TEST-SUMMARY: ALL PASS (38/38)` 与 `PASS`。（本用例只组链既有函数，应直接通过；若失败说明前序任务有缺陷，修复后重跑。）

- [ ] **步骤 3：README 新增「补充模式」小节**

在 `## 可靠性说明` 之后插入：

```markdown
## 补充模式

大文件漏片时无需等完整循环：接收端「复制缺失序号」→ 文本带回发送端（剪贴板共享或手打）→ 粘贴进「补充模式」→ 点「仅补发这些帧」，发送端只循环 `[头帧, …缺失帧…]`。

- 文本格式：`#3-7,15;C9F27`——序号即分片序号；区间 `3-7`（或 `3~7`）；分隔符中英文逗号/分号/空格均可；`;C` 后 4 位为校验码，手打错一位会拒绝启动。
- 每圈头帧重复时接收端 Console 自动报告剩余缺失；收齐自动校验下载，发送端手动暂停即可。
- 补发对同一次传输有效（不要重新选文件，否则 tid 变化接收端会整体重来）。
```

- [ ] **步骤 4：全量回归 + 手测清单**

运行：`bash test/run-tests.sh`
预期：`TEST-SUMMARY: ALL PASS (38/38)` 与 `PASS`。

人工验证（真实双端，宿主机 + 虚拟机）：
1. 传一个几十 KB 文件，中途遮挡发送窗口制造缺失
2. 发送端暂停 → 接收端「复制缺失序号」→ 粘贴回发送端 → 「仅补发这些帧」
3. 观察：补发圈内 Console `头帧重复` 日志的缺失列表逐圈缩短；收齐后自动下载且 SHA-256 校验通过
4. 手打场景：抄错一位序号 → 「未启动：校验不符」

- [ ] **步骤 5：Commit**

```bash
git add qr-transfer.html README.md
git commit -m "test: 补充模式全链路用例（导出→解析→重播→收齐）；docs: README 补充模式说明"
```

---

## 自检记录

- **规格覆盖度：** §4 文本格式（任务 1）；§6 状态机（任务 2）与 UI（任务 3）；§5 接收端导出（任务 4）；§8 测试（任务 1/2/4/5）与 README（任务 5）；§7 边界——A 帧禁用（任务 2 `canRetry` + 任务 3 显隐）、已收片重播去重（任务 5 用例隐含）、接收端重置后缺失骤增（任务 4 `reset()` 调 `refreshMissing`）、重载文件回全量（任务 2 步骤 3e + 任务 3 步骤 2 清空）、剪贴板降级（任务 4 `copyMissing`）。无遗漏。
- **占位符扫描：** 无 TODO/待定/「类似任务 N」。
- **类型一致性：** `retryChecksum/formatMissingSeqs/parseRetryList`（任务 1）→ 任务 4/5 引用一致；`buildRetryPlaySeq/canRetry`（任务 2）→ 任务 3/5 一致；`missingSeqsOf`（任务 4）→ 任务 5 一致；`sender.startRetry/startFull/refreshMissing/copyMissing` 命名前后一致。
