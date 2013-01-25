package BaNG::Statistics;
use Dancer ':syntax';
use BaNG::Reporting;
use Date::Parse;
use List::Util qw(min max);
use POSIX qw(floor);

use Exporter 'import';
our @EXPORT = qw(
    statistics_json
    statistics_decode_path
);

my %BackupsByPath;
my %RickshawData;
my @fields = qw( TotFileSizeTrans TotFileSize NumOfFilesTrans NumOfFiles Runtime );

sub statistics_decode_path {
    my ($path) = @_;

    $path =~ s|%|/|g;                               # decode percent signs to slashes
    $path = '/' . $path unless ($path =~ m|^/|);    # should always start with slash

    return $path;
}

sub statistics_json {
    my ($host, $share, $days) = @_;
    my $lastXdays = $days || 150;

    bangstat_db_connect();
    bangstat_db_query_statistics($host, $share, $lastXdays);
    extract_rickshaw_data();

    return rickshaw_json();
}

sub bangstat_db_query_statistics {
    my ($host, $share, $lastXdays) = @_;

    # query database
    my $sth = $BaNG::Reporting::bangstat_dbh->prepare("
        SELECT *
        FROM statistic
        WHERE Start > date_sub(now(), interval $lastXdays day)
        AND BkpFromHost = '$host'
        AND BkpFromPath LIKE '\%$share'
        AND BkpToHost LIKE 'phd-bkp-gw\%'
        ORDER BY Start;
    ");
    $sth->execute();

    # gather information into hash
    %BackupsByPath = ();
    while (my $dbrow=$sth->fetchrow_hashref()) {
        # reformat timestamp as "YY/MM/DD HH:MM:SS" for cross-browser compatibility
        (my $time_start = $dbrow->{'Start'}) =~ s/\-/\//g;
        (my $time_stop  = $dbrow->{'Stop' }) =~ s/\-/\//g;
        my $hostname    = $dbrow->{'BkpFromHost'};
        my $BkpFromPath = $dbrow->{'BkpFromPath'};
        $BkpFromPath =~ s/://g; # remove colon separators

        # compute runtime of backup in minutes with 2 digits
        my $Runtime = sprintf("%.2f", (str2time($time_stop)-str2time($time_start)) / 60.);

        push( @{$BackupsByPath{$BkpFromPath}}, {
            Runtime          => $Runtime,
            time_start       => $time_start,
            time_stop        => $time_stop,
            BkpFromPath      => $BkpFromPath,
            BkpToPath        => $dbrow->{'BkpToPath'},
            BkpFromHost      => $dbrow->{'BkpFromHost'},
            BkpToHost        => $dbrow->{'BkpToHost'},
            TotFileSize      => $dbrow->{'TotFileSize'},
            TotFileSizeTrans => $dbrow->{'TotFileSizeTrans'},
            NumOfFiles       => $dbrow->{'NumOfFiles'},
            NumOfFilesTrans  => $dbrow->{'NumOfFilesTrans'},
        });
    }
    # disconnect database
    $sth->finish();

    return 1;
}

sub extract_rickshaw_data {

    %RickshawData = ();
    foreach my $bkppath (sort keys %BackupsByPath) {
        my (%min, %max);
        foreach my $field (@fields) {
            # find min- and maxima of given fields
            $max{$field}  = sprintf("%.2f", max( map{$_->{$field}} @{$BackupsByPath{$bkppath}} ));
            $min{$field}  = sprintf("%.2f", min( map{$_->{$field}} @{$BackupsByPath{$bkppath}} ));
            $max{$field}  = sprintf("%.2f", 2*$max{$field}) if ($min{$field} == $max{$field}); # prevent division by zero
        }
        foreach my $bkp (@{$BackupsByPath{$bkppath}}) {
            my $t = str2time($bkp->{'time_start'}); # monotonically increasing coordinate to have single-valued function

            foreach my $field (@fields) {
                my $normalized = ($bkp->{$field} - $min{$field}) / ($max{$field} - $min{$field});

                my $humanreadable;
                if( $field eq 'Runtime' ) {
                    $humanreadable = "\"" . time2human($bkp->{$field}) . "\"";
                } else {
                    $humanreadable = "\"" . num2human($bkp->{$field})  . "\"";
                }

                $RickshawData{Normalized}{$field}    .= qq|\n        { "x": $t, "y": $normalized },|;
                $RickshawData{HumanReadable}{$field} .= qq|\n        { "x": $t, "y": $humanreadable },|;
            }
        }
        last;
    }

    return 1;
}

sub rickshaw_json {

    my %color = (
        "Runtime"          => "#00CC00",
        "NumOfFiles"       => "#0066B3",
        "NumOfFilesTrans"  => "#330099",
        "TotFileSize"      => "#FFCC00",
        "TotFileSizeTrans" => "#FF8000",
    );

    my $json .= "[\n";
    foreach my $field (@fields) {
        $json .= qq|{\n|;
        $json .= qq|    "name"          : "$field",\n|;
        $json .= qq|    "color"         : "$color{$field}",\n|;
        $json .= qq|    "data"          : [$RickshawData{Normalized}{$field}\n    ],\n|;
        $json .= qq|    "humanReadable" : [$RickshawData{HumanReadable}{$field}\n    ]\n|;
        $json .= qq|},\n|;
    }
    $json .= "]\n";

    # sanitize json by removing trailing spaces
    $json =~ s/\},(\s*)\]/\}$1\]/g;

    # minimize json by removing all whitespaces
    $json =~ s/\s+//g;

    return $json;
}

sub num2human {
    # convert large numbers to K, M, G, T notation
    my ($num) = @_;
    foreach my $unit ('', qw(K M G T P)) {
        if ($num < 1000) {
            if ($num < 10 && $num > 0) {
                return sprintf("\%.1f \%s", $num, $unit);  # print small values with 1 decimal
            }
            else {
                return sprintf("\%.0f \%s", $num, $unit);  # print larger values without decimals
            }
        }
        $num = $num / 1000.;
    }
}

sub time2human {
    # convert large times in minutes to hours
    my ($minutes) = @_;

    if ($minutes < 60) {
        return "$minutes min";
    } else {
        return sprintf("\%dh\%02dmin", floor($minutes/60), $minutes%60);
    }
}

1;
