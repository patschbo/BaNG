#!/usr/bin/perl
#
# copyright 2013 Patrick Schmid <schmid@phys.ethz.ch>, distributed under
# the terms of the GNU General Public License version 2 or any later
# version.
#
# This is compiled with threading support
#
# 2013.02.20, Patrick Schmid <schmid@phys.ethz.ch> & Claude Becker <becker@phys.ethz.ch>
#
use strict;
use warnings;
use Cwd 'abs_path';
use File::Basename;
use lib dirname(abs_path($0))."/lib";
use Getopt::Long qw(:config no_auto_abbrev);

use BaNG::Hosts;
use BaNG::Config;
our %hosts;

my $version         = '3.0';
my $debug           = 1;
my $debuglevel      = 2;        #1 normal output, 2 ultimate output, 3 + rsync verbose!
my $nthreads        = 1;
my $wipe            = '';
my $help            = '';
my $showversion     = '';
my $group_arg       = '';
my $host_arg        = '';
my $nthreads_arg    = '';

my @queue;


#################################
# Main
#
parse_command_options();
get_global_config();
get_host_config($host_arg, $group_arg);

# run wipe jobs or fill queue with backup jobs
foreach my $config (keys %hosts) {
    if ( $wipe ) {
        do_wipe(  $hosts{$config}->{hostname}, $hosts{$config}->{group});
    } else {
        queue_backup($hosts{$config}->{hostname}, $hosts{$config}->{group});
    }
}
print "Queue: @queue\n" if $debug;

# stop if queue is empty
if( !@queue ) {
    print "Exit because queue is empty.\n" if $debug;
    exit 0;
}

# use threads to empty queue
initialize_threads();


exit 0;


#################################
# Initialize threads
#
sub initialize_threads {

    # define number of threads
    if( $nthreads_arg ){
        # If nthreads was defined by cli argument, use it
        $nthreads = $nthreads_arg;
        print "Using nthreads = $nthreads from command line argument\n" if $debug;
    } elsif ( $host_arg && $group_arg) {
        # If no nthreads was given, and we back up a single host and group, get nthreads from its config
        $nthreads = $hosts{"$host_arg-$group_arg"}->{hostconfig}->{BKP_THREADS_DEFAULT};
        print "Using nthreads = $nthreads from $host_arg-$group_arg config file\n" if $debug;
    }

    return 1;
}

#################################
# Add task to make new backup to queue
#
sub queue_backup {
    my ($host, $group) = @_;

    print "sub queue_backup($host, $group)\n" if $debug;

    # make sure backup is enabled
    return unless $hosts{"$host-$group"}->{status} eq 'enabled';
    # stop if trying to do bulk backup if it's not allowed
    return unless ( ($group_arg && $host_arg) || $hosts{"$host-$group"}->{hostconfig}->{BKP_BULK_ALLOW});

    # get list of partitions to back up
    my (@src_part) = split ( / /, $hosts{"$host-$group"}->{hostconfig}->{BKP_SOURCE_PARTITION});
    print "Number of partitions: " . ($#src_part+1) . " ( @src_part )\n" if $debug;

    # optionally queue each subfolder
    foreach my $part (@src_part) {
        if( $hosts{"$host-$group"}->{hostconfig}->{BKP_THREAD_SUBFOLDERS} ) {
            queue_remote_subfolders($host,$group, $part);
        } else {
            # queue whole partitions
            push @queue, $part;
        }
    }

    print "Queued backup of host $host group $group\n" if $debug;

    return 1;
}

#################################
# Make new backup
#
sub do_backup {
    my ($host, $group) = @_;

    # make sure host is online
    my ($conn_status, $conn_msg ) = chkClientConn($host, $hosts{"$host-$group"}->{hostconfig}->{BKP_GWHOST});
    print "chkClientConn: $conn_status, $conn_msg\n" if $debug;
    die "Error: host is offline\n" unless $conn_status;

    eval_rsync_options($host,$group);

    # if BKP_STORE_MODUS == BTRFS
        # use rsync with btrfs snapshots
    # else
        # use rsync with --link-dest
    # endif

    print "Backup host $host group $group\n" if $debug;

    return 1;
}

#################################
# Wipe old backup
#
sub do_wipe {
    my ($host, $group) = @_;

    print "Wipe host $host group $group\n" if $debug;

    return 1;
}

#################################
# Add list of remote folders to thread queue
#
sub queue_remote_subfolders {
    my ($host, $group, $partition) = @_;

    $partition =~ s/://;

    my $remoteshell   = $hosts{"$host-$group"}->{hostconfig}->{BKP_RSYNC_RSHELL};
    my @remotedirlist = `$remoteshell $host find $partition -xdev -mindepth 1 -maxdepth 1`;
    print "eval subfolders command: @remotedirlist\n" if $debug;

    foreach my $remotedir (@remotedirlist) {
        chomp $remotedir;
        push @queue, $remotedir;
    }

    return 1;
}
#################################
# Evaluate rsync options
#
sub eval_rsync_options {
    my ($host, $group) = @_;
    my $rsync_options  = '';
    my $hostconfig = $hosts{"$host-$group"}->{hostconfig};

    $rsync_options .= "-ax "            if $hostconfig->{BKP_RSYNC_ARCHIV};
    $rsync_options .= "-R "             if $hostconfig->{BKP_RSYNC_RELATIV};
    $rsync_options .= "-H "             if $hostconfig->{BKP_RSYNC_HLINKS};
    $rsync_options .= "--delete "       if $hostconfig->{BKP_RSYNC_DELETE};
    $rsync_options .= "--force "        if $hostconfig->{BKP_RSYNC_DELETE_FORCE};
    $rsync_options .= "--numeric-ids "  if $hostconfig->{BKP_RSYNC_NUM_IDS};
    $rsync_options .= "--inplace "      if $hostconfig->{BKP_RSYNC_INPLACE};
    $rsync_options .= "--acls "         if $hostconfig->{BKP_RSYNC_ACL};
    $rsync_options .= "--xattrs "       if $hostconfig->{BKP_RSYNC_XATTRS};
    $rsync_options .= "--no-D "         if $hostconfig->{BKP_RSYNC_OSX};
    $rsync_options .= "-v "             if ($debug && ($debuglevel == 3));

    if ($hostconfig->{BKP_RSYNC_RSHELL}){
        if ($hostconfig->{BKP_GWHOST}){
            $rsync_options .= "-e $hostconfig->{BKP_RSYNC_RSHELL} $hostconfig->{BKP_GWHOST} ";
        } else {
            $rsync_options .= "-e $hostconfig->{BKP_RSYNC_RSHELL} ";
        }
    }
    if ($hostconfig->{BKP_RSYNC_RSHELL_PATH}){
        $rsync_options .= "--rsync-path=$hostconfig->{BKP_RSYNC_RSHELL_PATH} ";
    }
    if ($hostconfig->{BKP_EXCLUDE_FILE}){
        $rsync_options .= "--exclude-from=$config_path/$hostconfig->{BKP_EXCLUDE_FILE} ";
    }

    $rsync_options =~ s/\s+$//; # remove trailing space
    print "Rsync Options: $rsync_options\n" if $debug;

    return $rsync_options;
}

#################################
# Get/Check command options
#
sub parse_command_options {
    GetOptions (
        "help"         => sub { usage('') },
        "v|version"    => \$showversion,
        "d|debug"      => \$debug,
        "g|group=s"    => \$group_arg,
        "h|host=s"     => \$host_arg,
        "t|threads=i"  => \$nthreads_arg,
        "w|wipe"       => \$wipe,
    )
    or usage("Invalid commmand line options.");
    usage("You must provide some arguments")    unless ($host_arg || $group_arg || $showversion);
    usage("Current version number: $version")   if ( $showversion );
    usage("Number of threads must be positive") if ( $nthreads_arg && $nthreads_arg <= 0 );
}

##############
# Usage
#
sub usage {
    my ($message) = @_;

    if (defined $message && length $message) {
        $message .= "\n"
            unless $message =~ /\n$/;
    }

    my $command = $0;
    $command    =~ s#^.*/##;

    print STDERR (
        $message, qq(
        Usage Examples:

        $command -h <hostname> -g <group>   # back up given host and group
        $command -h <hostname>              # back up all groups of given host
        $command -g <group>                 # back up all hosts of given group
        $command -v                         # show version number
        $command --help                     # show this help message

        Optional Arguments:

        -t <nr>         # number of threads, default: 1
        -w              # wipe the backup
        -d              # show debugging messages
    \n)
    );
    exit 0;
}
