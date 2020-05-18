#!/usr/bin/env bash
echo "Running get_ciks.py ..."
filer_ciks/get_ciks.R
echo "Running get_filings.R ..."
core/get_filings.R
echo "Running get_accession_nos.R ..."
core/get_accession_nos.R
echo "Running get_filer_ciks.R ..."
filer_ciks/get_filer_ciks.R
echo "Running get_item_nos.R ..."
item_nos/get_item_nos.R
echo "Running get_item_no_desc.R ..."
item_nos/get_item_no_desc.R
# $EDGAR_CODE_DIR/./get_server_logs.R
echo "Running scrape_filing_docs.R ..."
filing_docs/scrape_filing_docs.R
