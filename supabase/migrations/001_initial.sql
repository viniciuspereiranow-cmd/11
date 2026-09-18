create extension if not exists pgcrypto;
create extension if not exists btree_gist;

create table if not exists public.professionals (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  active boolean not null default true,
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  professional_id uuid references public.professionals(id) on delete set null,
  name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  email text,
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  duration_minutes integer not null default 30 check (duration_minutes > 0),
  price numeric(12,2) not null default 0 check (price >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create type public.appointment_status as enum (
  'scheduled',
  'confirmed',
  'in_progress',
  'completed',
  'cancelled',
  'no_show'
);

create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete restrict,
  professional_id uuid not null references public.professionals(id) on delete restrict,
  service_id uuid references public.services(id) on delete set null,
  appointment_date date not null,
  start_time time not null,
  end_time time not null,
  notes text,
  status public.appointment_status not null default 'scheduled',
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint appointment_time_order check (end_time > start_time)
);

create table if not exists public.app_settings (
  id boolean primary key default true,
  access_code_hash text not null,
  opening_time time not null default '08:00',
  closing_time time not null default '18:00',
  slot_minutes integer not null default 30 check (slot_minutes in (15, 30, 60)),
  updated_at timestamptz not null default now(),
  constraint only_one_settings_row check (id)
);

create table if not exists public.access_grants (
  user_id uuid primary key references auth.users(id) on delete cascade,
  granted_at timestamptz not null default now()
);

insert into public.professionals (name, display_order)
values
  ('Marina', 1),
  ('Jéssica', 2),
  ('Gabrielle Cardoso', 3),
  ('Ana Clara', 4)
on conflict (name) do update set active = true, display_order = excluded.display_order;

insert into public.app_settings (id, access_code_hash)
values (true, encode(digest('12345678p', 'sha256'), 'hex'))
on conflict (id) do nothing;

create or replace function public.is_authorized()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.access_grants
    where user_id = auth.uid()
  );
$$;

create or replace function public.verify_access_code(p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  ok boolean;
begin
  select access_code_hash = encode(digest(trim(p_code), 'sha256'), 'hex')
  into ok
  from public.app_settings
  where id = true;

  return coalesce(ok, false);
end;
$$;

create or replace function public.grant_access(p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  ok boolean;
begin
  ok := public.verify_access_code(p_code);
  if not ok then
    return false;
  end if;

  insert into public.access_grants (user_id)
  values (auth.uid())
  on conflict (user_id) do nothing;

  return true;
end;
$$;

create or replace function public.update_access_code(p_current_code text, p_new_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_authorized() then
    raise exception 'not_authorized';
  end if;

  if length(trim(p_new_code)) < 4 then
    raise exception 'access_code_too_short';
  end if;

  if not public.verify_access_code(p_current_code) then
    raise exception 'invalid_current_code';
  end if;

  update public.app_settings
  set access_code_hash = encode(digest(trim(p_new_code), 'sha256'), 'hex'),
      updated_at = now()
  where id = true;

  return true;
end;
$$;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists professionals_updated_at on public.professionals;
create trigger professionals_updated_at before update on public.professionals
for each row execute function public.touch_updated_at();

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at before update on public.profiles
for each row execute function public.touch_updated_at();

drop trigger if exists customers_updated_at on public.customers;
create trigger customers_updated_at before update on public.customers
for each row execute function public.touch_updated_at();

drop trigger if exists services_updated_at on public.services;
create trigger services_updated_at before update on public.services
for each row execute function public.touch_updated_at();

drop trigger if exists appointments_updated_at on public.appointments;
create trigger appointments_updated_at before update on public.appointments
for each row execute function public.touch_updated_at();

create or replace function public.prevent_appointment_overlap()
returns trigger
language plpgsql
as $$
begin
  if new.status <> 'cancelled' then
    if exists (
      select 1
      from public.appointments a
      where a.professional_id = new.professional_id
        and a.appointment_date = new.appointment_date
        and a.status <> 'cancelled'
        and a.id <> new.id
        and tsrange(
          (a.appointment_date::text || ' ' || a.start_time::text)::timestamp,
          (a.appointment_date::text || ' ' || a.end_time::text)::timestamp,
          '[)'
        ) &&
        tsrange(
          (new.appointment_date::text || ' ' || new.start_time::text)::timestamp,
          (new.appointment_date::text || ' ' || new.end_time::text)::timestamp,
          '[)'
        )
    ) then
      raise exception 'appointment_conflict';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists appointments_no_overlap on public.appointments;
create trigger appointments_no_overlap
before insert or update on public.appointments
for each row execute function public.prevent_appointment_overlap();

alter table public.professionals enable row level security;
alter table public.profiles enable row level security;
alter table public.customers enable row level security;
alter table public.services enable row level security;
alter table public.appointments enable row level security;
alter table public.app_settings enable row level security;
alter table public.access_grants enable row level security;

drop policy if exists "professionals shared read" on public.professionals;
create policy "professionals shared read" on public.professionals
for select to authenticated using (public.is_authorized());

drop policy if exists "professionals shared write" on public.professionals;
create policy "professionals shared write" on public.professionals
for all to authenticated using (public.is_authorized()) with check (public.is_authorized());

drop policy if exists "profiles shared read" on public.profiles;
create policy "profiles shared read" on public.profiles
for select to authenticated using (public.is_authorized());

drop policy if exists "profiles self write" on public.profiles;
create policy "profiles self write" on public.profiles
for all to authenticated using (id = auth.uid() and public.is_authorized())
with check (id = auth.uid() and public.is_authorized());

drop policy if exists "customers shared" on public.customers;
create policy "customers shared" on public.customers
for all to authenticated using (public.is_authorized()) with check (public.is_authorized());

drop policy if exists "services shared" on public.services;
create policy "services shared" on public.services
for all to authenticated using (public.is_authorized()) with check (public.is_authorized());

drop policy if exists "appointments shared" on public.appointments;
create policy "appointments shared" on public.appointments
for all to authenticated using (public.is_authorized()) with check (public.is_authorized());

drop policy if exists "settings read" on public.app_settings;
create policy "settings read" on public.app_settings
for select to authenticated using (public.is_authorized());

drop policy if exists "access grants self" on public.access_grants;
create policy "access grants self" on public.access_grants
for select to authenticated using (user_id = auth.uid());

grant execute on function public.verify_access_code(text) to anon, authenticated;
grant execute on function public.grant_access(text) to anon, authenticated;
grant execute on function public.update_access_code(text, text) to authenticated;
