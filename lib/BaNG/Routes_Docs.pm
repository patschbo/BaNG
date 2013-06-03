package BaNG::Routes_Docs;

use Dancer ':syntax';
use BaNG::Config;
use Template::Plugin::Markdown;
use Text::Markdown;

prefix '/docs';

get '/' => sub {
    redirect '/docs/Index';
};

get '/:file' => sub {
    my $file = "$prefix/docs/" . param('file') . ".markdown";
    open my $MARKDOWN, '<', $file;
    my $markdown = do { local $/; <$MARKDOWN> };
    template 'documentation' => {
        section      => 'documentation',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        content      => $markdown,
    };
};

1;