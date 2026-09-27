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
