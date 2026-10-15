-- =============================================================
-- 团队通 TeamChat - 0002 Storage 存储桶与访问策略
-- 附件桶为私有桶；对象路径格式：{conversation_id}/{attachment_id}.bin
-- 文件内容在上传前已于客户端加密，服务端（含 Storage）只有密文。
-- 本文件可重复执行。
-- =============================================================

insert into storage.buckets (id, name, public)
values ('attachments', 'attachments', false)
on conflict (id) do nothing;

-- 会话成员可读
drop policy if exists "attachments_read" on storage.objects;
create policy "attachments_read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'attachments'
    and public.is_member(public.try_uuid((storage.foldername(name))[1]))
  );

-- 会话成员可上传（路径必须以会话 id 开头）
drop policy if exists "attachments_upload" on storage.objects;
create policy "attachments_upload" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'attachments'
    and public.is_member(public.try_uuid((storage.foldername(name))[1]))
  );

-- 会话成员可删除（清空聊天记录时需要删除所有人的附件）
drop policy if exists "attachments_delete" on storage.objects;
create policy "attachments_delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'attachments'
    and public.is_member(public.try_uuid((storage.foldername(name))[1]))
  );
