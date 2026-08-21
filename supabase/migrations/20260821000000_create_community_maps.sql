-- SOCOM-141 community map registry and private asset storage.
-- Storage object convention: <owner_uuid>/<map_uuid>/<sha256>.glb

create extension if not exists pgcrypto;

create table public.community_maps (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  slug text not null,
  title text not null check (char_length(title) between 1 and 80),
  description text not null default '' check (char_length(description) <= 2000),
  visibility text not null default 'private' check (visibility in ('private', 'unlisted', 'public')),
  lifecycle text not null default 'draft' check (lifecycle in ('draft', 'published', 'archived')),
  current_version integer not null default 0 check (current_version >= 0),
  thumbnail_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, slug)
);

create table public.community_map_collaborators (
  map_id uuid not null references public.community_maps(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'editor' check (role in ('editor', 'viewer')),
  created_at timestamptz not null default now(),
  primary key (map_id, user_id)
);

create table public.community_map_versions (
  id uuid primary key default gen_random_uuid(),
  map_id uuid not null references public.community_maps(id) on delete cascade,
  version_number integer not null check (version_number > 0),
  created_by uuid not null references auth.users(id) on delete restrict,
  map_document jsonb not null,
  asset_manifest jsonb not null default '[]'::jsonb,
  document_sha256 text not null check (document_sha256 ~ '^[0-9a-f]{64}$'),
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  unique (map_id, version_number)
);

create table public.community_map_assets (
  id uuid primary key default gen_random_uuid(),
  map_id uuid not null references public.community_maps(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null unique,
  original_filename text not null,
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  byte_size bigint not null check (byte_size between 1 and 134217728),
  mime_type text not null default 'model/gltf-binary' check (mime_type = 'model/gltf-binary'),
  moderation_state text not null default 'pending' check (moderation_state in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  unique (map_id, sha256)
);

create index community_maps_owner_idx on public.community_maps(owner_id);
create index community_maps_discovery_idx on public.community_maps(lifecycle, visibility, updated_at desc);
create index community_map_collaborators_user_idx on public.community_map_collaborators(user_id, map_id);
create index community_map_versions_map_idx on public.community_map_versions(map_id, version_number desc);
create index community_map_assets_map_idx on public.community_map_assets(map_id);
create index community_map_assets_owner_idx on public.community_map_assets(owner_id);

create or replace function public.set_community_map_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger community_maps_set_updated_at
before update on public.community_maps
for each row execute function public.set_community_map_updated_at();

alter table public.community_maps enable row level security;
alter table public.community_map_collaborators enable row level security;
alter table public.community_map_versions enable row level security;
alter table public.community_map_assets enable row level security;

grant select on public.community_maps, public.community_map_collaborators, public.community_map_versions, public.community_map_assets to anon;
grant select, insert, update, delete on public.community_maps, public.community_map_collaborators, public.community_map_versions, public.community_map_assets to authenticated;

create policy "published maps are discoverable"
on public.community_maps for select to anon, authenticated
using (
  (lifecycle = 'published' and visibility in ('public', 'unlisted'))
  or owner_id = (select auth.uid())
  or exists (
    select 1 from public.community_map_collaborators c
    where c.map_id = community_maps.id and c.user_id = (select auth.uid())
  )
);

create policy "authenticated users create owned maps"
on public.community_maps for insert to authenticated
with check ((select auth.uid()) is not null and owner_id = (select auth.uid()));

create policy "owners update maps"
on public.community_maps for update to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

create policy "owners delete maps"
on public.community_maps for delete to authenticated
using (owner_id = (select auth.uid()));

create policy "map participants read collaborators"
on public.community_map_collaborators for select to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1 from public.community_maps m
    where m.id = community_map_collaborators.map_id and m.owner_id = (select auth.uid())
  )
);

create policy "owners manage collaborators"
on public.community_map_collaborators for all to authenticated
using (
  exists (
    select 1 from public.community_maps m
    where m.id = community_map_collaborators.map_id and m.owner_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from public.community_maps m
    where m.id = community_map_collaborators.map_id and m.owner_id = (select auth.uid())
  )
);

create policy "read permitted map versions"
on public.community_map_versions for select to anon, authenticated
using (
  exists (
    select 1 from public.community_maps m
    where m.id = community_map_versions.map_id
      and (
        (m.lifecycle = 'published' and m.visibility in ('public', 'unlisted') and community_map_versions.is_published)
        or m.owner_id = (select auth.uid())
        or exists (
          select 1 from public.community_map_collaborators c
          where c.map_id = m.id and c.user_id = (select auth.uid())
        )
      )
  )
);

create policy "editors create map versions"
on public.community_map_versions for insert to authenticated
with check (
  created_by = (select auth.uid())
  and exists (
    select 1 from public.community_maps m
    where m.id = community_map_versions.map_id
      and (
        m.owner_id = (select auth.uid())
        or exists (
          select 1 from public.community_map_collaborators c
          where c.map_id = m.id and c.user_id = (select auth.uid()) and c.role = 'editor'
        )
      )
  )
);

create policy "owners delete map versions"
on public.community_map_versions for delete to authenticated
using (
  exists (
    select 1 from public.community_maps m
    where m.id = community_map_versions.map_id and m.owner_id = (select auth.uid())
  )
);

create policy "read permitted map asset metadata"
on public.community_map_assets for select to anon, authenticated
using (
  exists (
    select 1 from public.community_maps m
    where m.id = community_map_assets.map_id
      and (
        (m.lifecycle = 'published' and m.visibility in ('public', 'unlisted'))
        or m.owner_id = (select auth.uid())
        or exists (
          select 1 from public.community_map_collaborators c
          where c.map_id = m.id and c.user_id = (select auth.uid())
        )
      )
  )
);

create policy "editors register owned map assets"
on public.community_map_assets for insert to authenticated
with check (
  owner_id = (select auth.uid())
  and exists (
    select 1 from public.community_maps m
    where m.id = community_map_assets.map_id
      and (
        m.owner_id = (select auth.uid())
        or exists (
          select 1 from public.community_map_collaborators c
          where c.map_id = m.id and c.user_id = (select auth.uid()) and c.role = 'editor'
        )
      )
  )
);

create policy "asset owners delete metadata"
on public.community_map_assets for delete to authenticated
using (owner_id = (select auth.uid()));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('community-map-assets', 'community-map-assets', false, 134217728, array['model/gltf-binary'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "participants download permitted map assets"
on storage.objects for select to anon, authenticated
using (
  bucket_id = 'community-map-assets'
  and exists (
    select 1 from public.community_maps m
    where m.id::text = (storage.foldername(name))[2]
      and (
        (m.lifecycle = 'published' and m.visibility in ('public', 'unlisted'))
        or m.owner_id = (select auth.uid())
        or exists (
          select 1 from public.community_map_collaborators c
          where c.map_id = m.id and c.user_id = (select auth.uid())
        )
      )
  )
);

create policy "users upload assets to editable maps"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'community-map-assets'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1 from public.community_maps m
    where m.id::text = (storage.foldername(name))[2]
      and (
        m.owner_id = (select auth.uid())
        or exists (
          select 1 from public.community_map_collaborators c
          where c.map_id = m.id and c.user_id = (select auth.uid()) and c.role = 'editor'
        )
      )
  )
);

create policy "users update owned map assets"
on storage.objects for update to authenticated
using (bucket_id = 'community-map-assets' and owner_id = (select auth.uid())::text)
with check (bucket_id = 'community-map-assets' and owner_id = (select auth.uid())::text);

create policy "users delete owned map assets"
on storage.objects for delete to authenticated
using (bucket_id = 'community-map-assets' and owner_id = (select auth.uid())::text);
