# AdmitCrew verification

Verified on 26 September 2026, using fictional records only.

## Automated application tests: 12 passed

Latest full run: 27 September 2026. Shared student/admin sign-in and role isolation
were added and passed, including rejection of a student token used as a staff cookie.

Run `.\.venv\Scripts\python.exe -m unittest discover -s tests -v`.
Tests use temporary SQLite databases and never alter Supabase.

1. Conversational intake saves all fields; alternate phone formatting reopens the same lead.
2. Manchester, Leeds, and Toronto responses contain exact catalog fees, deadlines, programs, and documents.
3. Unknown university questions create staff escalations; unrelated questions are declined.
4. The supplied prompt-injection message is refused without an acceptance promise.
5. All four generated PDFs have the expected result: valid passport, expired passport,
   mismatched transcript name, and valid IELTS result.
6. Hamza's reminder stays pending until approval. Four concurrent approval attempts
   produce one delivery. Running reminders again does not create a duplicate.
7. Student records, messages, and activity survive reopening the local database;
   replaying a chat request does not create a duplicate message.
8. Unauthenticated callers cannot read the staff workspace or approve drafts.
   Student responses contain only received and delivered messages.
9. Cross-origin mutations and invalid uploads are rejected.
10. Student registration, case-insensitive email sign-in, incorrect-password rejection,
    sign-out, account separation, and exclusion of password hashes from staff data.
11. Invalid sign-ups and duplicate emails/phones leave no orphan student records.

## Supabase SQL: tested locally, not against the user's hosted project

Executed 001, 002, 004, and 003 using PGlite, a local PostgreSQL-compatible runtime,
with the Supabase API roles represented. The original seed was also run twice.
Verified constraints, phone normalization, duplicate prevention, RLS configuration,
anonymous access denial, backend access, and approval-state ordering.

Executed `approve_and_deliver` twice as the backend role: one delivery, unchanged
approved text on the second call. This validates local SQL behavior, not hosted
Supabase API connectivity or actual staff identity.

## Browser: passed in headless Microsoft Edge

Staff login, all navigation screens, student chat, draft invisibility, approval
and subsequent student visibility, expired-passport upload, and 390px mobile layout.
No JavaScript page errors. Screenshots were reviewed locally. All four PDFs were
rendered and inspected for readable, unclipped text.

Student signup was additionally checked on desktop and mobile against an isolated
QA server: confirmation mismatch, successful account creation, sign-out, incorrect
password, and returning sign-in all passed. Migration 005 passed a local PostgreSQL
check including duplicate registration rollback and anonymous account access denial.

`scripts/browser_check.py` reproduces the UI check against a running local demo.
It creates sample activity and expects a fresh demo database and the default password.
Install `requirements-dev.txt` for this optional browser check.

## Not verified / not connected

- The private `.env` contains local admin configuration only. Supabase credentials were not available, so the hosted Supabase project
  was not contacted, migrated, or verified.
- No OpenAI key was available. The live structured-output integration is implemented
  but untested; acceptance tests exercised the deterministic fallback.
- Delivery is a transactional simulated inbox. No WhatsApp, Facebook, SMS, or email
  provider is connected. General scanned-document OCR is not implemented; supplied
  text PDFs are supported.
- This is a loopback-only classroom demonstration. Students now have password accounts;
  fictional profile selection is staff-only. Email verification, password recovery,
and durable sessions across app restarts are not implemented.

## Opportunities slideshow

Verified desktop/mobile layout, previous/next and country controls, keyboard navigation,
pause, reduced-motion default, and destination preselection on sign-up. The four slides
describe subjects from the practice catalog; they do not make visa, scholarship, or
employment promises. Added entrance animations and subtle hover feedback.

## Single-page public website

Verified with scripts/check_home.py: anchor navigation stays on the homepage;
About includes the user-provided four-decade statement; animated counters settle
at 100,000+ and 40+; sign-in and sign-up switch inline; staff login remains at
/staff. Desktop and mobile screenshots were inspected and mobile has no horizontal
overflow. Browser checks reported no JavaScript errors. The business statistics are
user-provided marketing copy, not figures calculated from the practice database.
