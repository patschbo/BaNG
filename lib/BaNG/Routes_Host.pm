package BaNG::Routes_Host;

use Dancer ':syntax';
use BaNG::Config;
use BaNG::Reporting;

prefix '/host';

get '/' => sub {
    template 'host-search', {
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        section      => 'host',
    };
};

get '/add' => sub {
    template 'host-edit', {
        section       => 'host_edit',
        remotehost    => request->remote_host,
        webDancerEnv  => config->{run_env},
        title         => 'Create new Hostconfig',
        add_entry_url => uri_for('/host/add'),
    };
};

post '/add' => sub {
    template 'host-edit', {
        section       => 'host_edit',
        remotehost    => request->remote_host,
        webDancerEnv  => config->{run_env},
        title         => 'Well done!',
        add_entry_url => uri_for('/host/add'),
    };
};

get '/:host' => sub {
    get_serverconfig();
    get_host_config(param('host'));
    my %RecentBackups = bangstat_recentbackups( param('host') );

    template 'host', {
        section       => 'host',
        remotehost    => request->remote_host,
        webDancerEnv  => config->{run_env},
        host          => param('host'),
        hosts         => \%hosts,
        cronjobs      => get_cronjob_config(),
        RecentBackups => \%RecentBackups,
    };
};

1;