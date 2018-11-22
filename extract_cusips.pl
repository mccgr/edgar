#!/usr/bin/env perl
use DBI;
use HTML::Strip;
use File::stat;
use File::Spec;
use Env qw($PGDATABASE $PGUSER $PGHOST $EDGAR_DIR);

$path_to_edgar = $EDGAR_DIR ? $EDGAR_DIR : "/Volumes/2TB/data/";

# Connect to my database
$PGDATABASE = $PGDATABASE ? $PGDATABASE : "crsp";
$PGUSER = $PGUSER ? $PGUSER : "igow";
$PGHOST= $PGHOST ? $PGHOST : "localhost";

$file_name = @ARGV[0];

my $dbh = DBI->connect("dbi:Pg:dbname=$PGDATABASE;host=$PGHOST", "$PGUSER")
	or die "Cannot connect: " . $DBI::errstr;

# Get the file name
# File::Spec->catfile( @directories, $filename );
$full_path = File::Spec->catfile( $path_to_edgar, $file_name );

# Skip if there is no file or if the file is over 1MB
unless (-e $full_path) {
    exit;
}
my $filesize = stat($full_path)->size;
if ($filesize > 1000000) {
    exit;
}

# Open the SEC text filing
open(my $fh, "<", $full_path) or die "$0: can't open $full_path: $!";
my $lines = join '', <$fh>;

# Strip out HTML tags
my $hs = HTML::Strip->new();
my $lines = $hs->parse( $lines );
$hs->eof;

# Regular expressions
$cusip_hdr = 'CUSIP\s+(?:No\.|#|Number):?';
$cusip_fmt = '[0-9A-Z]{1,3}[\s-]?[0-9A-Z]{3}[\s-]?[0-9A-Z]{2}[\s-]?\d{1}';

if ($lines =~ /$cusip_hdr\s+($cusip_fmt)/si) {
    # Format A:
    # CUSIP No. (or CUSIP #) followed by seven- to nine-character CUSIP
    $format= "A";
    $cusip = $1;
    $cusip =~ s/[\s-]//g;

} elsif ($lines =~ /($cusip_fmt)\s+(?:[_-]{9,})?\s*\(CUSIP Number\)/si) {
    # Format D:
    # CUSIP followed by "CUSIP Number" perhaps with a row of underscores
    # between.
    #                    808513-10-5
    #                   (CUSIP Number)
    $format = "D";
    $cusip = $1;
    $cusip =~ s/[)(\.\s-]//g;
}

# Close the full-text filing
close($fh);

# Now get data from the SGML header file.
$sgml_file = $full_path;

# Use a regular expression to locate the SGML header file
$sgml_file =~ s/(\d{10})-(\d{2})-(\d{6})\.txt/$1$2$3\/$1-$2-$3.hdr.sgml/g;

# Skip if there is no file
print "Hi!\n";
unless (-e $sgml_file) {
    exit;
}


# Open the SGML header file and join its text
open(my $fh, "<", $sgml_file) or die "$0: can't open $sgml_file: $!";
my $lines = join '', <$fh>;

# Get the portion related the SUBJECT COMPANY
if ($lines =~ /<SUBJECT-COMPANY>(.*)<\/SUBJECT-COMPANY>/s) {
    $sub_co_text = $1;

    # Get the name ...
    if ($sub_co_text =~ /<CONFORMED-NAME>(.*)/) {
        $co_name = $1;
    }

    # ... and CIK
    if ($sub_co_text =~ /<CIK>(.*)/) {
        $cik = $1;
    }
}

# Close the SGML header file
close($fh);

$co_name =~ s/\s+$//g;
$co_name =~ s/'/''/g;
if ($cik=='') {
    $cik=NULL; # exit;
}

# Output the result
# Output results num_sentences
$sql = "INSERT INTO edgar.cusip_cik ";
$sql .= "(file_name, cusip, cik, company_name, format) ";
$sql .= "VALUES ('$file_name','$cusip',$cik,'$co_name','$format')";
$dbh->do($sql);

print "$sql\n";
# clean up
$dbh->disconnect();


