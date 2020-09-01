# `edgar.cusip_cik_exceptions`

The table `edgar.cusip_cik_exceptions` is a table written to handle a number of types of exceptional cases that arise in the raw `edgar.cusip_cik` table. These, for the main part, are:

 - Mappings between `cik`s and `cusip`s for which the `cusip` is a valid 9-character cusip number, but which are incorrect or possibly incorrect.
 
 - Cases where the raw cusip is 8 characters long. For these cases, we both consider the raw cusip as a valid cusip8, as well as the raw cusip padded with a zero from the left.  
 
 - Cases where the raw cusip is 7 characters long. For these cases, we both consider the first six characters of the raw cusip as a valid cusip6, as well as the raw cusip padded with a zero from the left, and also the raw cusip padded with two zeros from the left.  
 
 - Cases where the raw cusip is 6 characters long. For these cases, we consider the raw cusip as a valid cusip6, as well as the first six characters of the raw cusip padded with a zero from the left as a valid cusip6, then the raw cusip padded with two zeros from the left as a valid cusip8, and then finally the raw cusip padded with three zeros from the left as a valid cusip. 
 

 
## The fields

- `cik`: the cik number for the pair considered

- `cusip`: the cusip number for the pair considered, given as a character string. This is not always the same as the cusip string extracted from the original data in `cusip_cik`; in same cases it has been modified from the original cusip string, though the original cusip string can always be found in the later field `cusip_raw` (see below). For the sake of clarity, `cusip` is always taken to be 6, 8 or 9 characters long, depending on the `cusip_raw` and the modifications made to it to derive `cusip`. 

- `company_name`: The company name for the given cik for the row

- `issuer_name`: The issuer name for the given `cusip`, constructed from the fields `issuer_name_1`, `issuer_name_2` and `issuer_name_3` if cusip maps onto the table `cusipm.issuer`, and equal to the the field `comnam` of `crsp.stocknames` if the cusip only maps onto `stocknames`

- `issuer_adl`: This is a pasting of the fields `issuer_adl_1`, `issuer_adl_2`, `issuer_adl_3` and `issuer_adl_4` of `cusipm.issuer`, if the cusip maps onto the table, and is null if the cusip does not map to `cusipm.issuer`. This field can be very useful as it contains historical information on the company and often contains a historical name which often matches `company_name` in the cases where `company_name` appears to not match the `issuer_name`

- `company_name_norm`: the normalization of `company_name`, in the case of a valid 9-digit `cusip_raw` which maps to `cusipm.issuer`. In this normalization, letters are converted to upper case, punctuation is stripped, and common abbreviations for words are substituted (see a later section for more details). 

- `issuer_name_norm`: the normalization of `issuer_name`, in the case of valid 9-digit `cusip_raw` which maps to `cusipm.issuer`. In this normalization, letters are converted to upper case, punctuation is stripped, and common abbreviations for words are substituted (see a later section for more details). 

- `sim_index_norm`: an index between 0 and 1 which measures how well `company_name` matches `issuer_name`, with 0 corresponding to a complete non-match, and 1 corresponding to a perfect match. This is calculated using the Levenshtein distance by the function `get_name_similarity_index` (see later section). In the case of a valid 9-digit `cusip_raw` which map onto `cusipm.issuer`, this index is calculated from `company_name_norm` and `issuer_name_norm`; in the cases where a valid 9-digit `cusip_raw` only maps onto `crsp.stocknames`, it is simply calculated from `company_name` and `issuer_name`. For cases where `cusip_raw` is less than 9 digits long, this variable is not calculated (for reasons why, see later section).

- `sim_index_max`: this is the maximum of `sim_index_norm` within the data after grouping by (`cik`, `cusip`), where this is valid. This variable was used to decide which valid 9-digit raw cusips to look at for the sake of making `cusip_cik_exceptions` (we considered rows for which `sim_index_max` is less than 0.8)

- `valid_match`: a boolean variable which is `TRUE` if the (`cik`, `cusip`) pair in question was determined to be valid, `FALSE` if the pair was determined to be an incorrect match, and `NULL` if open to interpretation. Usually, the null cases are ones in which `company_name` and `issuer_name` are technically not the same entities, but are somewhat related (eg. "ISHARES INC" versus "ISHARES TRUST")

- `better_cik`: a cik which has a company name which better matches the `issuer_name` for the given `cusip` of the pair (either determined by noting that the alternate `sim_index_max` is more, or by through observation). This field is null if there is no such cik

- `better_cik_company_name`: the company name for the `better_cik`, if `better_cik` is non-null.

- `sim_ix_better_cik`: `sim_index_max`/`sim_index_norm` between `better_cik_company_name` and `issuer_name`, in cases where `cusip_raw` is 9 digits long, and the `better_cik` was found within the data by looking for rows with the given `cusip` (achieved by joining relevant dataframes). If `better_cik` was found manually, this field is usually null.  

- `better_cusip`: a cusip which has an `issuer_name` which better matches the given `company_name` for the given `cik` of the pair (either determined by noting that the alternate `sim_index_max` is more, or by through observation). This field is null if there is no such cusip

- `better_cusip_issuer_name`: the `issuer_name` for the `better_cusip`, if `better_cusip` is non-null. 

- `better_cusip_issuer_adl` : the `issuer_adl` for the `better_cusip`, if `better_cusip` is non-null, and if `better_cusip` maps onto or is derived from `cusipm.issuer`. 

- `sim_ix_better_cusip`: `sim_index_max`/`sim_index_norm` between `better_cusip_issuer_name` and `company_name`, in cases where `cusip_raw` is 9 digits long, and the `better_cusip` was found within the data by looking for rows with the given `cik` (achieved by joining relevant dataframes). If `better_cusip` was found manually, this field is usually null.  

- `better_cusip6`: Similar to `better_cusip`, but is a cusip6 (usually found from `cusipm.issuer`), which has an issuer name which better matches the `company_name`. Usually found by manually searching `cusipm.issuer`.

- `better_cusip6_issuer_name`: the `issuer_name` for `better_cusip6`, if `better_cusip6` is non-null. 

- `better_cusip6_issuer_adl`: the `issuer_adl` for `better_cusip6`, if `better_cusip6` is non-null. As `better_cusip6` is usually found manually, this field is usually null unless the `issuer_adl` was relevant to determining `valid_match`. 

- `better_cusip8`: Similar to `better_cusip`, but is a cusip8 (usually found from `crsp.stocknames`), which has an issuer name (given in the `comnam` field) which better matches the `company_name`. Usually found by manually searching `crsp.stocknames`.

- `better_cusip8_comnam`: the issuer name, or `comnam` from `crsp.stocknames`, for the `better_cusip8`, if `better_cusip8` is non-null

- `other_reason`: A text field, used to give further details/explanation in cases which were not obviously wrong, or in some cases, not obviously right. 

- `cusip_raw`: the raw cusip used to generate the candidate `cusip`. This is always equal to the extracted `cusip` from `edgar.cusip_cik`. In cases where `cusip_raw` is modified to give `cusip` in `edgar.cusip_cik_exceptions` (eg. padding with zeros from the left, cutting to 6 digits in the case of raw 7 digit cusips), `cusip` will not be equal to `cusip_raw`


## How `edgar.cusip_cik_exceptions` was initially generated






