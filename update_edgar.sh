#!/usr/bin/env bash
echo "get_filings"
./get_filings.R
echo "get_accession_nos"
./get_accession_nos.R
echo "get_filing_docs"
./get_filing_docs.R
echo "get_filer_ciks"
./get_filer_ciks.R
echo "get_item_nos"
./get_item_nos.R
echo "get_item_no_desc"
./get_item_no_desc.R
# ./get_server_logs.R
