use inc::Module::Install;

RTx('RT-Extension-MergeUsers');
all_from       ('lib/RT/Extension/MergeUsers.pm');
readme_from    ('lib/RT/Extension/MergeUsers.pm');

requires        ('Hook::LexWrap');
build_requires  ('RT');

my ($lib_path) = $INC{'RT.pm'} =~ /^(.*)[\\\/]/;
my $local_lib_path = "$RT::LocalPath/lib";
substitute( { RT_LIB_PATH => join( ' ', $local_lib_path, $lib_path ), },
    'bin/rt-update-merged-users',
    'bin/rt-merge-users',
);  

auto_install();
WriteAll();
