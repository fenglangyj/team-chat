# 架构与加密设计

## 总体结构

```
Flutter 客户端（6 端单一代码库）
├─ 配置层        SUPABASE_URL / ANON_KEY（本地保存）
├─ 认证层        Supabase Auth（虚拟邮箱 = 账号 + 固定域）
├─ 加密层        X25519 + XChaCha20-Poly1305 + Argon2id（全部端侧）
├─ 数据层        Supabase Postgres（表）/ Storage（附件）/ Realtime（推送）
└─ 内存层        聊天记录仅存内存：Map<会话, 消息分页>，退出即清空
```

服务端仅承担：账号认证、密文存储、实时转发、定时清扫。

## 密钥体系

| 密钥 | 生成方式 | 存放位置 | 用途 |
| --- | --- | --- | --- |
| 用户口令 | 用户设置 | 用户大脑 | 登录 + 派生 KEK |
| KEK | Argon2id(口令, 随机盐) | 不存储 | 解封私钥 |
| 身份私钥 (X25519) | 注册时随机生成 | 用 KEK 加密（`sealed_private_key`）后存服务端 | 解封其他成员封装的会话密钥 |
| 身份公钥 (X25519) | 随私钥生成 | `profiles.public_key`（公开） | 被他人用于封装会话密钥 |
| 会话密钥 CEK | 创建会话者随机生成 32 字节 | 每个成员一份，用其公钥封装后存 `conversation_members.wrapped_key` | 加解密该会话的消息与附件 |

封装格式（sealed-box 风格）：`ephemeral_pub(32) || nonce(24) || AEAD(CEK)`，
共享密钥 = HKDF-SHA256(X25519(临时私钥, 接收方公钥))。服务端没有任何一环的私钥材质。

## 消息流程

### 注册

1. 本地生成 X25519 密钥对
2. `KEK = Argon2id(password, salt)`；`sealed = XChaCha20-Poly1305(KEK, seed, AAD="teamchat/v1:" + account)`
3. `supabase.auth.signUp(email = account + "@teamchat.local", password)`
4. 写入 `profiles`（昵称、公钥、封装私钥、KDF 参数）
5. 调用 `join_default_group` 加入/创建全员群

### 发送消息

1. 取会话 CEK（本会话内已解封则直接用，否则从自己的 `wrapped_key` 解封）
2. `payload = {t: text|image|file, ...}`（文件名、类型、大小等都在其中）
3. `AEAD(CEK, payload)`，AAD 绑定会话 id；只把密文 + nonce 写入 `messages`
4. 其他成员经 Realtime 收到密文 → 用各自解封的 CEK 解密 → 上屏

### 会话密钥分发

- **建会话时**：创建者拿到全部成员公钥，逐一封装 CEK 一并写入 `conversation_members`
- **补充成员**：同流程；无法封装时 `wrapped_key = null`
- **无法封装的新成员**：客户端写入 `key_requests` 行；在线成员收到 Realtime 事件后用自己的 CEK 封装并调用 `provide_key` RPC 回填

### 附件（图片/文件）

1. 客户端随机生成 `attachment_id`，登记 `attachments` 行（此时 `message_id` 为空）
2. 文件分块加密（1 MiB/块）：
   - 文件头 `TCA1 + version + chunkSize + fileId(16B)`
   - 第 i 块 nonce = `fileId || uint64(i)`，AEAD 密钥 = CEK，AAD = 文件头 + 块序号
3. 密文上传到 `attachments/{conversation_id}/{attachment_id}.bin`
4. 发送附带 `attachment_id` 的消息；随后回填 `attachments.message_id`
5. 接收方点击下载 → 逐块解密到内存/临时文件 → 预览或另存

## 24 小时销毁

- `sweep` Edge Function：删除 `created_at < now() - 24h` 的消息；删除失去消息关联（`message_id is null` 且超过 10 分钟宽限）的附件（Storage 对象 + 登记行）
- 触发方式：客户端启动与每小时心跳；可选 pg_cron 每小时兜底（见 `cron_setup.sql.example`）
- 消息删除时外键自动把附件的 `message_id` 置空 → 附件在下一轮清扫中删除，保证「记录删、文件删」

## 清空会话

1. 任一成员调用 `clear_conversation` RPC（security definer，校验成员身份）→ 硬删除该会话全部消息
2. 附件登记随外键置空 → 由清扫函数删除存储对象（在线成员也会立即批量删除自己可见的对象）
3. Realtime 的 DELETE 事件（`replica identity full`）把被删消息推给所有在线成员 → 各端内存缓存同步清除
4. 离线成员本地无任何持久化记录，无需同步

## 客户端缓存与懒加载

- `ChatController` 维护 `Map<conversationId, List<Message>>`（纯内存）
- 打开会话：只拉取最近 50 条（`order by created_at desc`），滚动到顶部再拉更早的一页
- Realtime：当前打开的会话订阅消息 INSERT/DELETE；收到的密文按需解密
- 退出程序/退出登录：内存缓存与解封密钥全部丢弃

## 数据表

| 表 | 内容 | 谁能读 |
| --- | --- | --- |
| `profiles` | 账号、昵称、公钥、封装私钥 | 全体成员（密钥封装需要公钥） |
| `conversations` | 会话种类、加密群名 | 仅会话成员 |
| `conversation_members` | 成员 + 封装后的 CEK | 仅会话成员 |
| `messages` | 消息密文 | 仅会话成员 |
| `attachments` | 附件登记（路径、关联消息） | 仅会话成员 |
| `key_requests` | 密钥分发请求 | 仅会话成员 |

## 已知边界（有意为之的取舍）

1. **依赖至少一名在线老成员分发密钥**：全员群新成员在所有人离线时需等待；这是「服务端零密钥」的必然代价
2. **元数据不加密**：时间、发送者、会话归属在服务端可见
3. **成员数量级**：会话密钥逐人封装，适合数十人以内团队；超大群需引入发送者密钥（sender keys）等方案
4. **忘记密码不可恢复**：没有任何后门可以找回私钥
