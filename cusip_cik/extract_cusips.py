import pandas as pd
import requests
from bs4 import BeautifulSoup
import psycopg2
import re

def get_index_file(file_name): 
    
    # This is a Python version of the function of the same name in scrape_filing_doc_functions.R
    
    regex = "/(\\d+)/(\\d{10}-\\d{2}-\\d{6})"
    matches = re.findall(regex, file_name)[0]
    
    cik = matches[0]
    acc_no = matches[1]
    
    path = re.sub("[^\\d]", "", acc_no)
    
    url = "https://www.sec.gov/Archives/edgar/data/" + cik + "/" + path + "/" + acc_no + "-index.htm"
    
    return(url)
    

def get_filing_document_url(file_name, document): 
    
    # This is a Python version of the function of the same name in forms_345_xml_functions.R
    
    regex = "/(\\d+)/(\\d{10}-\\d{2}-\\d{6})"
    matches = re.findall(regex, file_name)[0]
    
    cik = matches[0]
    acc_no = matches[1]
    
    path = re.sub("[^\\d]", "", acc_no)
    
    url = "https://www.sec.gov/Archives/edgar/data/" + cik + "/" + path + "/" + document
    
    return(url)
    
    
def get_filing_txt_url(file_name): 
    
    # This is a Python version of the function of the same name in scrape_filing_doc_functions.R
    
    regex = "/(\\d+)/(\\d{10}-\\d{2}-\\d{6})"
    matches = re.findall(regex, file_name)[0]
    
    cik = matches[0]
    acc_no = matches[1]
    
    path = re.sub("[^\\d]", "", acc_no)
    
    url = "https://www.sec.gov/Archives/edgar/data/" + cik + "/" + path + "/" + acc_no + ".txt"
    
    return(url)    


def get_filing_list(engine, num_files = None):
    
    inspector = inspect(engine)
    
    
    if('cusip_cik' in inspector.get_table_names(schema = 'edgar')):
        
        sql = """
              SELECT a.file_name FROM edgar.filings AS a
              LEFT JOIN edgar.cusip_cik AS b
              ON a.file_name = b.file_name
              WHERE b.file_name IS NULL
              """
        
        
    else:
        sql = """
              SELECT file_name FROM edgar.filings
              WHERE form_type IN ('SC 13G', 'SC 13G/A', 'SC 13D', 'SC 13D/A')
              """
        
    if(num_files is not None):
        
        if(type(num_files) == int):
            
            if(num_files > 0):
                sql = sql + 'LIMIT ' + str(num_files)
                
            else: 
                raise ValueError("num_files must be a positive integer")
            
        else:
            raise TypeError("num_files must be of type int or None")
        
    df = pd.read_sql(sql, engine)
    
    return(df)
    
    
def get_cusip_cik(file_name, document):
    
    url = get_file_document_url(file_name, document)
    page = requests.get(url)
    soup = BeautifulSoup(page.content, 'html.parser')
    text = soup.getText()
    
    cusip_hdr = r'CUSIP\s+(?:No\.|#|Number):?'
    cusip_fmt = r'([0-9A-Z]{1,3}[\s-]?[0-9A-Z]{3,5}[\s-]?[0-9A-Z]{2}[\s-]?[0-9A-Z]{1}|' \
                + '[0-9A-Z]{4,6}[\s-]?[0-9A-Z]{2}[\s-]?[0-9A-Z]{1})'
    
    regex_dict = {'A': cusip_hdr + '[\t\r\n\s]+' + cusip_fmt,
                  'B': cusip_fmt + r'[\n]?[_-]?\s+(?:[_-]{9,})?[\s\r\t\n]*\(CUSIP Number\)',
                  'C': cusip_fmt + '[\s\t\r]*[\n]?' + '[\s\t\r]*\(CUSIP Number of Class of Securities\)'
                 }
    
    df_list = []
    
    for key, regex in regex_dict.items():

        matches = re.findall(regex, text)

        cusips = [re.sub('[^0-9A-Z]', '', re.search(cusip_fmt, match).group(0)) for match in matches]

        if(len(cusips)):
            df = pd.DataFrame({'cusip': cusips})
            df['format'] = key
            df['file_name'] = file_name
            df = df[["file_name", "cusip", "format"]]

        else:
            df = pd.DataFrame({"file_name": [], "cusip": [], "format": []})

        df_list.append(df)
        
    
    full_df = pd.concat(df_list)
    
    
    formats = full_df.groupby('cusip').apply(lambda x: ''.join(x['format'].unique().tolist()))
    
    full_df['formats'] = full_df['cusip'].apply(lambda x: formats[x])
    
    full_df = full_df[['file_name', 'cusip', 'formats']]
    
    full_df = full_df.drop_duplicates()
    
    return(full_df)







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
