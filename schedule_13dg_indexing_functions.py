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
    

def clean_text(text):
    
    # this function gets rid of unwanted characters and spaces
    
    result = text
    
    char_list = ['\xa0', '&#160;', '&#\n160;']
    
    for c in char_list:
        
        result = re.sub(c, ' ', result) 
        
    return(result)

   
    
def get_main_doc_text(file_name, document, directory):
  
    full_text = clean_text(get_file_text_from_directory(file_name, document, directory))
    soup = BeautifulSoup(full_text, 'html5lib')
    main_doc_text = soup.find(["document", "DOCUMENT"]).get_text()
    
    return(main_doc_text)
    
   
   
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
        
        
def find_orthodox_cover_page_q1_start(text):

    text_raised = text.upper()

    regex0 = '\s+[\(\|]?\s*[1L]\s*[\)\|]?\s*[:\.]{0,1}(\s*[\(\|]\s*A\s*[\)\|])?\s*(.){0,50}\s*' + \
             'NAME[\(]?[S]?[\)]?\s+(?:OF|OR)(\s+THE)?\s+(?:REPORTING|ABOVE|REPORT)'
    
    regex1 = '\s+[\(\|]?\s*[1L]\s*[\)\|]?\s*[:\.]{0,1}(\s*[\(\|]\s*A\s*[\)\|])?\s*(.){0,50}\s*' + \
             'NAME[\(]?[S]?[\)]?\s+(?:OF|OR)(\s+THE)?(\s+(?:REPORTING|ABOVE|REPORT))?\s+' + \
             'PERSON[\(]?[S]?[\)]?'

    regex2 = '\s+[\(\|]?\s*[1L]\s*[\)\|]?\s*[:\.]{0,1}(\s*[\(\|]\s*A\s*[\)\|])?\s*(.){0,50}\s*' + \
             'NAME[\(]?[S]?[\)]?\s+(?:AND|OF|OR)(\s+I[\.]?R[\.]?S)?\s+IDENTIFICATION\s+NO[\(]?[S]?[\)]?\.'
    
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
    
    regex9 = 'NAME[\(]?[S]?[\)]?\s+(?:AND|OF|OR)(\s+I[\.]?R[\.]?S)?\s+IDENTIFICATION\s+NO[\(]?[S]?[\)]?.'
    
    regex10 = '\s+[\(\|]?\s*[1L]\s*[\)\|]?\s*[:\.]{0,1}(\s*[\(\|]\s*A\s*[\)\|])?\s*(.){0,50}\s*' + \
              'NAME[\(]?[S]?[\)]?\s+(?:AND|OF|OR)(\s+I[\.]?R[\.]?S)?\s+NUMBER\s+OF\s+REPORTING\s+PERSON[S]?'
    
    
    regex_list = [regex0, regex1, regex2, regex3, regex4, regex5, regex6, regex7, regex8, regex9, regex10]
    
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
        
    answer_regex = '\s*([A-Z0]{1}[;, \.]?[A-Z0]{1}[;, \.]?)*([A-Z0]{1}[;, \.]?[A-Z0]{1}[;, \.]?)\s*\n?'
    
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
    
    
    regex0 = '\n\s*item\s+10(\.)?\s+certification'
    
    regex1 = 'the\s+following\s+certification\s+shall\s+be\s+included\s+if\s+the\s+statement\s+is\s+filed\s+' + \
             'pursuant to rule 13d-1\(b\)'
    
    regex2 = 'by\s+signing\s+below\s+i\s+certify\s+that,\s+to\s+the\s+best\s+of\s+my\s+knowledge'
    
    regex3 = '\n\s*(signature|signatures)\s*(\.)?\n'

    regex4 = 'after\s+reasonable\s+inquiry\s+'
    
    regex_list = [regex0, regex1, regex2, regex3, regex4]
    
    regex_search = None
    
    for i in range(len(regex_list)):
        
        regex_search = re.search(regex_list[i], text_lowered)
        
        if(regex_search):
            
            break
        
    if(regex_search):
        
        return(regex_search.start())
    
    else:
        return(None)
    
    
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
    
    key_info['amendment_statement_start'] = find_amendment_statement_start(text, form_type, \
                    lower_bound = amend_l_bound, upper_bound = key_info['item_section_start'][0])
    
    
    key_info_df = pd.DataFrame(key_info)
    
    return(key_info_df) 
    
    
def write_indexes_to_table(file_name, document, form_type, directory, engine):
    
    try:
        
        df = get_key_indices(file_name, document, form_type, directory)
        df['success'] = True
        df.to_sql('sc13dg_indexes', engine, schema="edgar", if_exists="append", index=False)
        
    except:
        
        df = pd.DataFrame({'file_name': [file_name], 'document': [document], 'form_type': [form_type], \
              'title_page_end_lower_bound': [-2], 'cover_page_q1_start': [-2], 'is_rep_q_as_items': [-2],\
              'num_cusip_sedol_b_q1': [-2], 'cover_page_start': [-2], 'item_section_start': [-2], \
              'cover_page_last_q_end': [-2], 'cover_page_end': [-2], 'num_cusip_b_items': [-2],\
              'signature_start': [-2], 'amendment_statement_start': [-2], 'success': [False]})
        
        df.to_sql('sc13dg_indexes', engine, schema="edgar", if_exists="append", index=False)    
    
    
    
    
    
    
    
    
