import os
import pandas as pd
import numpy as np
import requests
from bs4 import BeautifulSoup
import re
from codecs import decode
from sqlalchemy import create_engine, inspect
import datetime as dt

def get_txt_file_url(file_name):
  
    url = "https://www.sec.gov/Archives/" + file_name
    
    return(url)
  
  
def get_file_path(file_name, document):
    
    url = re.sub("(\\d{10})-(\\d{2})-(\\d{6})\\.txt", "\\1\\2\\3", file_name)
    
    path = url + '/' + document
    
    return(path)  
    
    
def get_file_text_from_directory(file_name, document, directory):

    path = directory + '/' + get_file_path(file_name, document)
    f = open(path, 'r')
    txt = f.read()
    f.close()
    return(txt)
    

def get_main_doc_text_by_url(url):
  
    page = requests.get(url)
    soup = BeautifulSoup(page.content, 'html.parser')
    main_doc_text = soup.find(["document", "DOCUMENT"]).get_text()
    
    return(main_doc_text)
  
  
def get_header(file_name, document, directory):
  
    full_text = get_file_text_from_directory(file_name, document, directory)
    soup = BeautifulSoup(full_text, 'html.parser')
    text = soup.find(["sec-header", "SEC-HEADER"]).get_text()
    
    return(text)  
  
    
def get_main_doc_text(file_name, document, directory):
  
    full_text = get_file_text_from_directory(file_name, document, directory)
    soup = BeautifulSoup(full_text, 'html5lib')
    main_doc_text = soup.find(["document", "DOCUMENT"]).get_text()
    
    return(main_doc_text)
  
    
    
def get_sc_13_dg_doc_text(file_name):
    
    url = get_txt_file_url(file_name)
    page = requests.get(url)
    all_text = page.text
    end = all_text.find('</DOCUMENT>')
    
    soup = BeautifulSoup(all_text[:end], 'html.parser')
    doc_text = soup.text
    return(doc_text)
    
    
def get_soup(file_name):
    
    url = get_txt_file_url(file_name)
    page = requests.get(url)
    all_text = page.text
    end = all_text.find('</DOCUMENT>')
    
    soup = BeautifulSoup(all_text[:end], 'html.parser')
    
    return(soup)
    

def get_file_text(file_name):
    
    soup = get_soup(file_name)
    text = soup.get_text()
    
    # Replace annoying soft hyphens and non-breaking spaces
    
    text = re.sub('\xa0', ' ', text)
    text = re.sub('\xad', '', text)
    
    return(text)    

def find_header_end(text):
    
    return(re.search('(</SEC-HEADER>|</sec-header>)', text.upper()).end())




def find_last_search_start(regex, text):
    
    search = re.search(regex, text)
    
    if(search is None):
        
        return(None)
    
    else:
        
        end = 0
        
        while(search is not None):
            
            start = end + search.start()
            end = end + search.end()
            search = re.search(regex, text[end:])
        
    return(start)
    
    


def find_last_search_end(regex, text):
    
    search = re.search(regex, text)
    
    if(search is None):
        
        return(None)
    
    else:
        
        end = 0
        
        while(search is not None):
            
            end = end + search.end()
            search = re.search(regex, text[end:])
        
    return(end)




def is_rep_q_as_items(text, q1_start = None):
    
    # this function works on the basis that the the actual "items" in the real item section does not go beyond
    # Item 10. So by searching for Item 12 or 14 (in SC 13G and SC 13D respectively), we can detect whether
    # a filer has erroneously labelled the questions in the reporting pages as items
    
    if(q1_start is None):
      
        q1_start = find_orthodox_cover_page_q1_start(text)
    
    if(q1_start == -1):
    
        text_raised = text.upper()
        
        regex = '\n\s*ITEM\s*(\.)?\s*[\(]?\s*1[24]\s*[\)]?(\.)?'
        
        search = re.search(regex, text_raised)
        
        if(search):
            return(True)
        else:
            return(False)
            
    else:
      
        return(False)
        
        


def find_doe_statement_end(file_name):
    
    try:
        url = get_txt_file_url(file_name)
        page = requests.get(url)
        doc_end = page.text.find('</DOCUMENT>')
        soup = BeautifulSoup(page.content[:doc_end], 'html.parser')
        text = soup.get_text().lower()
        
        regex = '[\(]?\s*date\s+of\s+event(.*?\s)*?(?:statement|schedule)\s*[\)]?\s*'
        
        end = find_last_search_end(regex, text)
        
        if(end is not None):
            
            return(end)
        
        else:
            # Use -1 to distinguish cases where regex was not found from other failures
            return(-1)
            
        
    except:
        return(None)
        

def find_name_address_statement_end(file_name):
    
    try:
        url = get_txt_file_url(file_name)
        page = requests.get(url)
        doc_end = page.text.find('</DOCUMENT>')
        soup = BeautifulSoup(page.content[:doc_end], 'html.parser')
        text = soup.get_text().lower()
        
        regex = '[\(]?\s*name(,)?\s*address(.*?\s)*?communications\s*[\)]?\s*'
        
        end = find_last_search_end(regex, text)
        
        if(end is not None):
            
            return(end)
        
        else:
            # Use -1 to distinguish cases where regex was not found from other failures
            return(-1)
            
        
    except:
        return(None)

def is_rep_page_short_form(text):
    
    text_raised = text.upper()
    
    regex_q = '\n\s*[\(\|]?(#)?\s1\s?[\)\|]?\s*[:\.]{0,1}(.)+?' + \
            '[\(\|]?(#)?\s2\s?[\)\|]?\s*[:\.]{0,1}'
    
    search = re.search(regex_q, text_raised, flags = re.DOTALL)
    
    regex_w = '(?:NAME|REPORTING|S\.S\.|I\.R\.S\.|FILING\s+(?:PARTY|PARTIES|PERSON|PERSONS))'
    
    if(re.search(regex_w, text_raised)):
        
        return(False)
    
    else:
        
        return(True)

def get_title_page_end_lower_bound(text, upper_bound = None):
    
    rep_q_as_items = is_rep_q_as_items(text)
    
    if(upper_bound is None):
        upper_bound = get_title_page_end_upper_bound(text)
    
    text_raised = text.upper()[:upper_bound]
    
    if(not rep_q_as_items):
        
        last_search = find_last_search_end('\((?:NAME|CUSIP|SEDOL|DATE|TITLE|AMENDMENT)(.*?\s)*?' + \
                     '(?:ISSUER|SECURITIES|NUMBER|STATEMENT|SCHEDULE|NO\.?|#)\)', text_raised)
        
        if(last_search):
            
            return(last_search)
        
        else:
            return(0)
        
    else:
        
        return(0)

        
        
def get_title_page_end_upper_bound(text, rep_q_as_items = None):
    
    if(rep_q_as_items is None):
        rep_q_as_items = is_rep_q_as_items(text)

    text_raised = text.upper()

    if(rep_q_as_items):

        end = re.search('ITEM\s*[#\.\:]?\s*[\(]?\s*1[24]\s*[\)]?[\.\:]?', text_raised).start()

        regex = 'ITEM\s*[#\.\:]?\s*[\(]?\s*1\s*[\)]?[\.\:]?'

        search = re.search(regex, text_raised[:end])

        return(search.start())

    else:

        regex = '[\(]?\s*1\s*[\)]?\s*[:\.]{0,1}\s*NAME[S]?\s+(OF\s+(?:REPORTING|ABOVE)\s+PERSON[S]?)?' + \
                '(\s*/\s*)?(S\.S\.\s+)?(\s+(?:OR|AND))\s+I\.R\.S\.\s+IDENTIFICATION\s+NO[S]?\.\s+' + \
                '(OF\s+(?:REPORTING|ABOVE)\s+PERSON[S]?)?'     

        search = re.search(regex, text_raised)

        if(search):

            return(search.start())

        else:
            regex = '(?<!DESCRIBED\sIN)\s*ITEM\s*[#\.\:]?\s*[\(]?\s*[0-9]{1,2}\s*' + \
                    '[\)]?[\.\:]?'
            search = re.search(regex, text_raised)

            return(search.start())
   
   
   
def find_orthodox_cover_page_q1_start(text):

    text_raised = text.upper()

    
    regex0 = '\s+[\(\|]?\s*[1L]\s*[\)\|]?\s*[:\.]{0,1}(\s*[\(\|]\s*A\s*[\)\|])?\s*(.){0,50}\s*' + \
             'NAME[\(]?[S]?[\)]?\s+(?:OF|OR)(\s+THE)?\s+(?:REPORTING|ABOVE|REPORT)'
    
    regex1 = '\s+[\(\|]?\s*[1L]\s*[\)\|]?\s*[:\.]{0,1}(\s*[\(\|]\s*A\s*[\)\|])?\s*(.){0,50}\s*' + \
             'NAME[\(]?[S]?[\)]?\s+(?:OF|OR)(\s+THE)?(\s+(?:REPORTING|ABOVE|REPORT))?\s+' + \
             'PERSON[\(]?[S]?[\)]?'

    regex2 = '\s+[\(\|]?\s*[1L]\s*[\)\|]?\s*[:\.]{0,1}(\s*[\(\|]\s*A\s*[\)\|])?\s*(.){0,50}\s*' + \
             'NAME[\(]?[S]?[\)]?\s+(?:AND|OF|OR)(\s+I\.R\.S\.)?\s+IDENTIFICATION\s+NO[\(]?[S]?[\)]?\.'
    
    regex3 = '(NAME[\(]?[S]?[\)]?\s+(?:OF|OR)(\s+THE)?(\s+(?:REPORTING|ABOVE|REPORT))?\s+' + \
             'PERSON[\(]?[S]?[\)]?\s+)?[\(\|]?\s*[1L]\s*[\)\|]?\s*[:\.\|]{0,1}\s*' + \
             'I\.R\.S\.\s+IDENTIFICATION\s+NO[\(]?[S]?[\)]?\.\s+(?:OF|OR)\s+(\s+THE)?ABOVE\s+' + \
             'PERSON[\(]?[S]?[\)]?'
    
    regex4 = '(NAME[\(]?[S]?[\)]?\s+(?:OF|OR)(\s+THE)?(\s+(?:REPORTING|ABOVE|REPORT))?\s+' + \
             'PERSON[\(]?[S]?[\)]?\s+)?[\(\|]?\s*[1L]\s*[\)\|]?\s*[:\.\|]{0,1}\s*S\.S\.\s+OR\s+' + \
             'I\.R\.S\.\s+IDENTIFICATION\s+NO[\(]?[S]?[\)]?\.\s+(?:OF|OR)(\s+THE)?\s+' + \
             'ABOVE\s+PERSON[\(]?[S]?[\)]?'
    
    regex5 = '[\(\|]?\s*[1L]\s*[\)\|]?\s*[:\.]{0,1}(\s*[\(\|]\s*A\s*[\)\|])?\s*' + \
             'NAME[\(]?[S]?[\)]?\s+(?:OF|OR)(\s+THE)?\s+FILING\s+(?:PARTY|PARTIES|PERSON|PERSONS)'
    
    regex6 = 'NAME[\(]?[S]?[\)]?\s+(?:OF|OR)(\s+THE)?(\s+(?:REPORTING|ABOVE|REPORT))?\s+' + \
             'PERSON[\(]?[S]?[\)]?\s+(S\.S\.\s+OR\s+I\.R\.S\.\s+IDENTIFICATION\s+NO[\(]?[S]?[\)]?\.\s+' + \
             '(?:OF|OR)(\s+THE)?\s+ABOVE\s+PERSON[\(]?[S]?[\)]?)?' + \
             '\s+[\(\|]?\s*[1L]\s*[\)\|]?\s*[:\.]{0,1}(\s*[\(\|]\s*A\s*[\)\|])?'
    
    
    regex7 = '\n\s*[\(\|]?\s1\s?[\)\|]?\s*[:\.]{0,1}([A-Z0-9\s\.\(\)_]?)+?' + \
             '[\(\|]?\s2\s?[\)\|]?\s*[:\.]{0,1}([A-Z0-9\s\.\(\)_]?)+?' + \
             '[\(\|]?\s3\s?[\)\|]?\s*[:\.]{0,1}\s+(.)+\s*\(SEC USE ONLY\)'
    
    regex8 = 'NAME[\(]?[S]?[\)]?\s+(?:OF|OR)(\s+THE)?\s+(?:REPORTING|ABOVE|REPORT)'
    
    regex9 = 'NAME[\(]?[S]?[\)]?\s+(?:AND|OF|OR)(\s+I\.R\.S\.)?\s+IDENTIFICATION\s+NO[\(]?[S]?[\)]?.'
    
    
    regex_list = [regex0, regex1, regex2, regex3, regex4, regex5, regex6, regex7, regex8, regex9]
    
    start = None
    
    for i in range(len(regex_list)):
        
        search = re.search(regex_list[i], text_raised)
        
        if(search):
            
            if(start is None):
                
                start = search.start()
                
            else:
                
                new = search.start()
                
                if(new < start):
                    
                    start = new            

    if(start):
        
        return(start)
    
    else:
        
        return(-1)   
            
            
   
def find_cover_page_q1_start(text, rep_q_as_items = None):
    
    if(rep_q_as_items is None):
        rep_q_as_items = is_rep_q_as_items(text)

    text_raised = text.upper()

    if(rep_q_as_items):

        end = re.search('ITEM\s*[#\.\:]?\s*[\(]?\s*1[24]\s*[\)]?[\.\:]?', text_raised).start()

        regex = 'ITEM\s*[#\.\:]?\s*[\(]?\s*1\s*[\)]?[\.\:]?'

        search = re.search(regex, text_raised[:end])

        return(search.start())

    else:
        
        regex0 = '\s+[\(\|]?\s*[1L]\s*[\)\|]?\s*[:\.]{0,1}(\s*[\(\|]\s*A\s*[\)\|])?\s*(.){0,50}\s*' + \
                 'NAME[\(]?[S]?[\)]?\s+(?:OF|OR)(\s+THE)?\s+(?:REPORTING|ABOVE|REPORT)'
        
        regex1 = '\s+[\(\|]?\s*[1L]\s*[\)\|]?\s*[:\.]{0,1}(\s*[\(\|]\s*A\s*[\)\|])?\s*(.){0,50}\s*' + \
                 'NAME[\(]?[S]?[\)]?\s+(?:OF|OR)(\s+THE)?(\s+(?:REPORTING|ABOVE|REPORT))?\s+' + \
                 'PERSON[\(]?[S]?[\)]?'

        regex2 = '\s+[\(\|]?\s*[1L]\s*[\)\|]?\s*[:\.]{0,1}(\s*[\(\|]\s*A\s*[\)\|])?\s*(.){0,50}\s*' + \
                 'NAME[\(]?[S]?[\)]?\s+(?:AND|OF|OR)(\s+I\.R\.S\.)?\s+IDENTIFICATION\s+NO[\(]?[S]?[\)]?\.'
        
        regex3 = '(NAME[\(]?[S]?[\)]?\s+(?:OF|OR)(\s+THE)?(\s+(?:REPORTING|ABOVE|REPORT))?\s+' + \
                 'PERSON[\(]?[S]?[\)]?\s+)?[\(\|]?\s*[1L]\s*[\)\|]?\s*[:\.\|]{0,1}\s*' + \
                 'I\.R\.S\.\s+IDENTIFICATION\s+NO[\(]?[S]?[\)]?\.\s+(?:OF|OR)\s+(\s+THE)?ABOVE\s+' + \
                 'PERSON[\(]?[S]?[\)]?'
        
        regex4 = '(NAME[\(]?[S]?[\)]?\s+(?:OF|OR)(\s+THE)?(\s+(?:REPORTING|ABOVE|REPORT))?\s+' + \
                 'PERSON[\(]?[S]?[\)]?\s+)?[\(\|]?\s*[1L]\s*[\)\|]?\s*[:\.\|]{0,1}\s*S\.S\.\s+OR\s+' + \
                 'I\.R\.S\.\s+IDENTIFICATION\s+NO[\(]?[S]?[\)]?\.\s+(?:OF|OR)(\s+THE)?\s+' + \
                 'ABOVE\s+PERSON[\(]?[S]?[\)]?'
        
        regex5 = '[\(\|]?\s*[1L]\s*[\)\|]?\s*[:\.]{0,1}(\s*[\(\|]\s*A\s*[\)\|])?\s*' + \
                 'NAME[\(]?[S]?[\)]?\s+(?:OF|OR)(\s+THE)?\s+FILING\s+(?:PARTY|PARTIES|PERSON|PERSONS)'
        
        regex6 = 'NAME[\(]?[S]?[\)]?\s+(?:OF|OR)(\s+THE)?(\s+(?:REPORTING|ABOVE|REPORT))?\s+' + \
                 'PERSON[\(]?[S]?[\)]?\s+(S\.S\.\s+OR\s+I\.R\.S\.\s+IDENTIFICATION\s+NO[\(]?[S]?[\)]?\.\s+' + \
                 '(?:OF|OR)(\s+THE)?\s+ABOVE\s+PERSON[\(]?[S]?[\)]?)?' + \
                 '\s+[\(\|]?\s*[1L]\s*[\)\|]?\s*[:\.]{0,1}(\s*[\(\|]\s*A\s*[\)\|])?'
        
        
        regex7 = '\n\s*[\(\|]?\s1\s?[\)\|]?\s*[:\.]{0,1}([A-Z0-9\s\.\(\)_]?)+?' + \
                 '[\(\|]?\s2\s?[\)\|]?\s*[:\.]{0,1}([A-Z0-9\s\.\(\)_]?)+?' + \
                 '[\(\|]?\s3\s?[\)\|]?\s*[:\.]{0,1}\s+(.)+\s*\(SEC USE ONLY\)'
        
        regex8 = 'NAME[\(]?[S]?[\)]?\s+(?:OF|OR)(\s+THE)?\s+(?:REPORTING|ABOVE|REPORT)'
        
        regex9 = 'NAME[\(]?[S]?[\)]?\s+(?:AND|OF|OR)(\s+I\.R\.S\.)?\s+IDENTIFICATION\s+NO[\(]?[S]?[\)]?.'
        
        
        regex_list = [regex0, regex1, regex2, regex3, regex4, regex5, regex6, regex7, regex8, regex9]
        
        start = None
        
        for i in range(len(regex_list)):
            
            search = re.search(regex_list[i], text_raised)
            
            if(search):
                
                if(start is None):
                    
                    start = search.start()
                    
                else:
                    
                    new = search.start()
                    
                    if(new < start):
                        
                        start = new            

        if(start):
            
            return(start)
        
        else:
            
            return(-1)   
   
   
            
def rep_page_start_alt(text, form_type, lower_bound = None, rep_q_as_items = None):
    
    if(lower_bound):
        text_raised = text.upper()[lower_bound:]
        
    else:
        lower_bound = 0
        text_raised = text.upper()
        
    search = None
    
    if(rep_q_as_items is None):
        
        rep_q_as_items = is_rep_q_as_items(text)

    if(re.search('SC 13D', form_type)):
        
        if(rep_q_as_items):
            
            search = re.search('\n\s*ITEM\s+[\(\|]?\s?1\s?[\)\|]?\s*[:\.]{0,1}(.)+?' + \
                  '\n\s*ITEM\s+[\(\|]?\s?14\s?[\)\|]?\s*[:\.]{0,1}', text_raised, flags = re.DOTALL)
            
        else:
            search = re.search('\n\s*[\(\|]?\s?1\s?[\)\|]?\s*[:\.]{0,1}(.)+?' + \
                  '\n\s*[\(\|]?\s?14\s?[\)\|]?\s*[:\.]{0,1}', text_raised, flags = re.DOTALL)
        
    if(re.search('SC 13G', form_type)):
        
        if(rep_q_as_items):
            
            search = re.search('\n\s*ITEM\s+[\(\|]?\s?1\s?[\)\|]?\s*[:\.]{0,1}(.)+?' + \
                  '\n\s*ITEM\s+[\(\|]?\s?12\s?[\)\|]?\s*[:\.]{0,1}', text_raised, flags = re.DOTALL)
            
        else:
            search = re.search('\n\s*[\(\|]?\s?1\s?[\)\|]?\s*[:\.]{0,1}(.)+?' + \
                  '\n\s*[\(\|]?\s?12\s?[\)\|]?\s*[:\.]{0,1}', text_raised, flags = re.DOTALL)
            
    if(search):
        
        return(search.start() + lower_bound)
    
    else:
        
        return(-1)
            
def find_regex1_end(text):
    
    text_lowered = text.lower()

    regex1 = 'but\s+shall\s+be\s+subject\s+to\s+all\s+other\s+provisions\s+of\s+the\s+act\s*' + \
              '(\(however,\s+see\s+the\s+notes\s*\))?(\.)?'

    end = find_last_search_end(regex1, text_lowered)
    
    if(end is not None):
        
        return(end)
    
    else:
        # Use -1 to distinguish cases where regex was not found from other failures
        return(-1)


def cover_page_start(text, form_type, cover_page_q1 = None, rep_q_as_items = None):
    
    if(rep_q_as_items is None):
        
        rep_q_as_items = is_rep_q_as_items(text)
    
    if(cover_page_q1 is None):
        
        cover_page_q1 = find_cover_page_q1_start(text, rep_q_as_items)
        
    if(cover_page_q1 == -1):
        
        # No question 1 found, so no cover pages, return -1
        return(-1) 
        
    else:
        
        text_to_search = text[:cover_page_q1]
    
        text_reversed_and_raised = text_to_search[::-1].upper()

        regex = '(PISUC|LODES)\s*\n'

        search = re.search(regex, text_reversed_and_raised)

        if(search):

            num_back = search.end()

        else:

            num_back = 0

        start = cover_page_q1 - num_back

        return(start)



def find_title_page_end(text):
    
    rep_q_as_items = is_rep_q_as_items(text)
    
    upper_bound = get_title_page_end_upper_bound(text, rep_q_as_items)
    
    text_raised = text.upper()[:upper_bound]
    
    regex1_end = find_regex1_end(text)
    
    num_cusip_lines = len(re.findall('(?:CUSIP|SEDOL)', text_raised))
    
    if(regex1_end != -1):
        
        return(regex1_end)
    
    elif(num_cusip_lines < 2):
        
        return(upper_bound)
        
    else:
            
        
        rep_start_re = ['(?:CUSIP|SEDOL)', 'SCHEDULE\s+13[DG](/A)?', 'SC\s+13[DG](/A)?', \
                        'PAGE', '13[DG](/A)?']

        pot_results = []

        for regex in rep_start_re:

            start = find_last_search_start(regex, text_raised)

            if(start):
                pot_results.append(start)
                
        result = min(pot_results)
        
        return(result)
    
        

def find_title_page_end(text):
    
    text_lowered = text.lower()
    
    regex1 = 'but\s+shall\s+be\s+subject\s+to\s+all\s+other\s+provisions\s+of\s+the\s+act\s*' + \
             '(\(however,\s+see\s+the\s+notes\s*\))?(\.)?'

    regex2 = 'for\s+any\s+subsequent\s+amendment\s+containing\s+information\s+which\s+' + \
             'would\s+alter\s+(the\s+)?disclosures\s+provided\s+in\s+a\s+prior\s+cover\s+page(\.)?'

    regex3 = 'see\s+((?:section|rule|[\xa7]{1,2})\s*)?(240\.\s*)?(\.\s*)?13d\s*[-\u2011]?\s*7' + \
                 '(\s*\(\s*[a-z]\s*\)\s*)?\s+for\s+other\s+parties\s+to\s+whom\s+copies\s+' + \
                 'are\s+to\s+be\s+sent(\.)'
    
    regex4 = 'persons\s+who\s+respond\s+to\s+the\s+collection\s+of\s+information\s+contained\s+in\s+' + \
             'this\s+form\s+are\s+not\s+required\s+to\s+respond\s+unless\s+the\s+form\s+displays\s+a\s+' + \
             'currently\s+valid \s+omb\s+control\s+number(\.)?'

    regex4 = '(\xa7\xa7)?(240\.)?13d-1\(e\),\s+' + \
             '(\xa7\xa7)?(240\.)?13d-1\(f\)\s+or\s+(\xa7\xa7)?(240\.)?13d-1\(g\),\s+check\s+the\s+' + \
             'following\s+box(\.)?\s+\[\s+\]\s*(\.)?'
    
    

    regex5 = '(\()?\s*date\s+of\s+event\s+which\s+requires\s+filing\s+of\s+this\s+statement\s*(\))?'

    regex6 = '(\()?\s*name,\s+address\s+and\s+telephone\s+number\s+of\s+person\s+authorized\s+to\s+receive\s+' + \
             'notices\s+and\s+communication(s)?\s*(\))?'

    regex7 = '(\()?\s*(cusip\s+number|cusip\s+number\s+of\s+class\s+of\s+securities)\s*(\))?'
    
    
    
    
    regex_list = [regex1, regex2, regex3, regex4, regex5, regex6, regex7]
    
    regex_end_list = []
    
    for i in range(len(regex_list)):
        
        regex_end = find_last_search_end(regex_list[i], text_lowered)
        
        if(regex_end):
            
            regex_end_list.append(regex_search.end())
        
    if(len(regex_end_list)):
        
        return(max(regex_end_list))
    
    else:
        return(-1)

def get_text_past_title_page(file_name):
        
    url = get_txt_file_url(file_name)
    text = requests.get(url).text
  
    header_end = find_header_end(text)
    
     # Git rid of the annoying tags
    text_rem = text[header_end:]
    soup = BeautifulSoup(text_rem, 'html.parser')
    text_rem = soup.get_text()
    
    title_page_end = find_title_page_end(text_rem)
    
    result = text_rem[title_page_end:]
    
    return(result)
   
   
        
def find_cover_pages_last_question(text, rep_q_as_items = None,  lower_bound = None, upper_bound = None):
    
    if(rep_q_as_items is None):
        
        rep_q_as_items = is_rep_q_as_items(text)
    
    if(lower_bound is not None and lower_bound > 0):
        
        if(upper_bound is not None and upper_bound > 0):
            
            text_raised = text.upper()[lower_bound:upper_bound]
            
        else:
            
            text_raised = text.upper()[lower_bound:]
            
    else:
        
        if(upper_bound is not None and upper_bound > 0):
            
            text_raised = text.upper()[:upper_bound]
            
        else:
            
            text_raised = text.upper() 
    
    if(rep_q_as_items):
        
        regex = 'ITEM\s*[\(]?\s*1[24]\s*[\)]?\s*[\:\.]?'
        
    else:
    
        regex = '[\(]?\s*1[24][\)]?\s*[\:\.]?\s*TYPE[S]?\s+OF\s+REPORTING\s+PERSON[S]?[\*]?\s*(\(SEE\s+INSTRUCTIONS\))?'

    search = re.search(regex, text_raised)

    if(search is None):
        return(None)
    
    end = 0

    while(search is not None):
        
        end = end + search.end()
        search = re.search(regex, text_raised[end:])

    if(lower_bound is not None and lower_bound > 0):
        
        end = end + lower_bound
        
    return(end)       
    
    
def find_cover_pages_end(text, rep_q_as_items = None, lower_bound = None, upper_bound = None):
    
    
    end = find_cover_pages_last_question(text, rep_q_as_items, lower_bound, upper_bound)
        
    answer_regex = '\s+([A-Z0]{1}[;, \.]?[A-Z0]{1}[;, \.]?)*([A-Z0]{1}[;, \.]?[A-Z0]{1}[;, \.]?)\s*\n?'
    
    if(upper_bound is not None):
    
        last_answer = re.search(answer_regex, text[end:upper_bound])
        
    else:
        
        last_answer = re.search(answer_regex, text[end:])
    
    if(last_answer is not None):
    
        return(end + last_answer.end())
    
    else:
        
        return(-1)

 
def num_cusip_sedol_before_index(text, index = None):

    try:
        if(index):
            text_lowered = text.lower()[:index]
        else:
            text_lowered = text.lower()
        
        num_cusip_sedol = len(re.findall('(cusip|sedol)', text_lowered))
        
        return(num_cusip_sedol)

    except Exception as e:
        print(e)
        return(None)

    
def find_explanatory_statement_start(text, lower_bound = None, upper_bound = None):
    
    # This function is designed to get the start of the explanatory/amendment statement 
    # that is sometimes found between the end of the cover pages and the start of the item section 
    
    

    regex_list = ['\n\s*explanatory\s+note', '\n\s*amendment\s+(number|no)(\.)?\s*[0-9]+\s*\n',\
                  '\n\s*schedule\s+13[dg]\s+amendment\s+(number|no)(\.)?\s*[0-9]+\s*\n',\
                  '\n\s*this\s+amendment\s+(number|no)(\.)?\s*[0-9]+\s+', \
                    '\n\s*pursuant\s+to\s+rule\s+13d-', '\n\s*this\s+amended\s+schedule\s+13[dg]', \
'\n\s*the\s+undersigned(\s+reporting\s+person(s)?)?\s+hereby\s+amend\s+(the|their)\s+schedule\s+13[dg]',\
                  '\n\s*the\s+schedule\s+13[dg]\s+was\s+initially\s+filed',\
                 '\n(.)+hereby\s+amends\s+the\s+schedule\s+13[dg]',\
                  '\n\s*the\s+filing\s+of\s+this\s+schedule\s+13[dg]',\
                 '\n\s*the\s+filing\s+of\s+this\s+statement\s+on\s+schedule\s+13[dg]',\
                 '\n\s*the\s+reporting\s+person(s)?\s+listed\s+']

    if(lower_bound):

        if(upper_bound):

            text_lowered = text.lower()[lower_bound:upper_bound]

        else:

            text_lowered = text.lower()[lower_bound:]

    else:

        if(upper_bound):

            text_lowered = text.lower()[:upper_bound]

        else:

            text_lowered = text.lower()

    search_starts = []

    for pattern in regex_list:

        search = re.search(pattern, text_lowered)

        if(search):

            search_starts.append(search.start())

    if(len(search_starts)):

        if(lower_bound):

            return(min(search_starts) + lower_bound)

        else:

            return(min(search_starts))

    else:

        return(-1)
        
    
  

def get_key_indices(file_name, document, form_type, directory):
    
    key_info = {}
    
    text = get_main_doc_text(file_name, document, directory)
    
    key_info['file_name'] = [file_name]
    key_info['document'] = [document]
    key_info['form_type'] = [form_type]
    key_info['title_page_end_lower_bound'] = [find_title_page_end(text)]
    key_info['cover_page_q1_start'] = [find_orthodox_cover_page_q1_start(text)]
    key_info['is_rep_q_as_items'] = [is_rep_q_as_items(text, key_info['cover_page_q1_start'][0])]
    if(key_info['is_rep_q_as_items'][0]):
        
        key_info['cover_page_q1_start'] = [cover_page_start_is_rep_as_q(text, form_type, \
                                                lower_bound = key_info['title_page_end_lower_bound'][0])]
    key_info['num_cusip_sedol_b_q1'] = [num_cusip_sedol_before_index(text, \
                                                                    key_info['cover_page_q1_start'][0])]
    key_info['cover_page_start'] = [cover_page_start(text, form_type, \
            cover_page_q1 = key_info['cover_page_q1_start'][0], \
                                                     rep_q_as_items = key_info['is_rep_q_as_items'][0])]
    
    
    key_info['item_section_start'] = [get_item_section_start(text, form_type)]
    key_info['cover_page_last_q_end'] = [find_cover_pages_last_question(text, \
                        key_info['is_rep_q_as_items'][0], key_info['cover_page_q1_start'][0], \
                                                                        key_info['item_section_start'][0])]
    key_info['cover_page_end'] = [find_cover_pages_end(text, key_info['is_rep_q_as_items'][0],\
                                key_info['cover_page_q1_start'][0], key_info['item_section_start'][0])]
    
    key_info['num_cusip_b_items'] = [num_cusip_sedol_before_index(text, \
                                                                  index = key_info['item_section_start'][0])]
    key_info['signature_start'] = [get_signatures_sec_start(text)]
    
    if(key_info['cover_page_start'][0] != -1 and key_info['item_section_start'][0] != -1\
      and key_info['item_section_start'][0] > key_info['cover_page_start'][0]):
        
        amend_l_bound = key_info['cover_page_start'][0]
        
    else:
        
        amend_l_bound = None
    
    key_info['explanatory_statement_start'] = find_explanatory_statement_start(text, \
                            lower_bound = amend_l_bound, upper_bound = key_info['item_section_start'][0])
    
    
    key_info_df = pd.DataFrame(key_info)
    
    return(key_info_df)
    
    
    

  
def get_item_section_start(text, form_type):    
    
    
    if(re.search('SC\s+13D', form_type)):
        
        re_list = ['\n\s*[#\.\;\:]?\s*1[#\.\;\:]?\s*security\s+and\s+issuer',
                   '\n\s*[#\.\;\:]?\s*2[#\.\;\:]?\s*identity\s+and\s+background',
                   '\n\s*[#\.\;\:]?\s*3[#\.\;\:]?\s*source\s+and\s+amount\s+of\s+funds',
                   '\n\s*[#\.\;\:]?\s*4[#\.\;\:]?\s*purpose\s+of\s+transaction',
                   '\n\s*[#\.\;\:]?\s*5[#\.\;\:]?\s*interest\s+in\s+securities\s+of\s+the\s+issuer',
                   '\n\s*[#\.\;\:]?\s*6[#\.\;\:]?\s*contracts,\s+arrangements,\s+understandings',
                   '\n\s*[#\.\;\:]?\s*7[#\.\;\:]?\s*material\s+to\s+be\s+filed\s+as\s+exhibits'
                  ]
                       
        
    elif(re.search('SC\s+13G', form_type)):
        
        re_list = ['\n\s*[#\.\;\:]?\s*1[#\.\;\:]?[\(]?\s*a[\)]?[#\.\;\:]?\s*name\s+of\s+issuer',
                   '\n\s*[#\.\;\:]?\s*1[#\.\;\:]?[\(]?\s*b[\)]?[#\.\;\:]?\s*address\s+of\s+issuer',
                   '\n\s*[#\.\;\:]?\s*2[#\.\;\:]?[\(]?\s*a[\)]?[#\.\;\:]?\s*name[s]?\s+of\s+person[s]?\s+filing',
                   '\n\s*[#\.\;\:]?\s*2[#\.\;\:]?[\(]?\s*b[\)]?[#\.\;\:]?\s*address\s+of\s+principle',
                   '\n\s*[#\.\;\:]?\s*2[#\.\;\:]?[\(]?\s*c[\)]?[#\.\;\:]?\s*citizenship',
                   '\n\s*[#\.\;\:]?\s*2[#\.\;\:]?[\(]?\s*d[\)]?[#\.\;\:]?\s*title\s+of\s+class',
                   '\n\s*[#\.\;\:]?\s*2[#\.\;\:]?[\(]?\s*e[\)]?[#\.\;\:]?\s*cusip\s+number',
                   '\n\s*[#\.\;\:]?\s*3[#\.\;\:]?\s*if\s+this\s+statement\s+is\s+filed\s+pursuant',
                   '\n\s*[#\.\;\:]?\s*4[#\.\;\:]?\s*ownership',
                   '\n\s*[#\.\;\:]?\s*5[#\.\;\:]?\s*ownership\s+of\s+five',
                   '\n\s*[#\.\;\:]?\s*6[#\.\;\:]?\s*ownership\s+of\s+more',
                   '\n\s*[#\.\;\:]?\s*7[#\.\;\:]?\s*identification\s+and\s+classification',
                   '\n\s*[#\.\;\:]?\s*8[#\.\;\:]?\s*identification\s+and\s+classification',
                   '\n\s*[#\.\;\:]?\s*9[#\.\;\:]?\s*notice\s+of\s+dissolution',
                   '\n\s*[#\.\;\:]?\s*10[#\.\;\:]?\s*certification'
                  ]
        
    else:
        
        # Not a Schedule 13D(/A) or 13G(/A)
        return(None)
   
    cover_pages_end = find_cover_pages_last_question(text)
    
    if(cover_pages_end):

        text_lowered = text[cover_pages_end:].lower()

        search = re.search('\n\s*item\s*[#\.\;\:]?\s*(?:[0-9])[#\.\;\:]?', text_lowered)
        
        if(search):

            return(cover_pages_end + search.start())  
        
        else:
            return(None) # ie. assume no Item section (this probably happens with 13D/A and 13G/A)
    
    else:
        
        text_lowered = text.lower() # Assume NO REPORTING PAGES (this happens, especially with 13D/A and 13G/A)

        search = re.search('\n\s*item\s*[#\.\;\:]?\s*[0-9][#\.\;\:]?', text_lowered)

        if(search):

            return(search.start())  
        
        else: 
             
            result = None # ie. assume no Item section (this probably happens with 13D/A and 13G/A) if no matches in
                          # re_list
                
            for i in range(len(re_list)):
                
                search = re.search(re_list[i], text_lowered)
                
                if(search):
                    
                    result = search.start()
                    break
            
            
            return(result) 
        
        
        
        

def get_signatures_sec_start(text):
    
    text_lowered = text.lower()
    
    regex0 = '\n\s*(signature|signatures)\s*(\.)?\n'
    
    regex1 = 'the\s+following\s+certification\s+shall\s+be\s+included\s+if\s+the\s+statement\s+is\s+filed\s+' + \
             'pursuant to rule 13d-1\(b\)'
    
    regex2 = 'by\s+signing\s+below\s+i\s+certify\s+that,\s+to\s+the\s+best\s+of\s+my\s+knowledge'
  
    regex3 = 'after\s+reasonable\s+inquiry\s+'
    
    regex_list = [regex0, regex1, regex2, regex3]
    
    regex_search = None
    
    for i in range(len(regex_list)):
        
        regex_search = re.search(regex_list[i], text_lowered)
        
        if(regex_search):
            
            break
        
    if(regex_search):
        
        return(regex_search.start())
    
    else:
        return(None)
    
        
def get_exhibit_sec_start(text):
    
    text_upper = text.upper()
    
    regex0 = 'EXHIBIT\s+INDEX'
    
    regex1 = '\n\s*EXHIBIT\s+[0-9A-Z](:)?'
    
    regex2 = '\n\s*APPENDIX\s+[0-9A-Z](:)?'
    
    regex_list = [regex0, regex1, regex2]
    
    regex_search = None
    
    for i in range(len(regex_list)):
        
        regex_search = re.search(regex_list[i], text_upper)
        
        if(regex_search):
            
            break
        
    if(regex_search):
        
        return(regex_search.start())
    
    else:
        return(None)
        
        
        
def get_text_components(text):
  
    header_end = find_header_end(text)
    
    header = text[:header_end]
    
    title_page_end = header_end + find_title_page_end(text[header_end:])
    
    title_page = text[header_end:title_page_end]
    
    text_rem = text[title_page_end:]
    
    # Git rid of the annoying tags
    soup = BeautifulSoup(text_rem, 'html.parser')
    
    text_rem = soup.get_text()
    
    rep_pages_end = find_reporting_pages_end(text_rem)
    
    if(rep_pages_end):
        
        item_section_start = rep_pages_end
        
    else:
        
        item_section_start = get_item_section_start(text_rem)
    
    reporting_pages_text = text[:item_section_start]
    
    signatures_start = item_section_start + get_signatures_sec_start(text_rem[item_section_start:])
    
    item_section = text[item_section_start:signatures_start]
    
    exhibit_start = get_exhibit_sec_start(text_rem[signatures_start:])
    
    if(exhibit_start is not None):
        
        exhibit_start = signatures_start + exhibit_start
        signatures = text[signatures_start:exhibit_start]
        exhibits = text[exhibit_start:]
        
    else:
        signatures = text[signatures_start:]
        exhibits = None
        
    return(header, title_page, reporting_pages_text, item_section, signatures, exhibits)
    
    
    
def get_text_components_by_name(file_name):
    
    url = get_txt_file_url(file_name)
    text = requests.get(url).text
  
    header_end = find_header_end(text)
    
    header = text[:header_end]
    
    text_rem = text[header_end:]
    
    # Git rid of the annoying tags
    soup = BeautifulSoup(text_rem, 'html.parser')
    
    text_rem = soup.get_text()
    
    title_page_end = find_title_page_end(text_rem)
    
    title_page = text_rem[:title_page_end]
    
    # Git rid of the annoying tags
    soup = BeautifulSoup(text_rem, 'html.parser')
    
    text_rem = soup.get_text()
    
    item_section_start = get_item_section_start(text_rem[title_page_end:])
    
    if(item_section_start):
        
        item_section_start = title_page_end + item_section_start
        
    else:
        item_section_start = title_page_end + find_reporting_pages_end(text_rem)
        
    
    reporting_pages_text = text_rem[title_page_end:item_section_start]
    
    signatures_start = item_section_start + get_signatures_sec_start(text_rem[item_section_start:])
    
    item_section = text_rem[item_section_start:signatures_start]
    
    exhibit_start = get_exhibit_sec_start(text_rem[signatures_start:])
    
    if(exhibit_start is not None):
        
        exhibit_start = signatures_start + exhibit_start
        signatures = text_rem[signatures_start:exhibit_start]
        exhibits = text_rem[exhibit_start:]
        
    else:
        signatures = text_rem[signatures_start:]
        exhibits = None
        
    return(header, title_page, reporting_pages_text, item_section, signatures, exhibits)   
    
    
    
    
    
def get_reporting_pages(text):
    
    # This function is designed to take in reporting_pages_text from the output of get_text_components
    # and to split this text into the individual pages
    
    text_upper = text.upper()
    
    regex = '1[24]\s*[:\.]?\s+TYPE[S]?\s+OF\s+REPORTING\s+PERSON[S]?\s*[\*]?\s*' + \
            '(\(SEE\s+INSTRUCTIONS\))?[:\.]?\s*([0-9A-Z]{2}[:;,\s])*([0-9A-Z]{2})\s+\n?'
    
    search = re.search(regex, text_upper)
    
    if(search is None):
        return(None)
    
    end = 0
    end_list = []
    
    while(search is not None):
        
        end = end + search.end()
        end_list.append(end)
        search = re.search(regex, text_upper[end:])
        
    pages = []    
        
    for i in range(len(end_list)):
        
        if(i == 0):
            pages.append(text[0:end_list[0]])
        else:
            pages.append(text[end_list[i-1]:end_list[i]])
    
    return(pages)
    
    
    


# These handle reporting page questions
    
    
def get_filing_report_q_and_a(text, form_type):
    
    # This function is designed to be used on an individual page from the list returend from get_reporting pages. It is designed to split this page in to the individual segments for each question
    # which correspond from 0 (for Cusip) through to 14 for 13D's and 0 to 12 for 13G's
    
    text_upper = text.upper()
    
    if(re.search('^SC 13D', form_type)):
        question_regex_dict = {1: '[\(]?1[\)]?\s*[:\.]{0,1}\s*NAME[S]?\s+OF\s+REPORTING\s+PERSON[S]?',
                       2: '[\(]?2[\)]?\s*[:\.]{0,1}\s*CHECK\s+THE\s+APPROPRIATE\s+BOX\s+IF\s+A\s+MEMBER',
                       3: '[\(]?3[\)]?\s*[:\.]{0,1}\s*SEC\s+USE\s+ONLY',
                       4: '[\(]?4[\)]?\s*[:\.]{0,1}\s*SOURCE\s+OF\s+FUNDS[\*]?',
                       5: '[\(]?5[\)]?\s*[:\.]{0,1}\s*CHECK(\s+BOX)?\s+IF\s+DISCLOSURE\s+OF\s+LEGAL\s+PROCEEDINGS',
                       6: '[\(]?6[\)]?\s*[:\.]{0,1}\s*CITIZENSHIP\s+OR\s+PLACE\s+OF\s+ORGANIZATION', 
                       7: '[\(]?7[\)]?\s*[:\.]{0,1}\s*SOLE\s+VOTING\s+POWER',
                       8: '[\(]?8[\)]?\s*[:\.]{0,1}\s*SHARED\s+VOTING\s+POWER',
                       9: '[\(]?9[\)]?\s*[:\.]{0,1}\s*SOLE\s+DISPOSITIVE\s+POWER',
                       10: '[\(]?10[\)]?\s*[:\.]{0,1}\s*SHARED\s+DISPOSITIVE\s+POWER',
                       11: '[\(]?11[\)]?\s*[:\.]{0,1}\s*AGGREGATE\s+AMOUNT\s+BENEFICIALLY\s+OWNED',
                       12: '[\(]?12[\)]?\s*[:\.]{0,1}\s*CHECK(\s+BOX)?\s+IF\s+THE\s+AGGREGATE\s+AMOUNT',
                       13: '[\(]?13[\)]?\s*[:\.]{0,1}\s*PERCENT\s+OF\s+CLASS\s+REPRESENTED',
                       14: '[\(]?14[\)]?\s*[:\.]{0,1}\s*TYPE[S]?\s+OF\s+REPORTING\s+PERSON[S]?'}
       
        num_sec = 15
       
    elif(re.search('^SC 13G', form_type)):
        
        question_regex_dict = {1: '[\(]?1[\)]?\s*[:\.]{0,1}\s*NAME[S]?\s+OF\s+REPORTING\s+PERSON[S]?',
                       2: '[\(]?2[\)]?\s*[:\.]{0,1}\s*CHECK\s+THE\s+APPROPRIATE\s+BOX\s+IF\s+A\s+MEMBER',
                       3: '[\(]?3[\)]?\s*[:\.]{0,1}\s*SEC\s+USE\s+ONLY',
                       4: '[\(]?4[\)]?\s*[:\.]{0,1}\s*CITIZENSHIP\s+OR\s+PLACE\s+OF\s+ORGANIZATION', 
                       5: '[\(]?5[\)]?\s*[:\.]{0,1}\s*SOLE\s+VOTING\s+POWER',
                       6: '[\(]?6[\)]?\s*[:\.]{0,1}\s*SHARED\s+VOTING\s+POWER',
                       7: '[\(]?7[\)]?\s*[:\.]{0,1}\s*SOLE\s+DISPOSITIVE\s+POWER',
                       8: '[\(]?8[\)]?\s*[:\.]{0,1}\s*SHARED\s+DISPOSITIVE\s+POWER',
                       9: '[\(]?9[\)]?\s*[:\.]{0,1}\s*AGGREGATE\s+AMOUNT\s+BENEFICIALLY\s+OWNED',
                       10: '[\(]?10[\)]?\s*[:\.]{0,1}\s*CHECK(\s+BOX)?\s+IF\s+THE\s+AGGREGATE\s+AMOUNT',
                       11: '[\(]?11[\)]?\s*[:\.]{0,1}\s*PERCENT\s+OF\s+CLASS\s+REPRESENTED',
                       12: '[\(]?12[\)]?\s*[:\.]{0,1}\s*TYPE[S]?\s+OF\s+REPORTING\s+PERSON[S]?'}
        
        num_sec = 13
        
    else:
        
        raise ValueError("form_type is not equal to 'SC 13D', 'SC 13 D/A', 'SC 13G' or an 'SC 13G/A'")

    start_dict = {}

    for key, regex in question_regex_dict.items():

        start_dict[key] = re.search(regex, text_upper).start()


    text_dict = {}
    for i in range(num_sec):

        if(i == 0):
            text_dict[i] = text[0:start_dict[i+1]]
        elif(i == num_sec - 1):
            text_dict[i] = text[start_dict[i]:]
        else:
            text_dict[i] = text[start_dict[i]:start_dict[i+1]]
            
    return(text_dict)    
    
    
    

def get_reporting_page_cusip_sedol(q0_text):
    
    text_upper = q0_text.upper()
    
    sd_regex = '(SCHEDULE\s+13\s*[DG]\s*(/\s*A)?|SC\s+13\s*[DG](/A)?|\s+13\s*[DG]\s*(/A)?\s{10,})'
    
    # get rid of schedule phrases
    
    cusip_text = re.sub(sd_regex, ' ', text_upper)
    
    # Next, get rid of instances of page phrases with a 13D or 13G in front. Start with most complex first
    
    pages_regex1 = '\s+13\s*[DG]\s*(/\s*A)?\s+PAGE\s+[0-9]{1,2}\s+OF\s+[0-9]{1,2}\s+(PAGES){0,1}'
    cusip_text = re.sub(pages_regex1, ' ', cusip_text)

    pages_regex2 = '\s+13\s*[DG]\s*(/\s*A)?\s+PAGE\s+[0-9]{1,2}\s+'
    cusip_text = re.sub(pages_regex2, ' ', cusip_text)

    pages_regex3 = '\s+13\s*[DG]\s*(/\s*A)?\s+[0-9]{1,2}\s+(PAGES)\s+'
    cusip_text = re.sub(pages_regex3, ' ', cusip_text)

    # Next get rid of the page phrases without 13D or G in front

    pages_regex4 = '\s+PAGE\s+[0-9]{1,2}\s+OF\s+[0-9]{1,2}\s+(PAGES){0,1}'
    cusip_text = re.sub(pages_regex4, ' ', cusip_text)

    pages_regex5 = '\s+PAGE\s+[0-9]{1,2}\s+'
    cusip_text = re.sub(pages_regex5, ' ', cusip_text)

    pages_regex6 = '\s+[0-9]{1,2}\s+(PAGES)\s+'
    cusip_text = re.sub(pages_regex6, ' ', cusip_text)
  
    # lastly any other page words
    
    page_regex_small = '(<PAGE>|PAGE|PAGES)'
    
    cusip_text = re.sub(page_regex_small, ' ', cusip_text)
    
    cusip_hdr = 'CUSIP\s+(?:NO\.|#|NUMBER):?\s+'
    sedol_hdr = 'SEDOL\s+(?:NO\.|#|NUMBER):?\s+'
    cusip_num_regex = '((?:[0-9A-Z]{1}[ -]{0,3}){4,9})'
    sedol_num_regex = '((?:[0-9A-Z]{1}[ -]{0,3}){4,7})'
    
    cusip_search = re.search(cusip_hdr, cusip_text)
    sedol_search = re.search(sedol_hdr, cusip_text)
    
    if(sedol_search is None):
        
        # Assume Cusips in this case, whether cusip regex appears or not, as these are the usual cases
        if(cusip_search is not None):
            cusips = re.findall(cusip_num_regex, cusip_text[cusip_search.end():])
            sedols = []
        else:
            cusips = re.findall(cusip_num_regex, cusip_text)
            sedols = []
        
    elif(cusip_search is None and sedol_search is not None):
        
        cusips = []
        sedols = re.findall(sedol_num_regex, cusip_text[sedol_search.end():])
        
    else: 
        
        # both cusip and sedol searches are not none, need to determine which appears first
        
        if(cusip_search.end() > sedol_search.end()):
            
            cusips = re.findall(cusip_num_regex, cusip_text[cusip_search.end():])
            sedols = re.findall(sedol_num_regex, cusip_text[sedol_search.end():cusip_search.end()])
            
        else:
            
            cusips = re.findall(cusip_num_regex, cusip_text[cusip_search.end():sedol_search.end()])
            sedols = re.findall(sedol_num_regex, cusip_text[sedol_search.end():])
            
    
    # lastly, clean cusips and sedols
    
    cusips = [re.sub('[^0-9A-Z]', '', cusip) for cusip in cusips]
    sedols = [re.sub('[^0-9A-Z]', '', sedol) for sedol in sedols]

    return(cusips, sedols)



def strip_form_statement(text, statement):

    statement_raised = re.sub('\s+', ' ', statement).upper()
    text_raised = text.upper()
    
    words = statement_raised.split(' ')

    regex_list = []

    for i in range(len(words)):
        
        if(i == 0):
            
            regex_list.append('\n\s*(?:' + '|'.join(words) + ')')
            
        else:
            regex_list.append('(?:' + '|'.join(words[i:]) + ')?')
                              
    regex = '(' + '[\s-]*'.join(regex_list) + ')'
    
    regex_start = '^(' + '[\s-]*'.join(regex_list).lstrip('\n') + ')'

    start_search = re.search(regex_start, text_raised)

    if(start_search):

        statement_parts = [start_search.group(0)] + re.findall(regex, text_raised)

    else:
        statement_parts = re.findall(regex, text_raised)
        
    result = text

    for part in statement_parts:

        start = result.upper().find(part)
        if(start != -1):
            end = start + len(part)
            result = result[:start] + ' ' + result[end:]
    
    return(result)


def eliminate_beneficial_own_statement(text):
    
    # This function is designed to get rid of the irritating 
    # 'NUMBER OF SHARES BENEFICIALLY OWNED BY EACH REPORTING PERSON WITH' statement, or any occurences of 
    # any part of it, around q6, q7, q8, q9, q10 (on SC 13D)
    
    result = strip_form_statement(text, 'NUMBER OF SHARES BENEFICIALLY OWNED BY EACH REPORTING PERSON WITH')
    
    return(result)        
    
    
def get_answer_text(q_text, form_type, question_number):
    
    # This function is designed to be used on all questions except question 2, 
    # in which there are boxes (a) and (b)
   
    
    # First, get rid of beneficial ownership statement
      
    if(re.search("13D", form_type)):
        
        ben_own_statement_keys = [6, 7, 8, 9, 10, 11]
        
        q_regex_dict = {1: '(?:NAMES|NAME) OF REPORTING (?:PERSONS|PERSON)[*]? S.S. ' + \
                         'OR I.R.S. IDENTIFICATION (?:NOS.|NO.) OF ABOVE (?:PERSONS|PERSON) \(ENTITIES ONLY\)',
                        4: 'SOURCE OF FUNDS[*]? \(SEE INSTRUCTIONS\)',
                        5: 'CHECK BOX IF DISCLOSURE OF LEGAL PROCEEDINGS IS REQUIRED PURSUANT' + \
                           ' TO ITEMS 2\(D\) OR 2\(E\)',
                        6: 'CITIZENSHIP OR PLACE OF ORGANIZATION',
                        7: 'SOLE VOTING POWER',
                        8: 'SHARED VOTING POWER',
                        9: 'SOLE DISPOSITIVE POWER',
                        10: 'SHARED DISPOSITIVE POWER', 
                        11: 'AGGREGATE AMOUNT BENEFICIALLY OWNED BY EACH REPORTING PERSON',
                        12: 'CHECK BOX IF THE AGGREGATE AMOUNT IN ROW \(11\) EXCLUDES CERTAIN SHARES[*]?',
                        13: 'PERCENT OF CLASS REPRESENTED BY AMOUNT IN ROW \(11\)',
                        14: 'TYPE[S]? OF REPORTING PERSON[S]? \(SEE INSTRUCTIONS\)'
                       }
        
    elif(re.search("13G", form_type)):
        
        ben_own_statement_keys = [4, 5, 6, 7, 8, 9]
        
        q_regex_dict = {1: '(?:NAMES|NAME) OF REPORTING (?:PERSONS|PERSON)[*]? S.S. ' + \
                         'OR I.R.S. IDENTIFICATION (?:NOS.|NO.) OF ABOVE (?:PERSONS|PERSON) \(ENTITIES ONLY\)',
                        4: 'CITIZENSHIP OR PLACE OF ORGANIZATION',
                        5: 'SOLE VOTING POWER',
                        6: 'SHARED VOTING POWER',
                        7: 'SOLE DISPOSITIVE POWER',
                        8: 'SHARED DISPOSITIVE POWER',
                        9: 'AGGREGATE AMOUNT BENEFICIALLY OWNED BY EACH REPORTING PERSON',
                        10: 'CHECK BOX IF THE AGGREGATE AMOUNT IN ROW \(9\) EXCLUDES CERTAIN SHARES[*]?',
                        11: 'PERCENT OF CLASS REPRESENTED BY AMOUNT IN ROW \(9\)',
                        12: 'TYPE[S]? OF REPORTING PERSON[S]? \(SEE INSTRUCTIONS\)'
                       }
    
    # First, get rid of beneficial ownership statement
    
    if(question_number in ben_own_statement_keys):

        result = eliminate_beneficial_own_statement(q_text)

    else:

        result = q_text
    
    result = re.sub('^[\(]?' + str(question_number) + '[\)]?\s*[:\.]?', '', result)
    
    result = re.sub('(^[\:\;\-\–\.\s]+|[\s\-]+$)', '', strip_form_statement(result, q_regex_dict[question_number]))
    
    return(result)
    
    
    
def q2_boxes_a_and_b(q2_text):
    
    a_start = re.search('\([aAcCeE][\.]?\)', q2_text).end()
    a_end = re.search('\([bBdDfF][\.]?\)', q2_text).start()
    b_start = re.search('\([bBdDfF][\.]?\)', q2_text).end()
    
    q2a_ticked = (re.search('[xX]', q2_text[a_start:a_end]) is not None)
    q2b_ticked = (re.search('[xX]', q2_text[b_start:]) is not None)
    
    return(q2a_ticked, q2b_ticked)
    
    
    
def q4_get_source_of_funds(q4_text, form_type):
    
    if(re.search('13D', form_type)):
    
        text = get_answer_text(q4_text, form_type, 4)

        result = re.findall('(SC|BK|AF|WC|PF|OO|00)', text)
        result = [re.sub('00', 'OO', x) for x in result]
        
        return(result)
        
    else:
        
        raise ValueError("form is not of type SC 13D or SC 13D/A")
  
  
def q5_12_box(q_text, form_type, question_number):
    
   
    if(re.search('13D', form_type)):
        
        if(question_number in [5, 12]):
        
            text = get_answer_text(q_text, form_type, question_number)
            result = (re.search('[xX1]', text) is not None)
            return(result)
    
        else:
            raise ValueError("form is of type SC 13D(/A), but question_number is not 5 or 12")
            
    elif(re.search('13G', form_type)):
        
        if(question_number == 10):
        
            text = get_answer_text(q_text, form_type, question_number)
            result = (re.search('[xX1]', text) is not None)
            return(result)
    
        else:
            raise ValueError("form is of type SC 13G(/A), but question_number is not 10")
        
    else:
        
        raise ValueError("form is not of type SC 13D(/A) or SC 13G(/A)")        
        
        
        
def q14_get_type_rep_person(q14_text, form_type, question_number):
    
    is_13d = re.search('13D', form_type) is not None
    is_13g = re.search('13G', form_type) is not None
    
    if((is_13d and question_number == 14) or (is_13g and question_number == 12)):
    
        text = get_answer_text(q14_text, form_type, question_number)

        result = re.findall('(BD|BK|IC|IV|IA|EP|HC|SA|CP|CO|C0|PN|IN|OO|00)', text)
        result = [re.sub('0', 'O', x) for x in result]
        
        return(result)
        
    else:
        
        if(is_13d):
            
            raise ValueError("form is of type SC 13D or SC 13D/A, but question number is not 14")
            
        if(is_13g):
            
            raise ValueError("form is of type SC 13G or SC 13G/A, but question number is not 12")
            
        else:
            
            raise ValueError("form is not of type SC 13D or SC 13D/A")


def get_reporting_page_df(reporting_page, form_type):
    
    q_and_a = get_filing_report_q_and_a(reporting_page, form_type)
    
    answer_dict = {}
    answer_dict['form_type'] = [form_type]
    is_13d = re.search('13D', form_type) is not None
    is_13g = re.search('13G', form_type) is not None
    
    if(is_13g):
      
      # These fields do not appear in SC 13G or SC 13G/A. Set them to None
      answer_dict['SC_13D_box_5'] = None
      answer_dict['source_of_funds'] = None
      
    
    for key, q_text in q_and_a.items():
    
        if(key == 0):
            cusips, sedols = get_reporting_page_cusip_sedol(q_text)
            answer_dict['cusips'] = [cusips]
            answer_dict['sedols'] = [sedols]
            
        elif(key == 1):
            
            answer_dict['rep_person_name'] = [get_answer_text(q_text, form_type, key)]

        elif(key == 2):

            q_2a_ticked, q_2b_ticked = q2_boxes_a_and_b(q_text)
            answer_dict['box_2a'] = [q_2a_ticked]
            answer_dict['box_2b'] = [q_2b_ticked]

        elif(key == 3):

            pass
        
        elif(key == 4 and is_13d):
            
            answer_dict['source_of_funds'] = [q4_get_source_of_funds(q_text, form_type)]
            
        elif(key == 5 and is_13d):
            
            answer_dict['SC_13D_box_5'] = [q5_12_box(q_text, form_type, key)]
            
        elif((key == 4 and is_13g) or (key == 6 and is_13d)):
            
            answer_dict['citizenship_place_of_organization'] = [get_answer_text(q_text, form_type, key)]
             
        elif((key == 7 and is_13d) or (key == 5 and is_13g)):
            
            answer_dict['num_shares_sole_vp'] = [get_answer_text(q_text, form_type, key)]
             
        elif((key == 8 and is_13d) or (key == 6 and is_13g)):
            
            answer_dict['num_shares_shared_vp'] = [get_answer_text(q_text, form_type, key)]
             
        elif((key == 9 and is_13d) or (key == 7 and is_13g)):
            
            answer_dict['num_shares_sole_dp'] = [get_answer_text(q_text, form_type, key)]
             
        elif((key == 10 and is_13d) or (key == 8 and is_13g)):
            
            answer_dict['num_shares_shared_dp'] = [get_answer_text(q_text, form_type, key)]
             
        elif((key == 11 and is_13d) or (key == 9 and is_13g)):
            
            answer_dict['agg_amount_owned'] = [get_answer_text(q_text, form_type, key)]
             
        elif((key == 12 and is_13d) or (key == 10 and is_13g)):
            
            answer_dict['certain_shares_exc_from_agg'] = [q5_12_box(q_text, form_type, key)]
             
        elif((key == 13 and is_13d) or (key == 11 and is_13g)):
            
            answer_dict['agg_amount_percentage_share'] = [get_answer_text(q_text, form_type, key)]
             
        elif((key == 14 and is_13d) or (key == 12 and is_13g)):
            
            answer_dict['reporting_person_type'] = [q14_get_type_rep_person(q_text, form_type, key)]
             
             
    df = pd.DataFrame(answer_dict)
             
    return(df)


def get_all_reporting_pages_df(reporting_pages_text, file_name, form_type, is_rep_q_as_items):
    
    pages = get_reporting_pages(reporting_pages_text, form_type, is_rep_q_as_items)
    
    df_list = []
    
    for i in range(len(pages)):
        
        df = get_reporting_page_df(pages[i], form_type)
        df['file_name'] = file_name
        df['seq'] = i + 1
        
        df_list.append(df)
    
    order = ['file_name', 'form_type', 'seq', 'cusips', 'sedols', 'rep_person_name', 'box_2a', 'box_2b', \
                 'source_of_funds', 'SC_13D_box_5', 'citizenship_place_of_organization', 'num_shares_sole_vp', \
                 'num_shares_shared_vp', 'num_shares_sole_dp', 'num_shares_shared_dp', 'agg_amount_owned', \
                 'certain_shares_exc_from_agg', 'agg_amount_percentage_share', 'reporting_person_type']
    
    if(len(df_list)):
    
        full_df = pd.concat(df_list, ignore_index = True)
        full_df = full_df[order]
        
    else:
        
        full_df = pd.DataFrame(columns = order)
    
    return(full_df)



def test_get_reporting_pages_by_file_name(file_name, form_type):
    
    url = get_txt_file_url(file_name)
    text = requests.get(url).text
    
    _, _, reporting_pages_text, _, _, _ = get_text_components(text)
    
    df = get_all_reporting_pages_df(reporting_pages_text, file_name, form_type)
    
    return(df)



    
def calculate_sedol_check_digit(sedol):
    
    values = {'0': 0, '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9,
              'A': 10, 'B':11, 'C': 12, 'D': 13, 'E':14, 'F': 15, 'G': 16, 'H': 17, 'I': 18, 'J': 19,
              'K': 20, 'L': 21, 'M': 22, 'N': 23, 'O': 24, 'P': 25, 'Q': 26, 'R': 27, 'S': 28, 'T': 29,
              'U': 30, 'V': 31, 'W': 32, 'X': 33, 'Y': 34, 'Z': 35, '*': 36, '@': 37, '#': 38
               }
    
    digit_str = ''
    
    weights = [1, 3, 1, 7, 3, 9]
    
    if(len(sedol) >= 6):
    
        weighted_sum = 0
    
        for i in range(6):
            
            weighted_sum = weighted_sum + weights[i] * values[sedol[i]]

        
        weighted_sum_mod_10 = weighted_sum % 10

        result = (10 - weighted_sum_mod_10) % 10

        return(result)
    
    
    else:
        
        return(None)    
    


### These are import cases where words have been extracted as cusips. Want to build a set to handle these exceptions

['NONE13D', 'SCHEDULE', 'SCHEDULEA', 'PAGEOF', 'PAGE[0-9]{1,2}OF', 'PAGE[0-9]{1}OF[1-9]{1,2}', 'PAGE[0-9]{1,2}OF[1-9]{1}', ]


