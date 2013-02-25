package BaNG::Route_Schedule;
use Dancer ':syntax';
use BaNG::Config;

prefix '/schedule';

get '/' => sub {
    get_global_config();
    get_host_config("*");
    get_cronjob_config();

    template 'schedule-overview', {
        section      => 'schedule',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        hosts        => \%hosts ,
        cronjobs     => \%cronjobs ,
    };
};

