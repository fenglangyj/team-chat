-- =============================================================
-- 团队通 TeamChat - 0001 核心表结构 / RLS / RPC
-- 在 Supabase SQL Editor 中整体粘贴并运行。
-- 服务端只保存密文：消息与文件名均为端到端加密后的内容。
-- =============================================================

-- ---------- 工具函数 ----------

-- 安全地把 text 转为 uuid（用于 storage 路径解析），失败返回 null
create or replace function public.try_uuid(t text)
returns uuid
language plpgsql immutable
as $$
begin
  return t::uuid;
exception when others then
  return null;
end $$;

-- 当前用户是否为某会话成员（security definer，避免 RLS 递归）
create or replace function public.is_member(conv uuid, uid uuid default auth.uid())
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.conversation_members m
    where m.conversation_id = conv and m.user_id = uid
  );
$$;

revoke all on function public.try_uuid(text) from public, anon;
grant execute on function public.try_uuid(text) to authenticated;

revoke all on function public.is_member(uuid, uuid) from public, anon;
grant execute on function public.is_member(uuid, uuid) to authenticated;

-- ---------- 表结构 ----------

-- 用户资料（昵称、公钥、被口令封装过的私钥；私钥服务端无法解密）
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  account text not null unique check (account ~ '^[a-zA-Z0-9_]{3,32}$'),
  nickname text not null check (char_length(nickname) between 1 and 32),
  public_key text not null,
  sealed_private_key text not null,
  kdf_salt text not null,
  kdf_params jsonb not null default '{"algo":"argon2id","m":65536,"t":3,"p":1}'::jsonb,
  created_at timestamptz not null default now()
);

-- 会话（direct 单聊 / group 群聊；群名也加密存储）
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('direct','group')),
  is_default_group boolean not null default false,
  name_cipher text,
  name_nonce text,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create unique index if not exists uq_conversations_default_group
  on public.conversations (is_default_group) where is_default_group;

-- 会话成员（wrapped_key = 用成员公钥封装的会话密钥 CEK；null 表示等待他人分发密钥）
create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  wrapped_key text,
  key_nonce text,
  wrapped_by uuid references public.profiles(id) on delete set null,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

-- 消息（只存密文）
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('text','image','file')),
  ciphertext text not null,
  nonce text not null,
  attachment_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists idx_messages_conv_created
  on public.messages (conversation_id, created_at, id);

alter table public.messages replica identity full;

-- 附件登记（消息被删除后 message_id 置空，由清扫任务删除存储对象）
create table if not exists public.attachments (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  uploader_id uuid not null references public.profiles(id) on delete cascade,
  storage_path text not null,
  message_id uuid references public.messages(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_attachments_orphans
  on public.attachments (created_at) where message_id is null;

alter table public.messages
  add constraint messages_attachment_fk
  foreign key (attachment_id) references public.attachments(id) on delete set null;

-- 密钥分发请求（新成员加入全员群等场景，等待在线成员把 CEK 封装给他）
create table if not exists public.key_requests (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

-- ---------- 行级安全 ----------

alter table public.profiles enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.attachments enable row level security;
alter table public.key_requests enable row level security;

-- profiles：团队内可见（公钥与昵称本就是团队公开信息）
create policy profiles_select on public.profiles
  for select to authenticated using (true);
create policy profiles_insert on public.profiles
  for insert to authenticated with check (id = auth.uid());
create policy profiles_update on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- conversations：仅成员可见；创建走 RPC
create policy conv_select on public.conversations
  for select to authenticated using (public.is_member(id));

-- conversation_members：成员互见；只能给他人的空槽位分发密钥，或更新自己的密钥
create policy members_select on public.conversation_members
  for select to authenticated using (public.is_member(conversation_id));
create policy members_update on public.conversation_members
  for update to authenticated
  using (public.is_member(conversation_id) and (wrapped_key is null or user_id = auth.uid()))
  with check (public.is_member(conversation_id) and wrapped_key is not null);

-- messages：成员可读、可发、可删（任何人可清空会话）；消息不可修改
create policy messages_select on public.messages
  for select to authenticated using (public.is_member(conversation_id));
create policy messages_insert on public.messages
  for insert to authenticated
  with check (sender_id = auth.uid() and public.is_member(conversation_id));
create policy messages_delete on public.messages
  for delete to authenticated using (public.is_member(conversation_id));

-- attachments
create policy attachments_select on public.attachments
  for select to authenticated using (public.is_member(conversation_id));
create policy attachments_insert on public.attachments
  for insert to authenticated
  with check (uploader_id = auth.uid() and public.is_member(conversation_id));
create policy attachments_update on public.attachments
  for update to authenticated
  using (public.is_member(conversation_id))
  with check (public.is_member(conversation_id));
create policy attachments_delete on public.attachments
  for delete to authenticated using (public.is_member(conversation_id));

-- key_requests
create policy keyreq_select on public.key_requests
  for select to authenticated using (public.is_member(conversation_id));
create policy keyreq_insert on public.key_requests
  for insert to authenticated
  with check (user_id = auth.uid() and public.is_member(conversation_id));
create policy keyreq_delete on public.key_requests
  for delete to authenticated using (public.is_member(conversation_id));

-- ---------- RPC ----------

-- 创建（或复用）与某人的单聊。双方密钥由调用方封装好后一并写入。
create or replace function public.create_direct_conversation(
  peer uuid,
  my_wrapped_key text,
  my_key_nonce text,
  peer_wrapped_key text,
  peer_key_nonce text
)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  cid uuid;
begin
  if me is null then raise exception 'unauthenticated'; end if;
  if peer is null or peer = me then raise exception 'invalid peer'; end if;
  if not exists (select 1 from public.profiles where id = peer) then
    raise exception 'peer not found';
  end if;

  -- 同一对用户只允许一个单聊（加排他锁防并发重复创建）
  perform pg_advisory_xact_lock(hashtext(least(me::text, peer::text) || ':' || greatest(me::text, peer::text)));

  select c.id into cid
  from public.conversations c
  join public.conversation_members m1 on m1.conversation_id = c.id and m1.user_id = me
  join public.conversation_members m2 on m2.conversation_id = c.id and m2.user_id = peer
  where c.kind = 'direct'
  limit 1;

  if cid is not null then
    return cid;
  end if;

  insert into public.conversations (kind, created_by) values ('direct', me)
  returning id into cid;

  insert into public.conversation_members (conversation_id, user_id, wrapped_key, key_nonce, wrapped_by)
  values
    (cid, me, my_wrapped_key, my_key_nonce, me),
    (cid, peer, peer_wrapped_key, peer_key_nonce, me);

  return cid;
end $$;

-- 创建群聊；members 为 [{"user_id": uuid, "wrapped_key": text|null, "key_nonce": text|null}, ...]
create or replace function public.create_group_conversation(
  group_name_cipher text,
  group_name_nonce text,
  members jsonb
)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  cid uuid;
  item jsonb;
  included boolean := false;
begin
  if me is null then raise exception 'unauthenticated'; end if;
  if members is null or jsonb_array_length(members) < 1 then
    raise exception 'members required';
  end if;

  insert into public.conversations (kind, created_by, name_cipher, name_nonce)
  values ('group', me, group_name_cipher, group_name_nonce)
  returning id into cid;

  for item in select * from jsonb_array_elements(members) loop
    if (item->>'user_id')::uuid = me then included := true; end if;
    insert into public.conversation_members (conversation_id, user_id, wrapped_key, key_nonce, wrapped_by)
    values (cid, (item->>'user_id')::uuid, item->>'wrapped_key', item->>'key_nonce', me)
    on conflict (conversation_id, user_id) do nothing;
  end loop;

  if not included then
    delete from public.conversations where id = cid;
    raise exception 'creator must be included in members';
  end if;

  return cid;
end $$;

-- 向群聊补充成员（与 create_group 相同的入参结构）
create or replace function public.add_group_members(conv uuid, members jsonb)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  item jsonb;
begin
  if me is null then raise exception 'unauthenticated'; end if;
  if not public.is_member(conv, me) then raise exception 'not a member'; end if;

  for item in select * from jsonb_array_elements(coalesce(members, '[]'::jsonb)) loop
    insert into public.conversation_members as cm (conversation_id, user_id, wrapped_key, key_nonce, wrapped_by)
    values (conv, (item->>'user_id')::uuid, item->>'wrapped_key', item->>'key_nonce', me)
    on conflict (conversation_id, user_id) do update
      set wrapped_key = coalesce(cm.wrapped_key, excluded.wrapped_key),
          key_nonce = coalesce(cm.key_nonce, excluded.key_nonce),
          wrapped_by = coalesce(cm.wrapped_by, excluded.wrapped_by);
    delete from public.key_requests
      where conversation_id = conv and user_id = (item->>'user_id')::uuid
        and exists (
          select 1 from public.conversation_members m
          where m.conversation_id = conv and m.user_id = (item->>'user_id')::uuid
            and m.wrapped_key is not null
        );
  end loop;
end $$;

-- 加入（必要时创建）全员群。已有密钥可传入，否则传 null 等待在线成员分发。
create or replace function public.join_default_group(
  my_wrapped_key text default null,
  my_key_nonce text default null
)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  cid uuid;
begin
  if me is null then raise exception 'unauthenticated'; end if;

  select id into cid from public.conversations where is_default_group limit 1;

  if cid is null then
    begin
      insert into public.conversations (kind, created_by, is_default_group)
      values ('group', me, true)
      returning id into cid;
    exception when unique_violation then
      select id into cid from public.conversations where is_default_group limit 1;
    end;
  end if;

  insert into public.conversation_members as cm (conversation_id, user_id, wrapped_key, key_nonce, wrapped_by)
  values (cid, me, my_wrapped_key, my_key_nonce, me)
  on conflict (conversation_id, user_id) do update
    set wrapped_key = coalesce(cm.wrapped_key, excluded.wrapped_key),
        key_nonce   = coalesce(cm.key_nonce, excluded.key_nonce),
        wrapped_by  = coalesce(cm.wrapped_by, excluded.wrapped_by);

  return cid;
end $$;

-- 为某成员分发会话密钥（只允许填补空槽位；更新自己的密钥也允许）
create or replace function public.provide_key(
  conv uuid,
  target uuid,
  new_wrapped_key text,
  new_key_nonce text
)
returns boolean
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  updated int;
begin
  if me is null then raise exception 'unauthenticated'; end if;
  if not public.is_member(conv, me) then raise exception 'not a member'; end if;

  update public.conversation_members
     set wrapped_key = new_wrapped_key,
         key_nonce = new_key_nonce,
         wrapped_by = me
   where conversation_id = conv
     and user_id = target
     and (wrapped_key is null or target = me);

  get diagnostics updated = row_count;

  if updated > 0 then
    delete from public.key_requests
     where conversation_id = conv and user_id = target;
  end if;

  return updated > 0;
end $$;

-- 清空会话：服务端硬删除全部消息（任何人可对自己参与的会话发起）
create or replace function public.clear_conversation(conv uuid)
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  deleted int;
begin
  if me is null then raise exception 'unauthenticated'; end if;
  if not public.is_member(conv, me) then raise exception 'not a member'; end if;

  delete from public.messages where conversation_id = conv;
  get diagnostics deleted = row_count;
  return deleted;
end $$;

-- ---------- 函数权限 ----------

revoke all on function public.create_direct_conversation(uuid, text, text, text, text) from public, anon;
revoke all on function public.create_group_conversation(text, text, jsonb) from public, anon;
revoke all on function public.add_group_members(uuid, jsonb) from public, anon;
revoke all on function public.join_default_group(text, text) from public, anon;
revoke all on function public.provide_key(uuid, uuid, text, text) from public, anon;
revoke all on function public.clear_conversation(uuid) from public, anon;

grant execute on function public.create_direct_conversation(uuid, text, text, text, text) to authenticated;
grant execute on function public.create_group_conversation(text, text, jsonb) to authenticated;
grant execute on function public.add_group_members(uuid, jsonb) to authenticated;
grant execute on function public.join_default_group(text, text) to authenticated;
grant execute on function public.provide_key(uuid, uuid, text, text) to authenticated;
grant execute on function public.clear_conversation(uuid) to authenticated;

-- ---------- Realtime ----------

do $$ begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null; end $$;

do $$ begin
  alter publication supabase_realtime add table public.conversation_members;
exception when duplicate_object then null; end $$;

do $$ begin
  alter publication supabase_realtime add table public.conversations;
exception when duplicate_object then null; end $$;

do $$ begin
  alter publication supabase_realtime add table public.key_requests;
exception when duplicate_object then null; end $$;
