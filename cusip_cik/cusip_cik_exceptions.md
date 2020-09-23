# `edgar.cusip_cik_exceptions`

The table `edgar.cusip_cik_exceptions` is a table written to handle a number of types of exceptional cases that arise in the raw `edgar.cusip_cik` table. These, for the main part, are:

 - Mappings between `cik`s and `cusip`s for which the `cusip` is a valid 9-character cusip number, but which are incorrect or possibly incorrect.
 
 - Cases where the raw cusip is 8 characters long. For these cases, we consider the raw cusip as a valid cusip8, as well as the raw cusip padded with a zero from the left.  
 
 - Cases where the raw cusip is 7 characters long. For these cases, we consider the first six characters of the raw cusip as a valid cusip6, as well as the raw cusip padded with a zero from the left, and finally the raw cusip padded with two zeros from the left.  
 
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

In this section, we discuss how the cusip-cik pairs to be analysed for veracity were chosen. Firstly, we should mention that in all the cases to be discussed, we restricted ourselves to cusip-cik pairs which have a frequency in `edgar.cusip_cik` above a threshold of 10. 

By far the set of cases which is the most complex is the set of valid 9-digit cusips which map onto `cusipm.issuer`, as there are 19321 of them. This turns out to be orders of magnitude larger than any of the other groups of cusip-cik pairs that we consider for the purpose of `edgar.cusip_cik_exceptions`. Thus, it is important to have some procedure of narrowing down the number of cases from these that we consider. We chose to utilize a couple of things: approximate string matching and name normalization. 

The way we use approximate string matching is to utilize a string metric called the [Levenshtein distance](https://en.wikipedia.org/wiki/Levenshtein_distance), calculate this metric between the company names and the issuer names, and then exploit its properties to map the results to ratios between 0 and 1, with 0 corresponding to a complete non-match, and 1 corresponding to a perfect match. We then select just the pairs for which this ratio, which is stored in the field `sim_inde_max`, is less than some threshold, which we chose to be 0.8. 

We utilize name normalization to really complement the use of approximate string matching; it can help make the procedure described in the previous paragraph much more decisive, resulting in less cusip-cik pairs having a ratio in the middle of the range between 0 and 1, and thus helping to narrow the numbers further. The first step here is to strip punctuation and to convert all letters to upper case. We then consider mappings between words appearing in the company names of `edgar.cusip_cik` and words appearing in the issuer names appearing in `cusipm.issuer`. We did this to find the common abbreviations appearing mostly in `cusipm.issuer`, and map them to the corresponding words appearing in `edgar.cusip_cik` (or vice versa, though `cusipm.issuer` makes a particularly heavy use of abbreviation of words, so this is not as common). The result is that we end up with dataframe that we call `map_df` which maps common words to their common abbreviations, such as "FUND" to "FD", "TRUST" to "TR", "HOLDINGS" to "HLDGS", "INTERNATIONAL" to "INTL", and so on. This way, we make sure that common words and their common abbreviations always appear the same form in the normalized versions of the company names in `edgar.cusip_cik` and the issuer names from `cusipm.issuer`.


For more details concerning approximate string matching and name normalization, see the Jupyter Notebook `handle_cusip_cik_exceptions.ipynb`. But essentially, after normalizing the company names coming from `edgar.cusip_cik` and the issuer_names in `cusipm.issuer`, and then calculating `sim_index_max` for the normalized names, imposing the ratio that `sim_index_max` is less than 0.8 reduces the number of cusip-cik pairs, where the cusip is 9 digits in length, to consider from 19321 to around 1200. 

From the remaining 1200 candidates, we selected pairs that seemed to be either wrong or not obviously correct. From these selected candidates, we then made dataframes which contained information on better ciks, better cusips and other reasons for why the entries might be considered wrong (`valid_match = FALSE`), undecided (`valid_match = NULL`), and correct (`valid_match = TRUE`). We then binded these dataframes and wrote them to `edgar.cusip_cik_exceptions`.

We repeated this process for 6, 7 and 8-digit cusips, considering cases with both unpadded cusips and cusips padded with up to three zeros on the left. For all of these cases, the data to look at was significantly smaller, making an analysis by hand feasible, so we ignored approximate string matching and name normalization here. 


As alluded to above, the notebook `handle_cusip_cik_exceptions.ipynb` contains more information on the code used to generate the dataframes described in the previous two paragraphs, so refer to that for more details. This notebook has also been designed to be used to keep `edgar.cusip_cik_exceptions` up to date, and it is split into sections with cells containing the functions and packages needed, as well as sections working through all of the various cases described above with 6, 7, 8 and 9-digit cusips in a step-by-step manner. It has been written in a way so that the previous pairs written into  `cusip_cik_exceptions` can be eliminated from the pairs to be looked at in the future, so that a user does not have to look at many pairs at a time each time the table is updated.







