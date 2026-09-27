"""Read-only milestone check: python scripts/check_supabase.py"""
import os
from pathlib import Path

from dotenv import load_dotenv
from supabase import create_client


def main():
    load_dotenv(Path(__file__).resolve().parents[1] / '.env')
    url = os.getenv('SUPABASE_URL', '')
    key = os.getenv('SUPABASE_SECRET_KEY', '')
    if not url.startswith('https://') or not key or 'YOUR_' in url or 'YOUR_' in key:
        raise SystemExit('Copy .env.example to .env and enter your Supabase URL and backend secret key locally.')
    client = create_client(url, key)
    programs = client.table('programs').select('*').execute().data
    leads = client.table('leads').select('id,name,phone_normalized').eq('is_test_data', True).execute().data
    for table in ('messages', 'document_checks', 'activity_log', 'escalations', 'student_accounts'):
        client.table(table).select('id').limit(1).execute()
    countries = {row['country'] for row in programs}
    if len(programs) < 15 or len(countries) < 3:
        raise SystemExit('Practice catalog is incomplete. Run supabase/002_seed.sql.')
    if not {'Ali Khan', 'Ayesha Noor', 'Hamza Iqbal'} <= {row['name'] for row in leads}:
        raise SystemExit('Test students are missing. Run supabase/002_seed.sql.')
    match = next((row for row in programs if row['university'] == 'University of Manchester'
                  and row['program'] == 'BSc Computer Science'), None)
    if match is None:
        raise SystemExit('Manchester program is missing.')
    print(f'Connected. {len(programs)} programs across {len(countries)} countries; test students found.')
    print(f"{match['university']} — {match['program']}")
    print(f"Fee: {match['fee_display']} | Deadline: {match['deadline']}")
    print(f"Minimum marks: {match['min_marks']}% | IELTS: {match['min_ielts']}")
    print('Documents: ' + ', '.join(match['required_documents']))
    print('Read-only check complete. No messages created or sent.')


if __name__ == '__main__':
    main()
