use inc::Module::Install;

RTx('RT-Extension-MergeUsers');

name            ('RT-Extension-MergeUsers');
abstract        ('Merges two users into the same effective user');
author          ('Alex Vandiver <alexmv@bestpractical.com>');
version_from    ('lib/RT/Extension/MergeUsers.pm');
license         ('GPL version 2');

requires        ('Hook::LexWrap');

my ($lib_path) = $INC{'RT.pm'} =~ /^(.*)[\\\/]/;
my $local_lib_path = "$RT::LocalPath/lib";
substitute( { RT_LIB_PATH => join( ' ', $local_lib_path, $lib_path ), },
    'bin/rt-update-merged-users',
    'bin/rt-merge-users',
);  

WriteAll();
