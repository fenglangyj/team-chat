# 手把手：准备你的 Supabase 后端

> 团队通 TeamChat 不提供公共服务器，而是让你（或团队里任意一人）注册一个**自己的** Supabase 免费账号作为后端。
> 整个过程约 5 分钟，不需要写代码，也不需要信用卡。
> 做完后你会得到两个值：`SUPABASE_URL` 和 `SUPABASE_ANON_KEY`，把它们填入客户端即可使用。

## 目录

1. [注册 Supabase 账号](#1-注册-supabase-账号)
2. [创建项目](#2-创建项目)
3. [获取 SUPABASE_URL 和 SUPABASE_ANON_KEY](#3-获取-supabase_url-和-supabase_anon_key)
4. [初始化数据库（执行两个 SQL 文件）](#4-初始化数据库执行两个-sql-文件)
5. [关闭邮箱验证](#5-关闭邮箱验证重要)
6. [部署清扫函数 sweep](#6-部署清扫函数-sweep)
7. [（推荐）开启服务端定时清理](#7-推荐开启服务端定时清理)
8. [测试并开始使用](#8-测试并开始使用)

---

## 1. 注册 Supabase 账号

1. 打开 <https://supabase.com>，点击右上角 **Start your project**。
2. 选择 **Sign up with GitHub**（推荐，一步完成）或使用邮箱注册。
3. 首次登录可能需要创建一个 **Organization（组织）**：名称随便填（如 `my-team`），计划选择 **Free**。

> 免费版限制：最多 2 个免费项目、数据库 500MB、文件存储 1GB、每月 5GB 流量。小团队日常聊天完全够用。

## 2. 创建项目

1. 在控制台点击 **New project**。
2. 填写：
   - **Name**：项目名，如 `team-chat`
   - **Database Password**：数据库密码，点 **Generate a password** 生成并**保存好**（此密码只用于数据库直连，日常使用不需要它）
   - **Region**：选择离团队最近的区域（国内团队建议 `Northeast Asia (Tokyo)` 或 `Southeast Asia (Singapore)`）
3. 点击 **Create new project**，等待 1~3 分钟初始化完成。

## 3. 获取 SUPABASE_URL 和 SUPABASE_ANON_KEY

左侧菜单 **Project Settings（齿轮图标）→ API Keys**（旧版界面为 **Settings → API**）。

- **SUPABASE_URL**：页面上方的 `Project URL`，形如 `https://abcdefgh.supabase.co`
- **SUPABASE_ANON_KEY**：
  - 新版界面：复制 **Publishable key**（形如 `sb_publishable_...`）
  - 如果找不到，切换 **Legacy API keys** 标签，复制 **anon public** key（形如 `eyJhbGciOi...` 的长字符串）

> ⚠️ 不要使用 `service_role` / `secret` key！那是管理员密钥，会绕过所有安全策略。
> `SUPABASE_URL + anon key` 就是「团队通行证」：知道它们的人都能注册进入你的团队，请只发给信任的同事。

把这两个值先记在记事本里，第 8 步要用。

## 4. 初始化数据库（执行两个 SQL 文件）

左侧菜单打开 **SQL Editor**，点击 **New query**，依次执行本仓库 `supabase/migrations/` 下的两个文件（**顺序不能反**）：

1. 打开仓库里的 [`supabase/migrations/0001_schema.sql`](../supabase/migrations/0001_schema.sql)，全选复制 → 粘贴到 SQL Editor → 点击 **Run**（或按 `Ctrl+Enter`）→ 看到 `Success. No rows returned` 即成功
2. 清空编辑框，再打开 [`supabase/migrations/0002_storage.sql`](../supabase/migrations/0002_storage.sql)，同样复制 → 粘贴 → **Run**

> 这两个文件包含：表结构、行级安全策略（只有会话成员能看到对应数据）、附件存储桶与访问策略、实时推送配置。

## 5. 关闭邮箱验证（重要！）

本应用使用「账号」注册，内部会自动拼出一个虚拟邮箱。为了避免注册时报「邮箱未验证」：

左侧菜单 **Authentication → Sign In / Providers**（旧版为 **Authentication → Providers → Email**）：

1. 找到 **Email** 提供者，确保它是 **Enabled** 状态
2. 关闭 **Confirm email**（确认邮箱）开关 —— **必须关闭**，否则注册后无法直接登录

## 6. 部署清扫函数 sweep

`sweep` 函数负责删除超过 24 小时的消息与文件。二选一：

### 方式 A：在网页上部署（推荐，最简单）

1. 左侧菜单打开 **Edge Functions**，点击 **Deploy a new function** → **Via Editor**
2. 函数名填 `sweep`（必须恰好是这个名字）
3. 把仓库 [`supabase/functions/sweep/index.ts`](../supabase/functions/sweep/index.ts) 的全部内容粘贴进编辑器，覆盖默认代码
4. 点击 **Deploy**，等待状态变为 `ACTIVE`

### 方式 B：使用 Supabase CLI（适合开发者）

```bash
npm install -g supabase
supabase login                # 会打开浏览器授权
cd <本仓库目录>
supabase functions deploy sweep --project-ref <你的项目 ref，即 URL 里的子域名>
```

## 7. （推荐）开启服务端定时清理

完成这一步后，即使**没有任何人打开客户端**，服务端也会每小时自动清理过期数据。

1. 左侧菜单 **Database → Extensions**，搜索并启用 **pg_cron** 和 **pg_net** 两个扩展
2. 打开仓库里的 [`supabase/cron_setup.sql.example`](../supabase/cron_setup.sql.example)，把其中两处占位符替换成你自己的值：
   - `YOUR-PROJECT` → 你的项目子域名（即 URL `https://YOUR-PROJECT.supabase.co` 中那一段）
   - `YOUR-ANON-KEY` → 第 3 步拿到的 anon key
3. 到 **SQL Editor** 粘贴执行一次即可

> 不配置也没关系：只要有客户端在运行，它启动时和每小时都会主动触发一次清理，效果相同。

## 8. 测试并开始使用

1. 打开团队通客户端，首次运行会要求填写：
   - `SUPABASE_URL`：第 3 步复制的 Project URL
   - `SUPABASE_ANON_KEY`：第 3 步复制的 Publishable / anon key
2. 点击「连接」→ 注册你的账号（账号、密码、昵称）→ 自动进入全员群
3. 把 **URL + KEY** 发给同事，他们下载同一客户端、填相同配置、自行注册，即可加入同一个团队

### 常见问题排查

| 现象 | 原因与解决 |
| --- | --- |
| 注册时报 `Email not confirmed` | 第 5 步没关闭「Confirm email」，关闭后重试 |
| 注册时报 `User already registered` | 该账号名已被占用，换一个 |
| 连接失败 / 加载不出来 | 检查 URL 是否复制完整（必须带 `https://`）；确认项目未被暂停（免费项目长期无活动会暂停，控制台点 Restore） |
| 消息显示「等待密钥」 | 群里暂时没有其他在线成员能分发密钥，等任一老成员上线后会自动完成 |
| 执行 SQL 报错 `must be owner of table objects` | 请在 SQL Editor（以 postgres 身份）执行，而不是在其他连接方式中执行 |

---

下一步：阅读 [用户教程](user-guide.md)，了解日常怎么用。
