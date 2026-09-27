-- AdmitCrew / milestone 1. Run ONCE in a new Supabase project's SQL Editor.
-- This transaction intentionally fails if these tables already exist.
begin;

create table public.programs (
    id uuid primary key default gen_random_uuid(),
    university text not null check (length(trim(university)) > 0),
    country text not null,
    program text not null,
    fee_display text not null,
    deadline date not null,
    min_marks numeric(5,2) not null check (min_marks between 0 and 100),
    min_ielts numeric(2,1) not null check (min_ielts between 0 and 9),
    required_documents text[] not null,
    is_practice_data boolean not null default true,
    created_at timestamptz not null default now(),
    unique (university, program)
);

create table public.leads (
    id uuid primary key default gen_random_uuid(),
    name text not null check (length(trim(name)) between 2 and 100),
    phone_normalized text not null unique check (phone_normalized ~ '^[1-9][0-9]{9,14}$'),
    country text,
    marks numeric(5,2) check (marks between 0 and 100),
    ielts numeric(2,1) check (ielts between 0 and 9),
    budget text,
    last_reply_at timestamptz not null default now(),
    intake_stage text not null default 'collecting' check (intake_stage in ('collecting', 'complete')),
    is_test_data boolean not null default false,
    created_at timestamptz not null default now()
);

-- Pakistani local numbers and their international forms share one identity.
-- Other countries must be entered with their country code.
create function public.normalize_lead_phone() returns trigger
language plpgsql set search_path = '' as $$
declare phone text;
begin
    phone := regexp_replace(new.phone_normalized, '[^0-9]', '', 'g');
    if left(phone, 2) = '00' then phone := substring(phone from 3); end if;
    if left(phone, 2) = '03' and length(phone) = 11 then
        phone := '92' || substring(phone from 2);
    end if;
    new.phone_normalized := phone;
    return new;
end;
$$;
create trigger normalize_phone before insert or update of phone_normalized
on public.leads for each row execute function public.normalize_lead_phone();

create table public.messages (
    id uuid primary key default gen_random_uuid(),
    lead_id uuid not null references public.leads(id) on delete restrict,
    direction text not null check (direction in ('inbound', 'outbound')),
    content text not null check (length(trim(content)) between 1 and 12000),
    agent_name text,
    status text not null default 'pending_approval'
        check (status in ('received', 'pending_approval', 'approved', 'rejected', 'sent', 'failed')),
    -- Reuse this key when retrying creation of the SAME draft.
    idempotency_key text unique,
    created_at timestamptz not null default now(),
    approved_at timestamptz,
    approved_by text,
    sent_at timestamptz,
    check (
        (direction = 'inbound' and status = 'received' and approved_at is null and approved_by is null and sent_at is null)
        or (direction = 'outbound' and (
            (status in ('pending_approval','rejected') and approved_at is null and approved_by is null and sent_at is null)
            or (status in ('approved','failed') and approved_at is not null and length(trim(approved_by)) > 0 and approved_by is not null and sent_at is null)
            or (status = 'sent' and approved_at is not null and approved_by is not null and length(trim(approved_by)) > 0 and sent_at is not null)
        ))
    ),
    check (sent_at is null or sent_at >= approved_at)
);

-- An approval applies to the exact text and recipient reviewed.
-- Staff authentication will live in the Python app in the next milestone.
-- This trigger enforces state order; it does not authenticate a staff member.
create function public.guard_message_transition() returns trigger
language plpgsql set search_path = '' as $$
begin
    if tg_op = 'INSERT' then
        if new.status not in ('received','pending_approval') then
            raise exception 'New messages must be received or pending approval';
        end if;
        return new;
    end if;
    if new.id is distinct from old.id or new.lead_id is distinct from old.lead_id
       or new.direction is distinct from old.direction or new.created_at is distinct from old.created_at
       or new.idempotency_key is distinct from old.idempotency_key or new.agent_name is distinct from old.agent_name then
        raise exception 'Message identity is immutable';
    end if;
    if old.status in ('received','rejected','sent') then
        if new is distinct from old then raise exception 'Final messages are immutable'; end if;
        return new;
    end if;
    if old.status in ('approved','failed') and
       (new.content is distinct from old.content or new.approved_at is distinct from old.approved_at
        or new.approved_by is distinct from old.approved_by) then
        raise exception 'Create a new draft when changing an approved message';
    end if;
    if new.status = old.status then return new; end if;
    if old.status = 'pending_approval' and new.status in ('approved','rejected') then return new; end if;
    if old.status = 'approved' and new.status in ('sent','failed') then return new; end if;
    if old.status = 'failed' and new.status = 'approved' then return new; end if;
    raise exception 'Invalid message transition: % -> %', old.status, new.status;
end;
$$;
create trigger message_transition before insert or update on public.messages
for each row execute function public.guard_message_transition();

create index messages_pending_idx on public.messages(created_at) where status = 'pending_approval';
create index messages_lead_history_idx on public.messages(lead_id, created_at);
create index leads_last_reply_idx on public.leads(last_reply_at);

-- All database access is through the trusted Python backend for now.
-- Browser clients get no access, even when signed in. Add scoped policies
-- alongside staff authentication later; never expose the backend secret key.
alter table public.programs enable row level security;
alter table public.leads enable row level security;
alter table public.messages enable row level security;
revoke all on table public.programs, public.leads, public.messages from anon, authenticated;
grant select, insert, update, delete on table public.programs, public.leads, public.messages to service_role;
revoke execute on function public.normalize_lead_phone() from public, anon, authenticated;
revoke execute on function public.guard_message_transition() from public, anon, authenticated;
grant execute on function public.normalize_lead_phone(), public.guard_message_transition() to service_role;
commit;
