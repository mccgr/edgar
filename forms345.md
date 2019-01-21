# Forms 3, 4, and 5

## Description

This README file describes the collection of tables used to store data extracted from the xml files associated with the filings for Forms 3, 4 and 5.


## List of tables

* `forms345_header`: This table contains all information at the heading of each xml file, as well as that contained in the `remarks` node. This set of information corresponds with all information not contained in any of the subsequent tables mentioned below. The variables are:

  - `file_name`: this is the file name of the filing
  - `document`: this is the name of the filing document
  - `schemaVersion`: this is the version number of the
  - `documentType`: this is the form type of the filing (`3`, `4`, `5`, `3/A`, `4/A`, or `5/A`)
  - `periodOfReport`: the date of the earliest transaction
  - `dateOfOriginalSubmission`:
  - `noSecuritiesOwned`: this Boolean variable is `TRUE` in the case that the filing is a Form 3 and the insider does not own any securities; in this case, there will be no entries in either Table 1 or Table 2. Otherwise, this variable is `FALSE` or null.
  - `notSubjectToSection16`:
  - `form3HoldingsReported`: this Boolean variable is `TRUE` in the case that the filing is a Form 5 and the insider is reporting any holdings that should have been reported on a previous Form 3. The insider is required to provide a footnote as a an explanation. Otherwise, this variable is `FALSE` or null.
  - `form4TransactionsReported`: this Boolean variable is `TRUE` in the case that the filing is a Form 5 and the insider is reporting any transactions that should have been reported on a previous Form 4. The insider is required to provide a footnote as a an explanation. Otherwise, this variable is `FALSE` or null.
  - `issuerCik`: the Central Index Key (CIK) of the issuer/company
  - `issuerName`: the name of the issuer/company
  - `issuerTradingSymbol`: the Trading Symbol of the issuer/company
  - `remarks`: additional remarks on the filing

* `forms345_reporting_owners`: This table contains the information on all the reporting owners listed in the filing. In the xml file for each filing, the information on each reporting owner is contained in each of the `reportingOwner` nodes. The fields are:

  - `file_name`: As above
  - `document`: As above
  - `seq`: An index indicating the order in which the reporting owner appeared in the xml file.
  - `rptOwnerCik`: The CIK number of the reporting owner
  - `rptOwnerCcc`: The CCC number of the reporting owner. This field is optional in the xml file when the reporting owner makes the filing, though the CCC number has to be provided to the SEC so that the filing can be made with the given CIK number. (This may be redundant. Has not been found to be non-null on any publically displayed xml file. Probably a variable that the SEC uses internally)
  - `rptOwnerName`: the name of the reporting owner
  - `rptOwnerStreet1`: the primary street address of the reporting owner or the first piece of information about the reporting owner's address
  - `rptOwnerStreet2`: a secondary street address of the reporting owner or the second piece of information about the reporting owner's address
  - `rptOwnerCity`: The reporting owner's city
  - `rptOwnerState`: The state in which the reporting owner resides
  - `rptOwnerZipCode`: The zip code of the reporting owner's address
  - `rptOwnerStateDescription`: A description of, or further information on, the reporting owner's state, often used if the reporting owner's address is outside the United States
  - `rptOwnerGoodAddress`: (This may be redundant. Has not been found to be non-null on any publically displayed xml file. Probably a variable that the SEC uses internally)
  - `isDirector`: this field is `TRUE` if the reporting owner is a director in the company, else it is `FALSE`
  - `isOfficer`: this field is `TRUE` if the reporting owner is an officer in the company, else it is `FALSE`. If `TRUE`, the filling of the `officerTitle` field is then mandatory.
  - `isTenPercentOwner`: this field is `TRUE` if the reporting owner is an officer in the company, else it is `FALSE`
  - `isOther`: this field is `TRUE` if the reporting owner is not , else it is `FALSE`. If `TRUE`, the filling of the `otherText` field is then mandatory, to explain the reporting owner's role with the issuer.
  - `officerTitle`: A description of the reporting owner's title as an officer, if the reporting owner has entered `TRUE` for `isOfficer`. This field must be filled if `isOfficer` is set to `TRUE`
  - `otherText`: A description of the reporting owner's role or former role with the issuer/company, if the reporting owner has entered `TRUE` for `isOther`. This field must be filled if `isOther` is set to `TRUE`

* `forms345_signatures`: Contains the information on each person who signed the filing. The information on each of these is contained in the `ownerSignature` nodes for each corresponding xml file, and as with the number of reporting owners before, there can be more than one signatory for each filing. The fields are:

  - `file_name`: As above
  - `document`: As above
  - `seq`: the node number/index corresponding to the particular signature
  - `signatureName`: the name of the signatory
  - `signatureDate`: the date of the signature

* `forms345_table1`: Corresponds to Table 1 on Forms 3, 4 and 5; that is, the table containing information on all non-derivative transactions and holdings. The fields are:

  - `file_name`: As above
  - `document`: As above
  - `form_type`: the form type of the filing
  - `transactionOrHolding`: a variable which states whether the row corresponds to a transaction or a holding. Equal to either `Transaction` or `Holding` for these respective cases.
  - `seq`: the row number/index of the transaction/holding as it appears in the table with a given `tab_index` (as explained below) on the corresponding form.
  - `tab_index`: the index of the instance of `nonDerivativeTable` from which the transaction or holding originated as a `nonDerivativeTransaction` or `nonDerivativeHolding` node respectively.
  - `securityTitle`: the name of the type of security for the transaction or holding.
  - `transactionDate`: the date of the transaction (if `transactionOrHolding` is equal to `Transaction`, otherwise this is null).
  - `deemedExecutionDate`:
  - `transactionFormType`: the form type of the transaction (this is null if the row corresponds to a holding). This is not always the same as the `form_type`.
  - `transactionCode`: the code of the transaction. See Section 3.6.9 in this [document](https://www.sec.gov/info/edgar/ownershipxmltechspec-v3.pdf) for more details.
  - `equitySwapInvolved`: a Boolean variable which is True if the transaction involves an equity swap, and False if the transaction does not. This field is null for holdings.
  - `transactionTimeliness`:
  - `transactionShares`: the number of shares traded in the transaction, if the row corresponds to a transaction. Otherwise, for holdings, this field is null.
  - `transactionPricePerShare`: the price per share of the security traded in the transaction, if the row corresponds to a transaction. Otherwise, for holdings, this field is null.
  - `transactionAcquiredDisposedCode`: this field contains a code for whether the reporting owner(s) acquired or disposed shares in the transaction. If shares were acquired, this field is equal to `A`, if disposed, it is equal to `D`. If the row corresponds to holding, this field is null.
  - `sharesOwnedFollowingTransaction`: the number of shares in the security owned following a transaction, if the row corresponds to a `Transaction`. If the row corresponds to a `Holding`, it is simply the number of shares owned. This field is null if the reporting owner(s) filled `valueOwnedFollowingTransaction` instead.
  - `valueOwnedFollowingTransaction`: the value of the shares/stock in the security owned following a transaction, if the row corresponds to a `Transaction`. If the row corresponds to a `Holding`, it is simply the value of shares/stock owned. This field is null if the reporting owner(s) filled `valueOwnedFollowingTransaction` instead.
  - `directOrIndirectOwnership`: a field which is equal to `D` if the ownership is direct, or `I` if the ownership is indirect.
  - `natureOfOwnership`: a field which provides further details on the ownership, if the ownership is indirect. If `directOrIndirectOwnership` is equal to `D`, this field is null.

* `forms345_table2`: Corresponds to Table 2 on Forms 3, 4 and 5; that is, the table containing information on all derivative transactions and holdings. The fields are:

  - `file_name`: As above
  - `document`: As above
  - `form_type`: the form type of the filing.
  - `transactionOrHolding`: a variable which states whether the row corresponds to a transaction or a holding. Equal to either `Transaction` or `Holding` for these respective cases.
  - `seq`: the row number/index of the transaction/holding as it appears in the table with a given `tab_index` (as explained below) on the corresponding form.
  - `tab_index`: the index of the instance of `derivativeTable` from which the transaction or holding originated as a `derivativeTransaction` or `derivativeHolding` node respectively.
  - `securityTitle`:  the name of the type of security for the transaction or holding.
  - `conversionOrExercisePrice`: the conversion or exercise price of the derivative security
  - `transactionDate`: the date of the transaction (if `transactionOrHolding` is equal to `Transaction`, otherwise this is null).
  - `deemedExecutionDate`:
  - `transactionFormType`: the form type of the transaction (this is null if the row corresponds to a holding). This is not always the same as the `form_type`.
  - `transactionCode`: the code of the transaction. See Section 3.6.9 in this [document](https://www.sec.gov/info/edgar/ownershipxmltechspec-v3.pdf) for more details.
  - `equitySwapInvolved`: a Boolean variable which is True if the transaction involves an equity swap, and False if the transaction does not. This field is null for holdings.
  - `transactionTimeliness`:
  - `transactionShares`: the number of shares traded in the transaction, if the row corresponds to a transaction. Otherwise, for holdings, this field is null.
  - `transactionTotalValue`: the total value of the security traded in the transaction, if the row corresponds to a transaction. Otherwise, for holdings, this field is null.
  - `transactionPricePerShare`: the price per share of the security traded in the transaction, if the row corresponds to a transaction. Otherwise, for holdings, this field is null.
  - `transactionAcquiredDisposedCode`: this field contains a code for whether the reporting owner(s) acquired or disposed shares/stock in the transaction. If shares were acquired, this field is equal to `A`, if disposed, it is equal to `D`. If the row corresponds to holding, this field is null.
  - `exerciseDate`: the date from which a derivative is exercisable
  - `expirationDate`: the date on which a derivative expires
  - `underlyingSecurityTitle`: the name of the type of underlying security from which the derivative derives its value
  - `underlyingSecurityShares`: the number of shares of the underlying security
  - `underlyingSecurityValue`: the total value of the underlying security
  - `sharesOwnedFollowingTransaction`: the number of shares in the security owned following a transaction, if the row corresponds to a `Transaction`. If the row corresponds to a `Holding`, it is simply the number of shares owned. This field is null if the reporting owner(s) filled `valueOwnedFollowingTransaction` instead.
  - `valueOwnedFollowingTransaction`: the value of the shares/stock in the security owned following a transaction, if the row corresponds to a `Transaction`. If the row corresponds to a `Holding`, it is simply the value of shares/stock owned. This field is null if the reporting owner(s) filled `valueOwnedFollowingTransaction` instead.
  - `directOrIndirectOwnership`: a field which is equal to `D` if the ownership is direct, or `I` if the ownership is indirect.
  - `natureOfOwnership`: a field which provides further details on the ownership, if the ownership is indirect. If `directOrIndirectOwnership` is equal to `D`, this field is null.

* `forms345_footnotes`: This table contains information on all the footnotes listed in footnote section; that is under the `footnotes` node in each xml file. The fields are:

  - `file_name`: As above
  - `document`: As above
  - `footnote_index`: the index of the footnote. This index is cited in the `footnoteId` nodes where relevant in the xml files
  - `footnote`: the content of the footnote

* `forms345_footnote_indices`: Tracks the table, variable name and indices of each use of each of the footnotes in `forms345_footnotes`.

  - `file_name`: As above
  - `document`: As above
  - `table`: The name of the table for the instance of the footnote index corresponding to the row. Equal to `header`, `table1`, `table2`, `reporting_owners` or `signatures`. Notice the omission of the `forms345_` stem from the names of the tables.
  - `tab_index`: The same as `tab_index` in `forms_345_table1` if `table` is equal to `table1`, and likewise `tab_index` in `forms345_table2` if `table` is equal to `table2`. This field is null for rows where `table` is equal to `header`, `reporting_owners` or `signatures`, or for the rows with `table` equal to `table1` or `table2` which correspond to `nonDerivativeSecurity` or `derivativeSecurity` nodes, rather than the subnodes within a `nonDerivativeTable` or `derivativeTable` node.
  - `seq`: For cases where `table` is equal to `table1`, `table2`, `reporting_owners` or `signatures`, this is equal to `seq` from the tables `forms_345_table1`, `forms_345_table2`, `forms_345_reporting_owners` and `forms_345_signatures` respectively. This field is null in the case where `table` is equal to `header`.
  - `footnote_variable`: the name of the variable/node under which the footnote was made. This usually corresponds to a column name from the corresponding `table`. There is, however, a common exception; some rows, with `table` equal to `table1` or `table2`, have this field equal to `transactionCoding`, which is the name of the parent node for the nodes yielding the fields `transactionCode`, `transactionFormType` and `equitySwapInvolved` from the tables `forms345_table1` and `forms345_table2`.
  - `footnote_index`: the index of the footnote, which is the same as the corresponding `footnote_index` in `forms345_footnotes`.

* `forms345_xml_process_table`: This table tracks the success of the scraping of the data for each of the tables, the success of writing the data for each of the tables to the database, as well as a number of key properties of `forms345_table1` and `forms345_table2`. This table is written to by the function `process_345_filing`, after this function has done the required scraping and writing. The fields are:

  - `file_name`: As above
  - `document`: As above
  - `form_type`: the form type of the filing
  - `got_xml`: this variable is `True` if the xml was successfully extracted into RAM, `False` otherwise
  - `got_header`: `True` if the contents pertaining to `forms345_header` were successfully extracted, `False` otherwise
  - `got_rep_own`: `True` if the contents pertaining to `forms345_reporting_owners` were successfully extracted, `False` otherwise
  - `got_table1`: `True` if the contents pertaining to `forms345_table1` were successfully extracted, `False` otherwise
  - `num_non_derivative_tables`: the number of `nonDerivativeTable` nodes in the xml file
  - `num_non_derivative_tran`: the total number of `nonDerivativeTransaction` nodes in the xml file (these are children of `nonDerivativeTable`)
  - `num_non_derivative_hold`: the total number of `nonDerivativeHolding` nodes in the xml file (these are children of `nonDerivativeHolding`)
  - `num_non_derivative_sec`: the total number of `nonDerivativeSecurity` nodes in the xml file (these are NOT children of `nonDerivativeTable`)
  - `total_non_derivative_nodes`: the total number of nodes which correspond to a row in Table 1 of Form 3, 4 or 5 filing. Equal to the sum of `num_non_derivative_tran`, `num_non_derivative_hold` and `num_non_derivative_sec`
  - `got_table2`: `True` if the contents pertaining to `forms345_table2` were successfully extracted, `False` otherwise
  - `num_derivative_tables`: the number of `derivativeTable` nodes in the xml file
  - `num_derivative_tran`: the total number of `derivativeTransaction` nodes in the xml file (these are children of `derivativeTable`)
  - `num_derivative_hold`: the total number of `derivativeHolding` nodes in the xml file (these are children of `derivativeTable`)
  - `num_derivative_sec`: the total number of `derivativeSecurity` nodes in the xml file (these are NOT children of `derivativeTable`)
  - `total_derivative_nodes`: the total number of nodes which correspond to a row in Table 2 of Form 3, 4 or 5 filing. Equal to the sum of `num_derivative_tran`, `num_derivative_hold` and `num_derivative_sec`
  - `got_footnotes`: `True` if the contents pertaining to `forms345_footnotes` were successfully extracted, `False` otherwise
  - `got_footnote_indices`: `True` if the contents pertaining to `forms345_footnote_indices` were successfully extracted, `False` otherwise
  - `got_signatures`: `True` if the contents pertaining to `forms345_signatures` were successfully extracted, `False` otherwise
  - `wrote_header`: `True` if the contents extracted which pertain to `forms345_header` were successfully written to `forms345_header`, `False` otherwise
  - `wrote_rep_own`: `True` if the contents extracted which pertain to `forms345_reporting_owners` were successfully written to `forms345_reporting_owners`, `False` otherwise
  - `wrote_table1`: `True` if the contents extracted which pertain to `forms345_table1` were successfully written to `forms345_table1`, `False` otherwise
  - `wrote_table2`: `True` if the contents extracted which pertain to `forms345_table2` were successfully written to `forms345_table2`, `False` otherwise
  - `wrote_footnotes`: `True` if the contents extracted which pertain to `forms345_footnotes` were successfully written to `forms345_footnotes`, `False` otherwise
  - `wrote_footnote_indices`: `True` if the contents extracted which pertain to `forms345_footnote_indices` were successfully written to `forms345_footnote_indices`, `False` otherwise
  - `wrote_signatures`: `True` if the contents extracted which pertain to `forms345_signatures` were successfully written to `forms345_signatures`, `False` otherwise

* `forms345_xml_fully_processed`: This table tracks whether the xml file for a filing has been fully processed by `process_345_filing`. The fields are:

  - `file_name`: As above
  - `document`: As above
  - `fully_processed`: A boolean variable which is `True` if the xml file for a filing with the given `file_name` and `document` has been fully processed by `process_345_filing`, and `False` otherwise.



  ### Tables used in updating tables above

- `filings`: Index of all filings in the SEC EDGAR database (since 1993). Code: [`get_filings.R`](get_filings.R).
- `filing_docs`: Table listing the documents associated with each filing.
See [here](filing_docs.md). Code: [`get_filing_docs.R`](get_filing_docs.R).

## Code


- [`get_form_345_filing_docs.R`](get_form_345_filing_docs.R): This program scrapes the metadata for filings from `edgar.filings` with the `type` being equal to `3`, `4`, `5`, `3/A`, `4/A` or `5/A`, and writes the subsequent data to `edgar.filing_docs`.

- [`forms345_xml_functions.R`](forms345_xml_functions.R): This file is a repository of functions which are used to download and scrape the xml files for Forms 3, 4, and 5 (as well as their amendments), and also functions to to write the scraped data to the tables above. This file gets `sourced` by other programs.

- [`process_345_xml_documents.R`](process_345_xml_documents.R): This program gets the rows from `edgar.filing_docs` which correspond to the xml files of Forms 3, 4 and 5 (as well as their amendments), and then scrapes the data from the xml files and
