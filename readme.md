# EDGAR

## List of tables

- `filings`: Index of all filings in the SEC EDGAR database (since 1993). Code: [`get_filings.R`](get_filings.R).
- `accession_numbers`: Each filing has an accession number. This table contains these. Code: [`get_accession_nos.R`](get_accession_nos.R):
- `cusip_cik`: Table mapping CUSIPs to CIKs. Data are scraped from `SC 13D` and `SC 13G` forms.
- `filer_ciks`: Data on filer CIKs from `SC 13D` and `SC 13G` forms. Code: [`get_filer_ciks.R`](get_filer_ciks.R).
- `filing_docs`: Table listing the documents associated with each filing. 
See [here](filing_docs.md). Code: [`get_filing_docs.R`](get_filing_docs.R).
- `item_no`: Table listing item numbers associated with each 8-K filing. 
Code:  [`get_item_nos.R`](get_item_nos.R)
- `item_no_desc`: Table providing explanations for each item number used in 8-K filings. Data extracted from [here](https://www.sec.gov/fast-answers/answersform8khtm.html). Code: [`get_item_no_desc.R`](get_item_no_desc.R) scrapes the descriptions for each of the unique item numbers stored in `item_no`. 
- `server_log`: **Details to come.**

### Tables used in updating tables above

- `index_last_modified`: Table used in updating `filings`.
- `filing_docs_processed`: Table used in updating `filing_docs`. 
- `server_log_processed`: Table used in updating `server_log`.

## Code

A script to update the Edgar database is found [here](update_edgar.sh).

- [`get_server_logs.R`](server_logs/get_server_logs.R): Script to get server logs from EDGAR to populate `server_log` and `server_log_processed`.
- [`get_13D_filings.R`](get_13D_filings.R): Script to get the 13D filings. Always run this before running `extract_cusips.R`.
- [`get_13D_filing_details`](get_13D_filing_details.R): Extracts the details from the files contained in `edgar.filings`
- [`extract_cusips.pl`](extract_cusips.pl): Contains Perl code which extracts the cusip_cik numbers. This file is used and sourced by extract_cusips.R, so one should run the latter to put the cusip_ciks in the database.
- [`extract_cusips.R`](extract_cusips.R): Puts the cusip_cik numbers in the database.
