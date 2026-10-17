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
