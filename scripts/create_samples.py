"""Create the four fictional PDFs required by the project brief."""
from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor

out=Path(__file__).resolve().parents[1]/'output'/'pdf'
out.mkdir(parents=True,exist_ok=True)
samples=[('passport-a','Passport A','Passport','Ali Khan','Expires: 2030-03-10'),
         ('passport-b','Passport B','Passport','Ali Khan','Expires: 2025-01-01'),
         ('transcript','Transcript','Transcript','Ali Ahmed','Marks: 78'),
         ('ielts','IELTS result','IELTS','Ayesha Noor','Score: 7.0')]
for filename,title,kind,name,detail in samples:
    c=canvas.Canvas(str(out/(filename+'.pdf')),pagesize=(595,420))
    c.setTitle('AdmitCrew fictional training document - '+title)
    c.setFillColor(HexColor('#153e33'));c.rect(0,320,595,100,fill=1,stroke=0)
    c.setFillColor(HexColor('#ffffff'));c.setFont('Helvetica-Bold',23);c.drawString(38,371,'AdmitCrew / '+title)
    c.setFont('Helvetica',11);c.drawString(38,344,'FICTIONAL TRAINING DOCUMENT')
    c.setFillColor(HexColor('#203f32'));c.setFont('Helvetica',16)
    for y,line in zip((278,238,198),('Type: '+kind,'Name: '+name,detail)):c.drawString(38,y,line)
    c.setStrokeColor(HexColor('#dce6df'));c.line(38,148,557,148)
    c.setFont('Helvetica-Bold',12);c.drawString(38,117,'SAMPLE ONLY - NOT VALID FOR IDENTIFICATION')
    c.setFont('Helvetica',10);c.drawString(38,91,'Created for the AI Skool Nowshera admissions project.')
    c.drawString(38,72,'Use only for software testing. This is not an official document.')
    c.save()
print('Created four fictional PDFs in output/pdf.')
