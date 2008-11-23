package RT::Users;
use warnings;
use strict;

no warnings qw/redefine/;


=head2 Next

This custom iterator makes sure that duplicate users are never shown in search results.

=cut

package RT::Users;
use RT::Users;
        
no warnings qw'redefine';
sub Next {
    my $self = shift;
    
    my $user = $self->SUPER::Next(@_);
    return unless ($user && $user->id);
    unless ($user) {
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
1;
