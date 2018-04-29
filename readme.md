# EDGAR

## List of tables

- `filings`: Index of all filings in the SEC EDGAR database (since 1993)
- `accession_numbers`: Each filing has an accession number. This table contains these.
- `cusip_cik`: Table mapping CUSIPs to CIKs. Data are scraped from `SC 13D` and `SC 13G` forms.
- `filer_ciks`: Data on filer CIKs from `SC 13D` and `SC 13G` forms.
- `filing_docs`: Table listing the documents associated with each filing. 
- `item_no`: Table listing item numbers associated with each 8-K filing.
- `item_no_desc`: Table providing explanations for each item number used in 8-K filings. Data extracted from [here](https://www.sec.gov/fast-answers/answersform8khtm.html).
- `server_log`: **Details to come.**

### Tables used in updating tables above
- `server_log_processed`: Table used in updating `server_log`.
- `index_last_modified`: Table used in updating `filings`.
- `filing_docs_processed`: Table used in updating `filing_docs`. See [here](filing_docs.md).

## Code

- [`get_filings.R`](get_filings.R): Script to get index files from EDGAR to populate `filings`.
- [`get_accession_nos.R`](get_accession_nos.R): Script to get the accession numbers from the EDGAR file URLs.
- [`get_filing_docs.R`](get_filing_docs.R): Script to blah 
- [`get_filer_ciks.R`](get_filer_ciks.R): Script to blah
- [`get_item_nos.R`](get_item_nos.R): Script to blah
- [`get_item_no_desc.R`](get_item_no_desc.R): Script to scrape the descriptions for each of the unique item numbers stored in `item_no`, and store them in the table `item_no_desc`.
- [`get_server_logs.R`](server_logs/get_server_logs.R): Script to get server logs from EDGAR to populate `server_log` and `server_log_processed`.
- [`get_13D_filings.R`](get_13D_filings.R): Script to get the 13D filings. Always run this before running `extract_cusips.R`.
- [`get_13D_filing_details`](get_13D_filing_details.R): Extracts the details from the files contained in `edgar.filings`
- [`extract_cusips.pl`](extract_cusips.pl): Contains Perl code which extracts the cusip_cik numbers. This file is used and sourced by extract_cusips.R, so one should run the latter to put the cusip_ciks in the database.
- [`extract_cusips.R`](extract_cusips.R): Puts the cusip_cik numbers in the database.

A script to update the Edgar database is found [here](update_edgar.sh).


