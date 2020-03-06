import os
import pandas as pd
import requests
import re
from sqlalchemy import create_engine

dbname = os.getenv("PGDATABASE")

host = os.getenv("PGHOST", "localhost")

conn_string = "postgresql://" + host + "/" + dbname

engine = create_engine(conn_string)

page = requests.get('https://www.sec.gov/Archives/edgar/cik-lookup-data.txt')
text = page.text

text = text.strip('\n') # Strip any redundant newlines at beginning and end
lines = text.split('\n')
lines = [l.rstrip(':') for l in lines]

company_names = []
ciks = []

for line in lines:
    
    search = re.search(':[0-9]{10}$', line)
    ciks.append(int(search.group(0).lstrip(':')))
    company_names.append(line[:search.start()])
 

ciks_df = pd.DataFrame({'cik': ciks, 'company_name': company_names})

ciks_df.to_sql('ciks', engine, schema="edgar", if_exists="replace", index=False) # Write data to table, replacing old table

# Finally, set ownership and access

engine.execute("ALTER TABLE edgar.ciks OWNER TO edgar")
engine.execute("GRANT SELECT ON TABLE edgar.ciks TO edgar_access")

engine.dispose()




