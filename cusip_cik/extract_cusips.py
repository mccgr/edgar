import pandas as pd
import requests
from bs4 import BeautifulSoup
import psycopg2
import re

page = requests.get('https://www.sec.gov/Archives/edgar/data/315066/000031506618001444/filing.txt')
soup = BeautifulSoup(page.content, 'html.parser')
text = soup.getText()
lines = pd.Series(text.split('\n'))

cusip_hdr = r'CUSIP\s+(?:No\.|#|Number):?'
cusip_fmt = r'[0-9A-Z]{1,3}[\s-]?[0-9A-Z]{3}[\s-]?[0-9A-Z]{2}[\s-]?\d{1}'

conn = psycopg2.connect(database = os.getenv('PGDATABASE'), host = os.getenv('PGHOST'), user = os.getenv('PGUSER'), password = os.getenv('PGPASSWORD'))

is_hdr = lines.str.match(cusip_hdr)
is_fmt = lines.str.match(cusip_hdr)

is_a = re.search(cusip_hdr + '\s+' + cusip_fmt , text)
is_d = re.search(cusip_fmt + r'\s+(?:[_-]{9,})?\s*\(CUSIP Number\)', text)
if(is_a is not None):
    Format = 'A'
    match = is_a.group(0)
    cusip = re.search(cusip_fmt, match).group(0)
elif(is_d is not None):
    Format = 'D'
    match = is_d.group(0)
    cusip = re.search(cusip_fmt, match).group(0)
