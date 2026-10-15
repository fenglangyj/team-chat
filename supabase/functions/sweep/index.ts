// 团队通 TeamChat - sweep 清扫边缘函数
// 职责：
//   1. 删除超过 24 小时的消息（服务端强制销毁）
//   2. 删除已失去消息关联的附件（存储对象 + 登记行）
//   3. 清理过期的密钥分发请求
// 触发方式：
//   - 客户端启动 / 定时心跳触发（已登录成员调用）
//   - 可选的 pg_cron 定时任务（见 supabase/cron_setup.sql.example）

import { createClient } from "jsr:@supabase/supabase-js@2";

const MESSAGE_TTL_MS = 24 * 60 * 60 * 1000; // 消息保留 24 小时
const ATTACHMENT_GRACE_MS = 10 * 60 * 1000; // 附件登记后 10 分钟内等待消息挂接
const KEY_REQUEST_TTL_MS = 7 * 24 * 60 * 60 * 1000; // 密钥请求 7 天过期
const REMOVE_BATCH = 100; // Storage 单次删除上限

Deno.serve(async (_req) => {
  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const now = Date.now();
  const msgCutoff = new Date(now - MESSAGE_TTL_MS).toISOString();
  const attCutoff = new Date(now - ATTACHMENT_GRACE_MS).toISOString();
  const keyReqCutoff = new Date(now - KEY_REQUEST_TTL_MS).toISOString();

  // 1) 过期消息（附件登记的 message_id 会被外键自动置空）
  const { count: deletedMessages, error: msgErr } = await admin
    .from("messages")
    .delete({ count: "exact" })
    .lt("created_at", msgCutoff);
  if (msgErr) {
    return Response.json({ ok: false, error: `messages: ${msgErr.message}` }, { status: 500 });
  }

  // 2) 失去消息关联的附件：先删存储对象，再删登记行
  let deletedAttachments = 0;
  for (;;) {
    const { data: orphans, error: selErr } = await admin
      .from("attachments")
      .select("id, storage_path")
      .is("message_id", null)
      .lt("created_at", attCutoff)
      .limit(500);
    if (selErr) {
      return Response.json({ ok: false, error: `attachments: ${selErr.message}` }, { status: 500 });
    }
    if (!orphans || orphans.length === 0) break;

    for (let i = 0; i < orphans.length; i += REMOVE_BATCH) {
      const batch = orphans.slice(i, i + REMOVE_BATCH);
      await admin.storage.from("attachments").remove(batch.map((o) => o.storage_path));
      await admin.from("attachments").delete().in("id", batch.map((o) => o.id));
      deletedAttachments += batch.length;
    }
    if (orphans.length < 500) break;
  }

  // 3) 过期的密钥请求（客户端会按需重新发起）
  const { error: krErr } = await admin
    .from("key_requests")
    .delete()
    .lt("created_at", keyReqCutoff);

  return Response.json({
    ok: true,
    deletedMessages: deletedMessages ?? 0,
    deletedAttachments,
    keyRequestError: krErr?.message ?? null,
  });
});
