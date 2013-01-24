package BaNG::Routes;
use Dancer ':syntax';
use BaNG::Config;

get '/' => sub {
     template 'index' => {
              section => 'dashboard'
     };
};

get '/config/global' => sub {
    get_global_config();

    template 'global-config' => {
        section      => 'global-config',
        globalconfig => \%globalconfig,
    };
};

get '/config/all' => sub {
    get_global_config();
    find_hosts();

    template 'configs-overview' => {
        section  => 'configs-overview',
        hosts    => \%hosts ,
    };
};

get '/statistics' => sub {
    template 'statistics' => {
        section  => 'statistics',
    };
};
