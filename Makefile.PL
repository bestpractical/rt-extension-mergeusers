use inc::Module::Install;

RTx('RT-Extension-MergeUsers');

name            ('RT-Extension-MergeUsers');
abstract        ('Merges two users into the same effective user');
author          ('Alex Vandiver <alexmv@bestpractical.com>');
version_from    ('lib/RT/Extension/MergeUsers.pm');
license         ('GPL version 2');

requires        ('Hook::LexWrap');

WriteAll();
