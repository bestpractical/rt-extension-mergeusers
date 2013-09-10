# BEGIN BPS TAGGED BLOCK {{{
# 
# COPYRIGHT:
#  
# This software is Copyright (c) 1996-2008 Best Practical Solutions, LLC 
#                                          <sales@bestpractical.com>
# 
# (Except where explicitly superseded by other copyright notices)
# 
# 
# LICENSE:
# 
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
# 
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
# 
# 
# CONTRIBUTION SUBMISSION POLICY:
# 
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
# 
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
# 
# END BPS TAGGED BLOCK }}}
use 5.008003;
use strict;
use warnings; no warnings qw(redefine);

package RT::Extension::MergeUsers;

our $VERSION = '0.11';

=head1 NAME

RT::Extension::MergeUsers - Merges two users into the same effective user

=head1 DESCRIPTION

This RT extension adds a "Merge Users" box to the User Administration page, 
which allows you to merge the user you are currently viewing with another
user on your RT instance.

It also adds L</MergeInto> and L</UnMerge> functions to the L<RT::User> class,
which allow you to programmatically accomplish the same thing from your code.

It also provides a version of L<CanonicalizeEmailAddress>, which means that
all e-mail sent from secondary users is displayed as coming from the primary
user.

=head1 INSTALLATION

If you're upgrading then, as well, read L</UPGRADING> below.

    perl Makefile.PL
    make
    make install
    clear your mason cache
        most often this would be rm -rf /opt/rt3/var/mason_data/*
    restart apache

For RT 3.8

    Add RT::Extension::MergeUsers to your /opt/rt3/etc/RT_SiteConfig.pm file
    Set(@Plugins, qw(RT::Extension::MergeUsers));

    If you have more than one Plugin enabled, you must enable them as one 
    Set(@Plugins, qw(Foo Bar)); command

=head1 UPGRADING

If you are upgrading from 0.03_01 or earlier, you must run F<rt-upgrade-merged-users>.
This script will create MergedUsers Attributes so RT can know when you're looking
at a user that other users have been merged into. If you don't run this script,
you'll have issues unmerging users. It can be safely run multiple times, it will
only create Attributes as needed.

=cut

package RT::User;

our %EFFECTIVE_ID_CACHE;

use RT::Interface::Web::Handler;

{
    my $i = 0;

    my $old_cleanup = \&RT::Interface::Web::Handler::CleanupRequest;
    no warnings 'redefine';
    *RT::Interface::Web::Handler::CleanupRequest = sub {
        $old_cleanup->(@_);
        return if ++$i % 100; # flush cache every N requests
        %EFFECTIVE_ID_CACHE = ();
    };
}

sub CanonicalizeEmailAddress {
    my $self = shift;
    my $address = shift;

    if ($RT::CanonicalizeEmailAddressMatch && $RT::CanonicalizeEmailAddressReplace ) {
        $address =~ s/$RT::CanonicalizeEmailAddressMatch/$RT::CanonicalizeEmailAddressReplace/gi;
    }

    # get the user whose email address this is
    my $canonical_user = RT::User->new($RT::SystemUser);
    $canonical_user->LoadByCols( EmailAddress => $address );
    return $address unless $canonical_user->id;
    return $address unless $canonical_user->EmailAddress ne $address;
    return $canonical_user->CanonicalizeEmailAddress(
        $canonical_user->EmailAddress
    );
}

sub LoadByCols {
    my $self = shift;
    $self->SUPER::LoadByCols(@_);
    return $self->id unless my $oid = $self->id;

    unless ( exists $EFFECTIVE_ID_CACHE{ $oid } ) {
        my $effective_id = RT::Attribute->new( $RT::SystemUser );
        $effective_id->LoadByCols(
            Name       => 'EffectiveId',
            ObjectType => __PACKAGE__,
            ObjectId   => $oid,
        );
        if ( $effective_id->id && $effective_id->Content && $effective_id->Content != $oid ) {
            $self->LoadByCols( id => $effective_id->Content );
            $EFFECTIVE_ID_CACHE{ $oid } = $self->id;
        } else {
            $EFFECTIVE_ID_CACHE{ $oid } = undef;
        }
    }
    elsif ( defined $EFFECTIVE_ID_CACHE{ $oid } ) {
        $self->LoadByCols( id => $EFFECTIVE_ID_CACHE{ $oid } );
    }

    return $self->id;
}

sub LoadOriginal {
    my $self = shift;
    return $self->SUPER::LoadByCols( @_ );
}

sub GetMergedUsers {
    my $self = shift;
    
    my $merged_users = $self->FirstAttribute('MergedUsers');
    unless ($merged_users) {
        $self->SetAttribute( 
            Name => 'MergedUsers',
            Description => 'Users that have been merged into this user',
            Content => [] );
        $merged_users = $self->FirstAttribute('MergedUsers');
    };
    return $merged_users;
}

sub MergeInto {
    my $self = shift;
    my $user = shift;

    # Load the user objects we were called with
    my $merge;
    if (ref $user) {
        return (0, "User is not loaded") unless $user->id;

        $merge = RT::User->new($RT::SystemUser);
        $merge->Load($user->id);
        return (0, "Could not reload user #". $user->id)
            unless $merge->id;
    } else {
        $merge = RT::User->new($RT::SystemUser);
        $merge->Load($user);
        return (0, "Could not load user '$user'") unless $merge->id;
    }
    return (0, "Could not load user to be merged") unless $merge->id;

    # Get copies of the canonicalized users
    my $email;

    my $canonical_self = RT::User->new($RT::SystemUser);
    $canonical_self->Load($self->id);
    return (0, "Could not load user to merge into") unless $canonical_self->id;

    # No merging into yourself!
    return (0, "Could not merge @{[$merge->Name]} into itself")
           if $merge->id == $canonical_self->id;

    # No merging if the user you're merging into was merged into you
    # (ie. you're the primary address for this user)
    my ($new) = $merge->Attributes->Named("EffectiveId");
    return (0, "User @{[$canonical_self->Name]} has already been merged")
           if defined $new and $new->Content == $canonical_self->id;

    # clean the cache
    delete $EFFECTIVE_ID_CACHE{$self->id};

    # do the merge
    $canonical_self->SetAttribute(
        Name => "EffectiveId",
        Description => "Primary ID of this email address",
        Content => $merge->id,
    );

    my $merged_users = $merge->GetMergedUsers;
    $merged_users->SetContent( [$canonical_self->Id, @{$merged_users->Content}] );

    $merge->SetComments(join "\n", grep /\S/,
        $merge->Comments||'',
        ($canonical_self->EmailAddress || $canonical_self->Name)." (".$canonical_self->id.") merged into this user",
    );

    $canonical_self->SetComments( join "\n", grep /\S/,
        $canonical_self->Comments||'',
        "Merged into ". ($merge->EmailAddress || $merge->Name)." (". $merge->id .")",
    );
    return (1, "Merged users successfuly");
}

sub UnMerge {
    my $self = shift;

    my ($current) = $self->Attributes->Named("EffectiveId");
    return (0, "Not a merged user") unless $current;

    # flush the cache, or the Sets below will
    # clobber $self
    delete $EFFECTIVE_ID_CACHE{$self->id};

    my $merge = RT::User->new($RT::SystemUser);
    $merge->Load( $current->Content );

    $current->Delete;
    $self->SetComments( join "\n", grep /\S/,
        $self->Comments||'',
        "Unmerged from ". ($merge->EmailAddress || $merge->Name) ." (".$merge->id.")",
    );

    $merge->SetComments(join "\n", grep /\S/,
        $merge->Comments,
        ($self->EmailAddress || $self->Name) ." (". $self->id .") unmerged from this user",
    );

    my $merged_users = $merge->GetMergedUsers;
    my @remaining_users = grep { $_ != $self->Id } @{$merged_users->Content};
    if (@remaining_users) {
        $merged_users->SetContent(\@remaining_users);
    } else {
        $merged_users->Delete;
    }

    return ($merge->id, "Unmerged @{[$self->NameAndEmail]} from @{[$merge->NameAndEmail]}");
}

sub SetEmailAddress {
    my $self = shift;
    my $value = shift;

    my ( $val, $msg ) = $self->ValidateEmailAddress($value);
    return ( 0, $msg || $self->loc('Email address in use') ) unless $val;

    # if value is valid then either there is no user or
    # user is merged into this one
    my $tmp = RT::User->new($RT::SystemUser);
    $tmp->LoadOriginal( EmailAddress => $value );
    if ( $tmp->id && $tmp->id != $self->id ) {
        # there is a different user record
        $tmp->_Set( Field => 'EmailAddress', Value => "" );
    }

    return $self->_Set( Field => 'EmailAddress', Value => $value );
}

sub NameAndEmail {
    my $self = shift;
    my $name = $self->Name;
    my $email = $self->EmailAddress;

    if ($name eq $email) {
        return $email;
    } else {
        return "$name <$email>";
    }
}

package RT::Users;
use RT::Users;

=head2 Next

This custom iterator makes sure that duplicate users are never shown in search results.

=cut

sub Next {
    my $self = shift;
    
    my $user = $self->SUPER::Next(@_);
    unless ($user and $user->id) {
        $self->{seen_users} = undef;
        return undef;
    }   
    
       

    my ($effective_id) = $user->Attributes->Named("EffectiveId");
    if ($effective_id && $effective_id->Content && $effective_id->Content != $user->id) {
        $user->LoadByCols(id =>$effective_id->Content);
    }   
    return $self->Next() if ($self->{seen_users}->{$user->id}++);

    return $user;
}

sub GotoFirstItem {
    my $self = shift;
    $self->{seen_users} = undef;
    $self->GotoItem(0);
}

=head1 AUTHOR

Alex Vandiver E<lt>alexmv@bestpractical.comE<gt>

=head1 LICENSE

GPL version 2.

=cut

1;
