import os
import pandas as pd
import numpy as np
import requests
from bs4 import BeautifulSoup
import re
from codecs import decode
from sqlalchemy import create_engine, inspect
import datetime as dt


def get_index_url(file_name): 
    
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
              WHERE a.form_type IN ('SC 13G', 'SC 13G/A', 'SC 13D', 'SC 13D/A')
              AND b.file_name IS NULL
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
    
    
def exceeded_sec_request_limit(soup):
    
    if(re.search("You’ve Exceeded the SEC’s Traffic Limit", soup.getText())):
        
        return(True)
    
    else:
        return(False)    
    
    
def get_subject_cik_company_name(file_name, soup = None):
    
    if(soup is None):
        
        url = get_filing_txt_url(file_name)
        page = requests.get(url)
        # Following two lines omit source code for added files, pdfs, gifs, etc...
        page_end = re.search(b'</DOCUMENT>', page.content).end() 
        content = page.content[:page_end] + b'\n</SEC-DOCUMENT>'
        soup = BeautifulSoup(content, 'html.parser')
        
        
    if(exceeded_sec_request_limit(soup)):
        
        raise ConnectionRefusedError("Hit SEC's too many requests page. Abort")
        
    try:
        header_tag = soup.find(['IMS-HEADER', 'SEC-HEADER', 'sec-header'])
        text = header_tag.getText()
        subject_company_start = re.search('SUBJECT COMPANY:', repr(text)).start()
        filer_company_start = re.search('FILED BY:', repr(text)).start()
        
        if(subject_company_start < filer_company_start):
            subject_text = decode(re.findall('(SUBJECT COMPANY:.*)FILED BY:', repr(text))[0], 'unicode_escape')
        else:
            subject_text = decode(re.findall('(SUBJECT COMPANY:.*)', repr(text))[0], 'unicode_escape')
            
        cik = int(re.sub('[^\d]*', '', \
                         re.findall('CENTRAL INDEX KEY:[\t\r\n]*(.*)[\t\r\n]', subject_text)[0]))

        company_name = re.sub('[\n\t\r]*', '', \
                                      re.findall('COMPANY CONFORMED NAME:[\t\r\n]*(.*)[\t\r\n]', subject_text)[0])

        company_name = company_name.strip(' ')
        
        return(cik, company_name)
        
    except:
        
        try:
            
            url = get_index_url(file_name)
            page = requests.get(url)
            soup = BeautifulSoup(page.content, 'html.parser')
            
            if(exceeded_sec_request_limit(soup)):
        
                raise ConnectionRefusedError("Hit SEC's too many requests page. Abort")

            subject_regex = "(.*)\(Subject\)|\(SUBJECT\)|\(subject\)(.*)"
            company_nodes = soup.findAll(attrs = {'class': 'companyName'})

            for node in company_nodes:

                if(re.search(subject_regex, node.getText())):

                    subject_node = node
                    break

            lines = subject_node.text.split('\n')
            cik = int(re.sub('[^\d]', '', re.sub('\(see all company filings\)|CIK:', '', lines[1]).strip(' ')))
            company_name = re.sub('\(Subject\)', '', lines[0]).strip(' ')

            return(cik, company_name)
        
        except ConnectionRefusedError:
            
            print("get_subject_cik_company_name failed on second effort due to reaching too many requests page")
            raise
        
        except:
            
            cik = None
            company_name = None
            return(cik, company_name)
        


def calculate_cusip_check_digit(cusip):
    
    values = {'0': 0, '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9,
              'A': 10, 'B':11, 'C': 12, 'D': 13, 'E':14, 'F': 15, 'G': 16, 'H': 17, 'I': 18, 'J': 19,
              'K': 20, 'L': 21, 'M': 22, 'N': 23, 'O': 24, 'P': 25, 'Q': 26, 'R': 27, 'S': 28, 'T': 29,
              'U': 30, 'V': 31, 'W': 32, 'X': 33, 'Y': 34, 'Z': 35, '*': 36, '@': 37, '#': 38
               }
    
    digit_str = ''
    
    if(len(cusip) >= 8):
    
        for i in range(8):

            if(i % 2 == 0):
                digit_str = digit_str + str(values[cusip[i]])
            else:
                digit_str = digit_str + str(2 * values[cusip[i]])

        result = 0

        for i in range(len(digit_str)):

            result = result + int(digit_str[i])

        result = (10 - result) % 10

        return(result)
    
    elif(len(cusip) >= 6):
        
        for i in range(6):

            if(i % 2 == 0):
                digit_str = digit_str + str(values[cusip[i]])
            else:
                digit_str = digit_str + str(2 * values[cusip[i]])

        result = 0

        for i in range(len(digit_str)):

            result = result + int(digit_str[i])

        result = (10 - result) % 10

        return(result)
    
    elif(len(cusip) >= 3):
        
        cusip = '0' * (9 - len(cusip)) + cusip
        
        for i in range(8):

            if(i % 2 == 0):
                digit_str = digit_str + str(values[cusip[i]])
            else:
                digit_str = digit_str + str(2 * values[cusip[i]])

        result = 0

        for i in range(len(digit_str)):

            result = result + int(digit_str[i])

        result = (10 - result) % 10

        return(result)
    
    else:
        
        return(None)


def get_cusip_cik(file_name):
    
    try:
    
        url = get_filing_txt_url(file_name)
        page = requests.get(url)
        # Following three lines omit source code for added files, pdfs, gifs, etc...
        page_end = re.search(b'</DOCUMENT>', page.content).end() 
        content = page.content[:page_end] + b'\n</SEC-DOCUMENT>'
        soup = BeautifulSoup(content, 'html.parser')

        if(exceeded_sec_request_limit(soup)):

            raise ConnectionRefusedError("Hit SEC's too many requests page. Abort")


        cik, company_name = get_subject_cik_company_name(file_name, soup)

        text = soup.getText()

        cusip_hdr = r'CUSIP\s+(?:No\.|NO\.|#|Number|NUMBER):?'
        cusip_fmt = '((?:[0-9A-Z]{1}[ -]{0,3}){6,9})'

        regex_dict = {'A': cusip_fmt + r'[\n]?[_\.-]?\s+(?:[_\.-]{9,})?[\s\r\t\n]*' +  \
        r'\(CUSIP\s+(?:Number|NUMBER|number|Number\s+of\s+Class\s+of\s+Securities|NUMBER\s+OF\s+CLASS\s+OF\s+SECURITIES)\)',
                      'B': cusip_fmt + '[\s\t\r]*[\n]?' + r'[\s\t\r]*' +  \
        r'\(CUSIP\s+(?:Number|NUMBER|number|Number\s+of\s+Class\s+of\s+Securities|NUMBER\s+OF\s+CLASS\s+OF\s+SECURITIES)\)',
                      'C': '[\s_]+' + cusip_hdr + '[ _]{0,50}' + cusip_fmt + '\s+',
                      'D': '[\s_]+' + cusip_hdr + '(?:\n[\s_]{0,50}){1,2}' + cusip_fmt + '\s+'
                     }
                                                  
        df_list = []

        for key, regex in regex_dict.items():

            matches = re.findall(regex, text)

            cusips = [re.sub('[^0-9A-Z]', '', match) for match in matches if len(match) > 0]
            check_digits = [calculate_cusip_check_digit(cusip) for cusip in cusips]

            if(len(cusips)):
                df = pd.DataFrame({'cusip': cusips, 'check_digit': check_digits})
                df['format'] = key
                df['file_name'] = file_name
                df['cik'] = cik
                df['company_name'] = company_name
                df = df[["file_name", "cusip", "cik", "check_digit", "company_name", "format"]]

            else:
                df = pd.DataFrame({"file_name": [], "cusip": [], "cik": [], "check_digit": [], \
                                   "company_name": [], "format": []})

            df_list.append(df)


        full_df = pd.concat(df_list)

        if(full_df.shape[0]):

            formats = full_df.groupby('cusip').apply(lambda x: ''.join(x['format'].unique().tolist()))

            full_df['formats'] = full_df['cusip'].apply(lambda x: formats[x])

            full_df = full_df[['file_name', 'cusip', 'check_digit', 'cik', 'company_name', 'formats']]

            full_df = full_df.drop_duplicates().reset_index(drop = True)

            full_df['cik'] = full_df['cik'].astype(np.int64)
            full_df['check_digit'] = full_df['check_digit'].astype(np.int64)

            return(full_df)

        else:

            full_df = pd.DataFrame({"file_name": [file_name], "cusip": [None], "check_digit": [None], \
                                    "cik": cik, "company_name": company_name, "formats": [None]})
        
        return(full_df)
        
    except ConnectionRefusedError:
        
        raise
        
    except:
        
        return(None)

        

        
def get_cusip_cik_from_list_df(filings_list):
    
    df_list = [get_cusip_cik(file_name) for file_name in filings_list]
    
    df = pd.concat(df_list, ignore_index = True)
    
    num_success = sum(x is not None for x in df_list)
    
    return(df, num_success)


def write_cusip_ciks(filings_list, engine):

    df, num_success = get_cusip_cik_from_list_df(filings_list)
    
    df.to_sql('cusip_cik', engine, schema="edgar", if_exists="append", 
        index=False)
    
    return(num_success)
        
        

dbname = os.getenv("PGDATABASE")
host = os.getenv("PGHOST", "localhost")
conn_string = "postgresql://" + host + "/" + dbname


engine = create_engine(conn_string)

inspector = inspect(engine)

table_exists = 'cusip_cik' in inspector.get_table_names("edgar")

if(not table_exists):
    
    create_tbl_sql = """
             CREATE TABLE edgar.cusip_cik(
             file_name TEXT,
             cusip TEXT,
             check_digit INTEGER,
             cik INTEGER,
             company_name TEXT,
             formats TEXT
             )
          """
    
    
    engine.execute(create_tbl_sql)

file_list = get_filing_list(engine)['file_name'].tolist()

num_filings = len(file_list)

batch_size = 200

num_batches = (num_filings // batch_size) + (num_filings % batch_size > 0)
num_success = 0

t1 = dt.datetime.now()


for i in range(num_batches):
    
    start = i * batch_size
    
    if(i == num_batches - 1):
        
        finish = num_filings 
        
    else:
        
        finish = (i + 1) * batch_size 

    
    num_success = num_success + write_cusip_ciks(file_list[start:finish], engine)
    t2 = dt.datetime.now()
    
    print(str(num_success) + " filings successfully processed out of " + str(finish))
    print("Time taken: " + str(t2 - t1))













