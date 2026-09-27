"""Package shareable source and fictional PDFs; exclude credentials and user data."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root=Path(__file__).resolve().parents[1]
files=['app.py','agents.py','repository.py','student_auth.py','programs.json',
       'requirements.txt','requirements-dev.txt','README.md','VERIFICATION.md',
       'start.ps1','.env.example','.gitignore']
for folder in ['static','supabase','scripts','tests','output/pdf']:
    files.extend(str(p.relative_to(root)) for p in (root/folder).rglob('*')
                 if p.is_file() and '__pycache__' not in p.parts)
with ZipFile(root/'output'/'AdmitCrew-source.zip','w',ZIP_DEFLATED) as archive:
    for file in files: archive.write(root/file,'AdmitCrew/'+file)
print(f'Packaged {len(files)} files. Credentials and user data excluded.')
