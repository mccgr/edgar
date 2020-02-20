# The indexing of Schedule 13D and Schedule 13G in the table `edgar.sc13dg_indexes`

This readme describes the table `edgar.sc13dg_indexes`. This purpose of this table is to give the indexes of the key parts of the documents, and to contain other information pertaining to the style used for the documents, so that it may be used later to extract information from the documents (such as `Cusip` numbers, or the information contained in the cover pages) in a clean and unambiguous manner. The extraction of the latter information is intended to be written into future tables in the database. 
    
So far, the usefulness and cleanness of the indexes varies; some indexes are very clearly found in the vast majority of cases, whereas some are found successfully only occassionally. The functions finding these indexes sometimes use a large number of regular expressions (particularly in the case)
    
    
    
    
    
## The table `edgar.sc13dg_indexes` and its fields


- `file_name`: the name of the filing. Same as the `file_name` in `edgar.filings`, `edgar.filing_docs`, and other tables which contain it. 

- `document`: the name of the document under the filing. Same as the `document` field in `edgar.filing_docs`.

- `form_type`: The form type of the filing. This is the same as `form_type` in `edgar.filings`, though subsetted to be one of `SC 13D`, `SC 13D/A`, `SC 13G`, or `SC 13G/A`

- `title_page_end_lower_bound`: this field gives a lower bound estimate of the end of the text on the title page of the filing, as found by the function `find_title_page_end`. This function finds a good answer for this field in around 90 percent of cases

- `cover_page_q1_start`: this field gives the index (if found succesfully) of the start of the first question of the first cover page. The statement of this question has very little variance, and it can found very accurately in almost all cases. This is an important field to know, as it can be used later on to help find `cover_page_start`, the start of the cover page section. 

- `is_rep_q_as_items`: for a small, but substantial number of filings (a little over 5 percent) have a format in which the cover pages are given very concisely on one line, but with the answer for each question of a cover page denoted, for example, `Item 1: (answer)`, `Item 2: (answer)`, and so on, until the last question of the cover page, which is number 14 for `SC 13D` and `SC 13D/A`, and 12 for `SC 13G` or `SC 13G/A`. It is important to know if a filing if of this style, since in these cases functions could potentially confuse the cover page section for the item section, or vice versa. So this field is a boolean variable, equal to `True` if the filing has this style, and `False` otherwise. The determination of this field is done by the function `is_rep_q_as_items`. The vast majority of these forms are either `SC 13G` or `SC 13G/A` (around 3 percent of cases for `SC 13G`, 9 percent for `SC 13G/A`).

- `is_schedule_to`: a small number of forms filed as `SC 13D`, `SC 13D/A`, `SC 13G`, or `SC 13G/A`, are in reality of type Schedule TO (`SC TO-C`, `SC TO-I`, `SC TO-I/A`, `SC TO-T`, or `SC TO-T/A`). This field is `True` if this is the case, and `False` otherwise. The frequency of these cases is around 0.06 percent.

- `has_table_of_contents`: A small number of cases (around 1 percent) have a table of contents below the end of the title page. This can confuse functions which search for the diverse sections of the document, as they can be stated and hyperlinked in the table of contents. This field is `True` in the case there is a table of contents, and `False` otherwise. 

- `num_cusip_sedol_b_q1`: this is the number of times either `Cusip` or `Sedol` appears before the first question of the first cover page. Used to determine if the last `Cusip` or `Sedol` appearing before the first question belongs to the first cover page, or to the title page. 

- `cover_page_start`: as alluded to in the definition of `cover_page_q1_start`, this is what is defined to be the actual start of the cover page section. It is found by taking `cover_page_q1_start`, and then looking backwards in the text for certain key words/regular expressions (eg. 'Cusip', 'Sedol', 'Schedule', '13[DG]', 'Page(s)') which typically appear just above question 1, and taking the starting index of the earliest occurance amongst these expressions as the value of this field. The field `title_page_end_lower_bound` is used as an opposite bound, if it is non-trivial. 

- `item_section_start`: this field gives the index for the start of the item section, usually taken to be the very beginning of the string which represents the first item, `Item 1`. As noted above, this could be considered confusing in the cases where `is_rep_q_as_items`, but in the case of `SC 13D` or `SC 13D/A`, the last item is `Item 7`, and in the case of `SC 13G` or `SC 13G/A` the last item is `Item 10`, so the sections can be distinguished by noting which one has `Item 14` in the case of the former, and `Item 12` in the latter case (in fact, the existence of these higher item numbers is what determines `is_rep_q_as_items`).

- `cover_page_last_q_end`: this field gives the index for the start of the last question of the last cover page. The statement of this question does not vary much among filings, so it can be found very accurately in almost all cases. This is an important field to know, as it can help to determine the actual end of the last cover page, and thus the end of the cover page section. For `SC 13D` or `SC 13D/A`, the number of the last question of a cover page is question number 14, and for `SC 13G` or `SC 13G/A` it is question 12.

- `cover_page_end`: the index of the end of the cover page section. This is found by searching for either the end of the footnotes of the cover pages, if they exist, or the end of the answer to the last question of the last cover page if there are no footnotes. 

- `num_cusip_b_items`: the number of times either `Cusip` or `Sedol` appears before the item section.

- `signature_start`: the starting index of the signature section. The vast majority of cases have this section starting with a line of the regex form `\n\s+SIGNATURE(S)?\s+\n` (ie. 'SIGNATURE' or 'SIGNATURES' in the middle of one line), and so this index is very clean and can be found very easily in the vast majority of cases. 

- `exhibit_start`: the starting index of the section containing the exhibits or a section pertaining to the exhibits (such as an 'EXHIBIT INDEX' section), if provided and existing in the main text. Normally appears after the signature section. An exhibits section in the main text is especially common in older filings in which there is little html to distinguish the parts, whereas newer filings usually have the main document text and the exhibits in separate `<DOCUMENT>` tags (the function `get_main_doc_text` just obtains the text for the tag corresponding to the main text if this is the case).

- `main_text_length`: this is the length, in number of characters, of the main text.

- `explanatory_statement_start` : this is admittedly an experimental field, intended to contain the index of the start of a statement that sometimes appears between the cover page section 

- `has_jumbled_order`: a boolean variable which is `TRUE` if: the cover page section, item section and signature section are not in the usual order (normally, the cover page section appears after the title page, followed by the item section), or there is some other arrangement that strays from the normal structure (eg. a filing which has the normal form up to the end of the signature section, but then has a cover page following the signature section). This variable is `FALSE` if the filing was successfully processed and it has the normal ordering and form, and `NULL` if it was not successfully processed.

- `has_exhibit_break`: a boolean variable which is `TRUE` if there are exhibit parts before the signature section, `FALSE` if the filing is successfully processed and this is not the case, and `NULL` if the filing was not successfully processed.

- `success`: a boolean variable which is `TRUE` if the indexes for the filing document were successfully processed, and `FALSE` otherwise. 







