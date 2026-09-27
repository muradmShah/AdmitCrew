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


-- FICTIONAL PRACTICE DATA. Fees and dates are not real admissions advice.
-- Repeatable: does not overwrite existing records or reset follow-up timestamps.
begin;
insert into public.programs
(university, country, program, fee_display, deadline, min_marks, min_ielts, required_documents)
values
('University of Manchester', 'UK', 'BSc Computer Science', '£32,000', '2027-01-15', 75, 6.5, array['Passport','transcript','IELTS']),
('University of Leeds', 'UK', 'BSc Business Management', '£27,000', '2027-01-31', 70, 6.5, array['Passport','transcript','IELTS','personal statement']),
('University of Toronto', 'Canada', 'BSc Computer Science', 'CAD 60,000', '2027-01-15', 80, 6.5, array['Passport','transcript','IELTS']),
('TU Munich', 'Germany', 'BSc Informatics', 'No tuition (about €150 a term)', '2027-07-15', 70, 6.5, array['Passport','transcript','IELTS']),
('Monash University', 'Australia', 'Bachelor of IT', 'AUD 48,000', '2026-11-30', 70, 6.0, array['Passport','transcript','IELTS']),
('Northbridge Practice University', 'UK', 'BSc Data Science', '£24,000', '2027-02-15', 70, 6.0, array['Passport','transcript','IELTS']),
('Westhaven Practice College', 'UK', 'BA Design', '£19,000', '2027-03-01', 65, 6.0, array['Passport','transcript','IELTS','portfolio']),
('Rivergate Practice University', 'UK', 'BEng Engineering', '£26,000', '2027-02-28', 75, 6.5, array['Passport','transcript','IELTS']),
('Maplefield Practice University', 'Canada', 'BBA Business', 'CAD 32,000', '2027-03-15', 70, 6.5, array['Passport','transcript','IELTS']),
('Lakeshore Practice College', 'Canada', 'BSc Computing', 'CAD 35,000', '2027-04-01', 75, 6.0, array['Passport','transcript','IELTS']),
('Cedarview Practice University', 'Canada', 'BA Economics', 'CAD 30,000', '2027-02-01', 70, 6.5, array['Passport','transcript','IELTS']),
('Rheinpark Practice Institute', 'Germany', 'BSc Software Engineering', '€6,000', '2027-06-15', 70, 6.0, array['Passport','transcript','IELTS']),
('Elmburg Practice University', 'Germany', 'BSc Mathematics', '€4,000', '2027-07-01', 75, 6.5, array['Passport','transcript','IELTS']),
('Harborlight Practice University', 'Australia', 'Bachelor of Business', 'AUD 36,000', '2027-01-10', 65, 6.0, array['Passport','transcript','IELTS']),
('Southernvale Practice College', 'Australia', 'Bachelor of Design', 'AUD 34,000', '2026-12-15', 65, 6.0, array['Passport','transcript','IELTS','portfolio'])
on conflict (university, program) do nothing;

insert into public.leads
(name, phone_normalized, country, marks, ielts, last_reply_at, intake_stage, is_test_data)
values
('Ali Khan', '0301 2345678', 'UK', 78, 6.5, now(), 'collecting', true),
('Ayesha Noor', '0333 9876543', 'Canada', 85, 7.0, now(), 'collecting', true),
('Hamza Iqbal', '0346 2223344', 'UK', 69, null, now() - interval '4 days', 'collecting', true)
on conflict (phone_normalized) do nothing;
commit;


-- Run once AFTER 001 and 002. Adds the full app's records and atomic demo delivery.
begin;
alter table public.leads drop constraint leads_intake_stage_check;
alter table public.leads add constraint leads_intake_stage_check check (intake_stage in ('collecting','complete','name','country','marks','ielts','budget'));
create table public.document_checks (
 id uuid primary key default gen_random_uuid(), lead_id uuid not null references public.leads(id),
 filename text not null, document_type text not null, extracted_fields jsonb not null,
 result text not null check(result in ('OK','Problem')), reasons jsonb not null,
 summary text not null, created_at timestamptz not null default now()
);
create table public.activity_log (
 id uuid primary key default gen_random_uuid(), lead_id uuid references public.leads(id),
 agent_name text not null, action text not null, created_at timestamptz not null default now()
);
create table public.escalations (
 id uuid primary key default gen_random_uuid(), lead_id uuid not null references public.leads(id),
 question text not null, reason text not null, status text not null default 'open' check(status in ('open','resolved')),
 created_at timestamptz not null default now()
);
alter table public.document_checks enable row level security;
alter table public.activity_log enable row level security;
alter table public.escalations enable row level security;
revoke all on public.document_checks, public.activity_log, public.escalations from anon,authenticated;
grant select,insert,update,delete on public.document_checks, public.activity_log, public.escalations to service_role;
create index documents_lead_idx on public.document_checks(lead_id);
create index escalations_lead_idx on public.escalations(lead_id);
create function public.approve_and_deliver(message_id uuid, reviewed_content text, staff_name text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare msg public.messages;
begin
 select * into msg from public.messages where id=message_id for update;
 if not found then raise exception 'Message not found'; end if;
 if msg.status <> 'pending_approval' then return jsonb_build_object('changed',false,'status',msg.status); end if;
 if length(trim(reviewed_content)) not between 1 and 12000 or length(trim(staff_name))=0 then raise exception 'Invalid approval'; end if;
 update public.messages set content=reviewed_content,status='approved',approved_at=now(),approved_by=staff_name where id=message_id;
 update public.messages set status='sent',sent_at=now() where id=message_id;
 insert into public.activity_log(lead_id,agent_name,action) values(msg.lead_id,'Staff','Approved and delivered message '||message_id);
 return jsonb_build_object('changed',true,'status','sent');
end;
$$;
revoke execute on function public.approve_and_deliver(uuid,text,text) from public,anon,authenticated;
grant execute on function public.approve_and_deliver(uuid,text,text) to service_role;
commit;


-- Apply once after 004_app.sql. Backend-only accounts; no public hash access.
begin;
create table public.student_accounts (
 id uuid primary key default gen_random_uuid(),
 lead_id uuid not null unique references public.leads(id),
 email text not null unique check(email=lower(trim(email))),
 password_hash text not null,
 created_at timestamptz not null default now()
);
alter table public.student_accounts enable row level security;
revoke all on public.student_accounts from anon,authenticated;
grant select,insert,update on public.student_accounts to service_role;
create function public.register_student_account(student_name text, student_email text, student_phone text, encoded_password text, destination text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare student_id uuid;
begin
 insert into public.leads(name,phone_normalized,country,intake_stage,is_test_data)
 values(student_name,student_phone,destination,'marks',false) returning id into student_id;
 insert into public.student_accounts(lead_id,email,password_hash) values(student_id,lower(trim(student_email)),encoded_password);
 insert into public.messages(lead_id,direction,content,agent_name,idempotency_key)
 values(student_id,'outbound','Welcome, '||student_name||'. Your account is ready. What is your percentage of marks?','Intake','welcome:'||student_id);
 insert into public.activity_log(lead_id,agent_name,action) values(student_id,'Intake','Student account created. Welcome reply awaits staff approval.');
 return jsonb_build_object('lead_id',student_id);
end;
$$;
revoke execute on function public.register_student_account(text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.register_student_account(text,text,text,text,text) to service_role;
commit;


-- Run after schema and seed. All temporary writes are rolled back.
-- On an error, execute ROLLBACK before running again.
begin;
do $$
declare student uuid; draft uuid; blocked boolean;
begin
    if (select count(*) from public.programs where is_practice_data) < 15 then
        raise exception 'Expected at least 15 practice programs';
    end if;
    if (select count(distinct country) from public.programs where is_practice_data) < 3 then
        raise exception 'Expected at least 3 countries';
    end if;
    if (select count(*) from public.leads where phone_normalized in ('923012345678','923339876543','923462223344')) <> 3 then
        raise exception 'Expected the three test students';
    end if;
    if not exists(select 1 from public.programs where university='University of Manchester'
        and program='BSc Computer Science' and fee_display='£32,000' and deadline='2027-01-15'
        and min_marks=75 and min_ielts=6.5 and required_documents=array['Passport','transcript','IELTS']) then
        raise exception 'Manchester data does not match the brief';
    end if;
    select id into student from public.leads where phone_normalized='923012345678';
    blocked := false;
    begin
        insert into public.leads(name,phone_normalized) values('Duplicate Ali','+92 301 2345678');
    exception when unique_violation then blocked := true;
    end;
    if not blocked then raise exception 'Duplicate number was not rejected'; end if;
    blocked := false;
    begin
        insert into public.leads(name,phone_normalized) values('Duplicate Ali','0092 301 2345678');
    exception when unique_violation then blocked := true;
    end;
    if not blocked then raise exception 'International prefix was not normalized'; end if;

    insert into public.leads(name,phone_normalized,country) values('Ali Khan','0301 2345678','UK')
    on conflict(phone_normalized) do update set country=excluded.country;
    if (select count(*) from public.leads where phone_normalized='923012345678') <> 1 then
        raise exception 'Upsert created a duplicate';
    end if;

    insert into public.messages(lead_id,direction,content,agent_name,idempotency_key)
    values(student,'outbound','Practice reply','advisor','qa:' || gen_random_uuid()) returning id into draft;
    if (select status from public.messages where id=draft) <> 'pending_approval' then
        raise exception 'Draft did not start pending';
    end if;
    blocked := false;
    begin
        update public.messages set status='sent',approved_at=now(),approved_by='QA',sent_at=now() where id=draft;
    exception when raise_exception then blocked := true;
    end;
    if not blocked then raise exception 'Draft skipped approval'; end if;
    blocked := false;
    begin
        insert into public.messages(lead_id,direction,content,status,approved_at,approved_by,sent_at)
        values(student,'outbound','Bad insert','sent',now(),'QA',now());
    exception when raise_exception then blocked := true;
    end;
    if not blocked then raise exception 'Insert bypassed approval'; end if;
    blocked := false;
    begin
        update public.messages set status='approved' where id=draft;
    exception when check_violation then blocked := true;
    end;
    if not blocked then raise exception 'Approval metadata was not required'; end if;

    update public.messages set status='approved',approved_at=now(),approved_by='QA staff' where id=draft;
    blocked := false;
    begin
        update public.messages set content='Unreviewed replacement' where id=draft;
    exception when raise_exception then blocked := true;
    end;
    if not blocked then raise exception 'Approved content was mutable'; end if;
    update public.messages set status='sent',sent_at=now() where id=draft;
    blocked := false;
    begin
        update public.messages set status='pending_approval',approved_at=null,approved_by=null,sent_at=null where id=draft;
    exception when raise_exception then blocked := true;
    end;
    if not blocked then raise exception 'Sent message was reopened'; end if;
    blocked := false;
    begin
        insert into public.messages(lead_id,direction,content,idempotency_key)
        select lead_id,direction,content,idempotency_key from public.messages where id=draft;
    exception when unique_violation then blocked := true;
    end;
    if not blocked then raise exception 'Duplicate draft key was accepted'; end if;
    if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname='public' and c.relname in ('programs','leads','messages') and not c.relrowsecurity) then
        raise exception 'RLS is missing';
    end if;
    if has_table_privilege('anon','public.leads','select')
       or has_table_privilege('authenticated','public.messages','insert') then
        raise exception 'Browser roles should not have access';
    end if;
    raise notice 'PASS: seed, normalization, upsert, approval lifecycle, immutable approval, draft deduplication, and access configuration';
end;
$$;
rollback;

